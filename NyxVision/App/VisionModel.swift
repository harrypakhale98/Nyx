import SwiftUI
import simd

/// One park on one night, computed on device: the sky, the night as the iPhone scores it
/// (`NightPlanner.night`: the cloud forecast where it reaches, eased toward the park's usual clouds
/// days ahead, the usual clouds alone beyond it) and what's up.
nonisolated struct NightPlan: Sendable {
    let park: Park
    let sky: SkyConditions
    let night: Night
    /// The park's last cloud forecast, for the immersive sky's hour-by-hour clouds.
    let forecast: Forecast?
    var score: DarknessScore { night.score }
    let whatsUp: WhatsUp
    let moon: MoonGeometry
    let moonMoment: Date
    /// The Moon's topocentric altitude at `moonMoment`, its highest of the night: below the
    /// horizon's −0.833° means it never rises that night.
    let moonAltitude: Double
    var span: DateInterval { SkyDome.span(for: sky) }
    init(park: Park, night: Date, isTonight: Bool, forecast: Forecast?, now: Date) {
        let engine = AstronomyEngine()
        self.park = park
        self.forecast = forecast
        sky = engine.conditions(for: park, on: night)
        self.night = NightPlanner.night(park: park, sky: sky, forecast: forecast, detail: nil, now: now)
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
    /// The sky's state in words: "True darkness", "Nautical twilight".
    var twilight: String {
        if sunAltitude > -0.833 { return String(localized: "The Sun is up") }
        if sunAltitude > -6 { return String(localized: "Civil twilight") }
        if sunAltitude > -12 { return String(localized: "Nautical twilight") }
        if sunAltitude > -18 { return String(localized: "Astronomical twilight") }
        return String(localized: "True darkness")
    }
    /// Planets worth showing: above the horizon in a sky dark enough to see them.
    var visiblePlanets: [Body] { sunAltitude <= -6 ? planets.filter { $0.altitude > 2 }.sorted { $0.magnitude < $1.magnitude } : [] }
}

/// The app's state, shared by the window and the immersive sky.
@Observable final class VisionModel {
    let parks: [Park]
    var selectedID: String? { didSet { if selectedID != oldValue { refresh(resetTime: true) } } }
    /// Nights after tonight (park-local), so stepping moves every park together.
    var nightOffset = 0 { didSet { if nightOffset != oldValue { refresh(resetTime: true); refreshList() } } }
    /// Position in the night's span, sunset (0) to sunrise (1).
    var fraction = 0.5
    var nightVision = false
    var immersiveOpen = false
    /// The body whose name card is showing in the sky.
    var selectedBody: String?
    private(set) var plan: NightPlan?
    /// Every park's night for the list, scored as `plan` is.
    private(set) var listNights: [String: Night] = [:]
    /// The last cloud forecast for each park, from this headset's cache or Open-Meteo
    /// (`VisionModel+Forecasts.swift`). A change rescores the night and the list.
    var forecasts: [String: Forecast] = [:] { didSet { refresh(resetTime: false); refreshList() } }
    /// "Cloud forecasts (Open-Meteo)" in Your privacy: on unless turned off. The transport reads
    /// the same preference before any request (`SafeHTTP`), so off means no request at all.
    var forecastsOn = CloudForecastSwitch.isOn() {
        didSet {
            guard forecastsOn != oldValue else { return }
            UserDefaults.standard.set(forecastsOn, forKey: CloudForecastSwitch.key)
            if forecastsOn { Task { await refreshForecasts() } }
        }
    }
    let weather: any WeatherProviding
    private var sweep: Task<Void, Never>?
    private var planTask: Task<Void, Never>?
    private var listTask: Task<Void, Never>?
    let now: Date

    init(now: Date = VisionDebug.date ?? .now, parks: [Park]? = nil, weather: (any WeatherProviding)? = nil) {
        self.now = now
        self.parks = (parks ?? (try? ParkData.load()) ?? []).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        self.weather = weather ?? WeatherService()
        nightVision = VisionDebug.isEnabled("night-vision")
        selectedID = VisionDebug.park ?? "jotr"
        nightOffset = VisionDebug.nightOffset ?? 0
        refresh(resetTime: true)
        refreshList()
        // The cached forecasts first, read off the main thread; the window asks for fresh ones.
        Task { await refreshForecasts(network: false) }
    }
    var park: Park? { parks.first { $0.id == selectedID } }
    func night(for park: Park) -> Date { park.date(park.currentNight(at: now), addingDays: nightOffset) }
    var moment: Date? { plan.map { SkyDome.moment(fraction, in: $0.span) } }
    var skyMoment: SkyMoment? { plan.flatMap { plan in moment.map { SkyMoment(park: plan.park, at: $0) } } }

    /// Recomputes the chosen night off the main thread; the sky opens at the middle of true darkness.
    private func refresh(resetTime: Bool) {
        guard let park else { plan = nil; return }
        let night = night(for: park), tonight = nightOffset == 0, forecast = forecasts[park.id], now = now
        planTask?.cancel()
        planTask = Task {
            let plan = await Task.detached(priority: .userInitiated) { NightPlan(park: park, night: night, isTonight: tonight, forecast: forecast, now: now) }.value
            guard !Task.isCancelled else { return }
            self.plan = plan
            if resetTime, let fraction = VisionDebug.time { self.fraction = fraction }
            else if resetTime { self.fraction = SkyDome.fraction(of: SkyDome.darkest(plan.sky), in: plan.span) }
        }
    }
    private func refreshList() {
        let parks = parks, offset = nightOffset, now = now, forecasts = forecasts
        listTask?.cancel()
        listTask = Task {
            let nights = await Task.detached(priority: .utility) {
                let engine = AstronomyEngine()
                var result: [String: Night] = [:]
                for park in parks {
                    let night = park.date(park.currentNight(at: now), addingDays: offset)
                    result[park.id] = NightPlanner.night(park: park, sky: engine.conditions(for: park, on: night), forecast: forecasts[park.id], detail: nil, now: now)
                }
                return result
            }.value
            guard !Task.isCancelled else { return }
            listNights = nights
        }
    }
    /// The fastest the immersive sky may turn during a sweep, in degrees a second. The real sky
    /// turns 15° an hour; a whole sky wheeling faster than this around someone standing in it is
    /// uncomfortable.
    static let comfortableTurn = 20.0
    /// Moves the night's clock. Sweeps on the shared spring's timing unless Reduce Motion is on,
    /// when the sky jumps straight there. While the immersive sky is open the sweep eases in and
    /// out and lasts long enough that the sky never turns faster than `comfortableTurn`.
    func move(to target: Double, reduceMotion: Bool) {
        sweep?.cancel(); chase?.cancel(); chase = nil
        let start = fraction, goal = min(1, max(0, target))
        guard !reduceMotion, abs(goal-start) > 0.002 else { fraction = goal; return }
        let immersive = immersiveOpen
        // Sidereal rate: 15.04° of sky per hour of clock. A cosine ease peaks at π/2 times its mean speed.
        let degrees = abs(goal-start)*(plan?.span.duration ?? 0)/3600*15.04
        let duration = immersive ? max(1.1, degrees/Self.comfortableTurn*Double.pi/2) : 1.1
        sweep = Task {
            let began = Date.now
            while !Task.isCancelled {
                let t = min(1, Date.now.timeIntervalSince(began)/duration)
                // In the window, a critically damped ease-out like the app's spring; in the sky, a
                // gentle ease in and out, so the stars never lurch into motion.
                let eased = immersive ? (1-cos(Double.pi*t))/2 : (1 - (1 + 6*t)*exp(-6*t))/(1 - 7*exp(-6))
                fraction = start + (goal-start)*(t >= 1 ? 1 : eased)
                if t >= 1 { break }
                try? await Task.sleep(for: .milliseconds(11))
            }
        }
    }
    func darkest(reduceMotion: Bool) {
        guard let plan else { return }
        move(to: SkyDome.fraction(of: SkyDome.darkest(plan.sky), in: plan.span), reduceMotion: reduceMotion)
    }
    func cancelSweep() { sweep?.cancel(); chase?.cancel(); chase = nil }

    // MARK: Turning the sky by hand

    /// Constellation figures in the immersive sky (the window's toggle). On by default; not
    /// stored, since Nyx on Vision Pro keeps nothing between launches.
    var constellations = true
    private var chase: Task<Void, Never>?
    private var chaseGoal = 0.0
    /// For a drag across the immersive sky: the clock follows the hand toward `target`, but the
    /// sky never turns faster than `comfortableTurn`, however fast the hand moves.
    func turn(toward target: Double) {
        sweep?.cancel()
        chaseGoal = min(1, max(0, target))
        guard chase == nil else { return }
        chase = Task {
            var last = Date.now
            while !Task.isCancelled {
                let now = Date.now, step = now.timeIntervalSince(last)
                last = now
                let degrees = (plan?.span.duration ?? 0)/3600*15.04
                fraction = SkyDome.chaseStep(from: fraction, toward: chaseGoal, seconds: step, degreesPerNight: degrees, limit: Self.comfortableTurn)
                if abs(chaseGoal-fraction) < 0.0001 { break }
                try? await Task.sleep(for: .milliseconds(11))
            }
            // A cancelled chase may already have been replaced; only a finished one clears itself.
            if !Task.isCancelled { chase = nil }
        }
    }
}
