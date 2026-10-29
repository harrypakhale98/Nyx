import Foundation

/// The best window in words, on the iPhone (the watch draws it on its dial and says it with the ring).
nonisolated extension ClearWindow {
    /// "Best window: 11:40 PM – 3:10 AM · clear, Moon down; Milky Way core up throughout", park-local, to ten
    /// minutes; "Clear 7:30 PM – 5:30 AM, under the Moon" when a bright Moon washes it (`moonlit`).
    func line(park: Park) -> String {
        func t(_ d: Date) -> String { WhatsUp.around(d, park: park) }
        let tolerance = 600.0
        let coreAll = core.map { abs($0.start.timeIntervalSince(interval.start)) <= tolerance && abs($0.end.timeIntervalSince(interval.end)) <= tolerance } ?? false
        var parts = [String(localized: "clear")]
        if moonDown { parts.append(String(localized: "Moon down")) }
        // Under a bright Moon the clear hours are said as what they are, never as the best window.
        let text = moonlit ? String(localized: "Clear \(t(interval.start)) – \(t(interval.end)), under the Moon")
            : String(localized: "Best window: \(t(interval.start)) – \(t(interval.end)) · \(Phrase.clauses(parts))")
        // The core in words of its own, as field mode names it: through the whole window, or for part of it.
        if coreAll { return Phrase.addition(text, String(localized: "Milky Way core up throughout")) }
        if let core { return Phrase.addition(text, String(localized: "Milky Way core up \(t(core.start)) – \(t(core.end))")) }
        return text
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

    static func notes(park: Park, sky: SkyConditions, core: SkyAlmanac.CoreNight?, aerosol: Double?, auroraForecast: Bool = false, glow: SkyGlow = .shared) -> [SkyNote] {
        var notes: [SkyNote] = []
        if let text = aurora(park: park, evening: sky.evening, forecast: auroraForecast) { notes.append(SkyNote(kind: .aurora, text: text)) }
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

    /// Where aurora reaches, by geomagnetic latitude (`Geomagnetic.AuroraReach`), in either
    /// hemisphere, on nights when the Sun gets at least 12° below the horizon (for Alaska, about
    /// late August to mid-April). Standing guidance; tonight's forecast, when it reaches here, is a What's up item (`AuroraForecast`).
    /// `forecast`: NOAA's forecast is switched on and in hand, so What's up names aurora when it
    /// reaches here; without it the note says only what the aurora depends on.
    static func aurora(park: Park, evening: Date, forecast: Bool = false, engine: AstronomyEngine = AstronomyEngine()) -> String? {
        let reach = Geomagnetic.auroraReach(park)
        guard reach != .none, lowestSun(park: park, evening: evening, engine: engine) <= -12 else { return nil }
        let poleward = park.southern ? String(localized: "south") : String(localized: "north")
        switch reach {
        case .often: return forecast ? String(localized: "Aurora is often seen here on dark nights, sometimes overhead. When it shows, it also brightens the sky. It depends on the Sun's activity; when NOAA's forecast for the next three nights reaches here, What's up says so.")
            : String(localized: "Aurora is often seen here on dark nights, sometimes overhead. When it shows, it also brightens the sky. It depends on the Sun's activity.")
        case .active: return forecast ? String(localized: "Aurora reaches here on active nights, usually low toward the \(poleward). When it shows, it also brightens the sky. It depends on the Sun's activity; when NOAA's forecast for the next three nights reaches here, What's up says so.")
            : String(localized: "Aurora reaches here on active nights, usually low toward the \(poleward). When it shows, it also brightens the sky. It depends on the Sun's activity.")
        case .storms: return forecast ? String(localized: "Aurora reaches here only during strong solar storms, low toward the \(poleward). It depends on the Sun's activity; when NOAA's forecast for the next three nights reaches here, What's up says so.")
            : String(localized: "Aurora reaches here only during strong solar storms, low toward the \(poleward). It depends on the Sun's activity.")
        case .none: return nil
        }
    }
    /// The Sun's altitude at solar midnight, degrees: |φ + δ| − 90, with δ the Sun's declination at the night's middle.
    static func lowestSun(park: Park, evening: Date, engine: AstronomyEngine = AstronomyEngine()) -> Double {
        let dec = engine.equatorial(of: .sun, at: evening.addingTimeInterval(12*3600)).dec*180/Double.pi
        return abs(park.latitude+dec)-90
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
        let moonFree = { (date: Date) in engine.moonHidden(at: date, park: park, phase: sky.moon) }
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
