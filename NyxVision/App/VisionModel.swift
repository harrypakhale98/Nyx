import SwiftUI
import simd

/// One park on one night, computed on device: the sky, the night as the iPhone scores it
/// (`NightPlanner.night`: the cloud forecast where it reaches, eased toward the park's usual clouds
/// days ahead, the usual clouds alone beyond it; mid and high cloud only over Haleakalā's summit
/// when its layer forecast covers the night; smoke or haze from the aerosol forecast) and what's up.
nonisolated struct NightPlan: Sendable {
    let park: Park
    let sky: SkyConditions
    let night: Night
    /// The park's last cloud forecast, for the immersive sky's hour-by-hour clouds: over a summit
    /// scored from mid and high cloud, those layers combined (low cloud lies below the observer).
    let forecast: Forecast?
    /// True when the night has no forecast clouds because it lies beyond the forecast's reach;
    /// false for one the forecast should reach but could not (switched off, never fetched, unreadable).
    var beyondForecast: Bool { night.beyondForecast }
    var score: DarknessScore { night.score }
    let whatsUp: WhatsUp
    let moon: MoonGeometry
    let moonMoment: Date
    /// The Moon's topocentric altitude at `moonMoment`, its highest of the night: below the
    /// horizon's −0.833° means it never rises that night.
    let moonAltitude: Double
    var span: DateInterval { SkyDome.span(for: sky) }
    /// `layers`: the summit's mid and high cloud (`SummitLayerService`), for parks above the inversion;
    /// `air`: the park's aerosol forecast (`ForecastDetailService`, smoke only).
    init(park: Park, night: Date, isTonight: Bool, forecast: Forecast?, layers: HourlySeries?, air: HourlySeries?, now: Date) {
        let engine = AstronomyEngine()
        self.park = park
        sky = engine.conditions(for: park, on: night)
        let scored = NightPlanner.night(park: park, sky: sky, forecast: forecast, detail: ForecastDetail.vision(layers: layers, air: air), now: now)
        self.night = scored
        self.forecast = scored.upperCloudOnly ? layers?.upperCloud ?? forecast : forecast
        whatsUp = WhatsUp(park: park, sky: sky, isTonight: isTonight)
        moonMoment = engine.moonViewTime(for: sky, park: park)
        moon = engine.moonGeometry(for: park, at: moonMoment)
        moonAltitude = engine.lunarAltitude(at: moonMoment, park: park)
    }
    /// The cloud cover the immersive sky draws at `moment` (0…1), or nil when no forecast hour
    /// reaches it (`SkyDome.cloud`).
    func cloud(at moment: Date) -> Double? { SkyDome.cloud(at: moment, forecast: forecast, basis: night.basis, usual: night.usualCloud) }
    /// The Moon's line when it neither rises nor sets this night.
    var moonAllNight: String { moonAltitude > -0.833 ? String(localized: "Up all night") : String(localized: "Down all night") }
}

/// Where everything is at one moment of a night, for the immersive sky and for the window's
/// spoken and written list of it (the non-immersive way to stand under the same sky).
nonisolated struct SkyMoment: Sendable {
    struct Body: Sendable, Identifiable, Equatable {
        enum Kind: Sendable { case moon, planet, core }
        let id: String
        let kind: Kind
        let name: String
        let altitude: Double
        let azimuth: Double
        /// Planets only: apparent magnitude.
        var magnitude: Double = 0
        var up: Bool { altitude > 0 }
        /// "32° up in the southeast" or "below the horizon".
        var place: String {
            altitude <= 0 ? String(localized: "below the horizon")
                : String(localized: "\(Int(altitude.rounded()))° up in the \(Compass.name(azimuth))")
        }
    }
    let date: Date
    let sunAltitude: Double
    let sunAzimuth: Double
    let moon: Body
    let moonIllumination: Double
    let planets: [Body]
    let core: Body
    let rotation: simd_double3x3

    init(park: Park, at date: Date) {
        let engine = AstronomyEngine(), almanac = SkyAlmanac()
        self.date = date
        let sun = engine.equatorial(of: .sun, at: date)
        let sunPlace = engine.horizontal(date: date, park: park, ra: sun.ra, dec: sun.dec)
        sunAltitude = sunPlace.altitude
        sunAzimuth = sunPlace.azimuth
        let moonPosition = engine.equatorial(of: .moon, at: date)
        let moonPlace = engine.horizontal(date: date, park: park, ra: moonPosition.ra, dec: moonPosition.dec)
        // Topocentric altitude: parallax lowers the Moon by up to a degree.
        moon = Body(id: "moon", kind: .moon, name: String(localized: "Moon"), altitude: engine.lunarAltitude(at: date, park: park), azimuth: moonPlace.azimuth)
        moonIllumination = engine.moonPhase(at: date).illumination
        planets = SkyAlmanac.Planet.allCases.map { planet in
            let p = almanac.position(of: planet, at: date)
            let h = engine.horizontal(date: date, park: park, ra: p.ra, dec: p.dec)
            return Body(id: planet.rawValue, kind: .planet, name: planet.name, altitude: h.altitude, azimuth: h.azimuth, magnitude: p.magnitude)
        }
        let corePlace = engine.horizontal(date: date, park: park, ra: SkyAlmanac.coreRA, dec: SkyAlmanac.coreDec)
        core = Body(id: "core", kind: .core, name: String(localized: "Milky Way core"), altitude: corePlace.altitude, azimuth: corePlace.azimuth)
        rotation = SkyDome.rotation(at: date, park: park)
    }
    /// The sky's state in words, as the iPhone's sky says it: "True darkness", "Late twilight".
    var twilight: String {
        if sunAltitude > -0.833 { return String(localized: "The Sun is up") }
        if sunAltitude > -6 { return String(localized: "Twilight") }
        if sunAltitude > -12 { return String(localized: "Late twilight") }
        if sunAltitude > -18 { return String(localized: "Nearly dark") }
        return String(localized: "True darkness")
    }
    /// Planets worth showing: above the horizon in a sky dark enough to see them.
    var visiblePlanets: [Body] { sunAltitude <= -6 ? planets.filter { $0.altitude > 2 }.sorted { $0.magnitude < $1.magnitude } : [] }
}

/// The app's state, shared by the window and the immersive sky.
@Observable final class VisionModel {
    let parks: [Park]
    var selectedID: String? {
        didSet {
            guard settled, selectedID != oldValue else { return }
            readCacheIfPending()
            refresh(resetTime: true)
            refreshAhead()
            // Remembered for the next launch; a pinned clock (previews, DEBUG captures) leaves it alone.
            if !pinned, let selectedID { UserDefaults.standard.set(selectedID, forKey: Self.parkKey) }
        }
    }
    /// Nights after tonight (park-local), so stepping moves every park together.
    var nightOffset = 0 { didSet { if settled, nightOffset != oldValue, !keepingNight { refresh(resetTime: true); refreshList() } } }
    /// Position in the night's span, sunset (0) to sunrise (1).
    var fraction = 0.5 { didSet { if fraction != oldValue { updateSkyMoment() } } }
    var nightVision = false
    var immersiveOpen = false
    /// The body whose name card is showing in the sky.
    var selectedBody: String?
    private(set) var plan: NightPlan? { didSet { updateSkyMoment() } }
    /// Where everything is at the clock's moment, computed once per change of the clock or the
    /// plan (the ornament, the window's written sky and the immersive sky all read it each frame
    /// of a sweep).
    private(set) var skyMoment: SkyMoment?
    /// Planner windows open right now (the planner is a window group, so there may be several);
    /// the Moon volume offers a way back to one only when none is on screen.
    var plannerWindows = 0
    var plannerOpen: Bool { plannerWindows > 0 }
    /// Every park's night for the list, scored as `plan` is.
    private(set) var listNights: [String: Night] = [:]
    /// The darkest of the chosen park's next 14 nights, scored as `plan` is (`NightsAhead`). It
    /// may still be the previous park's for a moment after a change: check its `park`.
    private(set) var ahead: NightsAhead?
    /// A park, or its sky, asked for by Siri or Shortcuts (`VisionIntents.swift`), for the planner
    /// window to act on once it is active.
    var intentRequest: VisionIntentRequest?
    /// A Handoff arrived for a place Vision Pro does not carry (a saved spot, a place abroad): the
    /// planner says so in a calm alert rather than doing nothing.
    var handoffElsewhere = false
    /// The last cloud forecast for each park, from this headset's cache or Open-Meteo
    /// (`VisionModel+Forecasts.swift`). A change rescores the night, the list and the nights ahead.
    var forecasts: [String: Forecast] = [:] { didSet { if settled { refresh(resetTime: false); refreshList(); refreshAhead() } } }
    /// Mid and high cloud over the summits above the inversion (Haleakalā), from this headset's
    /// cache or Open-Meteo (`SummitLayerService`). A change rescores the night, the list and the nights ahead.
    var summitLayers: [String: HourlySeries] = [:] { didSet { if settled { refresh(resetTime: false); refreshList(); refreshAhead() } } }
    /// Each park's aerosol forecast (smoke and haze), from this headset's cache or Open-Meteo's
    /// air-quality service (`ForecastDetailService`, smoke only), counted in the score as on the
    /// iPhone. A change rescores the night, the list and the nights ahead.
    var smoke: [String: HourlySeries] = [:] { didSet { if settled { refresh(resetTime: false); refreshList(); refreshAhead() } } }
    /// The last park update (NPS alerts for every park), from this headset's cache or
    /// developer.nps.gov (`ParkStore`): the closure beside each score.
    var alerts: ParkAlertsCache?
    /// The Park Service refused the last request, or is being left alone after one.
    var alertsBusy = false
    /// "Cloud forecasts (Open-Meteo)" in Your privacy: on unless turned off. The transport reads
    /// the same preference before any request (`SafeHTTP`), so off means no request at all.
    var forecastsOn = CloudForecastSwitch.isOn() {
        didSet {
            guard forecastsOn != oldValue else { return }
            UserDefaults.standard.set(forecastsOn, forKey: CloudForecastSwitch.key)
            if forecastsOn { Task { await refreshForecasts() } }
        }
    }
    /// "Smoke and haze" in Your privacy, the iPhone's preference and words. Off, the aerosol
    /// forecast on this headset is dropped, so no score counts it, and nothing more is asked.
    var smokeOn = UserDefaults.standard.object(forKey: VisionModel.smokeKey) as? Bool ?? true {
        didSet {
            guard smokeOn != oldValue else { return }
            UserDefaults.standard.set(smokeOn, forKey: Self.smokeKey)
            if smokeOn { Task { await refreshForecasts() } } else { smoke = [:]; Task { await detailService.forgetAir() } }
        }
    }
    /// "Park alerts" in Your privacy, the iPhone's preference. Off, nothing more is asked; closures
    /// already on this headset still stand beside the score, as on the iPhone.
    var alertsOn = UserDefaults.standard.object(forKey: VisionModel.alertsKey) as? Bool ?? true {
        didSet {
            guard alertsOn != oldValue else { return }
            UserDefaults.standard.set(alertsOn, forKey: Self.alertsKey)
            if alertsOn { Task { await refreshForecasts() } }
        }
    }
    nonisolated static let smokeKey = "smokeEnabled", alertsKey = "npsEnabled"
    /// What every score here counts, and what it says it does not (`ScoreInputs`).
    var inputs: ScoreInputs {
        ScoreInputs(smokeOn: smokeOn, smokeKnown: Set(smoke.keys), alertsOn: alertsOn, alerts: alerts, alertsBusy: alertsBusy)
    }
    let weather: any WeatherProviding
    let summits: SummitLayerService
    let detailService: ForecastDetailService
    let parkStore: ParkStore
    private var planTask: Task<Void, Never>?
    private var listTask: Task<Void, Never>?
    private var aheadTask: Task<Void, Never>?
    /// The moment "tonight" is judged from. Moved on only when some park's night turns over (its
    /// sunrise, or local noon in polar night), as on the iPhone (`PlanModel.tick`): Vision Pro
    /// keeps an app suspended for days, and a launch-time clock would leave Tonight, Back to
    /// tonight, the Moon volume and each night's forecast basis on a night long past.
    private(set) var now: Date
    /// Set while `tick` re-bases `nightOffset` on the new tonight, which keeps the same night.
    private var keepingNight = false
    /// False while `init` sets the launch state, so no observer starts a second computation of it.
    @ObservationIgnored private var settled = false
    /// True from launch until every park's cached forecast has been read off the main thread and
    /// merged. Meanwhile a newly chosen park reads its own cache first (`readCacheIfPending`) and
    /// the list waits, so no score is computed without a forecast already on this headset.
    @ObservationIgnored private var readingCache = false
    /// True when forecasts come from the app's own services, whose cache files a chosen park can
    /// read directly; previews and tests that hand in a service read only through it.
    @ObservationIgnored private var readsCacheFiles = false

    /// A clock fixed by the caller (previews) or by DEBUG's `-nyx-date` never moves.
    private let pinned: Bool

    init(now: Date? = nil, parks: [Park]? = nil, weather: (any WeatherProviding)? = nil, summits: SummitLayerService? = nil,
         detailService: ForecastDetailService? = nil, parkStore: ParkStore? = nil) {
        let start = now ?? VisionDebug.date ?? .now
        self.now = start
        pinned = now != nil || VisionDebug.date != nil
        self.parks = (parks ?? (try? ParkData.load()) ?? []).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        self.weather = weather ?? WeatherService()
        self.summits = summits ?? SummitLayerService()
        self.detailService = detailService ?? ForecastDetailService(extras: false)
        self.parkStore = parkStore ?? ParkStore()
        nightVision = VisionDebug.isEnabled("night-vision")
        // The park chosen last time; previews and DEBUG captures (a pinned clock) always open Joshua Tree.
        selectedID = VisionDebug.park ?? (pinned ? Self.defaultPark : Self.rememberedPark(in: self.parks))
        nightOffset = VisionDebug.nightOffset ?? 0
        // First content is the chosen park's night, computed here so the window's first frame holds
        // it rather than waiting its turn behind the scenes' setup on the main actor. It is scored
        // with that park's cached forecast (one small file, the one the service reads), so the
        // score shown first is the one the cache gives, never one that changes once it is read.
        if let park {
            #if DEBUG
            if let cover = VisionDebug.clouds { forecasts = Self.fixture(parks: self.parks, cover: cover, issued: start) }
            #endif
            if VisionDebug.clouds == nil, weather == nil {
                readsCacheFiles = true
                forecasts = Self.cachedForecast(for: park)
                summitLayers = Self.cachedLayers(for: park)
                if smokeOn { smoke = Self.cachedSmoke(for: park) }
                // One small file for every park: the closure stands beside the first score.
                alerts = ParkStore.stored(self.parks)
            }
            let first = NightPlan(park: park, night: night(for: park), isTonight: nightOffset == 0,
                                  forecast: forecasts[park.id], layers: summitLayers[park.id], air: smoke[park.id], now: start)
            fraction = Self.opening(of: first)
            plan = first
        }
        settled = true
        refreshAhead()
        // Every park's cached forecast, read off the main thread from the start. The list waits for
        // it, so no park's score changes once shown for want of a file already on this headset; the
        // window then asks for fresh forecasts.
        if VisionDebug.clouds == nil {
            let parks = self.parks, service = self.weather, summits = self.summits, details = self.detailService, store = self.parkStore
            let held = alerts, smokeOn = smokeOn
            readingCache = true
            let cached = Task.detached(priority: .userInitiated) {
                // The alerts already read are handed to the store, so its file is not read twice.
                if let held { await store.seed(held) }
                return (await service.forecasts(for: parks, network: false, force: false), await summits.layers(for: parks, network: false),
                        smokeOn ? await details.hydrate(parks).compactMapValues(\.air) : [:], await store.hydrate(parks))
            }
            Task {
                let (fresh, layers, air, update) = await cached.value
                readingCache = false
                take(update)
                if !merge(fresh, layers: layers, smoke: air) { refreshList() }
            }
        } else {
            refreshList()
        }
    }
    /// One park's cached cloud forecast and summit layers, read where the services keep them.
    private static func cachedForecast(for park: Park) -> [String: Forecast] {
        CacheDirectory.read(Forecast.self, name: SpotForecast.cacheName(park.id)).map { [park.id: $0] } ?? [:]
    }
    private static func cachedLayers(for park: Park) -> [String: HourlySeries] {
        guard park.aboveInversion == true else { return [:] }
        return CacheDirectory.read(HourlySeries.self, name: "summit-\(park.id)").map { [park.id: $0] } ?? [:]
    }
    /// One park's cached aerosol forecast, where `ForecastDetailService` keeps it.
    private static func cachedSmoke(for park: Park) -> [String: HourlySeries] {
        CacheDirectory.read(ForecastDetail.self, name: "detail-\(park.id)")?.air.map { [park.id: $0] } ?? [:]
    }
    /// A park chosen (from the list, Handoff, Siri or Shortcuts) before every park's cache has been
    /// read: its own cached forecast and summit layers, read here as `init` reads the first park's,
    /// so its night and nights ahead are scored with them from the first frame. Read quietly (no
    /// rescoring of the old park); the caller then scores the new one.
    private func readCacheIfPending() {
        guard readingCache, readsCacheFiles, let park else { return }
        let forecast = forecasts[park.id] == nil ? Self.cachedForecast(for: park) : [:]
        let layers = summitLayers[park.id] == nil ? Self.cachedLayers(for: park) : [:]
        let air = smokeOn && smoke[park.id] == nil ? Self.cachedSmoke(for: park) : [:]
        guard !forecast.isEmpty || !layers.isEmpty || !air.isEmpty else { return }
        settled = false
        defer { settled = true }
        if !forecast.isEmpty { forecasts.merge(forecast) { held, _ in held } }
        if !layers.isEmpty { summitLayers.merge(layers) { held, _ in held } }
        if !air.isEmpty { smoke.merge(air) { held, _ in held } }
    }
    /// Where the night's clock opens: the middle of true darkness, or DEBUG's `-nyx-vision-time`.
    private static func opening(of plan: NightPlan) -> Double {
        VisionDebug.time ?? SkyDome.fraction(of: SkyDome.darkest(plan.sky), in: plan.span)
    }
    var park: Park? { parks.first { $0.id == selectedID } }
    /// Where the chosen park is remembered between launches (this headset's UserDefaults only).
    nonisolated static let parkKey = "visionSelectedPark"
    nonisolated static let defaultPark = Park.defaultID
    /// The park chosen last time if it is still one of `parks`, else Joshua Tree.
    nonisolated static func rememberedPark(in parks: [Park], defaults: UserDefaults = .standard) -> String {
        guard let stored = defaults.string(forKey: parkKey), parks.contains(where: { $0.id == stored }) else { return defaultPark }
        return stored
    }
    func night(for park: Park) -> Date { park.date(park.currentNight(at: now), addingDays: nightOffset) }
    var moment: Date? { plan.map { SkyDome.moment(fraction, in: $0.span) } }
    private func updateSkyMoment() {
        skyMoment = plan.flatMap { plan in moment.map { SkyMoment(park: plan.park, at: $0) } }
    }

    /// Moves "tonight" on to `date` once some park's night has turned over; otherwise nothing
    /// changes (and nothing redraws). A later night the person stepped to stays the same night,
    /// one step nearer; tonight becomes the new tonight, opening at its middle of darkness. A
    /// pinned clock never moves.
    func tick(_ date: Date = .now) {
        guard !pinned, parks.contains(where: { $0.currentNight(at: now) != $0.currentNight(at: date) }) else { return }
        let before = now
        now = date
        var newNight = false
        if let park {
            let turned = park.calendar.dateComponents([.day], from: park.currentNight(at: before), to: park.currentNight(at: date)).day ?? 0
            // The chosen night changes unless a later night simply came one step nearer.
            newNight = turned < 0 || nightOffset < turned
            if turned > 0, nightOffset > 0 {
                keepingNight = true
                nightOffset = max(0, nightOffset-turned)
                keepingNight = false
            }
        }
        refresh(resetTime: newNight)
        refreshList()
        refreshAhead()
    }
    /// While a window is in use: the clock checked at once and every minute, so a night turning
    /// over at the chosen park's sunrise reaches the window within the minute.
    func keepClock() async {
        while !Task.isCancelled {
            tick()
            try? await Task.sleep(for: .seconds(60))
        }
    }

    /// Recomputes the chosen night off the main thread; the sky opens at the middle of true darkness.
    private func refresh(resetTime: Bool) {
        guard let park else { plan = nil; return }
        let night = night(for: park), tonight = nightOffset == 0, forecast = forecasts[park.id], layers = summitLayers[park.id], air = smoke[park.id], now = now
        planTask?.cancel()
        // Started at once, off the main actor; only handing the result over waits for it.
        let work = Task.detached(priority: .userInitiated) { NightPlan(park: park, night: night, isTonight: tonight, forecast: forecast, layers: layers, air: air, now: now) }
        planTask = Task {
            let plan = await work.value
            guard !Task.isCancelled else { return }
            self.plan = plan
            if resetTime { self.fraction = Self.opening(of: plan) }
        }
    }
    private func refreshList() {
        // Every park's cached forecast is still being read: the list keeps its loading state, and
        // is scored once the read lands (`init`).
        guard !readingCache else { return }
        let parks = parks, offset = nightOffset, now = now, forecasts = forecasts, layers = summitLayers, smoke = smoke
        listTask?.cancel()
        let work = Task.detached(priority: .utility) {
            let engine = AstronomyEngine()
            var result: [String: Night] = [:]
            for park in parks {
                let night = park.date(park.currentNight(at: now), addingDays: offset)
                result[park.id] = NightPlanner.night(park: park, sky: engine.conditions(for: park, on: night), forecast: forecasts[park.id],
                                                     detail: ForecastDetail.vision(layers: layers[park.id], air: smoke[park.id]), now: now)
            }
            return result
        }
        listTask = Task {
            let nights = await work.value
            guard !Task.isCancelled else { return }
            listNights = nights
        }
    }
    /// The chosen park's darkest nights from tonight on, off the main thread. Stepping between
    /// nights leaves it alone: it always looks ahead from tonight.
    private func refreshAhead() {
        guard let park else { ahead = nil; return }
        let now = now, forecasts = forecasts, details = Self.details(layers: summitLayers, smoke: smoke)
        aheadTask?.cancel()
        let work = Task.detached(priority: .utility) {
            NightsAhead(park: park, planner: NightPlanner(forecasts: forecasts, details: details), now: now)
        }
        aheadTask = Task {
            let ahead = await work.value
            guard !Task.isCancelled else { return }
            self.ahead = ahead
        }
    }
    /// Every park's detail as `NightPlanner` reads it: summit layers and smoke, as the night above.
    nonisolated static func details(layers: [String: HourlySeries], smoke: [String: HourlySeries]) -> [String: ForecastDetail] {
        Set(layers.keys).union(smoke.keys).reduce(into: [:]) { result, id in result[id] = ForecastDetail.vision(layers: layers[id], air: smoke[id]) }
    }
    /// Opens a park (or keeps the chosen one, for `nil`) on tonight, for Siri and Shortcuts.
    func openTonight(_ parkID: String?) {
        if let parkID, parks.contains(where: { $0.id == parkID }) { selectedID = parkID }
        nightOffset = 0
    }

    /// The fastest the immersive sky may turn during a sweep, in degrees a second. The real sky
    /// turns 15° an hour; a whole sky wheeling faster than this around someone standing in it is
    /// uncomfortable.
    static let comfortableTurn = 20.0
    /// Moves the night's clock. Sweeps on the shared spring's timing unless Reduce Motion is on,
    /// when the sky jumps straight there. While the immersive sky is open the sweep eases in and
    /// out and lasts long enough that the sky never turns faster than `comfortableTurn`.
    func move(to target: Double, reduceMotion: Bool) {
        cancelSweep()
        let start = fraction, goal = min(1, max(0, target))
        guard !reduceMotion, abs(goal-start) > 0.002 else { fraction = goal; return }
        let immersive = immersiveOpen
        // Sidereal rate: 15.04° of sky per hour of clock. A cosine ease peaks at π/2 times its mean speed.
        let degrees = abs(goal-start)*(plan?.span.duration ?? 0)/3600*15.04
        let duration = immersive ? max(1.1, degrees/Self.comfortableTurn*Double.pi/2) : 1.1
        sweeping = ClockSweep(start: start, goal: goal, began: .now, duration: duration, immersive: immersive)
        drive()
    }
    func darkest(reduceMotion: Bool) {
        guard let plan else { return }
        move(to: SkyDome.fraction(of: SkyDome.darkest(plan.sky), in: plan.span), reduceMotion: reduceMotion)
    }
    func cancelSweep() { sweeping = nil; chasing = nil; driver?.cancel(); driver = nil }

    // MARK: Turning the sky by hand

    /// Constellation figures in the immersive sky (the window's toggle). On by default; not
    /// stored: of the planner's choices, Nyx on Vision Pro remembers only the park.
    var constellations = true
    /// For a drag across the immersive sky: the clock follows the hand toward `target`, but the
    /// sky never turns faster than `comfortableTurn`, however fast the hand moves.
    func turn(toward target: Double) {
        sweeping = nil
        let goal = min(1, max(0, target))
        if chasing == nil { chasing = ClockChase(goal: goal, last: .now) } else { chasing?.goal = goal }
        drive()
    }

    // MARK: The clock's motion, frame by frame

    /// A sweep to `goal`, `duration` seconds from `began`: in the window a critically damped ease-out
    /// like the app's spring; in the sky a gentle ease in and out, so the stars never lurch into motion.
    private struct ClockSweep { let start: Double; let goal: Double; let began: Date; let duration: Double; let immersive: Bool }
    /// The clock following a hand, as of the last frame.
    private struct ClockChase { var goal: Double; var last: Date }
    @ObservationIgnored private var sweeping: ClockSweep?
    @ObservationIgnored private var chasing: ClockChase?
    /// Drives the motion while only the window shows it; the immersive sky drives it from its own
    /// frames (`SceneEvents.Update`, `SkySpace`), in step with what is drawn.
    @ObservationIgnored private var driver: Task<Void, Never>?
    /// Whether the clock is moving on its own (a sweep, or a chase after the hand).
    var clockMoving: Bool { sweeping != nil || chasing != nil }
    /// One frame of the clock's motion at `now`, from whichever display is drawing it. Time-based, so
    /// a frame from the sky and one from the window in the same instant agree. False once at rest.
    @discardableResult func advance(to now: Date) -> Bool {
        if let sweep = sweeping {
            let t = min(1, max(0, now.timeIntervalSince(sweep.began)/sweep.duration))
            let eased = sweep.immersive ? (1-cos(Double.pi*t))/2 : (1 - (1 + 6*t)*exp(-6*t))/(1 - 7*exp(-6))
            fraction = sweep.start + (sweep.goal-sweep.start)*(t >= 1 ? 1 : eased)
            if t >= 1 { sweeping = nil }
        }
        if var chase = chasing {
            let step = now.timeIntervalSince(chase.last)
            chase.last = now
            let degrees = (plan?.span.duration ?? 0)/3600*15.04
            fraction = SkyDome.chaseStep(from: fraction, toward: chase.goal, seconds: step, degreesPerNight: degrees, limit: Self.comfortableTurn)
            chasing = abs(chase.goal-fraction) < 0.0001 ? nil : chase
        }
        return clockMoving
    }
    /// The window's driver: about 90 steps a second until the clock rests or the immersive sky opens
    /// (whose frames then carry it).
    private func drive() {
        guard !immersiveOpen, driver == nil else { return }
        driver = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, !self.immersiveOpen, self.advance(to: .now) else { break }
                try? await Task.sleep(for: .milliseconds(11))
            }
            if !Task.isCancelled { self?.driver = nil }
        }
    }
}
