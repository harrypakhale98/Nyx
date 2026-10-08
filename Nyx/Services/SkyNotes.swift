import Foundation

/// The best stretch of one forecast night: clear (hourly cloud under 30%), in true darkness, with
/// the Moon down where it matters, and when the Milky Way's core is 10° up within it. Found from
/// the hourly forecast already on the phone; only forecast nights have one.
nonisolated struct ClearWindow: Sendable, Equatable {
    let interval: DateInterval
    /// True when the Moon (at least 5% lit) is below the horizon throughout; a new Moon is not named.
    let moonDown: Bool
    /// Where the core is 10° up inside the window, when for at least half an hour.
    let core: DateInterval?
    /// Hourly cloud under this is "clear".
    static let clearBelow = 30.0
    /// Shorter stretches are not worth naming.
    static let minimum: TimeInterval = 1800

    /// "Best window: 11:40 PM – 3:10 AM · clear, Moon down; Milky Way core up throughout", park-local, to ten minutes.
    func line(park: Park) -> String {
        func t(_ d: Date) -> String { WhatsUp.around(d, park: park) }
        let tolerance = 600.0
        let coreAll = core.map { abs($0.start.timeIntervalSince(interval.start)) <= tolerance && abs($0.end.timeIntervalSince(interval.end)) <= tolerance } ?? false
        var parts = [String(localized: "clear")]
        if moonDown { parts.append(String(localized: "Moon down")) }
        var text = String(localized: "Best window: \(t(interval.start)) – \(t(interval.end)) · \(parts.joined(separator: ", "))")
        // The core in words of its own, as field mode names it: through the whole window, or for part of it.
        if coreAll { text += "; "+String(localized: "Milky Way core up throughout") }
        else if let core { text += "; "+String(localized: "Milky Way core up \(t(core.start)) – \(t(core.end))") }
        return text
    }

    /// `hours` are hourly cloud values (each describing the half hour either side of its time).
    static func find(park: Park, sky: SkyConditions, hours: [(time: Date, cloud: Double)],
                     engine: AstronomyEngine = AstronomyEngine(), almanac: SkyAlmanac = SkyAlmanac()) -> ClearWindow? {
        guard let start = sky.darkStart, let end = sky.darkEnd, end.timeIntervalSince(start) >= minimum, !hours.isEmpty else { return nil }
        let dark = DateInterval(start: start, end: end)
        func cloud(_ date: Date) -> Double? {
            hours.min { abs($0.time.timeIntervalSince(date)) < abs($1.time.timeIntervalSince(date)) }
                .flatMap { abs($0.time.timeIntervalSince(date)) <= 1800 ? $0.cloud : nil }
        }
        let clear = { (date: Date) in (cloud(date) ?? 100) < clearBelow }
        let lit = sky.moon.illumination >= 0.05
        let moonOK = { (date: Date) in !lit || engine.lunarAltitude(at: date, park: park) < -0.833 }
        var moonDown = lit
        var base = almanac.longest(in: dark) { clear($0) && moonOK($0) }
        if (base?.duration ?? 0) < minimum { base = almanac.longest(in: dark, where: clear); moonDown = false }
        guard let base, base.duration >= minimum else { return nil }
        let coreUp = { (date: Date) in engine.horizontal(date: date, park: park, ra: SkyAlmanac.coreRA, dec: SkyAlmanac.coreDec).altitude >= SkyAlmanac.coreMinimumAltitude }
        let core = almanac.longest(in: base, where: coreUp).flatMap { $0.duration >= minimum ? $0 : nil }
        return ClearWindow(interval: base, moonDown: moonDown, core: core)
    }
}

/// Short, plain lines a serious observer looks for beside What's up. None of them changes the
/// score; each is worked out on the phone from the sky, the park and its light domes.
nonisolated struct SkyNote: Sendable, Identifiable, Equatable {
    enum Kind: String, Sendable { case aurora, satellites, zodiacal, limit, glow }
    var id: Kind { kind }
    let kind: Kind
    let text: String
    var symbol: String {
        switch kind {
        case .aurora: "sparkles"
        case .satellites: "dot.radiowaves.up.forward"
        case .zodiacal: "sun.dust"
        case .limit: "eye"
        case .glow: "lightbulb"
        }
    }
}
nonisolated enum SkyNotes {
    /// Altitude of the Starlink-like shell whose sunlit satellites cross dark skies, km.
    static let shellKilometres = 550.0
    /// How far below the horizon the Sun can be with that shell overhead still sunlit: arccos(R/(R+h)), about 23°.
    static var shellDepression: Double { acos(6371/(6371+shellKilometres))*180/Double.pi }

    static func notes(park: Park, sky: SkyConditions, core: SkyAlmanac.CoreNight?, aerosol: Double?, glow: SkyGlow = .shared) -> [SkyNote] {
        var notes: [SkyNote] = []
        if let text = aurora(park: park, evening: sky.evening) { notes.append(SkyNote(kind: .aurora, text: text)) }
        if let text = coreGlow(park: park, sky: sky, core: core, glow: glow) { notes.append(SkyNote(kind: .glow, text: text)) }
        if let text = zodiacal(park: park, sky: sky) { notes.append(SkyNote(kind: .zodiacal, text: text)) }
        if let text = satellites(park: park, sky: sky) { notes.append(SkyNote(kind: .satellites, text: text)) }
        if let magnitude = limitingMagnitude(park: park, sky: sky, aerosol: aerosol) {
            let shown = (magnitude*2).rounded()/2
            notes.append(SkyNote(kind: .limit, text: String(localized: "Faintest stars to the eye at the darkest hour: about magnitude \(shown.formatted(.number.precision(.fractionLength(1)))), an estimate. Higher numbers are fainter stars.")))
        }
        return notes
    }

    // MARK: Aurora

    /// The eight Alaska parks, about August 20 to April 20, when nights are dark enough. Static:
    /// Nyx does not forecast aurora (that would need another service).
    static func aurora(park: Park, evening: Date) -> String? {
        guard park.state == "AK" else { return nil }
        let parts = park.calendar.dateComponents([.month, .day], from: evening)
        let key = (parts.month ?? 1)*100+(parts.day ?? 1)
        guard key >= 820 || key <= 420 else { return nil }
        return String(localized: "Aurora season here runs from late August to mid-April. When it shows, it also brightens the sky. Nyx does not forecast aurora.")
    }

    // MARK: Satellites

    /// When satellites overhead still catch sunlight during true darkness: while the Sun is less
    /// than about 23° below the horizon (a 550 km shell, arccos(R/(R+h))).
    static func satellites(park: Park, sky: SkyConditions, engine: AstronomyEngine = AstronomyEngine(), almanac: SkyAlmanac = SkyAlmanac()) -> String? {
        guard let start = sky.darkStart, let end = sky.darkEnd, end > start else { return nil }
        let depression = shellDepression
        let shadowed = { (date: Date) in engine.solarAltitude(at: date, park: park) < -depression }
        guard let shadow = almanac.longest(in: DateInterval(start: start, end: end), where: shadowed), shadow.duration >= 600 else {
            return String(localized: "Satellites overhead catch sunlight all through true darkness at this time of year.")
        }
        return String(localized: "Satellites overhead catch sunlight until \(WhatsUp.around(shadow.start, park: park)) and again from \(WhatsUp.around(shadow.end, park: park)).")
    }

    // MARK: Zodiacal light

    /// Sunlit dust along the ecliptic, seen where the ecliptic stands steep to the horizon: after
    /// dusk in late winter and spring, before dawn in autumn (inverted south of the equator). Only
    /// on a moon-free dark night under a reasonably dark sky (Bortle 4 or darker).
    static func zodiacal(park: Park, sky: SkyConditions, engine: AstronomyEngine = AstronomyEngine()) -> String? {
        guard sky.darkHours > 0, park.bortleEstimate <= 4, let start = sky.darkStart, let end = sky.darkEnd else { return nil }
        let month = park.calendar.component(.month, from: sky.evening)
        let south = park.latitude < 0
        let evening = south ? (8...10).contains(month) : (2...4).contains(month)
        let morning = south ? (3...5).contains(month) : (9...11).contains(month)
        let moonFree = { (date: Date) in sky.moon.illumination < 0.05 || engine.lunarAltitude(at: date, park: park) < -0.833 }
        if evening, moonFree(start.addingTimeInterval(2700)) {
            return String(localized: "Zodiacal light may show in the west after dusk: a faint cone of sunlit dust rising along the Sun's path.")
        }
        if morning, moonFree(end.addingTimeInterval(-2700)) {
            return String(localized: "Zodiacal light may show in the east before dawn: a faint cone of sunlit dust rising along the Sun's path.")
        }
        return nil
    }

    // MARK: Limiting magnitude

    /// Naked-eye limiting magnitude at the zenith at the night's best moment, an estimate: the
    /// Bortle class's (Bortle 2001), less up to 2 magnitudes for moonlight (the Krisciunas–Schaefer
    /// moonlight share at that moment), 1.086 × aerosol optical depth for haze, and twilight when
    /// the night has no true darkness. Never brighter than magnitude 3.
    static func limitingMagnitude(park: Park, sky: SkyConditions, aerosol: Double?, engine: AstronomyEngine = AstronomyEngine()) -> Double? {
        let window = SkyAlmanac.nightWindow(sky)
        guard window.duration > 0 else { return nil }
        let dark = sky.darkStart.flatMap { s in sky.darkEnd.map { DateInterval(start: s, end: max(s, $0)) } }
        let span = dark.flatMap { $0.duration > 0 ? $0 : nil } ?? window
        var best = Double.infinity
        var t = span.start
        while t <= span.end {
            let sun = engine.solarAltitude(at: t, park: park)
            let twilight = sun < -18 ? 0 : min(4, (sun+18)*0.35)
            let moon = AstronomyEngine.moonlight(phaseAngle: AstronomyEngine.phaseAngle(illumination: engine.moonPhase(at: t).illumination),
                                                 altitude: engine.lunarAltitude(at: t, park: park))
            best = min(best, 2*moon + twilight)
            t = t.addingTimeInterval(900)
        }
        guard best.isFinite else { return nil }
        let haze = aerosol.map { 1.086*max(0, $0) } ?? 0
        return max(3, SkyAlmanac.limitingMagnitude(bortle: park.bortleEstimate) - best - haze)
    }

    // MARK: Light domes

    /// When the core, at its highest in true darkness, stands within 30° of the park's strongest
    /// light dome (a dome with at least a fifth of the park's modelled glow, outside the darkest
    /// fifth of parks, where no dome is bright enough to matter).
    static func coreGlow(park: Park, sky: SkyConditions, core: SkyAlmanac.CoreNight?, glow: SkyGlow, almanac: SkyAlmanac = SkyAlmanac()) -> String? {
        guard let dark = core?.dark, let site = glow.park(park.id), glow.level(site.glow) >= 2,
              let dome = SkyGlow.namedDomes(site.domes).first, dome.share >= 0.2 else { return nil }
        let peak = almanac.highest(ra: SkyAlmanac.coreRA, dec: SkyAlmanac.coreDec, park: park, in: dark)
        let difference = abs(((peak.azimuth-dome.bearing).truncatingRemainder(dividingBy: 360)+540).truncatingRemainder(dividingBy: 360)-180)
        guard difference <= 30 else { return nil }
        if let city = dome.city, !city.isEmpty { return String(localized: "The core rises into the glow of \(city).") }
        return String(localized: "The core rises into the glow of a town to the \(SkyGlow.direction(dome.bearing)).")
    }
}
