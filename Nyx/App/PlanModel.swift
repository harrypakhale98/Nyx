import Foundation
import Observation
import CoreLocation

@MainActor @Observable final class PlanModel {
    let parks: [Park]
    let loadError: Bool
    private let astronomy: any AstronomyProviding
    private let scoring: any ScoreProviding
    private let weather: any WeatherProviding
    private let parkStore: any ParkProviding
    private let detailService: any DetailProviding
    @ObservationIgnored private var conditions: [String: [Date:SkyConditions]] = [:]
    var forecasts: [String:Forecast] = [:] { didSet { outlookCache=[:] } }
    /// Model agreement, cloud layers, cold, dew, wind and smoke. Context only; never in the score.
    /// With "Smoke and haze" off in Your privacy, the air-quality host's data is not used at all:
    /// no aerosol series is kept here, so no score, caveat or snapshot counts cached smoke.
    var details: [String:ForecastDetail] = [:] {
        didSet {
            if !smokeEnabled, details.values.contains(where:{ $0.air != nil }) { details=Self.withoutAir(details) }
            outlookCache=[:]
        }
    }
    /// Outlooks already derived, so a river scrub does not rescan every hour of 30 nights per frame.
    @ObservationIgnored private var outlookCache: [String:[Date:NightOutlook?]] = [:]
    /// What's up each night. Astronomy only, so never invalidated by a forecast.
    @ObservationIgnored private var skyCache: [SkyKey:WhatsUp] = [:]
    @ObservationIgnored private var eventCache: [SkyKey:WhatsUp.Events] = [:]
    /// A park's night, worded for tonight or not (events ignore the wording: always false).
    nonisolated private struct SkyKey: Hashable, Sendable { let park:String; let night:Date; let isTonight:Bool }
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
    /// in this session: Tonight and the park list need only clouds.
    @ObservationIgnored private var detailWanted=false
    @ObservationIgnored private var alertsCache: ParkAlertsCache?
    @ObservationIgnored private var programs: [String:ProgramsCache] = [:]
    /// The cached forecasts and alerts, read off the main actor once at launch.
    @ObservationIgnored private var hydration: Task<Void,Never>?
    /// Keeps the widget, the watch, Siri and reminders in step with the saved parks, once per process.
    @ObservationIgnored let savedSync=SavedSkySync()
    /// When Tonight's candidates were last refreshed, for a refresh on return.
    @ObservationIgnored private(set) var lastRefresh: Date?
    var homeID: String { didSet { if DebugScenario.screen == nil { UserDefaults.standard.set(homeID,forKey:"homePark") } } }
    /// A city or town chosen as the starting point (`places.json`). Distances are measured from it
    /// and `homeID` holds the park nearest to it; nil when the starting point is a park.
    var homePlace: StartingPlace? { didSet { if DebugScenario.screen == nil { UserDefaults.standard.set(homePlace.flatMap { try? JSONEncoder().encode($0) },forKey:"homePlace") } } }
    /// Whether a starting point was ever chosen: a park, a place, or "Near me". Until then Tonight
    /// asks, and its answer is labelled an example. Anyone who chose a park before has.
    var startChosen: Bool { didSet { if DebugScenario.screen == nil { UserDefaults.standard.set(startChosen,forKey:"startChosen") } } }
    var radiusMiles: Double { didSet { if DebugScenario.screen == nil { UserDefaults.standard.set(radiusMiles,forKey:"radiusMiles") } } }
    var weatherEnabled: Bool { didSet { if DebugScenario.screen == nil { UserDefaults.standard.set(weatherEnabled,forKey:"weatherEnabled") } } }
    var npsEnabled: Bool { didSet { if DebugScenario.screen == nil { UserDefaults.standard.set(npsEnabled,forKey:"npsEnabled") } } }
    var smokeEnabled: Bool {
        didSet {
            if DebugScenario.screen == nil { UserDefaults.standard.set(smokeEnabled,forKey:"smokeEnabled") }
            guard !smokeEnabled, oldValue else { return }
            // Switched off: cached smoke stops counting at once, here and in the cache Siri reads.
            details=Self.withoutAir(details)
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
        return .now
    }
    /// The moment "tonight" is judged from. Advanced only when some park's night turns over
    /// (at its sunrise or local noon), so open screens move on without constant redraws.
    private(set) var clock=Date.now
    func tick(_ now:Date = .now) {
        guard parks.contains(where:{ $0.currentNight(at:clock) != $0.currentNight(at:now) }) else { return }
        clock=now
        trimPastNights()
    }
    /// Once a night turns over, the kept astronomy, outlooks and what's-up of nights that have
    /// passed are let go (a screen that shows one again simply works it out again).
    private func trimPastNights() {
        let tonights=Dictionary(parks.map { ($0.id,tonight($0)) },uniquingKeysWith:{ first,_ in first })
        func current(_ id:String,_ night:Date)->Bool { tonights[id].map { night>=$0 } ?? true }
        for (id,nights) in conditions { conditions[id]=nights.filter { current(id,$0.key) } }
        for (id,nights) in outlookCache { outlookCache[id]=nights.filter { current(id,$0.key) } }
        skyCache=skyCache.filter { current($0.key.park,$0.key.night) }
        eventCache=eventCache.filter { current($0.key.park,$0.key.night) }
    }
    init(astronomy: any AstronomyProviding = AstronomyEngine(), scoring: any ScoreProviding = ScoreEngine(),
         weather: any WeatherProviding = WeatherService(), parkStore: any ParkProviding = ParkStore(),
         detail: any DetailProviding = ForecastDetailService(), preload: CachePreload?=nil) {
        do { parks=try ParkData.load(); loadError=false } catch { parks=[]; loadError=true }
        self.astronomy=astronomy; self.scoring=scoring; self.weather=weather; self.parkStore=parkStore; self.detailService=detail
        // Parks opens darkest tonight first: the list answers the app's question before it is asked.
        // (A registered default: anyone who chose Name keeps it.)
        UserDefaults.standard.register(defaults:["parksByScore":true])
        homeID=UserDefaults.standard.string(forKey:"homePark") ?? "jotr"
        homePlace=UserDefaults.standard.data(forKey:"homePlace").flatMap { try? JSONDecoder().decode(StartingPlace.self,from:$0) }
        startChosen=UserDefaults.standard.object(forKey:"startChosen") as? Bool ?? (UserDefaults.standard.string(forKey:"homePark") != nil)
        radiusMiles=UserDefaults.standard.object(forKey:"radiusMiles") as? Double ?? 200
        weatherEnabled=UserDefaults.standard.object(forKey:"weatherEnabled") as? Bool ?? true
        npsEnabled=UserDefaults.standard.object(forKey:"npsEnabled") as? Bool ?? true
        smokeEnabled=UserDefaults.standard.object(forKey:"smokeEnabled") as? Bool ?? true
        // The last forecasts and park updates are read by the services, off the main actor, while
        // the first frame paints from the bundled parks; refreshes wait for them and then replace them.
        if DebugScenario.screen == nil {
            if let preload {
                // Read in the background since launch began; taken now, before the first frame.
                let cached=preload.wait()
                forecasts=cached.forecasts; details=smokeEnabled ? cached.details : Self.withoutAir(cached.details)
                seed(cached.conditions)
                apply(AlertsUpdate(cache:cached.alerts,busy:false))
                LaunchSignposts.note("Caches ready")
                let parks=self.parks, weather=self.weather, detailService=self.detailService, parkStore=self.parkStore
                hydration=Task {
                    await weather.seed(cached.forecasts,parks:parks)
                    await detailService.seed(cached.details,parks:parks)
                    await parkStore.seed(cached.alerts)
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
    }
    var home: Park? { parks.first { $0.id==homeID } ?? parks.first }
    /// The park-local night in progress (or about to begin) right now.
    func tonight(_ park:Park)->Date { park.currentNight(at:today) }
    func park(_ id:String)->Park? { parks.first { $0.id==id } }
    func night(_ park:Park,on date:Date?=nil)->Night {
        let evening=park.evening(date ?? tonight(park))
        let sky:SkyConditions
        if let cached=conditions[park.id]?[evening] { sky=cached } else {
            sky=astronomy.conditions(for:park,on:evening); conditions[park.id,default:[:]][evening]=sky
        }
        return NightPlanner.night(park:park,sky:sky,forecast:forecasts[park.id],detail:details[park.id],now:present,scoring:scoring)
    }
    /// What the forecast says around the score for one night: model agreement (with the score the
    /// clearest and cloudiest model would give), cloud layers, cold, dew, wind and smoke. Agreement
    /// is shown only beside a score that includes clouds, so the two never contradict each other.
    func outlook(_ night:Night)->NightOutlook? {
        if let cached=outlookCache[night.park.id]?[night.id] { return cached }
        let outlook=deriveOutlook(night)
        outlookCache[night.park.id,default:[:]][night.id]=outlook
        return outlook
    }
    private func deriveOutlook(_ night:Night)->NightOutlook? {
        guard let detail=details[night.park.id] else { return nil }
        let window=night.sky.cloudWindow
        var outlook=detail.outlook(from:window.start,to:window.end,now:present)
        // The smoke words describe the smoke the score counted, whatever the aerosol forecast's age.
        outlook.aerosol=night.aerosol
        if night.score.hasForecast, !night.upperCloudOnly, let agreement=outlook.agreement {
            // The same caps as the score itself, smoke included.
            let aerosol=night.aerosol
            let clearest=scoring.score(sky:night.sky,bortle:night.park.bortleEstimate,cloud:agreement.low,basis:.forecast,aerosol:aerosol).value
            let cloudiest=scoring.score(sky:night.sky,bortle:night.park.bortleEstimate,cloud:agreement.high,basis:.forecast,aerosol:aerosol).value
            // Widened to hold the score itself: its best-match clouds can sit just outside the three
            // models' averages, and a range beside a score must never leave that score out. Done once
            // here, so the dial, the time river, the chart and every spoken sentence give one range.
            let score=night.score.value
            outlook.scoreRange=min(clearest,cloudiest,score)...max(clearest,cloudiest,score)
        } else { outlook.agreement=nil }
        return outlook.isEmpty ? nil : outlook
    }
    /// The core, planets, a meteor shower and an eclipse for one night, worded for that night
    /// ("peak tonight" only on tonight). Kept per park and night: scrubbing recomputes nothing.
    func whatsUp(_ night:Night)->WhatsUp {
        let isTonight=night.id==tonight(night.park), key=Self.skyKey(night,isTonight:isTonight)
        if let cached=skyCache[key] { return cached }
        let value=WhatsUp(park:night.park,sky:night.sky,isTonight:isTonight)
        skyCache[key]=value
        return value
    }
    /// Only the shower and eclipse: cheap enough for every night of a calendar month.
    func events(_ night:Night)->WhatsUp.Events {
        let key=SkyKey(park:night.park.id,night:night.id,isTonight:false)
        if let cached=eventCache[key] { return cached }
        let value=skyCache[Self.skyKey(night,isTonight:night.id==tonight(night.park))]?.events ?? WhatsUp.Events(park:night.park,sky:night.sky)
        eventCache[key]=value
        return value
    }
    /// Eclipse and shower-peak marks for a run of nights, keyed by night.
    func markers(_ nights:[Night])->[Date:WhatsUp.Events.Marker] {
        Dictionary(nights.compactMap { night in events(night).marker(park:night.park).map { (night.id,$0) } },uniquingKeysWith:{ first,_ in first })
    }
    /// Works out the river's nights off the main thread, so a scrub finds each one ready.
    func prepareWhatsUp(_ nights:[Night]) async {
        let missing=nights.map { ($0,$0.id==tonight($0.park)) }.filter { skyCache[Self.skyKey($0.0,isTonight:$0.1)] == nil }
        guard !missing.isEmpty else { return }
        let inputs=missing.map { (key:Self.skyKey($0.0,isTonight:$0.1),park:$0.0.park,sky:$0.0.sky,isTonight:$0.1) }
        let computed=await Task.detached(priority:.utility) { inputs.map { ($0.key,WhatsUp(park:$0.park,sky:$0.sky,isTonight:$0.isTonight)) } }.value
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
    /// Conditions worked out at launch for the parks near the starting point (`CachePreload`).
    private func seed(_ prepared:[String:[Date:SkyConditions]]) {
        guard astronomy is AstronomyEngine else { return }
        for (id,nights) in prepared { conditions[id,default:[:]].merge(nights) { kept,_ in kept } }
    }
    private static func skyKey(_ night:Night,isTonight:Bool)->SkyKey { SkyKey(park:night.park.id,night:night.id,isTonight:isTonight) }
    func outlooks(_ nights:[Night])->[Date:NightOutlook] {
        Dictionary(nights.compactMap { night in outlook(night).map { (night.id,$0) } },uniquingKeysWith:{ first,_ in first })
    }
    /// The best clear, dark, moon-free stretch of a forecast night, from the hourly clouds
    /// (mid and high cloud only at a summit above the inversion). Nil without a full forecast.
    func clearWindow(_ night:Night)->ClearWindow? {
        guard night.score.hasForecast else { return nil }
        let window=night.sky.cloudWindow
        var hours:[(time:Date,cloud:Double)]=[]
        if night.upperCloudOnly, let layers=details[night.park.id]?.layers, let mid=layers.values["cloud_cover_mid"], let high=layers.values["cloud_cover_high"], mid.count==layers.times.count, high.count==layers.times.count {
            hours=layers.times.indices.compactMap { i in
                guard let m=mid[i], let h=high[i], layers.times[i]+1800>window.start.timeIntervalSince1970, layers.times[i]-1800<window.end.timeIntervalSince1970 else { return nil }
                return (Date(timeIntervalSince1970:layers.times[i]),100*(1-(1-m/100)*(1-h/100)))
            }
        } else if let forecast=forecasts[night.park.id] { hours=forecast.hours(from:window.start,to:window.end) }
        return ClearWindow.find(park:night.park,sky:night.sky,hours:hours)
    }
    /// Aurora season, satellites, zodiacal light, the faintest stars and the core's light dome.
    func skyNotes(_ night:Night)->[SkyNote] {
        SkyNotes.notes(park:night.park,sky:night.sky,core:whatsUp(night).coreNight,aerosol:night.aerosol)
    }
    /// The amber caveat beside a score: haze or smoke thick enough to hide the Milky Way.
    func smokeCaveat(_ night:Night)->String? {
        guard let clarity=outlook(night)?.clarity, clarity.isCaveat else { return nil }
        return clarity.sentence
    }
    /// True when a night without clouds simply lies beyond the forecast's reach (past its last
    /// hour, or ten days or more ahead, where a forecast counts for nothing), rather than having a
    /// forecast that failed (`NightPlanner.beyondForecast`).
    func beyondForecast(_ night:Night)->Bool { NightPlanner.beyondForecast(night,forecast:forecasts[night.park.id],now:present) }
    func nights(_ park:Park,from date:Date,count:Int)->[Night] { (0..<count).map { night(park,on:park.date(date,addingDays:$0)) } }
    func nearby(latitude:Double?,longitude:Double?,radiusMiles:Double?=nil)->[Park] {
        guard let origin else { return [] }
        let lat=latitude ?? origin.latitude, lon=longitude ?? origin.longitude, miles=radiusMiles ?? self.radiusMiles
        return parks.filter { $0.distanceMeters(latitude:lat,longitude:lon)<=miles*1609.344 }
    }
    /// Where distances are measured from without "Near me": the chosen place, else the starting park.
    var origin:(latitude:Double,longitude:Double)? { homePlace.map { ($0.latitude,$0.longitude) } ?? home.map { ($0.latitude,$0.longitude) } }
    /// The starting point's name: "Chicago" or "Joshua Tree".
    var originName:String { homePlace?.name ?? home?.shortName ?? "" }
    /// Start from a park: distances from it, and no place.
    func choose(parkID:String) { homePlace=nil; homeID=parkID; startChosen=true }
    /// Start from a city or town: distances from it, and the park nearest to it as the home park
    /// (the sky behind the app, the calendar's first park, the widget before anything is saved).
    func choose(_ place:StartingPlace) {
        homePlace=place; startChosen=true
        if let nearest=Self.nearestPark(to:place,in:parks) { homeID=nearest.id }
    }
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
        let parks=self.parks, weather=self.weather, detailService=self.detailService, parkStore=self.parkStore
        async let cachedForecasts=weather.hydrate(parks)
        async let cachedDetails=detailService.hydrate(parks)
        async let cachedAlerts=parkStore.hydrate(parks)
        let (f,d,a)=await (cachedForecasts,cachedDetails,cachedAlerts)
        for (id,forecast) in f where forecasts[id] == nil { forecasts[id]=forecast }
        for (id,detail) in d where details[id] == nil { details[id]=detail }
        if alertsCache == nil { apply(a) }
        LaunchSignposts.end(interval)
        LaunchSignposts.note("Caches ready")
    }
    /// Forecasts for every park arrive together (one or two requests); park updates (alerts, and
    /// ranger programs where they are shown) follow park by park, and only when asked for.
    func refresh(_ parks:[Park],force:Bool=false,parkUpdates:Bool=true,programs:Bool=false) async {
        // Programs are asked for only on a park's page: from then on its forecast detail is wanted too.
        if programs { detailWanted=true }
        await refreshForecasts(watching:parks,force:force)
        lastRefresh=Date.now
        if parkUpdates { await refreshParkUpdates(parks,force:force,programs:programs) }
    }
    /// Always asks for all 63 parks, never only those near the device: it costs the same request,
    /// and a list of nearby parks would tell the forecast service roughly where you are.
    func refreshForecasts(watching parks:[Park],force:Bool=false) async {
        let live=DebugScenario.screen == nil || DebugScenario.state == "live"
        if DebugScenario.state=="no-forecast" { for park in parks { forecasts[park.id]=nil; details[park.id]=nil }; return }
        #if DEBUG
        if let state=DebugScenario.state, let fixture=DebugForecasts(state:state,parks:self.parks,now:today) {
            forecasts=fixture.forecasts; details=fixture.details; return
        }
        #endif
        await hydration?.value
        let network=weatherEnabled && live
        let fresh=await weather.forecasts(for:self.parks,network:network,force:force)
        for park in self.parks where forecasts[park.id]?.updated != fresh[park.id]?.updated { forecasts[park.id]=fresh[park.id] }
        // Switched off, the air-quality host's cached data is dropped rather than merely not refreshed.
        if !smokeEnabled { await detailService.forgetAir() }
        let detail=await detailService.details(for:self.parks,weather:network && detailWanted,smoke:smokeEnabled && live && detailWanted,force:force)
        for park in self.parks where details[park.id] != detail[park.id] { details[park.id]=detail[park.id] }
        let paused=await detailService.pausedForLowData()
        if paused != detailPausedForLowData { detailPausedForLowData=paused }
        guard network else { return }
        for park in parks {
            if let forecast=fresh[park.id],Date.now.timeIntervalSince(forecast.updated)<6*3600 { staleForecasts.remove(park.id) } else { staleForecasts.insert(park.id) }
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
            if let fresh=await parkStore.programs(for:park,key:key,network:network,force:force) { self.programs[park.id]=fresh; rebuild(park) }
        }
    }
    private func apply(_ update:AlertsUpdate) {
        // `-nyx-alerts-busy` (DEBUG): the busy state for screenshots.
        let busy=update.busy || DebugScenario.isEnabled("alerts-busy")
        if alertsBusy != busy { alertsBusy=busy }
        guard update.cache != alertsCache else { return }
        alertsCache=update.cache
        for park in parks { rebuild(park) }
    }
    /// One park's update as the screens read it: its alerts from the shared request, ranked, and
    /// its programs if its page has asked for them.
    private func rebuild(_ park:Park) {
        guard let cache=alertsCache, let alerts=cache.alerts[park.apiCode] else { return }
        let today=park.isoDay(Date.now), shown=programs[park.id]
        enrichments[park.id]=ParkEnrichment(updated:cache.updated,alerts:AlertRanking.ranked(alerts),programs:(shown?.programs ?? []).filter { $0.date>=today },description:nil,programsUpdated:shown?.updated)
    }
    /// A closure from the last park update, if any: a road, trail, campground, area or the park
    /// itself, never an amenity notice. Shown beside every score for that park.
    func closure(_ park:Park)->String? {
        AlertRanking.closure(enrichments[park.id]?.alerts ?? [])?.displayTitle(park:park)
    }
    /// Every park's campgrounds from the NPS, asked for only when a park's "Where to stay" opens,
    /// in one request for all 63 parks, kept seven days (`ParkStore.campgrounds`).
    func refreshCampgrounds(force:Bool=false) async {
        let live=DebugScenario.screen == nil || DebugScenario.state == "live"
        await hydration?.value
        let fresh=await parkStore.campgrounds(for:parks,key:npsKey,network:npsEnabled && live,force:force)
        if let fresh, fresh != campgrounds { campgrounds=fresh }
    }
    func alertSummary(_ park:Park)->String {
        guard let data=enrichments[park.id] else {
            return alertsBusy ? String(localized:"Park alerts are busy. Check current conditions on nps.gov.") : String(localized:"Access not checked. Confirm closures with the park.")
        }
        if let closure=closure(park) { return closure }
        if let danger=data.alerts.first(where:{ $0.kind == .danger }) { return danger.displayTitle(park:park) }
        if data.alerts.isEmpty { return String(localized:"No alerts in the last park update. Confirm access before travel.") }
        return String(localized:"No closures in the last park update. Check all park alerts before you go.")
    }
    /// `alertSummary` as short facts for one caption, only when the last park update lists nothing
    /// to stop a trip (no closure, no danger): the fact, then the cue to check before going. Nil
    /// otherwise, when the summary's full sentence stands alone.
    func alertFacts(_ park:Park)->[String]? {
        guard let data=enrichments[park.id], closure(park) == nil, !data.alerts.contains(where:{ $0.kind == .danger }) else { return nil }
        if data.alerts.isEmpty { return [String(localized:"No alerts listed"),String(localized:"confirm access before you go")] }
        return [String(localized:"No closures listed"),String(localized:"check alerts before you go")]
    }
}
@MainActor @Observable final class LocationService: NSObject, CLLocationManagerDelegate {
    var latitude:Double?
    var longitude:Double?
    var denied=false
    var locating=false
    var message:String?
    private let manager=CLLocationManager()
    override init() { super.init(); manager.delegate=self; manager.desiredAccuracy=kCLLocationAccuracyThreeKilometers }
    func request() {
        locating=true
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways { manager.requestLocation() }
        else if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted { denied=true; locating=false }
        else { manager.requestWhenInUseAuthorization() }
    }
    func locationManagerDidChangeAuthorization(_ manager:CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse,.authorizedAlways: denied=false; if locating { manager.requestLocation() }
        case .denied,.restricted: denied=true; locating=false
        default: break
        }
    }
    func locationManager(_ manager:CLLocationManager,didUpdateLocations locations:[CLLocation]) {
        guard let location=locations.last else { locating=false; return }
        latitude=location.coordinate.latitude; longitude=location.coordinate.longitude; locating=false; message=nil
    }
    /// Return to the chosen starting park.
    func clear() { latitude=nil; longitude=nil; message=nil }
    /// Back in the app: a fresh fix, only when "near me" is in use and already allowed. Never asks.
    func refreshIfAuthorized() {
        guard latitude != nil, manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways else { return }
        manager.requestLocation()
    }
    func locationManager(_ manager:CLLocationManager,didFailWithError error:any Error) {
        locating=false; message=String(localized:"Location is unavailable. Choose a starting point instead.")
    }
}
