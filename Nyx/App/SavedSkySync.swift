import BackgroundTasks
import SwiftUI
import WidgetKit

/// Brings the widget, the watch, Siri's park list and reminders in line with the saved parks. One
/// per process (owned by `PlanModel`), so two iPad windows never run it twice. It publishes from
/// what is cached first, so unsaving a park or switching shower reminders off takes effect at once
/// even on a weak signal, then again once fresh forecasts arrive. A change made while a run is under
/// way is never dropped: the run goes again when it ends.
@MainActor final class SavedSkySync {
    static let refreshTask="com.harrypakhale.nyx.refresh"
    private var running=false
    private var again=false
    /// The saved parks, once a window has read them (or, in a background launch, from the widget's snapshot).
    private(set) var parkIDs:[String]?
    /// The palette the widget's Moon pictures are drawn in; the window keeps it current.
    var palette=NyxPalette(nightVision:false,highContrast:false)

    /// `background`: a run iOS gave about 30 seconds (`backgroundRefresh`).
    func update(_ model:PlanModel,parkIDs ids:[String]?=nil,background:Bool=false) async {
        guard DebugScenario.screen == nil else { return }
        // When the store could not open, the windows read their saved parks from an empty stand-in.
        // That empty list must never reach the widget, the watch or reminders: the parks of the last
        // snapshot stay, and their forecasts keep being refreshed.
        if model.journalUnavailable { if parkIDs == nil { parkIDs=SharedSettings.read()?.parks.map(\.id) } }
        else if let ids { parkIDs=ids }
        guard let current=parkIDs else { return }
        guard !running else { again=true; return }
        running=true
        // "Tonight" as of now, even in a background launch whose model last looked at the clock hours ago.
        model.tick()
        defer {
            running=false
            // A run cut short (background time ran out) does not start another: the next opening of Nyx runs one.
            if again { again=false; if !Task.isCancelled { Task { await update(model) } } }
        }
        let parks=current.compactMap { model.park($0) }
        let ids=Set(parks.map(\.id))
        let cached=model.forecasts.filter { ids.contains($0.key) }.mapValues(\.updated)
        await publish(model,parks)
        // The widget and reminders need only forecasts; park alerts follow once they are done,
        // so a quick visit still leaves both up to date.
        let started=ContinuousClock.now
        await model.refreshForecasts(watching:parks)
        if !again, model.forecasts.filter({ ids.contains($0.key) }).mapValues(\.updated) != cached { await publish(model,parks) }
        // A followed night's Live Activity follows the new forecast.
        await Self.refreshFollowed(model)
        // In the background, alerts wait for the next run when time is up or the forecasts were
        // slow, and ask for one page only; the next refresh was already requested.
        if background, Task.isCancelled || ContinuousClock.now-started>Self.alertsAfter { return }
        let closures=Self.closures(model)
        await model.refreshParkUpdates(parks,alertPages:background ? 1 : ParkStore.alertPages)
        // A new closure reaches the widget's snapshot (and the watch) without waiting for the next refresh.
        if !again, Self.closures(model) != closures { writeSnapshot(model,parks); pushWatch(model); await Self.refreshFollowed(model) }
        Self.scheduleRefresh()
    }
    /// The system's background refresh: saved-park clouds (and alerts when due), the widget's
    /// snapshot, the watch and reminders, then the next request about six hours on. Same hosts and
    /// the same requests as in the app; nothing about the person is sent.
    /// iOS allows about 30 seconds: the run stops at `backgroundBudget`, and the next request is
    /// made first, so a run cut short still leaves one.
    func backgroundRefresh(_ model:PlanModel) async {
        Self.scheduleRefresh()
        if parkIDs == nil { parkIDs=SharedSettings.read()?.parks.map(\.id) }
        model.tick()
        await Self.run(within:Self.backgroundBudget) {
            await self.update(model,background:true)
            // A followed night's Live Activity catches up too: its next moment, or its end at dawn.
            if !Task.isCancelled { await Self.refreshFollowed(model) }
        }
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
    /// Every park's closure from the last park update, not only the saved parks': a widget or the
    /// control can be set to any park, and following a night works for any park.
    private static func closures(_ model:PlanModel)->[String:String] {
        Dictionary(model.parks.compactMap { park in model.closure(park).map { (park.id,$0) } },uniquingKeysWith:{ first,_ in first })
    }
    /// Writes the snapshot and, only when it says something new (or new Moon pictures were drawn),
    /// reloads the widgets and the Tonight control once and refreshes the Smart Stack's hints.
    @discardableResult private func writeSnapshot(_ model:PlanModel,_ parks:[Park],moonsDrawn:Bool=false)->SavedSkySnapshot {
        let ids=Set(parks.map(\.id))
        let snapshot=SavedSkySnapshot(parks:parks,forecasts:model.forecasts.filter { ids.contains($0.key) },details:model.details.filter { ids.contains($0.key) },closures:Self.closures(model))
        if SharedSettings.write(snapshot) || moonsDrawn {
            WidgetCenter.shared.reloadAllTimelines()
            ControlCenter.shared.reloadControls(ofKind:WidgetSelection.controlKind)
            // The Smart Stack's dusk hints come from the same snapshot; a timeline reload alone may not refresh them.
            WidgetCenter.shared.invalidateRelevance(ofKind:WidgetSelection.kind)
        }
        return snapshot
    }
    /// Publishes what is cached again, with no request: after a change that alters scores without
    /// new data (switching "Smoke and haze" off).
    func republish(_ model:PlanModel) async {
        guard DebugScenario.screen == nil, let ids=parkIDs else { return }
        await publish(model,ids.compactMap { model.park($0) })
    }
    /// Hands Apple Watch the saved parks (or, with the journal unavailable, the last snapshot's),
    /// the starting park, clouds, smoke and summit layers, closures and the models' ranges. Nothing is
    /// worked out where no watch can pair (iPad), and nothing is sent when nothing changed since the
    /// last hand-over or no watch is paired.
    func pushWatch(_ model:PlanModel) {
        guard let ids=parkIDs, WatchBridge.isAvailable else { return }
        WatchBridge.shared.push(savedParkIDs:ids,homeParkID:model.homeID,forecasts:model.forecasts,details:model.details,closures:Self.closures(model),
                                aboveInversion:Set(model.parks.filter { $0.aboveInversion == true }.map(\.id)),
                                ranges:Self.modelRanges(model,ids:ids+[model.homeID]))
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
        let snapshot=writeSnapshot(model,parks,moonsDrawn:moonsDrawn)
        // Siri's suggested parks for the App Shortcuts phrases start with the saved ones.
        NyxShortcuts.updateAppShortcutParameters()
        pushWatch(model)
        let defaults=UserDefaults.standard
        guard defaults.bool(forKey:"notificationsEnabled") else { return }
        let today=model.today, showers=defaults.object(forKey:"showerReminders") as? Bool ?? true
        let nights=await Task.detached(priority:.utility) { snapshot.nights(from:today,count:14) }.value
        // Reminders may have been switched off while the nights were computed.
        if defaults.bool(forKey:"notificationsEnabled") { await NotificationScheduler().reschedule(nights:nights,showers:showers,details:snapshot.details ?? [:]) }
    }
    /// The next week's Moons for each saved park, drawn once each for the widgets, so a widget left
    /// for days without Nyx being opened still shows the real Moon (`MoonImages.nearest`).
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
