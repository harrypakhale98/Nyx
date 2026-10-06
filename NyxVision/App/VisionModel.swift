import SwiftUI
import simd

/// One park on one night, computed on device: the sky, the moon-and-darkness score (Vision Pro
/// fetches no forecast, so clouds are never part of it) and what's up.
nonisolated struct NightPlan: Sendable {
    let park: Park
    let sky: SkyConditions
    let score: DarknessScore
    let whatsUp: WhatsUp
    let moon: MoonGeometry
    let moonMoment: Date
    var span: DateInterval { SkyDome.span(for: sky) }
    init(park: Park, night: Date, isTonight: Bool) {
        let engine = AstronomyEngine()
        self.park = park
        sky = engine.conditions(for: park, on: night)
        score = ScoreEngine().score(sky: sky, bortle: park.bortleEstimate, cloudCover: nil)
        whatsUp = WhatsUp(park: park, sky: sky, isTonight: isTonight)
        moonMoment = engine.moonViewTime(for: sky, park: park)
        moon = engine.moonGeometry(for: park, at: moonMoment)
    }
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
    private(set) var listScores: [String: DarknessScore] = [:]
    private var sweep: Task<Void, Never>?
    private var planTask: Task<Void, Never>?
    private var listTask: Task<Void, Never>?
    let now: Date

    init(now: Date = VisionDebug.date ?? .now) {
        self.now = now
        parks = ((try? ParkData.load()) ?? []).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        nightVision = VisionDebug.isEnabled("night-vision")
        selectedID = VisionDebug.park ?? "jotr"
        refresh(resetTime: true)
        refreshList()
    }
    var park: Park? { parks.first { $0.id == selectedID } }
    func night(for park: Park) -> Date { park.date(park.currentNight(at: now), addingDays: nightOffset) }
    var moment: Date? { plan.map { SkyDome.moment(fraction, in: $0.span) } }
    var skyMoment: SkyMoment? { plan.flatMap { plan in moment.map { SkyMoment(park: plan.park, at: $0) } } }

    /// Recomputes the chosen night off the main thread; the sky opens at the middle of true darkness.
    private func refresh(resetTime: Bool) {
        guard let park else { plan = nil; return }
        let night = night(for: park), tonight = nightOffset == 0
        planTask?.cancel()
        planTask = Task {
            let plan = await Task.detached(priority: .userInitiated) { NightPlan(park: park, night: night, isTonight: tonight) }.value
            guard !Task.isCancelled else { return }
            self.plan = plan
            if resetTime, let fraction = VisionDebug.time { self.fraction = fraction }
            else if resetTime { self.fraction = SkyDome.fraction(of: SkyDome.darkest(plan.sky), in: plan.span) }
        }
    }
    private func refreshList() {
        let parks = parks, offset = nightOffset, now = now
        listTask?.cancel()
        listTask = Task {
            let scores = await Task.detached(priority: .utility) {
                let engine = AstronomyEngine(), scorer = ScoreEngine()
                var result: [String: DarknessScore] = [:]
                for park in parks {
                    let night = park.date(park.currentNight(at: now), addingDays: offset)
                    result[park.id] = scorer.score(sky: engine.conditions(for: park, on: night), bortle: park.bortleEstimate, cloudCover: nil)
                }
                return result
            }.value
            guard !Task.isCancelled else { return }
            listScores = scores
        }
    }
    /// Moves the night's clock. Sweeps on the shared spring's timing unless Reduce Motion is on,
    /// when the sky jumps straight there.
    func move(to target: Double, reduceMotion: Bool) {
        sweep?.cancel()
        let start = fraction, goal = min(1, max(0, target))
        guard !reduceMotion, abs(goal-start) > 0.002 else { fraction = goal; return }
        sweep = Task {
            let duration = 1.1, began = Date.now
            while !Task.isCancelled {
                let t = min(1, Date.now.timeIntervalSince(began)/duration)
                // Critically damped ease-out: quick to start, settling softly, like the app's spring.
                let eased = 1 - (1 + 6*t)*exp(-6*t)
                fraction = start + (goal-start)*(t >= 1 ? 1 : eased/(1 - 7*exp(-6)))
                if t >= 1 { break }
                try? await Task.sleep(for: .milliseconds(11))
            }
        }
    }
    func darkest(reduceMotion: Bool) {
        guard let plan else { return }
        move(to: SkyDome.fraction(of: SkyDome.darkest(plan.sky), in: plan.span), reduceMotion: reduceMotion)
    }
    func cancelSweep() { sweep?.cancel() }
}
