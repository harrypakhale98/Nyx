import BackgroundTasks
import SwiftData
import SwiftUI
import WatchConnectivity
import WidgetKit

/// Brings the widget, the watch, Siri's park list and reminders in line with the saved parks. One
/// per process (owned by `PlanModel`), so two iPad windows never run it twice. It publishes from
/// what is cached first, so unsaving a park or switching shower reminders off takes effect at once
/// even on a weak signal, then again once fresh forecasts arrive. A change made while a run is under
/// way is never dropped: the run goes again when it ends.
@MainActor final class SavedSkySync {
    static let refreshTask="com.harrypakhale.nyx.refresh"
    private var running=false
    /// A run asked for while one was under way: it goes when that one ends. Publish-only (no
    /// request) and background only if every run asked for was.
    private var again:(publishOnly:Bool,background:Bool)?
    /// The saved parks, once a window has read them (or, in a background launch, from the widget's snapshot).
    private(set) var parkIDs:[String]?
    /// The palette the widget's Moon pictures are drawn in; the window keeps it current.
    var palette=NyxPalette(nightVision:false,highContrast:false)
    /// Whether the watch's "Update from iPhone" is answered with this model yet (`listenToWatch`).
    private var listening=false
    /// The places Home Screen widgets and the Tonight control are set to, as the last run read them (`widgetPlaces`).
    private var widgetIDs:[String]?
    /// What the widget, the watch and reminders were last handed, as `FollowedData` sees it.
    private var published:FollowedData?
    /// A republish waiting for changes made outside a run to settle (`noteChange`).
    private var settling:Task<Void,Never>?
    /// Something changed in the model while a run was under way (`noteChange`).
    private var changedDuringRun=false
    /// Writes the widgets' snapshot off the main actor, in the order asked.
    private let writer=SnapshotWriter()
    /// The watch session is set up at launch, as WatchConnectivity asks, so a watch's request that
    /// launched Nyx in the background is heard; it is answered once a run knows the model.
    init() { if DebugScenario.screen == nil, WatchBridge.isAvailable { WatchBridge.shared.activate() } }

    /// A window's run (the main window's `RootView`, or Assistive Access's): its saved spots and parks
    /// as the store holds them now. However many windows ask, the work is done once per process.
    func update(_ model:PlanModel,saved:[SavedPark],spots:[SavedSpot]) async {
        model.setSpots(spots)
        await update(model,parkIDs:saved.map(\.parkID))
    }
    /// `background`: a run iOS gave about 30 seconds (`backgroundRefresh`). `publishOnly`: what is
    /// cached is published again with no request (`republish`).
    func update(_ model:PlanModel,parkIDs ids:[String]?=nil,background:Bool=false,publishOnly:Bool=false) async {
        guard DebugScenario.screen == nil else { return }
        Self.loadSpotsIfNeeded(model)
        listenToWatch(model)
        // When the store could not open, the windows read their saved parks from an empty stand-in.
        // That empty list must never reach the widget, the watch or reminders: the parks of the last
        // snapshot stay, and their forecasts keep being refreshed.
        if model.journalUnavailable { if parkIDs == nil { parkIDs=SharedSettings.read()?.parks.map(\.id) } }
        else if let ids { parkIDs=ids }
        guard let current=parkIDs else { return }
        guard !running else {
            again=(publishOnly:(again?.publishOnly ?? true) && publishOnly,background:(again?.background ?? true) && background)
            return
        }
        running=true
        changedDuringRun=false
        // A widget set to a park is followed as a saved park is: its clouds are fetched and carried.
        if !publishOnly || widgetIDs == nil { widgetIDs=await Self.widgetPlaces() }
        // A followed world catalogue place (`wd:`) resolves only once the catalogue is read; it is
        // never dropped from the widget, the watch or reminders for having been asked too early.
        if followedIDs(model).contains(where:{ $0.hasPrefix(Park.catalogPrefix) }) { await model.catalogReady() }
        // "Tonight" as of now, even in a background launch whose model last looked at the clock hours ago.
        model.tick()
        // Never a snapshot from before the launch's cache reads land (`PlanModel.cachesPending`).
        await model.cachesReady()
        defer {
            running=false
            var queued=again
            // Something a followed place shows changed during the run without being handed over (a
            // park's page asking for its smoke while alerts were read): it follows from the cache.
            if queued == nil, followedData(model) != published { queued=(publishOnly:true,background:background) }
            if let next=Self.followUp(queued,cancelled:Task.isCancelled) { Task { await update(model,background:next.background,publishOnly:next.publishOnly) } }
            // A change made during the run at a place followed only by a Live Activity: it catches up from the cache.
            else if changedDuringRun, !FieldActivities.Item.activities.isEmpty { Task { await Self.refreshFollowed(model) } }
            changedDuringRun=false
            again=nil
        }
        let parks=current.compactMap { model.park($0) }
        await publish(model,parks)
        if publishOnly { return }
        // The widget and reminders need only forecasts; park alerts follow once they are done,
        // so a quick visit still leaves both up to date. Every followed place's clouds are asked
        // for: the starting park and Tonight's answer abroad too, which the parks' request leaves out.
        let started=ContinuousClock.now
        await model.refreshForecasts(watching:followed(model))
        // A followed night's Live Activity follows the new forecast: with the widget when that is
        // published again, else on its own (a night can be followed at a place nothing else follows).
        if again == nil, followedData(model) != published { await publish(model,parks) }
        else { await Self.refreshFollowed(model) }
        // In the background, alerts wait for the next run when time is up or the forecasts were
        // slow, and ask for one page only; the next refresh was already requested.
        if background, Task.isCancelled || ContinuousClock.now-started>Self.alertsAfter { return }
        let closures=Self.closures(model)
        await model.refreshParkUpdates(parks,alertPages:background ? 1 : ParkStore.alertPages)
        // A new closure reaches the widget's snapshot (and the watch) without waiting for the next refresh.
        // Reminders too: a pending one names the closure (or stops naming it) before it fires.
        if again == nil, Self.closures(model) != closures {
            // What is published is what the snapshot was built from: a change landing during the write is still seen as new.
            let data=followedData(model), snapshot=await writeSnapshot(model,parks); pushWatch(model); published=data; await Self.refreshFollowed(model)
            await remind(model,snapshot)
        }
        Self.scheduleRefresh()
    }
    /// The run that follows one that ends with `queued` asked for meanwhile. A run cut short
    /// (background time ran out, its window closed) starts no new requests: the next opening of Nyx
    /// runs them. What was queued is still published from the cache, though, as a republish asks:
    /// switching "Smoke and haze" off during a run must not leave the widget and the watch with the
    /// old scores until then.
    nonisolated static func followUp(_ queued:(publishOnly:Bool,background:Bool)?,cancelled:Bool)->(publishOnly:Bool,background:Bool)? {
        guard let queued else { return nil }
        return cancelled ? (publishOnly:true,background:queued.background) : queued
    }
    /// The system's background refresh: saved-park clouds (and alerts when due), the widget's
    /// snapshot, the watch and reminders, then the next request about six hours on. Same hosts and
    /// the same requests as in the app; nothing about the person is sent.
    /// iOS allows about 30 seconds: the run stops at `backgroundBudget`, and the next request is
    /// made first, so a run cut short still leaves one.
    func backgroundRefresh(_ model:PlanModel) async {
        Self.scheduleRefresh()
        // Nothing outside the app shows a forecast: no request at all (each parks request is 63 of
        // Open-Meteo's counted calls). The next open refreshes as usual.
        guard await Self.anythingOutsideTheApp() else { return }
        if parkIDs == nil { parkIDs=SharedSettings.read()?.parks.map(\.id) }
        model.tick()
        await Self.run(within:Self.backgroundBudget) {
            await self.update(model,background:true)
            // A followed night's Live Activity catches up too: its next moment, or its end at dawn.
            if !Task.isCancelled { await Self.refreshFollowed(model) }
        }
    }
    /// Whether a background refresh has anyone to serve: reminders, a Nyx widget, a followed night's
    /// Live Activity or the watch. Unsure counts as yes (a widget list that cannot be read, a watch
    /// session not yet active), so a person who relies on one never misses a refresh.
    static func anythingOutsideTheApp() async -> Bool {
        if UserDefaults.standard.bool(forKey:"notificationsEnabled") { return true }
        if !FieldActivities.Item.activities.isEmpty { return true }
        if WCSession.isSupported() {
            let session=WCSession.default
            if session.activationState != .activated || (session.isPaired && session.isWatchAppInstalled) { return true }
        }
        guard let widgets=try? await WidgetCenter.shared.currentConfigurations() else { return true }
        return !widgets.isEmpty
    }
    /// Brings followed nights' Live Activities up to date with what Nyx knows now: each night's
    /// score and band from the latest forecasts, and its park's closure line once alerts are read.
    static func refreshFollowed(_ model:PlanModel) async {
        await FieldActivities.refresh(nightVision:SharedSettings.defaults.bool(forKey:"nightVision")) { attributes in
            guard let park=model.park(attributes.parkID) else { return nil }
            return FieldActivities.Now(night:model.night(park,on:attributes.nightID ?? park.evening(attributes.dusk)),closure:model.closure(park),
                                       closureKnown:model.enrichments[park.id] != nil)
        }
    }
    static let backgroundBudget:Duration = .seconds(20)
    /// Forecasts slower than this leave park alerts to the next background run.
    static let alertsAfter:Duration = .seconds(10)
    /// Runs `work`, cancelling it once `limit` has passed. True when it finished in time.
    @discardableResult static func run(within limit:Duration,_ work:@escaping @MainActor @Sendable ()async->Void) async -> Bool {
        await withTaskGroup(of:Bool.self) { group in
            group.addTask { await work(); return true }
            group.addTask { try? await Task.sleep(for:limit); return false }
            let finished=await group.next() ?? false
            group.cancelAll()
            return finished
        }
    }
    /// Asks iOS for the next background refresh, about six hours from now (iOS decides when).
    static func scheduleRefresh(after delay:TimeInterval=6*3600,now:Date = .now) {
        let request=BGAppRefreshTaskRequest(identifier:refreshTask)
        request.earliestBeginDate=now.addingTimeInterval(delay)
        // Unavailable in the simulator and when Background App Refresh is off; the app then refreshes on open.
        try? BGTaskScheduler.shared.submit(request)
    }
    /// The places whose forecasts and closures the widget, the watch and reminders carry, in order and
    /// once each: the saved places, the starting park, Tonight's answer on this iPhone, the places
    /// Apple Watch asked for (its kept park and its complications'), then the parks widgets and the
    /// Tonight control are set to. Every surface that shows one of them scores it from the same data.
    nonisolated static func followedIDs(saved:[String],home:String,tonight:String?,watch:[String],widgets:[String])->[String] {
        var seen=Set<String>()
        return (WatchContext.followed(saved:saved,home:home,tonight:tonight,watch:watch)+widgets).filter { !$0.isEmpty && seen.insert($0).inserted }
    }
    func followedIDs(_ model:PlanModel)->[String] {
        Self.followedIDs(saved:parkIDs ?? [],home:model.homeID,tonight:model.tonightPick,watch:WatchBridge.requestedParkIDs,widgets:widgetIDs ?? [])
    }
    func followed(_ model:PlanModel)->[Park] { followedIDs(model).compactMap { model.park($0) } }
    func followedData(_ model:PlanModel)->FollowedData {
        FollowedData(ids:followedIDs(model),forecasts:model.forecasts,details:model.details,closures:Self.closures(model),aurora:model.aurora?.updated)
    }
    /// The parks the Tonight's sky widgets and the Tonight control are set to; empty when none is
    /// set or the system cannot say (a "darkest saved park" widget follows the saved parks anyway).
    static func widgetPlaces() async -> [String] {
        guard DebugScenario.screen == nil else { return [] }
        let widgets=(try? await WidgetCenter.shared.currentConfigurations()) ?? []
        let controls=(try? await ControlCenter.shared.currentControls()) ?? []
        return widgets.compactMap { $0.widgetConfigurationIntent(of:TonightWidgetIntent.self)?.park?.id }
            + controls.compactMap { $0.configurationIntent(of:TonightControlIntent.self)?.park?.id }
    }
    /// Forecasts, smoke, summit layers, closures or the followed places changed in the model. A run
    /// hands over its own changes; outside one (a pull to refresh on Tonight or Parks, a park's page
    /// asking for its smoke and summit layers, a new answer on Tonight) the widget, the watch and
    /// reminders follow from the cache once the changes settle, when anything a followed place
    /// shows is new. Never a request.
    /// A night can be followed at any place, not only a followed one: when nothing the widget shows
    /// changed, the Live Activities are still brought up to date (each is updated only if it changed).
    func noteChange(_ model:PlanModel) {
        guard DebugScenario.screen == nil else { return }
        guard !running else { changedDuringRun=true; return }
        settling?.cancel()
        settling=Task { [weak self, weak model] in
            try? await Task.sleep(for:Self.settleDelay)
            guard !Task.isCancelled, let self, let model else { return }
            guard !self.running else { self.changedDuringRun=true; return }
            if self.parkIDs != nil, self.followedData(model) != self.published { await self.republish(model) }
            else if !FieldActivities.Item.activities.isEmpty { await Self.refreshFollowed(model) }
        }
    }
    static let settleDelay:Duration = .seconds(1.5)
    /// Every park's closure from the last park update, not only the saved parks': a widget or the
    /// control can be set to any park, and following a night works for any park.
    private static func closures(_ model:PlanModel)->[String:String] {
        Dictionary(model.parks.compactMap { park in model.closure(park).map { (park.id,$0) } },uniquingKeysWith:{ first,_ in first })
    }
    /// Writes the snapshot (off the main actor, in order: `SnapshotWriter`) and, once written and only
    /// when it says something new (or new Moon pictures were drawn), reloads the widgets and the
    /// Tonight control once and refreshes the Smart Stack's hints.
    @discardableResult private func writeSnapshot(_ model:PlanModel,_ parks:[Park],moonsDrawn:Bool=false) async -> SavedSkySnapshot {
        let snapshot=Self.snapshot(parks:parks,followed:followed(model),bundled:model.parks,forecasts:model.forecasts,details:model.details,closures:Self.closures(model),closuresUpdated:model.alertsUpdated)
        if await writer.write(snapshot) || moonsDrawn {
            WidgetCenter.shared.reloadAllTimelines()
            ControlCenter.shared.reloadControls(ofKind:WidgetSelection.controlKind)
            // The Smart Stack's dusk hints come from the same snapshot; a timeline reload alone may not refresh them.
            WidgetCenter.shared.invalidateRelevance(ofKind:WidgetSelection.kind)
        }
        return snapshot
    }
    /// The widgets' snapshot: the saved places (which "darkest saved place" weighs and reminders
    /// read), with the forecasts and detail of every followed place, so a widget or the control set
    /// to a park that is not saved scores it from the same forecast the app does. Saved spots and
    /// world places carry their usual clouds from the grid, which the widgets do not bundle.
    /// `bundled`: every one of the 63 parks also carries its clouds and what its score reads of the
    /// detail (`scoring`), followed or not: a widget or the control newly set to a park is read by
    /// the app only on its next run (`widgetPlaces`), and until then must not score without a
    /// forecast the app has. About 12 KB a park, 0.8 MB for all 63 (about 30 ms to decode on a Mac).
    nonisolated static func snapshot(parks:[Park],followed:[Park],bundled:[Park]=[],forecasts:[String:Forecast],details:[String:ForecastDetail],
                                     closures:[String:String],closuresUpdated:Date?=nil)->SavedSkySnapshot {
        let ids=Set((parks+followed).map(\.id))
        var carried=forecasts.filter { ids.contains($0.key) }, detail=details.filter { ids.contains($0.key) }
        for park in bundled where !ids.contains(park.id) {
            carried[park.id]=forecasts[park.id]
            detail[park.id]=details[park.id].flatMap { scoring($0,summit:park.aboveInversion == true) }
        }
        return SavedSkySnapshot(parks:parks,forecasts:carried,details:detail,closures:closures,
                                usualClouds:CloudClimate.shared.carriedMonths(for:parks+followed),closuresUpdated:closuresUpdated)
    }
    /// Only what `NightPlanner.night` reads of a park's detail: the three models' clouds (which break
    /// ties), the aerosol (smoke) and, at a summit above the inversion, its mid and high cloud. Nil
    /// with none of them. Wind, cold, dew and particulates are shown only in the app and reminders.
    nonisolated static func scoring(_ detail:ForecastDetail,summit:Bool)->ForecastDetail? {
        func keep(_ series:HourlySeries?,_ keys:[String])->HourlySeries? {
            guard let series else { return nil }
            let values=series.values.filter { keys.contains($0.key) }
            return values.isEmpty ? nil : HourlySeries(updated:series.updated,times:series.times,values:values)
        }
        let trimmed=ForecastDetail(models:keep(detail.models,ForecastDetail.modelKeys),layers:summit ? keep(detail.layers,["cloud_cover_mid","cloud_cover_high"]) : nil,
                                   air:keep(detail.air,["aerosol_optical_depth"]))
        return trimmed.models == nil && trimmed.layers == nil && trimmed.air == nil ? nil : trimmed
    }
    /// Publishes what is cached again, with no request: after a change that alters scores without
    /// new data (switching "Smoke and haze" off).
    /// One run at a time, as any update: a republish asked for during a run follows it.
    func republish(_ model:PlanModel) async {
        guard parkIDs != nil else { return }
        await update(model,publishOnly:true)
    }
    /// Hands Apple Watch the saved parks (or, with the journal unavailable, the last snapshot's),
    /// the starting park, clouds, smoke and summit layers, closures and the models' ranges. Nothing is
    /// worked out where no watch can pair (iPad); the ranges, which score each followed park's week
    /// again, only once a paired watch with Nyx is known (until then the bridge asks for them when
    /// one is); nothing is sent when nothing changed since the last hand-over or no watch is paired.
    /// Saved spots and world catalogue places travel whole (`WatchContext.places`): the watch bundles neither.
    /// `watchSeen`: the bridge has just seen a paired watch with Nyx, so the ranges are worked out
    /// whatever the session reported a moment ago (and the bridge is never asked to call back again).
    func pushWatch(_ model:PlanModel,watchSeen:Bool=false) {
        Self.loadSpotsIfNeeded(model)
        listenToWatch(model)
        // A background launch (Control Center's night vision, a watch's request) pushes before any
        // update has run: the saved parks the widgets last had stand in, as in `answerWatch`.
        if parkIDs == nil { parkIDs=SharedSettings.read()?.parks.map(\.id) }
        guard let ids=parkIDs, WatchBridge.isAvailable else { return }
        let asked=WatchBridge.requestedParkIDs
        // A followed catalogue place goes to the watch whole, so the catalogue must be read first:
        // until then the hand-over waits rather than leaving the place out.
        if !model.catalogIsReady, (ids+[model.homeID]+(model.tonightPick.map { [$0] } ?? [])+asked).contains(where:{ $0.hasPrefix(Park.catalogPrefix) }) {
            Task { [weak self, weak model] in
                await model?.catalogReady()
                if let self, let model { self.pushWatch(model,watchSeen:watchSeen) }
            }
            return
        }
        // Tonight's answer and the watch's own places travel only when this iPhone knows them.
        // Only while the night it was picked for is still tonight there (`PlanModel.tonightPick`).
        let tonight=model.tonightPick.flatMap { model.park($0)?.id }, watchIDs=asked.filter { model.park($0) != nil }
        let all=WatchContext.followed(saved:ids,home:model.homeID,tonight:tonight,watch:watchIDs)
        let bridge=WatchBridge.shared, watch=watchSeen || bridge.hasWatchApp
        let ranges:[String:[String:ClosedRange<Int>]]?=watch ? Self.modelRanges(model,ids:all) : nil
        // Always handed over: the bridge keeps it only when it cannot send now (no ranges yet, or the
        // watch turned out unpaired after all), and runs it once a watch with Nyx is there.
        let complete:@MainActor @Sendable ()->Void={ [weak self, weak model] in if let self, let model { self.pushWatch(model,watchSeen:true) } }
        bridge.push(savedParkIDs:ids,homeParkID:model.homeID,tonightParkID:tonight,tonightNight:tonight == nil ? nil : model.tonightPickNight,watchParkIDs:watchIDs,forecasts:model.forecasts,details:model.details,closures:Self.closures(model),
                    aboveInversion:Set(model.parks.filter { $0.aboveInversion == true }.map(\.id)),ranges:ranges,
                    places:all.compactMap { model.park($0) }.filter { $0.isSavedSpot || $0.isCatalogPlace },aurora:model.aurora,complete:complete)
    }
    /// A launch with no window yet (a background refresh, a watch's request, Control Center) has had
    /// no window hand the model its saved spots (`RootView`): they are read from the store here, so a
    /// followed spot keeps its place in the widget, the watch and reminders. Windows keep them current after.
    static func loadSpotsIfNeeded(_ model:PlanModel) {
        guard model.spots.isEmpty, !model.journalUnavailable, DebugScenario.screen == nil, let container=JournalAccess.container,
              let records=try? container.mainContext.fetch(FetchDescriptor<SavedSpot>()), !records.isEmpty else { return }
        model.setSpots(records)
    }
    /// Answers Apple Watch's "Update from iPhone" with this model from now on (once per process).
    func listenToWatch(_ model:PlanModel) {
        guard !listening, DebugScenario.screen == nil, WatchBridge.isAvailable else { return }
        listening=true
        WatchBridge.shared.listen { [weak self, weak model] in
            guard let self, let model else { return }
            Task { await self.answerWatch(model) }
        }
    }
    /// The watch asked for its context: the same run as opening Nyx (saved parks' clouds when
    /// forecasts are on, then the widget, the watch and reminders), with the hand-over sent even if
    /// unchanged (`WatchBridge` cleared its record). Woken in the background by the request, the
    /// run asks iOS for time and keeps to `backgroundBudget`, as a background refresh does.
    func answerWatch(_ model:PlanModel) async {
        if parkIDs == nil { parkIDs=SharedSettings.read()?.parks.map(\.id) }
        let app=UIApplication.shared
        guard app.applicationState == .background else { await update(model); return }
        let task=app.beginBackgroundTask(withName:"Update Apple Watch",expirationHandler:nil)
        await Self.run(within:Self.backgroundBudget) { await self.update(model,background:true) }
        if task != .invalid { app.endBackgroundTask(task) }
    }
    /// The forecast models' range each followed park's dial shows for the week the watch shows
    /// (tonight and six more), keyed by park-local day: only where the iPhone draws one, so only
    /// for parks with forecast detail. Read from the model's outlook cache, which the park page
    /// and the river fill anyway.
    static func modelRanges(_ model:PlanModel,ids:[String])->[String:[String:ClosedRange<Int>]] {
        var ranges:[String:[String:ClosedRange<Int>]]=[:]
        for id in Set(ids) where model.forecasts[id] != nil && model.details[id] != nil {
            guard let park=model.park(id) else { continue }
            for offset in 0..<7 {
                let night=model.night(park,on:park.date(model.tonight(park),addingDays:offset))
                if let range=CelestialGauge.modelRange(model.outlook(night),basis:night.basis) { ranges[id,default:[:]][WatchContext.day(night.id,in:park)]=range }
            }
        }
        return ranges
    }
    private func publish(_ model:PlanModel,_ parks:[Park]) async {
        let moonsDrawn=await renderWidgetMoons(model,parks)
        // Taken as the snapshot is built (before its write suspends), so a change that lands during
        // the write still differs from `published` and is republished when this run ends.
        let data=followedData(model)
        let snapshot=await writeSnapshot(model,parks,moonsDrawn:moonsDrawn)
        // Siri's suggested parks for the App Shortcuts phrases start with the saved ones.
        NyxShortcuts.updateAppShortcutParameters()
        pushWatch(model)
        published=data
        // A followed night's Live Activity says what the widget now says, on every path that publishes.
        await Self.refreshFollowed(model)
        await remind(model,snapshot)
    }
    /// Reminders planned from the snapshot just written: the nights, smoke, layers and closures the
    /// widget shows, so a reminder never says less than the park page.
    private func remind(_ model:PlanModel,_ snapshot:SavedSkySnapshot) async {
        let defaults=UserDefaults.standard
        guard defaults.bool(forKey:"notificationsEnabled") else { return }
        let today=model.today, showers=defaults.object(forKey:"showerReminders") as? Bool ?? true
        let nights=await Task.detached(priority:.utility) { snapshot.nights(from:today,count:14) }.value
        // Reminders may have been switched off while the nights were computed.
        if defaults.bool(forKey:"notificationsEnabled") {
            await NotificationScheduler().reschedule(nights:nights,showers:showers,details:snapshot.details ?? [:],closures:snapshot.closures)
        }
    }
    /// The next week's Moons for each saved park, drawn once each for the widgets, so a widget left
    /// for a week without Nyx being opened still shows the real Moon; past that, its vector Moon.
    static let moonNights=7
    /// True when a picture was drawn that the widgets have not seen. Drawn only with Nyx on
    /// screen: the Moon is a Metal shader, which a background run may not use (a failed draw would
    /// leave a blank picture in place of that night's Moon). One picture at a time, letting the
    /// screen draw in between; a picture that comes back empty is not kept.
    @discardableResult private func renderWidgetMoons(_ model:PlanModel,_ parks:[Park]) async -> Bool {
        let engine=AstronomyEngine()
        var drawn=false
        let visible=UIApplication.shared.applicationState != .background
        // Drawn in starlight: the widget turns its own pictures red in night vision, so a picture
        // drawn red would stay red once night vision is off.
        let neutral=NyxPalette(nightVision:false,highContrast:palette.highContrast)
        var keep=Set<String>()
        for park in parks {
            for offset in 0..<Self.moonNights {
                let night=model.night(park,on:park.date(model.tonight(park),addingDays:offset))
                guard let url=SharedSettings.moonImageURL(park:park.id,night:night.id) else { continue }
                keep.insert(url.lastPathComponent)
                guard visible, !FileManager.default.fileExists(atPath:url.path) else { continue }
                await Task.yield()
                let renderer=ImageRenderer(content:MoonView(geometry:engine.moon(for:night).geometry).frame(width:60,height:60).environment(\.nyx,neutral))
                renderer.scale=3
                guard let image=renderer.uiImage, let cgImage=image.cgImage, Self.drawn(cgImage), let png=image.pngData() else { continue }
                if (try? png.write(to:url,options:.atomic)) != nil { drawn=true }
            }
        }
        // Forget pictures of nights that have passed or parks no longer saved.
        if let folder=SharedSettings.moonImageURL(park:"x",night:.now)?.deletingLastPathComponent(),
           let files=try? FileManager.default.contentsOfDirectory(atPath:folder.path) {
            for file in files where file.hasPrefix("moon-") && !keep.contains(file) { try? FileManager.default.removeItem(at:folder.appendingPathComponent(file)) }
        }
        return drawn
    }
    /// The picture's centre is not transparent: the disc is drawn on an opaque square, so a draw
    /// that failed comes back clear there.
    nonisolated static func drawn(_ image:CGImage)->Bool {
        var pixel=[UInt8](repeating:0,count:4)
        return pixel.withUnsafeMutableBytes { buffer in
            guard let context=CGContext(data:buffer.baseAddress,width:1,height:1,bitsPerComponent:8,bytesPerRow:4,space:CGColorSpaceCreateDeviceRGB(),
                                        bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            // The image's centre pixel lands on the one-pixel canvas.
            context.draw(image,in:CGRect(x:-CGFloat(image.width/2),y:-CGFloat(image.height/2),width:CGFloat(image.width),height:CGFloat(image.height)))
            return buffer[3]>0
        }
    }
}

/// What the widget, the watch and reminders show of each followed place, reduced to when each part
/// was issued: the clouds, the models, the cloud layers, the smoke, and the closure, and when the
/// aurora forecast the watch's What's up reads was received. Two moments
/// with the same value would hand over the same thing; any new forecast or detail, a closure, or a
/// change in which places are followed makes it differ.
nonisolated struct FollowedData:Equatable,Sendable {
    nonisolated struct Stamp:Equatable,Sendable {
        var clouds:Date?
        var models:Date?
        var layers:Date?
        var air:Date?
        var closure:String?
    }
    let ids:[String]
    let stamps:[Stamp]
    var aurora:Date?=nil
    init(ids:[String],forecasts:[String:Forecast],details:[String:ForecastDetail],closures:[String:String],aurora:Date?=nil) {
        self.ids=ids; self.aurora=aurora
        stamps=ids.map { id in
            let detail=details[id]
            return Stamp(clouds:forecasts[id]?.updated,models:detail?.models?.updated,layers:detail?.layers?.updated,air:detail?.air?.updated,closure:closures[id])
        }
    }
}
