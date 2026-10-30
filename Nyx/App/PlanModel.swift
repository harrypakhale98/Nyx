import Foundation
import Observation

@MainActor @Observable final class PlanModel {
    /// The catalogue: the bundled places, the same for everyone. Saved spots are never in it (`spots`).
    let parks: [Park]
    /// Each park's place in `parks` (the first, should an id repeat), for `park(_:)`.
    private let parkIndex: [String:Int]
    /// The places the person saved themselves (`SavedSpot`), scored, forecast and followed like
    /// parks. Set from the store by `setSpots`; `park(_:)` finds them by their `pin:` id.
    private(set) var spots: [Park] = []
    @ObservationIgnored private var spotIndex: [String:Int] = [:]
    /// Plan's best nights with the key they were ranked for (`BestNightsView`), so a return to the
    /// page, or a switch between Plan's modes, shows them again without ranking every night again.
    @ObservationIgnored var bestNightsKept:(key:String,ranking:BestNightsInReach)?
    /// Every place Nyx scores here: the catalogue, then the saved spots.
    var places: [Park] { parks+spots }
    /// The world catalogue (`catalog.json`): national parks worldwide and certified dark-sky places,
    /// never one of the 63 curated parks. Empty until `prepareCatalog` has read it off the main thread
    /// (it starts at launch); screens simply show more once it is ready, and never wait for it.
    private(set) var catalog: [Park] = []
    /// The catalogue's lookup, spatial index, search terms and forecast regions, built with it.
    @ObservationIgnored private var placeCatalog=PlaceCatalog.empty
    @ObservationIgnored private var catalogTask: Task<Void,Never>?
    /// True once the catalogue has been read (even if it came back empty). Observed, so a screen that
    /// waits for the world abroad (Tonight's loader, the Parks list's skeleton rows) moves on when it arrives.
    private(set) var catalogIsReady=false
    /// The curated parks' folded search terms, made on the first search.
    @ObservationIgnored private var curatedTerms: [PlaceCatalog.Terms]?
    let loadError: Bool
    private let astronomy: any AstronomyProviding
    private let scoring: any ScoreProviding
    private let weather: any WeatherProviding
    private let parkStore: any ParkProviding
    private let detailService: any DetailProviding
    private let auroraService: AuroraService
    /// NOAA's Kp forecast, for aurora under What's up (`AuroraForecast.item`); nil with "Aurora
    /// forecast" off, offline with no copy, or a copy over a day old. A new one redoes What's up.
    var aurora: AuroraOutlook? {
        didSet {
            guard aurora != oldValue else { return }
            skyCache.removeAll()
            // The watch's What's up reads the same forecast: hand it over once things settle.
            savedSync.noteChange(self)
        }
    }
    @ObservationIgnored private var conditions: [String: [Date:SkyConditions]] = [:]
    var forecasts: [String:Forecast] = [:] { didSet { forecastsChanged() } }
    /// Model agreement, cloud layers, cold, dew, wind and smoke. Context only; never in the score.
    /// With "Smoke and haze" off in Your privacy, the air-quality host's data is not used at all:
    /// no aerosol series is kept here, so no score, caveat or snapshot counts cached smoke.
    var details: [String:ForecastDetail] = [:] {
        didSet {
            if !smokeEnabled, details.values.contains(where:{ $0.air != nil }) { details=Self.withoutAir(details) }
            forecastsChanged()
        }
    }
    /// Everything worked out from the forecasts and their detail is let go when either changes.
    /// The widget, the watch and reminders follow too, once the changes settle (`SavedSkySync.noteChange`).
    private func forecastsChanged() { outlookCache=[:]; nightMemo=[:]; journalScores=[:]; dataRevision+=1; savedSync.noteChange(self); updateHindsight() }
    /// Counts every change to what a score or its caveats rest on: forecasts, their detail (smoke,
    /// layers, models) and closures. A screen that keeps a result worked out from them (the trip
    /// plan) works it out again when this moves, so it never disagrees with the calendar or a park's page.
    private(set) var dataRevision=0
    /// Outlooks already derived, so a river scrub does not rescan every hour of 30 nights per frame.
    /// Kept with which of the detail's series were recent (`ages`): one that turns 36 hours old drops out on the next read.
    /// And with what it read from its night (`OutlookKey`): a view can still hold a night scored before
    /// the latest forecast or smoke (the toolbar's share menu, redrawn before the page hands it the new
    /// night), and that night's outlook must never be the one the current night is shown with.
    @ObservationIgnored private var outlookCache: [String:[Date:(key:OutlookKey,outlook:NightOutlook?)]] = [:]
    nonisolated private struct OutlookKey: Equatable, Sendable { let ages:UInt8; let score:Int; let hasForecast:Bool; let upperCloudOnly:Bool; let aerosol:Double? }
    /// Nights already scored, by park and evening: the park list and a month ask for the same
    /// nights many times a pass. A night is a pure function of its park, sky, forecast, detail and
    /// scoring; "now" enters only as whether the model spread is recent (`HourlySeries.usable`),
    /// kept beside each night and checked on every read, and as "not yet" or "unavailable"
    /// (`NightPlanner.beyondForecast`, which moves with the forecast's age), worked out again on
    /// every read: no astronomy, so cheap. Cleared whenever forecasts or detail change.
    @ObservationIgnored private var nightMemo: [String:[Date:(recent:Bool,night:Night)]] = [:]
    /// Each park's tonight for the moment it was judged from (`today`), with its evening.
    @ObservationIgnored private var tonightMemo: [String:(at:Date,park:Park,night:Date,evening:Date)] = [:]
    /// Journal entries' scores, by entry, night and park (`loggedNights`). The score never reads
    /// "now", so only a change of forecasts or detail clears them.
    @ObservationIgnored private var journalScores: [JournalScoreKey:Int?] = [:]
    nonisolated private struct JournalScoreKey: Hashable, Sendable { let id:UUID; let date:Date; let park:String }
    /// What's up each night. Astronomy only, so never invalidated by a forecast.
    @ObservationIgnored private var skyCache: [SkyKey:WhatsUp] = [:]
    @ObservationIgnored private var eventCache: [SkyKey:WhatsUp.Events] = [:]
    /// A park's night, worded for tonight or not (events ignore the wording: always false).
    /// `aurora`: whether a usable aurora forecast was in hand, so What's up kept from before a
    /// forecast turned a day old is never shown with it.
    nonisolated private struct SkyKey: Hashable, Sendable { let park:String; let night:Date; let isTonight:Bool; var aurora=false }
    /// Parks whose forecast could not be updated on the last attempt, so the UI can say so calmly.
    var staleForecasts: Set<String> = []
    /// Shared by Tonight and Ask Nyx, so both reason from the same starting point.
    let location=LocationService()
    var enrichments: [String:ParkEnrichment] = [:]
    /// Campgrounds for every park, once "Where to stay" has asked (`refreshCampgrounds`).
    var campgrounds: CampgroundsCache?
    /// The journal's store could not be opened; Nyx runs with an empty one in memory and says so on the Journal tab.
    /// Nothing is written to that stand-in (journal entries, saved parks), since it is gone on the next launch.
    var journalUnavailable=false
    /// The store could not be opened and the device is nearly full: the Journal tab asks for space.
    var journalNeedsSpace=false
    /// A `.nyxjournal` opened from Files or another app, waiting for the Journal tab to import it.
    var journalFile:URL?
    /// The journal being read right now; the Inbox sweep leaves it alone until the import ends.
    var importingJournal:URL?
    /// NPS is refusing requests right now (the shared key's quota, or a struggling service).
    var alertsBusy=false
    /// The last forecast detail request was held back by Low Data Mode.
    var detailPausedForLowData=false
    /// Forecast detail (models, layers, smoke) is fetched only once a park's page has been opened
    /// in this session: Tonight and the park list need only clouds, apart from a summit above the
    /// inversion, whose clouds are its layers (`refreshForecasts`).
    @ObservationIgnored private(set) var detailWanted=false
    /// A world catalogue place's page has been opened in this session: from then on smoke is asked
    /// for at catalogue places too, by their tiles, without starting the US parks' detail.
    @ObservationIgnored private var catalogSmokeWanted=false
    @ObservationIgnored private var alertsCache: ParkAlertsCache?
    /// When the park alerts every closure here comes from were fetched; nil before any.
    var alertsUpdated: Date? { alertsCache?.updated }
    /// Each park's ranger programs as last fetched, alerts or no alerts (`rangerPrograms`).
    private var programs: [String:ProgramsCache] = [:]
    /// The cached forecasts and alerts, read off the main actor once at launch.
    @ObservationIgnored private var hydration: Task<Void,Never>?
    /// Keeps the widget, the watch, Siri and reminders in step with the saved parks, once per process.
    @ObservationIgnored let savedSync=SavedSkySync()
    /// When Tonight's candidates were last refreshed, for a refresh on return.
    @ObservationIgnored private(set) var lastRefresh: Date?
    /// The parks' forecast was due but held back: the service asked Nyx to wait, or this iPhone's
    /// request budget was spent (`ForecastRequest`). Read by a refresh's closing line.
    @ObservationIgnored private(set) var forecastsHeldBack=false
    /// Where the settings below are kept: the app's own defaults (tests pass a suite of their own, and
    /// a debug route a scratch one, `DebugScenario.plannerDefaults`, so a capture never touches them).
    @ObservationIgnored let defaults: UserDefaults
    var homeID: String { didSet { defaults.set(homeID,forKey:"homePark") } }
    /// The place Tonight last answered with on this iPhone (the darkest within reach, once a starting
    /// point is chosen), kept across launches with the place's night it was picked for
    /// (`tonightPickNight`). The widgets and Apple Watch follow it while that night is still tonight
    /// (`tonightPick`), so even a background refresh fetches and hands over its clouds.
    @ObservationIgnored var tonightPickID: String? {
        didSet {
            let night=tonightPickID.flatMap { park($0) }.map { $0.isoDay($0.currentNight(at:present)) }
            guard tonightPickID != oldValue || night != tonightPickNight else { return }
            tonightPickNight=night
            defaults.set(tonightPickID,forKey:"tonightPick"); defaults.set(night,forKey:"tonightPickNight")
            savedSync.noteChange(self)
            updateHindsight()
        }
    }
    /// "Looking back" (`Hindsight`): what Nyx said about Tonight's answers, and what the weather models
    /// said afterwards, newest first. Kept on this device in `defaults` ("hindsight").
    var hindsight:[HindsightRecord]=[]
    /// Set once the records are read at launch, so nothing written before then replaces them.
    @ObservationIgnored var hindsightLoaded=false
    /// The place-local night ("2026-10-16") `tonightPickID` was picked for.
    @ObservationIgnored private(set) var tonightPickNight: String?
    /// Tonight's pick while the night it was picked for is still tonight at that place; nil after,
    /// so a days-old answer is never handed on as tonight's. A place not yet loaded (the world
    /// catalogue at launch) keeps its pick until it can be checked.
    var tonightPick: String? {
        guard let id=tonightPickID, let night=tonightPickNight else { return nil }
        guard let park=park(id) else { return id }
        return park.isoDay(park.currentNight(at:present)) == night ? id : nil
    }
    /// A city or town chosen as the starting point (`places.json`). Distances are measured from it
    /// and `homeID` holds the park nearest to it; nil when the starting point is a park.
    var homePlace: StartingPlace? { didSet { defaults.set(homePlace.flatMap { try? JSONEncoder().encode($0) },forKey:"homePlace") } }
    /// Whether a starting point was ever chosen: a park, a place, or "Near me". Until then Tonight
    /// asks, and its answer is labelled an example. Anyone who chose a park before has.
    var startChosen: Bool { didSet { defaults.set(startChosen,forKey:"startChosen") } }
    /// Tonight's reach, as the crow flies, in metres; shown in miles or kilometres by locale (`SearchRadius`).
    var radiusMeters: Double { didSet { SearchRadius.store(radiusMeters,defaults) } }
    var weatherEnabled: Bool { didSet { defaults.set(weatherEnabled,forKey:NetworkService.forecasts.key) } }
    /// Apple Watch says when closures were not checked (`WatchContext.alertsOff`), so it hears the switch at once.
    var npsEnabled: Bool {
        didSet {
            defaults.set(npsEnabled,forKey:NetworkService.alerts.key)
            if npsEnabled != oldValue, DebugScenario.screen == nil { savedSync.pushWatch(self) }
        }
    }
    /// Saved spots' cloud forecasts (`SpotForecast`): a request with each spot's coordinates rounded
    /// to 0.1°, only while Cloud forecasts is on too. Off, spots keep what is cached, then their usual clouds.
    /// Apple Watch says why a spot's clouds stopped (`CloudSource.spotsOff`), so it hears the switch at once.
    var spotForecastsEnabled: Bool {
        didSet {
            defaults.set(spotForecastsEnabled,forKey:SpotForecast.key)
            if spotForecastsEnabled != oldValue, DebugScenario.screen == nil { savedSync.pushWatch(self) }
        }
    }
    /// NOAA's aurora forecast (services.swpc.noaa.gov): one global file, nothing about the person.
    /// Off, the copy here is dropped and nothing is asked.
    var auroraEnabled: Bool {
        didSet {
            defaults.set(auroraEnabled,forKey:NetworkService.aurora.key)
            guard !auroraEnabled, oldValue else { return }
            aurora=nil
            let service=auroraService
            Task { [weak self] in
                await service.forget()
                if let self { await savedSync.republish(self) }
            }
        }
    }
    var smokeEnabled: Bool {
        didSet {
            defaults.set(smokeEnabled,forKey:NetworkService.smoke.key)
            // Switched on, the watch stops saying smoke is not counted (`WatchContext.smokeOff`); off, the republish below tells it.
            if smokeEnabled, !oldValue, DebugScenario.screen == nil { savedSync.pushWatch(self) }
            guard !smokeEnabled, oldValue else { return }
            // Switched off: cached smoke stops counting at once, here and in the cache Siri reads.
            details=Self.withoutAir(details)
            // Smoke that landed in the last moments, waiting to be applied, is dropped too.
            landedDetails=Self.withoutAir(landedDetails)
            let service=detailService
            Task { [weak self] in
                await service.forgetAir()
                // The widgets, the watch and reminders stop counting it too.
                if let self { await savedSync.republish(self) }
            }
        }
    }
    nonisolated static func withoutAir(_ details:[String:ForecastDetail])->[String:ForecastDetail] {
        details.compactMapValues { detail in
            var kept=detail; kept.air=nil
            return kept == ForecastDetail() ? nil : kept
        }
    }
    var today: Date {
        #if DEBUG
        if DebugScenario.state=="polar-night" { return Date(timeIntervalSince1970:1797886800) }
        if DebugScenario.state=="polar" { return Date(timeIntervalSince1970:1782086400) }
        if let fixed=DebugScenario.date { return fixed }
        #endif
        return clock
    }
    /// The present moment for a forecast's age (the 36 hours after which model spread, layers and
    /// smoke stop being described): the real clock, never `today`, which moves only when a night
    /// turns over. Screenshot scenarios with a fixed date keep that date.
    var present: Date {
        #if DEBUG
        if DebugScenario.date != nil || DebugScenario.state=="polar-night" || DebugScenario.state=="polar" { return today }
        #endif
        return presentOverride ?? .now
    }
    /// Tests move the real clock here; nil in the app.
    @ObservationIgnored var presentOverride: Date?
    /// The moment "tonight" is judged from. Advanced only when some park's night turns over
    /// (at its sunrise or local noon), so open screens move on without constant redraws.
    private(set) var clock=Date.now
    #if DEBUG
    /// Tests pin the clock to a night of their choosing, so a result never depends on today's Moon.
    func pinClock(_ date:Date) { clock=date }
    #endif
    func tick(_ now:Date = .now) {
        // A saved spot far from every park (another continent) turns its night over at its own sunrise.
        guard (places+viewedCatalog).contains(where:{ $0.currentNight(at:clock) != $0.currentNight(at:now) }) else { return }
        clock=now
        trimPastNights()
    }
    /// Catalogue places whose night has been asked for: their nights turn over at their own sunrise,
    /// on any continent, so `tick` watches them as it watches the curated parks and the spots.
    private var viewedCatalog:[Park] { tonightMemo.values.map(\.park).filter(\.isCatalogPlace) }
    /// Once a night turns over, the kept astronomy, outlooks and what's-up of nights that have
    /// passed are let go (a screen that shows one again simply works it out again).
    private func trimPastNights() {
        let tonights=Dictionary((places+viewedCatalog).map { ($0.id,tonight($0)) },uniquingKeysWith:{ first,_ in first })
        func current(_ id:String,_ night:Date)->Bool { tonights[id].map { night>=$0 } ?? true }
        for (id,nights) in conditions { conditions[id]=nights.filter { current(id,$0.key) } }
        for (id,nights) in outlookCache { outlookCache[id]=nights.filter { current(id,$0.key) } }
        for (id,nights) in nightMemo { nightMemo[id]=nights.filter { current(id,$0.key) } }
        skyCache=skyCache.filter { current($0.key.park,$0.key.night) }
        eventCache=eventCache.filter { current($0.key.park,$0.key.night) }
    }
    init(astronomy: any AstronomyProviding = AstronomyEngine(), scoring: any ScoreProviding = ScoreEngine(),
         weather: any WeatherProviding = WeatherService(), parkStore: any ParkProviding = ParkStore(),
         detail: any DetailProviding = ForecastDetailService(), aurora: AuroraService = AuroraService(), preload: CachePreload?=nil, defaults: UserDefaults = .standard) {
        let loaded:[Park]
        do { loaded=try ParkData.load(); loadError=false } catch { loaded=[]; loadError=true }
        parks=loaded
        parkIndex=Dictionary(loaded.indices.map { (loaded[$0].id,$0) },uniquingKeysWith:{ first,_ in first })
        self.astronomy=astronomy; self.scoring=scoring; self.weather=weather; self.parkStore=parkStore; self.detailService=detail; self.auroraService=aurora
        self.defaults=defaults
        // Parks opens darkest tonight first: the list answers the app's question before it is asked.
        // (A registered default, in the app's own defaults where `ParksList` reads it: anyone who chose Name keeps it.)
        UserDefaults.standard.register(defaults:["parksByScore":true])
        homeID=defaults.string(forKey:"homePark") ?? Park.defaultID
        homePlace=defaults.data(forKey:"homePlace").flatMap { try? JSONDecoder().decode(StartingPlace.self,from:$0) }
        hindsight=defaults.data(forKey:"hindsight").flatMap { try? JSONDecoder().decode([HindsightRecord].self,from:$0) } ?? []
        hindsightLoaded=true
        tonightPickID=defaults.string(forKey:"tonightPick").flatMap(PlaceIDText.validated)
        tonightPickNight=defaults.string(forKey:"tonightPickNight")
        startChosen=defaults.object(forKey:"startChosen") as? Bool ?? (defaults.string(forKey:"homePark") != nil)
        // A radius kept in miles before 2.0 is written once as metres, exactly.
        SearchRadius.migrate(defaults)
        radiusMeters=SearchRadius.meters(defaults)
        weatherEnabled=NetworkService.forecasts.isOn(defaults)
        npsEnabled=NetworkService.alerts.isOn(defaults)
        spotForecastsEnabled=SpotForecast.isOn(defaults)
        smokeEnabled=NetworkService.smoke.isOn(defaults)
        auroraEnabled=NetworkService.aurora.isOn(defaults)
        // What a request keeps after the screen that asked has moved on (it went back, or a background
        // refresh ran out of time) still reaches the screens, as it lands.
        weather.observe { [weak self] fresh in await self?.receiveForecasts(fresh) }
        detail.observe { [weak self] fresh in await self?.receiveDetails(fresh) }
        parkStore.observePrograms { [weak self] update in await self?.takePrograms(update.0,update.1) }
        // The world catalogue is read in the background from the first moment; nothing waits for it.
        prepareCatalog()
        // The last forecasts and park updates are read by the services, off the main actor, while
        // the first frame paints from the bundled parks; refreshes wait for them and then replace them.
        if DebugScenario.screen == nil {
            if let preload {
                // Read in the background since launch began; taken now, before the first frame, when
                // they are done within `preloadWait`. Otherwise the first frame does not wait for them:
                // the screens that would show a score show their loading state (`cachesPending`) until
                // the same reads land, so no first frame shows a score the caches would change.
                if let cached=preload.wait(timeout:Self.preloadWait) {
                    take(cached,replacing:true)
                    hydration=seedServices(cached)
                } else {
                    cachesPending=true
                    LaunchSignposts.note("Caches late")
                    hydration=Task { [weak self] in
                        let cached=await preload.contents()
                        guard let self else { return }
                        self.take(cached,replacing:false)
                        self.cachesPending=false
                        await self.seedServices(cached).value
                    }
                }
                // Tonight's skies are built after the reads, so neither the first frame nor the scores wait
                // on them; kept as soon as they are done (one the first frame already has stays as it is).
                Task { [weak self] in
                    let skies=await preload.skies()
                    self?.keep(skies)
                }
            } else { hydration=Task { await hydrate() } }
        }
        #if DEBUG
        if DebugScenario.screen != nil { homeID="jotr"; homePlace=nil; startChosen=DebugScenario.state != "first-run" }
        // `-nyx-place "Chicago, IL"`: a city as the starting point, its nearest park as the home park.
        if let name=DebugScenario.place, let place=StartingPlaces.named(name) { choose(place) }
        if DebugScenario.state=="polar" { homeID="dena" }
        if DebugScenario.state=="polar-night" { homeID="gaar" }
        if let park=DebugScenario.park { homeID=park }
        #endif
        // Until a starting point is chosen, the example night is measured from a town in this
        // device's time zone (Toronto, Mumbai), worked out from settings alone, off the main thread.
        if DebugScenario.screen == nil, !startChosen {
            Task { [weak self] in
                let example=await Task.detached(priority:.userInitiated) { StartingPlaces.example() }.value
                self?.showExample(from:example)
            }
        }
    }
    /// How long the first frame may wait for the offline caches read since launch (`CachePreload`).
    static let preloadWait=0.15
    /// The offline caches are still being read after the first frame (`preloadWait` passed): every
    /// surface with a score waits behind `ScoreGate` rather than show a score the caches are about to change.
    private(set) var cachesPending=false
    /// Skies built ahead at launch, kept only when they come from the same astronomy as the screens'.
    private func keep(_ skies:[SkyProjection.Sky]) {
        if astronomy is AstronomyEngine { for sky in skies { SkyProjection.shared.store(sky) } }
    }
    /// What the launch reads found: forecasts, forecast detail, alerts, the week's astronomy near the
    /// starting point and tonight's skies there. `replacing`: before the first frame, nothing newer
    /// exists; later, anything already newer is kept.
    private func take(_ cached:CachePreload.Contents,replacing:Bool) {
        let details=smokeEnabled ? cached.details : Self.withoutAir(cached.details)
        if replacing { forecasts=cached.forecasts; self.details=details }
        else { fillIn(forecasts:cached.forecasts,details:details) }
        seed(cached.conditions)
        keep(cached.skies)
        if replacing || alertsCache == nil { apply(AlertsUpdate(cache:cached.alerts,busy:false)) }
        LaunchSignposts.note("Caches ready")
    }
    /// Returns once the offline caches read at launch are in the model (at once, almost always).
    func cachesReady() async { await hydration?.value }
    /// The services start from what the launch reads found, so no file is read twice.
    private func seedServices(_ cached:CachePreload.Contents)->Task<Void,Never> {
        let parks=self.parks, weather=self.weather, detailService=self.detailService, parkStore=self.parkStore
        return Task {
            await weather.seed(cached.forecasts,parks:parks)
            await detailService.seed(cached.details,parks:parks)
            await parkStore.seed(cached.alerts)
        }
    }
    var home: Park? { park(homeID) ?? parks.first }
    /// The park-local night in progress (or about to begin) right now.
    func tonight(_ park:Park)->Date { tonightEntry(park).night }
    /// Tonight and its evening, worked out once per park for each moment `today` stands at (it
    /// moves only when some park's night turns over). Reads `today` every time, as before.
    private func tonightEntry(_ park:Park)->(night:Date,evening:Date) {
        let at=today
        if let kept=tonightMemo[park.id], kept.at==at, kept.park==park { return (kept.night,kept.evening) }
        let night=park.currentNight(at:at), evening=park.evening(night)
        tonightMemo[park.id]=(at,park,night,evening)
        return (night,evening)
    }
    /// A curated park by its id, a world catalogue place by its `wd:` id (once the catalogue is read),
    /// or a saved spot by its `pin:` id. Curated ids read neither, so screens that show only parks do
    /// not redraw when a spot is saved or the catalogue arrives.
    func park(_ id:String)->Park? {
        if let index=parkIndex[id] { return parks[index] }
        if id.hasPrefix(Park.catalogPrefix) {
            // Read so a screen showing a catalogue place redraws once the catalogue is ready.
            _=catalog.isEmpty
            return placeCatalog.place(id)
        }
        guard id.hasPrefix(SavedSpots.prefix) else { return nil }
        return spotIndex[id].flatMap { spots.indices.contains($0) ? spots[$0] : nil }
    }
    // MARK: The world catalogue

    /// Starts reading the world catalogue off the main thread, once: decoding about 3,400 places,
    /// their 1° spatial index, search terms and forecast regions. Called at launch; safe to call again.
    func prepareCatalog() {
        guard catalogTask == nil else { return }
        let curated=Set(parks.map(\.id))
        catalogTask=Task { [weak self] in
            let built=await Task.detached(priority:.userInitiated) { PlaceCatalog.bundled(excluding:curated) }.value
            self?.install(built)
        }
    }
    /// Waits until the catalogue is ready (at once if it is). Paths that resolve saved `wd:` ids for
    /// the widgets, the watch and reminders wait here, so a followed catalogue place is never dropped.
    func catalogReady() async {
        prepareCatalog()
        await catalogTask?.value
    }
    /// A place named from outside the app (a widget, a reminder, Spotlight, a link, Handoff, Siri): at
    /// once when it is known; a world catalogue id named before the catalogue is read (a cold launch)
    /// once it is, so it is never dropped. Nil for an id Nyx does not know, never another place.
    func place(named id:String) async -> Park? {
        if let known=park(id) { return known }
        guard awaitsCatalog(id) else { return nil }
        await catalogReady()
        return park(id)
    }
    /// True for a world catalogue id while the catalogue is still being read: its place is not known yet.
    func awaitsCatalog(_ id:String)->Bool { id.hasPrefix(Park.catalogPrefix) && !catalogIsReady }
    /// Field mode's place when none was named (Control Center, "I'm stargazing"): the last place used in
    /// the field, else the starting place, each waited for when it is a catalogue place not read yet;
    /// the first park only when neither is known.
    func usualFieldPlace(lastUsed:String?) async -> Park? {
        for id in [lastUsed,homeID].compactMap({ $0 }) { if let found=await place(named:id) { return found } }
        return home
    }
    private func install(_ built:PlaceCatalog) {
        placeCatalog=built
        catalogIsReady=true
        catalog=built.places
        // A journal entry at a catalogue place read before the catalogue was there is scored again.
        journalScores=[:]
    }
    /// Curated parks, catalogue places and saved spots within `radiusMeters` (great-circle) of a point,
    /// nearest first (ties by id). The catalogue is found through its 1° buckets, so a radius looks at
    /// a few dozen cells, never all 3,400 places. Without the catalogue yet, the parks and spots.
    func places(near latitude:Double,longitude:Double,radiusMeters:Double)->[Park] {
        _=catalog.isEmpty
        guard latitude.isFinite, longitude.isFinite, radiusMeters>=0 else { return [] }
        let local=(parks+spots).filter { $0.distanceMeters(latitude:latitude,longitude:longitude)<=radiusMeters }
        var seen=Set<String>()
        return (local+placeCatalog.nearby(latitude:latitude,longitude:longitude,radiusMeters:radiusMeters))
            .filter { seen.insert($0.id).inserted }
            .map { ($0,$0.distanceMeters(latitude:latitude,longitude:longitude)) }
            .sorted { ($0.1,$0.0.id)<($1.1,$1.0.id) }.map(\.0)
    }
    /// Curated parks and catalogue places whose name, region or country (in the reader's language)
    /// matches `query`, folded as the park list folds it ("Iguazu" finds Iguazú). Ranked: the whole
    /// name, a name that begins with it, a word of the name that does, the name containing it, then
    /// region or country the same way; on a tie a curated park first, then by the name shown. Empty for an empty query.
    func searchPlaces(_ query:String,limit:Int=50)->[Park] {
        _=catalog.isEmpty
        let needle=Park.folded(query)
        guard !needle.isEmpty, limit>0 else { return [] }
        if curatedTerms == nil { curatedTerms=parks.map { PlaceCatalog.Terms($0) } }
        let curated=zip(parks,curatedTerms ?? []).compactMap { park,terms in terms.rank(needle).map { (park,$0) } }
        let found=curated+placeCatalog.search(needle)
        return found.sorted { a,b in
            if a.1 != b.1 { return a.1<b.1 }
            if a.0.curated != b.0.curated { return a.0.curated }
            // By the name the list shows, as the world list orders a country (`WorldBrowse.shownBefore`).
            return WorldBrowse.shownBefore(a.0,b.0)
        }.prefix(limit).map(\.0)
    }
    /// Forecasts for these places, as `refreshForecasts(watching:)`: the curated parks' request as it
    /// always was, saved spots' rounded request, and for catalogue places their whole 10° tiles
    /// (`CatalogForecast.Regions`), never a place alone and never the device's position.
    func refreshForecasts(for places:[Park],force:Bool=false) async { await refreshForecasts(watching:places,force:force) }
    /// The trip planner's candidates: the places Tonight and Plan's best nights weigh from here
    /// (`TonightReach.candidates`: from a US start with only US places in range, the national parks;
    /// otherwise every place, catalogue and saved spots too), at most `TripPlanner.maxCandidates` of
    /// them (`TripPlanner.limited`), sorted by id.
    func tripCandidates(latitude:Double,longitude:Double,radiusMeters:Double,drivableOnly:Bool=false)->[Park] {
        let everything=places(near:latitude,longitude:longitude,radiusMeters:radiusMeters)
        let reach=TonightReach.candidates(parks:nearby(latitude:latitude,longitude:longitude,radiusMeters:radiusMeters),places:everything,
                                          originInUS:USOutline.contains(latitude:latitude,longitude:longitude))
        return TripPlanner.limited(TripPlanner.candidates(reach,latitude:latitude,longitude:longitude,radiusMeters:radiusMeters,drivableOnly:drivableOnly),
                                   latitude:latitude,longitude:longitude)
    }
    /// The saved spots, from the store (call it whenever they change). A spot new to this launch
    /// gets its cached forecast at once; a spot deleted is forgotten here, along with its forecast.
    func setSpots(_ records:[SavedSpot]) { setSpots(places:records.sorted { $0.createdAt<$1.createdAt }.map { Place(spot:$0) }) }
    func setSpots(places:[Park]) {
        guard places != spots else { return }
        let before=Set(spots.map(\.id)), now=Set(places.map(\.id))
        spots=places
        spotIndex=Dictionary(places.indices.map { (places[$0].id,$0) },uniquingKeysWith:{ first,_ in first })
        for id in before.subtracting(now) {
            forecasts[id]=nil; staleForecasts.remove(id)
            conditions[id]=nil; tonightMemo[id]=nil
        }
        let added=places.filter { !before.contains($0.id) }
        guard !added.isEmpty, DebugScenario.screen == nil else { return }
        let weather=self.weather
        Task { [weak self] in
            await self?.hydration?.value
            let cached=await weather.spotForecasts(for:added,network:false,force:false)
            guard let self else { return }
            for (id,forecast) in cached where self.spotIndex[id] != nil && self.forecasts[id] == nil { self.forecasts[id]=forecast }
        }
    }
    func night(_ park:Park,on date:Date?=nil)->Night {
        let evening=date.map(park.evening) ?? tonightEntry(park).evening
        // Read on every call, kept or not, so a screen still redraws when either changes (the memo is not observed).
        let forecast=forecasts[park.id], detail=details[park.id], now=present
        let recent=detail?.models?.usable(now:now) == true
        if let kept=nightMemo[park.id]?[evening], kept.recent==recent, kept.night.park==park {
            // Offline past the forecast's 36 hours, "No cloud forecast yet" becomes "Cloud forecast unavailable", as the widget and Siri say it.
            var night=kept.night
            night.beyondForecast=NightPlanner.beyondForecast(night,forecast:forecast,detail:detail,now:now)
            return night
        }
        let sky:SkyConditions
        if let cached=conditions[park.id]?[evening] { sky=cached } else {
            sky=astronomy.conditions(for:park,on:evening); conditions[park.id,default:[:]][evening]=sky
        }
        let night=NightPlanner.night(park:park,sky:sky,forecast:forecast,detail:detail,now:now,scoring:scoring)
        nightMemo[park.id,default:[:]][evening]=(recent,night)
        return night
    }
    /// A journal entry's score at its park, kept per entry, night and park (`loggedNights`). Nil
    /// for a park Nyx does not know. Reads the forecasts and detail as `night(_:on:)` would.
    func journalScore(id:UUID,date:Date,parkID:String)->Int? {
        let key=JournalScoreKey(id:id,date:date,park:parkID)
        if let kept=journalScores[key] {
            if kept != nil { _=forecasts[parkID]; _=details[parkID] }
            return kept
        }
        let score=park(parkID).map { night($0,on:date).score.value }
        journalScores[key]=score
        return score
    }
    /// What the forecast says around the score for one night: model agreement (with the score the
    /// clearest and cloudiest model would give), cloud layers, cold, dew, wind and smoke. Agreement
    /// is shown only beside a score that includes clouds, so the two never contradict each other.
    func outlook(_ night:Night)->NightOutlook? {
        let key=OutlookKey(ages:Self.ages(details[night.park.id],now:present),score:night.score.value,hasForecast:night.score.hasForecast,
                           upperCloudOnly:night.upperCloudOnly,aerosol:night.aerosol)
        if let cached=outlookCache[night.park.id]?[night.id], cached.key==key { return cached.outlook }
        let outlook=deriveOutlook(night)
        outlookCache[night.park.id,default:[:]][night.id]=(key,outlook)
        return outlook
    }
    /// Which of a detail's series are recent enough to describe (models, layers, smoke), as bits.
    nonisolated private static func ages(_ detail:ForecastDetail?,now:Date)->UInt8 {
        guard let detail else { return 0 }
        return (detail.models?.usable(now:now) == true ? 1 : 0) | (detail.layers?.usable(now:now) == true ? 2 : 0) | (detail.air?.usable(now:now) == true ? 4 : 0)
    }
    private func deriveOutlook(_ night:Night)->NightOutlook? {
        details[night.park.id].flatMap { NightOutlook.of(night,detail:$0,now:present,scoring:scoring) }
    }
    /// The core, planets, a meteor shower and an eclipse for one night, worded for that night
    /// ("peak tonight" only on tonight). Kept per park and night: scrubbing recomputes nothing.
    func whatsUp(_ night:Night)->WhatsUp {
        let isTonight=night.id==tonight(night.park), key=skyKey(night,isTonight:isTonight)
        if let cached=skyCache[key] { return cached }
        let value=WhatsUp(park:night.park,sky:night.sky,isTonight:isTonight,aurora:auroraItem(night))
        skyCache[key]=value
        return value
    }
    /// Aurora in reach this night by NOAA's forecast, or nil (`AuroraForecast.item`).
    func auroraItem(_ night:Night)->WhatsUp.Item? { AuroraForecast.item(aurora,park:night.park,sky:night.sky,now:present) }
    /// Only the shower and eclipse: cheap enough for every night of a calendar month.
    func events(_ night:Night)->WhatsUp.Events {
        let key=SkyKey(park:night.park.id,night:night.id,isTonight:false)
        if let cached=eventCache[key] { return cached }
        let value=skyCache[skyKey(night,isTonight:night.id==tonight(night.park))]?.events ?? WhatsUp.Events(park:night.park,sky:night.sky)
        eventCache[key]=value
        return value
    }
    /// Eclipse and shower-peak marks for a run of nights, keyed by night.
    func markers(_ nights:[Night])->[Date:WhatsUp.Events.Marker] {
        Dictionary(nights.compactMap { night in events(night).marker(park:night.park).map { (night.id,$0) } },uniquingKeysWith:{ first,_ in first })
    }
    /// Works out the river's nights off the main thread, so a scrub finds each one ready.
    func prepareWhatsUp(_ nights:[Night]) async {
        let missing=nights.map { ($0,$0.id==tonight($0.park)) }.filter { skyCache[skyKey($0.0,isTonight:$0.1)] == nil }
        guard !missing.isEmpty else { return }
        let inputs=missing.map { (key:skyKey($0.0,isTonight:$0.1),park:$0.0.park,sky:$0.0.sky,isTonight:$0.1,aurora:auroraItem($0.0)) }
        let computed=await Task.detached(priority:.utility) { inputs.map { ($0.key,WhatsUp(park:$0.park,sky:$0.sky,isTonight:$0.isTonight,aurora:$0.aurora)) } }.value
        for (key,value) in computed where skyCache[key] == nil { skyCache[key]=value }
    }
    /// Works out the astronomy of these parks' next `count` nights off the main thread, so a
    /// first look (Parks, a calendar month) finds them ready. The same engine and the same inputs
    /// as `night(_:on:)`, kept only where nothing is yet: no score can differ.
    func prepareNights(_ parks:[Park],from start:((Park)->Date)?=nil,count:Int) async {
        let wanted=parks.flatMap { park in
            let first=start?(park) ?? tonight(park)
            return (0..<count).map { (park,park.evening(park.date(first,addingDays:$0))) }
        }.filter { conditions[$0.0.id]?[$0.1] == nil }
        guard !wanted.isEmpty else { return }
        let astronomy=self.astronomy
        let computed=await Task.detached(priority:.utility) { wanted.map { ($0.0.id,$0.1,astronomy.conditions(for:$0.0,on:$0.1)) } }.value
        for (id,evening,sky) in computed where conditions[id]?[evening] == nil { conditions[id,default:[:]][evening]=sky }
    }
    /// The nights' astronomy is the engine's own (always, outside tests that hand in another), so
    /// work done ahead with it (`SkyAhead`) is the work a screen would do.
    var astronomyIsEngine: Bool { astronomy is AstronomyEngine }
    /// Conditions worked out at launch for the parks near the starting point (`CachePreload`).
    private func seed(_ prepared:[String:[Date:SkyConditions]]) {
        guard astronomy is AstronomyEngine else { return }
        for (id,nights) in prepared { conditions[id,default:[:]].merge(nights) { kept,_ in kept } }
    }
    private func skyKey(_ night:Night,isTonight:Bool)->SkyKey {
        SkyKey(park:night.park.id,night:night.id,isTonight:isTonight,aurora:aurora?.usable(now:present) == true)
    }
    func outlooks(_ nights:[Night])->[Date:NightOutlook] {
        Dictionary(nights.compactMap { night in outlook(night).map { (night.id,$0) } },uniquingKeysWith:{ first,_ in first })
    }
    /// The best clear, dark, moon-free stretch of a forecast night, from the hourly clouds
    /// (mid and high cloud only at a summit above the inversion). Nil without a full forecast.
    func clearWindow(_ night:Night)->ClearWindow? {
        ClearWindow.find(night,forecast:forecasts[night.park.id],layers:details[night.park.id]?.layers)
    }
    /// Aurora season, satellites, zodiacal light, the faintest stars and the core's light dome.
    func skyNotes(_ night:Night)->[SkyNote] {
        SkyNotes.notes(park:night.park,sky:night.sky,core:whatsUp(night).coreNight,aerosol:night.aerosol,
                       auroraForecast:auroraEnabled && aurora?.usable(now:present) == true)
    }
    /// The amber caveat beside a score: haze or smoke thick enough to hide the Milky Way.
    func smokeCaveat(_ night:Night)->String? { night.smokeCaveat }
    func nights(_ park:Park,from date:Date,count:Int)->[Night] { (0..<count).map { night(park,on:park.date(date,addingDays:$0)) } }
    func nearby(latitude:Double?,longitude:Double?,radiusMeters:Double?=nil)->[Park] {
        guard let origin else { return [] }
        let lat=latitude ?? origin.latitude, lon=longitude ?? origin.longitude, reach=radiusMeters ?? self.radiusMeters
        return parks.filter { $0.distanceMeters(latitude:lat,longitude:lon)<=reach }
    }
    /// Where distances are measured from without "Near me": the chosen place, else the starting park.
    var origin:(latitude:Double,longitude:Double)? { homePlace.map { ($0.latitude,$0.longitude) } ?? home.map { ($0.latitude,$0.longitude) } }
    /// The starting point's name: "Chicago" or "Joshua Tree".
    var originName:String { homePlace?.name ?? home?.shortName ?? "" }
    /// Start from a park: distances from it, and no place.
    func choose(parkID:String) { homePlace=nil; homeID=parkID; startChosen=true }
    /// Start from a city or town: distances from it, and the park nearest to it as the home park
    /// (the sky behind the app, the calendar's first park, the widget before anything is saved).
    func choose(_ place:StartingPlace) { startChosen=true; start(from:place) }
    /// The example starting point until one is chosen (`StartingPlaces.example`): a town in this
    /// device's time zone, or the starting park in the US. Never counts as a choice.
    func showExample(from place:StartingPlace?) {
        guard !startChosen else { return }
        if let place { if place != homePlace { start(from:place) } }
        else if homePlace != nil { homePlace=nil; homeID=Park.defaultID }
        // Written out, so the home park kept for the example never reads as one chosen (`init`).
        startChosen=false
    }
    private func start(from place:StartingPlace) {
        homePlace=place
        let curated=Self.nearestPark(to:place,in:parks)
        if let curated { homeID=curated.id }
        // Far from every curated park (abroad), the nearest world catalogue place is the home park
        // instead. Within reach of one, the curated park stays, as before the catalogue.
        guard curated.map({ place.distanceMeters(to:$0)>Self.curatedReach }) ?? true else { return }
        guard catalogIsReady else {
            // Chosen before the catalogue was read (first run, a cold launch): the nearest curated park
            // stands in until it is, then the place nearest the city is chosen, unless the starting
            // point or the home park has changed meanwhile. Never a park an ocean away for good.
            let provisional=homeID
            Task { [weak self] in
                await self?.catalogReady()
                guard let self, self.homePlace == place, self.homeID == provisional else { return }
                self.chooseLocal(near:place,curated:curated)
            }
            return
        }
        chooseLocal(near:place,curated:curated)
    }
    /// The world catalogue place nearest a starting point abroad as the home park, when it is nearer
    /// than the nearest curated park.
    private func chooseLocal(near place:StartingPlace,curated:Park?) {
        let local=Self.nearestPark(to:place,in:placeCatalog.nearby(latitude:place.latitude,longitude:place.longitude,radiusMeters:2*Self.curatedReach))
        if let local, curated.map({ place.distanceMeters(to:local)<place.distanceMeters(to:$0) }) ?? true { homeID=local.id }
    }
    /// How far a starting place may be from the nearest curated park and still take it as its home park.
    nonisolated static let curatedReach:Double=500_000
    /// The park closest to a place, straight-line.
    nonisolated static func nearestPark(to place:StartingPlace,in parks:[Park])->Park? {
        parks.min { place.distanceMeters(to:$0)<place.distanceMeters(to:$1) }
    }
    /// The park this iPhone is in or beside, for offering field mode: within 60 km of the park's
    /// centre or 25 km of one of its viewing spots, nearest first. Straight-line, on this iPhone.
    func fieldPark(latitude:Double,longitude:Double)->Park? {
        parks.map { park in (park,min(park.distanceMeters(latitude:latitude,longitude:longitude)/60_000,
                                       park.viewingSpots.map { spot in Park.distance(spot.latitude,spot.longitude,latitude,longitude)/25_000 }.min() ?? .infinity)) }
            .filter { $0.1<=1 }.min { $0.1<$1.1 }?.0
    }
    func ranked(_ candidates:[Park])->[Park] {
        // Ranked as every other surface ranks nights: on a tie, the darker measured sky first.
        let nights=Dictionary(candidates.map { ($0.id,night($0)) },uniquingKeysWith:{ first,_ in first })
        return candidates.sorted { a,b in
            guard let x=nights[a.id], let y=nights[b.id] else { return a.name<b.name }
            return NightPlanner.better(x,y)
        }
    }
    /// The person's own key from Your privacy, else the key every install shares.
    var npsKey: String { NPSKeyStore().key ?? Bundle.main.object(forInfoDictionaryKey:"NPS_API_KEY") as? String ?? "" }
    /// Reads every cache once, in the services, and shows what they hold where nothing newer is.
    func hydrate() async {
        let interval=LaunchSignposts.begin("Hydrate caches")
        let parks=self.parks, weather=self.weather, detailService=self.detailService, parkStore=self.parkStore, auroraService=self.auroraService
        async let cachedForecasts=weather.hydrate(parks)
        async let cachedDetails=detailService.hydrate(parks)
        async let cachedAlerts=parkStore.hydrate(parks)
        async let cachedAurora=auroraService.cached()
        let (f,d,a,k)=await (cachedForecasts,cachedDetails,cachedAlerts,cachedAurora)
        fillIn(forecasts:f,details:d)
        if alertsCache == nil { apply(a) }
        if auroraEnabled, aurora == nil { aurora=k }
        LaunchSignposts.end(interval)
        LaunchSignposts.note("Caches ready")
    }
    /// Cached forecasts and detail where nothing newer is here yet, each in one assignment.
    private func fillIn(forecasts cachedForecasts:[String:Forecast],details cachedDetails:[String:ForecastDetail]) {
        let newForecasts=cachedForecasts.filter { forecasts[$0.key] == nil }
        if !newForecasts.isEmpty { forecasts.merge(newForecasts) { kept,_ in kept } }
        let newDetails=cachedDetails.filter { details[$0.key] == nil }
        if !newDetails.isEmpty { details.merge(newDetails) { kept,_ in kept } }
    }
    /// Forecasts a service has kept, wherever they came from (a refresh, or a request that outlived
    /// it): only those newer than what is here (`Forecast.replaces`), never a deleted spot's, in one
    /// assignment, so the kept nights are let go once.
    func takeForecasts(_ fresh:[String:Forecast]) {
        var updated=forecasts, changed=false
        for (id,forecast) in fresh where (!id.hasPrefix(SavedSpots.prefix) || spotIndex[id] != nil) && Forecast.replaces(forecast,updated[id],now:present) {
            updated[id]=forecast; changed=true
        }
        if changed { forecasts=updated }
    }
    /// Forecast detail the service holds, part by part the newer (`ForecastDetail.newer`), so a late
    /// delivery never puts an older part back; in one assignment.
    func takeDetails(_ fresh:[String:ForecastDetail]) {
        var updated=details, changed=false
        for (id,detail) in fresh {
            let merged=updated[id].map { $0.newer(detail) } ?? detail
            if updated[id] != merged { updated[id]=merged; changed=true }
        }
        if changed { details=updated }
    }
    /// What the services hand on as it lands (`StoreObserver`), gathered for a moment and taken
    /// together: a refresh's requests land one after another, and each assignment lets go of every
    /// night worked out, so a burst of them is one change, not one per request.
    @ObservationIgnored private var landedForecasts:[String:Forecast]=[:]
    @ObservationIgnored private var landedDetails:[String:ForecastDetail]=[:]
    @ObservationIgnored private var landing:Task<Void,Never>?
    static let landingWindow:Duration = .milliseconds(300)
    func receiveForecasts(_ fresh:[String:Forecast]) {
        for (id,forecast) in fresh where Forecast.replaces(forecast,landedForecasts[id]) { landedForecasts[id]=forecast }
        scheduleLanding()
    }
    func receiveDetails(_ fresh:[String:ForecastDetail]) {
        for (id,detail) in fresh { landedDetails[id]=landedDetails[id].map { $0.newer(detail) } ?? detail }
        scheduleLanding()
    }
    private func scheduleLanding() {
        guard landing == nil else { return }
        landing=Task { [weak self] in
            try? await Task.sleep(for:Self.landingWindow)
            guard let self else { return }
            let forecasts=landedForecasts, details=landedDetails
            landedForecasts=[:]; landedDetails=[:]; landing=nil
            if !forecasts.isEmpty { takeForecasts(forecasts) }
            if !details.isEmpty { takeDetails(details) }
        }
    }
    /// A park's programs as fetched, when newer than those here.
    func takePrograms(_ id:String,_ fresh:ProgramsCache) {
        guard programs[id].map({ $0.updated<fresh.updated }) ?? true, let park=park(id) else { return }
        programs[id]=fresh
        rebuild(park)
    }
    /// Forecasts for every park arrive together (one or two requests); park updates (alerts, and
    /// ranger programs where they are shown) follow park by park, and only when asked for.
    /// `page`: asked from a place's own page.
    func refresh(_ parks:[Park],force:Bool=false,parkUpdates:Bool=true,programs:Bool=false,page:Bool=false) async {
        // Programs are asked for only on a park's page: from then on its forecast detail is wanted too.
        if programs { detailWanted=true }
        // A catalogue place's page: smoke at catalogue places is wanted from then on.
        if page, parks.contains(where:\.isCatalogPlace) { catalogSmokeWanted=true }
        await refreshForecasts(watching:parks,force:force)
        // Cancelled (the question changed while it was asked): the next refresh says when it last happened.
        guard !Task.isCancelled else { return }
        lastRefresh=Date.now
        if parkUpdates { await refreshParkUpdates(parks,force:force,programs:programs) }
    }
    /// Always asks for all 63 parks, never only those near the device: it costs the same request,
    /// and a list of nearby parks would tell the forecast service roughly where you are. Saved spots
    /// follow in a separate request with rounded coordinates, behind their own switch as well. World
    /// catalogue places among `parks` are asked for by their whole 10° tiles (`CatalogForecast`).
    func refreshForecasts(watching parks:[Park],force:Bool=false) async {
        let live=DebugScenario.screen == nil || DebugScenario.state == "live"
        if DebugScenario.state=="no-forecast" { for park in parks { forecasts[park.id]=nil; details[park.id]=nil }; return }
        #if DEBUG
        // `-nyx-aurora 6`: NOAA's forecast holding that Kp for three days, for captures of the aurora item.
        if let kp=DebugScenario.number("-nyx-aurora") { aurora=DebugForecasts.aurora(kp:kp,now:today) }
        if let state=DebugScenario.state, let fixture=DebugForecasts(state:state,parks:self.parks,now:today) {
            forecasts=fixture.forecasts; details=fixture.details; return
        }
        #endif
        await hydration?.value
        let network=weatherEnabled && live
        var fresh=await weather.forecasts(for:self.parks,network:network,force:force)
        takeForecasts(fresh)
        // Cancelled while asking: what arrived is kept, and nothing is called stale for a request cut short.
        guard !Task.isCancelled else { return }
        // Saved spots in a request of their own, rounded to 0.1°, never mixed into the parks' (`SpotForecast`).
        let spots=self.spots
        if !spots.isEmpty {
            let spotNetwork=network && spotForecastsEnabled
            let ofSpots=await weather.spotForecasts(for:spots,network:spotNetwork,force:force)
            takeForecasts(ofSpots)
            if spotNetwork { fresh.merge(ofSpots) { park,_ in park } }
        }
        // World catalogue places by whole tiles (`CatalogForecast.Regions`), the same switch and host
        // as the parks: never one place alone, never the device's position.
        var askedCatalog=Set<String>()
        var catalogRequests:[[Park]]=[]
        if parks.contains(where:\.isCatalogPlace) {
            await catalogReady()
            let requests=placeCatalog.regions.plan(wanted:parks)
            catalogRequests=requests
            askedCatalog=Set(requests.joined().map(\.id))
            let ofCatalog=await weather.catalogForecasts(requests,network:network,force:force)
            takeForecasts(ofCatalog)
            if network { fresh.merge(ofCatalog) { park,_ in park } }
        }
        // Switched off, the air-quality host's cached data is dropped rather than merely not refreshed.
        if !smokeEnabled { await detailService.forgetAir() }
        forecastsHeldBack=network ? await weather.heldBack() : false
        // A summit above the inversion (Haleakalā) is scored from its mid and high cloud, which come
        // with forecast detail: asked for with the clouds from the first refresh, page or no page, so
        // Tonight never waits for a park page to score it. Every copy of Nyx asks for that one public
        // park whatever its whereabouts; once a page is open, the summit rides with every park.
        let summits=self.parks.filter { $0.aboveInversion == true }
        if network, !detailWanted, !summits.isEmpty { _=await detailService.details(for:summits,weather:true,smoke:false,force:force) }
        takeDetails(await detailService.details(for:self.parks,weather:network && detailWanted,smoke:smokeEnabled && live && detailWanted,force:force))
        // Smoke kept from a page opened in an earlier session still caps the score, so those parks' smoke is
        // kept current page or no page: an old smoke forecast must not hold the night down after the smoke has gone.
        let keptSmoke=self.parks.filter { details[$0.id]?.air != nil }
        if smokeEnabled, live, !detailWanted, !keptSmoke.isEmpty {
            takeDetails(await detailService.details(for:keptSmoke,weather:false,smoke:true,force:force))
        }
        // Smoke at catalogue places: the same whole tiles as their clouds, on the parks' terms (the
        // switch, and asked for only once a page has been opened); what is kept counts offline too.
        if smokeEnabled, !catalogRequests.isEmpty {
            takeDetails(await detailService.catalogAir(catalogRequests,network:live && (detailWanted || catalogSmokeWanted),force:force))
        }
        let paused=await detailService.pausedForLowData()
        if paused != detailPausedForLowData { detailPausedForLowData=paused }
        // NOAA's aurora forecast: one global file, at most every three hours.
        if auroraEnabled {
            let fresh=await auroraService.outlook(network:live,force:force)
            // Switched off while it was asked for: the switch's own `didSet` already cleared it.
            if auroraEnabled, fresh != aurora { aurora=fresh }
        }
        #if DEBUG
        exportWatchContext()
        #endif
        guard network, !Task.isCancelled else { return }
        // A spot whose forecasts are switched off is not "stale": it was never asked about.
        // Nor is a catalogue place beyond this refresh's budget (`CatalogForecast.maxPointsPerRefresh`).
        for park in parks where (spotForecastsEnabled || !park.isSavedSpot) && (!park.isCatalogPlace || askedCatalog.contains(park.id)) {
            if let forecast=fresh[park.id], !forecastIsStale(forecast.updated) { staleForecasts.remove(park.id) } else { staleForecasts.insert(park.id) }
        }
    }
    /// Alerts for every park arrive in one request (whichever screen asks first, at most every six
    /// hours), so the request never says which parks are near you; ranger programs follow only for
    /// the park whose page is open.
    /// `alertPages`: one in a background refresh, where time is short (`SavedSkySync`).
    func refreshParkUpdates(_ parks:[Park],force:Bool=false,programs:Bool=false,alertPages:Int=ParkStore.alertPages) async {
        let live=DebugScenario.screen == nil || DebugScenario.state == "live"
        let network=npsEnabled && live, key=npsKey
        await hydration?.value
        apply(await parkStore.alerts(for:self.parks,key:key,network:network,force:force,pages:alertPages))
        guard programs else { return }
        for park in parks {
            if Task.isCancelled { return }
            if let fresh=await parkStore.programs(for:park,key:key,network:network,force:force), fresh != self.programs[park.id] { takePrograms(park.id,fresh) }
        }
    }
    private func apply(_ update:AlertsUpdate) {
        // `-nyx-alerts-busy` (DEBUG): the busy state for screenshots.
        let busy=update.busy || DebugScenario.isEnabled("alerts-busy")
        if alertsBusy != busy { alertsBusy=busy }
        guard update.cache != alertsCache else { return }
        alertsCache=update.cache
        for park in parks { rebuild(park) }
        dataRevision+=1
        // A new closure reaches the widget and the watch too.
        savedSync.noteChange(self)
    }
    /// One park's update as the screens read it: its alerts from the shared request, ranked, and
    /// its programs if its page has asked for them. Without alerts for the park, no update is made
    /// up (its page says access is not checked), and its programs still show (`rangerPrograms`).
    private func rebuild(_ park:Park) {
        guard let cache=alertsCache, let code=park.nps, let alerts=cache.alerts[code] else { return }
        let today=park.isoDay(Date.now), shown=programs[park.id]
        enrichments[park.id]=ParkEnrichment(updated:cache.updated,alerts:AlertRanking.ranked(alerts),programs:(shown?.programs ?? []).filter { $0.date>=today },description:nil,programsUpdated:shown?.updated)
    }
    /// A park's upcoming ranger programs as its page shows them, with when they were last checked (nil:
    /// they could not be): from its park update, or on their own when the alerts could not be fetched
    /// (the Park Service refusing them, say). Nil while neither has arrived.
    func rangerPrograms(_ park:Park)->(programs:[RangerProgram],updated:Date?)? {
        if let data=enrichments[park.id] { return (data.programs,data.programsUpdated) }
        guard let shown=programs[park.id] else { return nil }
        let today=park.isoDay(Date.now)
        return (shown.programs.filter { $0.date>=today },shown.updated)
    }
    /// Why this night's score does not count smoke, in Vision Pro's words (`ScoreInputs.smokeNote`):
    /// switched off, none fetched here yet (smoke comes with a park's page), or none reaching the
    /// night (past its few days). Nil when it counts (`Night.aerosol`).
    func smokeNote(_ night:Night)->String? {
        let park=night.park
        return ScoreInputs(smokeOn:smokeEnabled,smokeKnown:details[park.id]?.air == nil ? [] : [park.id]).smokeNote(park,night:night)
    }
    /// Every park's campgrounds from the NPS, asked for only when a park's "Where to stay" opens,
    /// in one request for all 63 parks, kept seven days (`ParkStore.campgrounds`).
    func refreshCampgrounds(force:Bool=false) async {
        let live=DebugScenario.screen == nil || DebugScenario.state == "live"
        await hydration?.value
        let fresh=await parkStore.campgrounds(for:parks,key:npsKey,network:npsEnabled && live,force:force)
        if let fresh, fresh != campgrounds { campgrounds=fresh }
    }
}
