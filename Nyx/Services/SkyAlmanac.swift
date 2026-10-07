import Foundation

/// What is in a park's sky on a night besides darkness: the Milky Way's bright center, the naked-eye
/// planets, meteor showers and lunar eclipses. All computed on the phone from fixed positions,
/// low-precision orbital elements and a small bundled table (`sky-events.json`). None of it changes
/// the Darkness Score: these are reasons to go, never points.
///
/// Accuracy: the core and shower radiants are fixed J2000 positions (precession since 2000 moves them
/// about 0.4°); planets use Paul Schlyter's elements with the Jupiter–Saturn perturbations, within
/// about 1° of PyEphem from 2026 to 2032 (see `SkyAlmanacTests`). Times are found on a 5-minute grid
/// and refined to under a minute, so rise and set times carry the same ±few-minute horizon caveats as
/// the rest of the app (no terrain, standard refraction).
nonisolated struct SkyAlmanac: Sendable {
    private let engine = AstronomyEngine()
    private static let rad = Double.pi/180

    // MARK: The Milky Way's bright center

    /// Sagittarius A*, the galactic center (J2000).
    static let coreRA = 266.405*rad, coreDec = -29.008*rad
    /// The core counts as up when 10° clear of the horizon: lower, haze and terrain usually hide it.
    static let coreMinimumAltitude = 10.0

    struct CoreNight: Sendable, Equatable {
        /// Crossings of 10° altitude within the night (sunset to sunrise, or the cloud window).
        let rises: Date?
        let sets: Date?
        let highest: Date
        let highestAltitude: Double
        let highestAzimuth: Double
        /// The core is 10° up during true darkness (the longest such stretch).
        let dark: DateInterval?
        /// …and the Moon is below the horizon (or under 5% lit) as well. The window to go out.
        let moonFree: DateInterval?
        /// The highest the core can ever get at this latitude.
        let peakPossible: Double
        var neverUp: Bool { peakPossible < Self.minimum }
        static let minimum = SkyAlmanac.coreMinimumAltitude
    }

    func core(for park: Park, sky: SkyConditions) -> CoreNight {
        let window = Self.nightWindow(sky)
        let altitude = { (date: Date) in engine.horizontal(date: date, park: park, ra: Self.coreRA, dec: Self.coreDec).altitude }
        let up = { (date: Date) in altitude(date) >= Self.coreMinimumAltitude }
        var best = window.start, bestAltitude = -90.0
        sample(window) { date in let a = altitude(date); if a > bestAltitude { bestAltitude = a; best = date } }
        let edges = transitions(in: window, where: up)
        let darkWindow = sky.darkStart.flatMap { start in sky.darkEnd.map { DateInterval(start: start, end: max(start, $0)) } }
        let moonDown = { (date: Date) in sky.moon.illumination < 0.05 || engine.lunarAltitude(at: date, park: park) < -0.833 }
        let dark = darkWindow.flatMap { longest(in: $0, where: up) }
        let free = darkWindow.flatMap { longest(in: $0, where: { up($0) && moonDown($0) }) }
        return CoreNight(rises: edges.rises.first, sets: edges.sets.first, highest: best, highestAltitude: bestAltitude,
            highestAzimuth: engine.horizontal(date: best, park: park, ra: Self.coreRA, dec: Self.coreDec).azimuth,
            dark: dark, moonFree: free, peakPossible: 90-abs(park.latitude-Self.coreDec/Self.rad))
    }

    // MARK: Planets

    enum Planet: String, CaseIterable, Sendable, Codable {
        case mercury, venus, mars, jupiter, saturn
        var name: String {
            switch self {
            case .mercury: String(localized: "Mercury")
            case .venus: String(localized: "Venus")
            case .mars: String(localized: "Mars")
            case .jupiter: String(localized: "Jupiter")
            case .saturn: String(localized: "Saturn")
            }
        }
    }
    struct PlanetPosition: Sendable, Equatable {
        let planet: Planet
        /// Geocentric equatorial coordinates of date, radians.
        let ra: Double
        let dec: Double
        let magnitude: Double
        /// Angular distance from the Sun, degrees.
        let elongation: Double
    }
    struct PlanetNight: Sendable, Equatable, Identifiable {
        var id: Planet { planet }
        let planet: Planet
        let magnitude: Double
        /// Above 5° with the Sun at least 6° down: the stretch of the night it can be seen.
        let visible: DateInterval
        let best: Date
        let bestAltitude: Double
        let bestAzimuth: Double
        /// Rises or sets inside the night (nil when it is already up at dusk or still up at dawn).
        let rises: Date?
        let sets: Date?
    }

    /// Planets that clear 5° in a dark-enough sky during the night, brightest first.
    func planets(for park: Park, sky: SkyConditions) -> [PlanetNight] {
        let window = Self.nightWindow(sky)
        return Planet.allCases.compactMap { planet -> PlanetNight? in
            let altitude = { (date: Date) -> Double in
                let p = position(of: planet, at: date)
                return engine.horizontal(date: date, park: park, ra: p.ra, dec: p.dec).altitude
            }
            let seen = { (date: Date) in engine.solarAltitude(at: date, park: park) <= -6 && altitude(date) >= 5 }
            guard let visible = longest(in: window, where: seen) else { return nil }
            var best = visible.start, bestAltitude = -90.0
            sample(visible) { date in let a = altitude(date); if a > bestAltitude { bestAltitude = a; best = date } }
            let p = position(of: planet, at: best)
            // Rise and set on the refracted horizon (34'), as almanacs give them; planets are points.
            let edges = transitions(in: window) { altitude($0) >= -0.567 }
            return PlanetNight(planet: planet, magnitude: p.magnitude, visible: visible, best: best, bestAltitude: bestAltitude,
                bestAzimuth: engine.horizontal(date: best, park: park, ra: p.ra, dec: p.dec).azimuth,
                rises: edges.rises.first, sets: edges.sets.first)
        }.sorted { $0.magnitude < $1.magnitude }
    }

    /// Schlyter, "How to compute planetary positions": osculating elements with linear drift,
    /// Kepler's equation, then heliocentric → geocentric → equatorial. Ecliptic and equator of date.
    func position(of planet: Planet, at date: Date) -> PlanetPosition {
        let d = date.timeIntervalSince1970/86400 + 2440587.5 - 2451543.5
        let sun = Self.orbit(n: 0, i: 0, w: 282.9404+4.70935e-5*d, a: 1, e: 0.016709-1.151e-9*d, m: 356.0470+0.9856002585*d)
        let mj = 19.8950+0.0830853001*d, ms = 316.9670+0.0334442282*d
        let elements: (n: Double, i: Double, w: Double, a: Double, e: Double, m: Double) = switch planet {
        case .mercury: (48.3313+3.24587e-5*d, 7.0047+5.00e-8*d, 29.1241+1.01444e-5*d, 0.387098, 0.205635+5.59e-10*d, 168.6562+4.0923344368*d)
        case .venus: (76.6799+2.46590e-5*d, 3.3946+2.75e-8*d, 54.8910+1.38374e-5*d, 0.723330, 0.006773-1.302e-9*d, 48.0052+1.6021302244*d)
        case .mars: (49.5574+2.11081e-5*d, 1.8497-1.78e-8*d, 286.5016+2.92961e-5*d, 1.523688, 0.093405+2.516e-9*d, 18.6021+0.5240207766*d)
        case .jupiter: (100.4542+2.76854e-5*d, 1.3030-1.557e-7*d, 273.8777+1.64505e-5*d, 5.20256, 0.048498+4.469e-9*d, mj)
        case .saturn: (113.6634+2.38980e-5*d, 2.4886-1.081e-7*d, 339.3939+2.97661e-5*d, 9.55475, 0.055546-9.499e-9*d, ms)
        }
        var helio = Self.orbit(n: elements.n, i: elements.i, w: elements.w, a: elements.a, e: elements.e, m: elements.m)
        // The largest mutual perturbations, both in degrees (Schlyter §11).
        if planet == .jupiter {
            helio.lon += -0.332*sinD(2*mj-5*ms-67.6) - 0.056*sinD(2*mj-2*ms+21) + 0.042*sinD(3*mj-5*ms+21)
                - 0.036*sinD(mj-2*ms) + 0.022*cosD(mj-ms) + 0.023*sinD(2*mj-3*ms+52) - 0.016*sinD(mj-5*ms-69)
        } else if planet == .saturn {
            helio.lon += 0.812*sinD(2*mj-5*ms-67.6) - 0.229*cosD(2*mj-4*ms-2) + 0.119*sinD(mj-2*ms-3)
                + 0.046*sinD(2*mj-6*ms-69) + 0.014*sinD(mj-3*ms+32)
            helio.lat += -0.020*cosD(2*mj-4*ms-2) + 0.018*sinD(2*mj-6*ms-49)
        }
        let sunLon = sun.lon
        let xh = helio.r*cosD(helio.lon)*cosD(helio.lat), yh = helio.r*sinD(helio.lon)*cosD(helio.lat), zh = helio.r*sinD(helio.lat)
        let xg = xh + sun.r*cosD(sunLon), yg = yh + sun.r*sinD(sunLon), zg = zh
        let ecl = 23.4393-3.563e-7*d
        let xe = xg, ye = yg*cosD(ecl)-zg*sinD(ecl), ze = yg*sinD(ecl)+zg*cosD(ecl)
        let distance = sqrt(xe*xe+ye*ye+ze*ze)
        // Phase angle (Sun–planet–Earth) and Schlyter's visual magnitudes.
        let phase = acos(max(-1, min(1, (helio.r*helio.r + distance*distance - sun.r*sun.r)/(2*helio.r*distance))))/Self.rad
        let base = 5*log10(helio.r*distance)
        var magnitude: Double = switch planet {
        case .mercury: -0.36 + base + 0.027*phase + 2.2e-13*pow(phase, 6)
        case .venus: -4.34 + base + 0.013*phase + 4.2e-7*pow(phase, 3)
        case .mars: -1.51 + base + 0.016*phase
        case .jupiter: -9.25 + base + 0.014*phase
        case .saturn: -9.0 + base + 0.044*phase
        }
        if planet == .saturn {
            // The rings' tilt toward Earth brightens Saturn by up to about 1.4 magnitudes.
            let gLon = atan2(yg, xg)/Self.rad, gLat = atan2(zg, sqrt(xg*xg+yg*yg))/Self.rad
            let ir = 28.06, nr = 169.51+3.82e-5*d
            let b = asin(max(-1, min(1, sinD(gLat)*cosD(ir) - cosD(gLat)*sinD(ir)*sinD(gLon-nr))))
            magnitude += -2.6*abs(sin(b)) + 1.2*sin(b)*sin(b)
        }
        let elongation = acos(max(-1, min(1, (sun.r*sun.r + distance*distance - helio.r*helio.r)/(2*sun.r*distance))))/Self.rad
        return PlanetPosition(planet: planet, ra: Self.normalizedRadians(atan2(ye, xe)), dec: atan2(ze, sqrt(xe*xe+ye*ye)),
            magnitude: magnitude, elongation: elongation)
    }
    /// Heliocentric ecliptic longitude/latitude (degrees) and distance (AU) from orbital elements.
    private static func orbit(n: Double, i: Double, w: Double, a: Double, e: Double, m: Double) -> (lon: Double, lat: Double, r: Double) {
        let mr = (m - floor(m/360)*360)*rad
        var anomaly = mr + e*sin(mr)*(1+e*cos(mr))
        for _ in 0..<8 { anomaly -= (anomaly - e*sin(anomaly) - mr)/(1 - e*cos(anomaly)) }
        let xv = a*(cos(anomaly)-e), yv = a*sqrt(1-e*e)*sin(anomaly)
        let v = atan2(yv, xv), r = sqrt(xv*xv+yv*yv)
        let nr = n*rad, ir = i*rad, u = v + w*rad
        let x = r*(cos(nr)*cos(u) - sin(nr)*sin(u)*cos(ir))
        let y = r*(sin(nr)*cos(u) + cos(nr)*sin(u)*cos(ir))
        let z = r*sin(u)*sin(ir)
        return (atan2(y, x)/rad, atan2(z, sqrt(x*x+y*y))/rad, r)
    }

    // MARK: Meteor showers

    nonisolated struct MeteorShower: Codable, Sendable, Identifiable, Equatable {
        var id: String { code }
        let code: String
        /// The IMO's English name, as bundled. Display `localizedName`.
        let name: String
        /// The name in the reader's language: catalog key `shower.<code>` (written by
        /// Scripts/apply_translations.py from sky-events.json), falling back to the bundled English.
        var localizedName: String { Bundle.main.localizedString(forKey: "shower.\(code)", value: name, table: nil) }
        /// Activity window, "MM-dd".
        let start: String
        let end: String
        /// Solar longitude of the peak, J2000 degrees.
        let peakSolarLongitude: Double
        let radiantRA: Double
        let radiantDec: Double
        var driftRA: Double?
        var driftDec: Double?
        let zhr: Double
        var variable: Bool?
        let velocity: Double
        var parent: String?
        /// Published peak instants by year, ISO 8601 — preferred over the computed one when present.
        var peaks: [String: String]?
        /// Activity profile steepness, ZHR ∝ 10^(−B·|Δλ|) (IMO). Most showers rise and fall over days.
        var profileB: Double?
        /// Population index r. Default 2.5.
        var populationIndex: Double?
        /// `peaks` parsed once when the table loads, by year (nil when not parsed): peak lookups run
        /// for every shower on every calendar night, and parsing ISO dates each time dominated them.
        var publishedPeaks: [Int: Date]?
        private enum CodingKeys: String, CodingKey {
            case code, name, start, end, peakSolarLongitude, radiantRA, radiantDec, driftRA, driftDec, zhr, variable, velocity, parent, peaks, profileB, populationIndex
        }
    }
    struct ShowerNight: Sendable, Equatable, Identifiable {
        var id: String { shower.code }
        let shower: MeteorShower
        let peak: Date
        /// The peak falls within this night (local noon to noon).
        let isPeakNight: Bool
        /// Expected activity tonight relative to the peak ZHR (0…1).
        let activity: Double
        /// Best moment: radiant highest during true darkness, Moon down if possible.
        let best: Date?
        let radiantAltitude: Double
        let moonDownAtBest: Bool
        /// A rough guide to meteors per hour for one observer at `best`, under this park's estimated
        /// skyglow (IMO: HR = ZHR · sin h / r^(6.5 − LM)). Never more precise than "about".
        let hourlyRate: Int
    }

    func showers(_ table: [MeteorShower], for park: Park, sky: SkyConditions, bortle: Int) -> [ShowerNight] {
        let calendar = park.calendar
        return table.compactMap { shower -> ShowerNight? in
            guard let peak = peakDate(of: shower, near: sky.evening),
                  isActive(shower, on: sky.evening, calendar: calendar) || abs(peak.timeIntervalSince(sky.evening)) < 2*86400 else { return nil }
            let mid = sky.evening.addingTimeInterval(12*3600)
            let activity = { (date: Date) in pow(10, -(shower.profileB ?? 0.25)*abs(date.timeIntervalSince(peak))/86400*0.9856) }
            guard activity(mid) > 0.08 || isActive(shower, on: sky.evening, calendar: calendar) else { return nil }
            let days = peak.timeIntervalSince(mid)/86400
            let ra = (shower.radiantRA + (shower.driftRA ?? 0)*(-days))*Self.rad
            let dec = (shower.radiantDec + (shower.driftDec ?? 0)*(-days))*Self.rad
            // ZHR is defined for a limiting magnitude of 6.5; darker skies are not credited beyond it,
            // so the guide never promises more than the published rate.
            let limiting = min(6.5, Self.limitingMagnitude(bortle: bortle))
            let r = shower.populationIndex ?? 2.5
            var best: Date?, bestRate = 0.0, bestAltitude = -90.0, bestMoonDown = false, bestActivity = activity(mid)
            if let start = sky.darkStart, let end = sky.darkEnd, end > start {
                sample(DateInterval(start: start, end: end), step: 600) { date in
                    let altitude = engine.horizontal(date: date, park: park, ra: ra, dec: dec).altitude
                    guard altitude > 0 else { return }
                    let moonDown = sky.moon.illumination < 0.05 || engine.lunarAltitude(at: date, park: park) < -0.833
                    // Moonlight costs up to about 1.5 magnitudes of faint meteors.
                    let magnitude = moonDown ? limiting : limiting - 1.5*sky.moon.illumination
                    let rate = shower.zhr*activity(date)*sin(altitude*Self.rad)/pow(r, 6.5-magnitude)
                    if best == nil || rate > bestRate { best = date; bestRate = rate; bestAltitude = altitude; bestMoonDown = moonDown; bestActivity = activity(date) }
                }
            }
            let rate = bestRate
            let activityValue = bestActivity
            let isPeakNight = peak >= sky.evening && peak < sky.end
            return ShowerNight(shower: shower, peak: peak, isPeakNight: isPeakNight, activity: activityValue, best: best,
                radiantAltitude: bestAltitude, moonDownAtBest: bestMoonDown, hourlyRate: max(0, Int(rate.rounded())))
        }.sorted { $0.hourlyRate > $1.hourlyRate }
    }
    /// Naked-eye limiting magnitude at the zenith for each Bortle class (Bortle 2001, midpoints).
    static func limitingMagnitude(bortle: Int) -> Double {
        [7.8, 7.3, 6.8, 6.3, 5.8, 5.3, 4.8, 4.4, 4.0][min(8, max(0, bortle-1))]
    }
    private func isActive(_ shower: MeteorShower, on date: Date, calendar: Calendar) -> Bool {
        func key(_ text: String) -> Int? { let p = text.split(separator: "-").compactMap { Int($0) }; return p.count == 2 ? p[0]*100+p[1] : nil }
        guard let start = key(shower.start), let end = key(shower.end) else { return false }
        let parts = calendar.dateComponents([.month, .day], from: date)
        let today = (parts.month ?? 1)*100 + (parts.day ?? 1)
        return start <= end ? (start...end).contains(today) : (today >= start || today <= end)
    }
    /// The peak instant nearest `date`: the published one if the table has it for that year,
    /// otherwise the moment the Sun reaches the peak's solar longitude.
    func peakDate(of shower: MeteorShower, near date: Date) -> Date? {
        let year = Calendar(identifier: .gregorian).component(.year, from: date)
        let published = [year-1, year, year+1].compactMap { year in
            shower.publishedPeaks.map { $0[year] } ?? shower.peaks?[String(year)].flatMap(SkyEvents.date)
        }
        if let nearest = published.min(by: { abs($0.timeIntervalSince(date)) < abs($1.timeIntervalSince(date)) }),
           abs(nearest.timeIntervalSince(date)) < 183*86400 { return nearest }
        // Bisection on solar longitude within ±183 days.
        let target = shower.peakSolarLongitude
        func offset(_ t: Date) -> Double {
            var delta = solarLongitudeJ2000(at: t) - target
            delta -= 360*(delta/360).rounded()
            return delta
        }
        let guess = date.addingTimeInterval(-offset(date)/0.9856*86400)
        var lo = guess.addingTimeInterval(-3*86400), hi = guess.addingTimeInterval(3*86400)
        guard offset(lo) < 0, offset(hi) > 0 else { return nil }
        for _ in 0..<30 {
            let mid = lo.addingTimeInterval(hi.timeIntervalSince(lo)/2)
            if offset(mid) < 0 { lo = mid } else { hi = mid }
        }
        return lo
    }
    /// The Sun's apparent longitude, referred back to the J2000 equinox (general precession 1.39697° per century).
    func solarLongitudeJ2000(at date: Date) -> Double {
        let sun = engine.equatorial(of: .sun, at: date)
        let t = (date.timeIntervalSince1970/86400 + 2440587.5 - 2451545)/36525
        let eps = (23.439291-0.0130042*t)*Self.rad
        let lambda = atan2(sin(sun.ra)*cos(eps) + tan(sun.dec)*sin(eps), cos(sun.ra))/Self.rad
        let value = lambda - 1.39697*t
        return value - floor(value/360)*360
    }

    // MARK: Lunar eclipses

    nonisolated struct LunarEclipse: Codable, Sendable, Equatable, Identifiable {
        var id: String { date }
        let date: String
        /// "penumbral", "partial" or "total".
        let type: String
        let p1: Date?
        let u1: Date?
        let u2: Date?
        let greatest: Date
        let u3: Date?
        let u4: Date?
        let p4: Date?
        let umbralMagnitude: Double
        /// Shading is generally noticeable only above about 0.7 (NASA); used to skip the faintest penumbral eclipses.
        var penumbralMagnitude: Double?
    }
    struct EclipseNight: Sendable, Equatable {
        let eclipse: LunarEclipse
        /// The stage worth seeing (totality, else the partial phase, else the penumbral) as visible from the park:
        /// clipped to the time the Moon is up.
        let visible: DateInterval?
        let greatestVisible: Bool
        let altitudeAtGreatest: Double
    }
    func lunarEclipse(_ table: [LunarEclipse], for park: Park, sky: SkyConditions) -> EclipseNight? {
        guard let eclipse = table.first(where: { $0.greatest >= sky.evening && $0.greatest < sky.end }) else { return nil }
        let stage: DateInterval? = {
            if let a = eclipse.u2, let b = eclipse.u3, b > a { return DateInterval(start: a, end: b) }
            if let a = eclipse.u1, let b = eclipse.u4, b > a { return DateInterval(start: a, end: b) }
            if let a = eclipse.p1, let b = eclipse.p4, b > a { return DateInterval(start: a, end: b) }
            return nil
        }()
        // The same horizon as moonrise: upper limb on the refracted horizon.
        let moonUp = { (date: Date) in engine.lunarAltitude(at: date, park: park) > -0.833 }
        let visible = stage.flatMap { longest(in: $0, where: moonUp) }
        let altitude = engine.lunarAltitude(at: eclipse.greatest, park: park)
        return EclipseNight(eclipse: eclipse, visible: visible, greatestVisible: altitude > -0.833, altitudeAtGreatest: altitude)
    }

    // MARK: Shared time search

    /// The highest point of a fixed position within an interval, on the same 5-minute grid as the rest.
    func highest(ra: Double, dec: Double, park: Park, in window: DateInterval) -> (date: Date, altitude: Double, azimuth: Double) {
        var best = window.start, bestAltitude = -90.0
        sample(window) { date in
            let a = engine.horizontal(date: date, park: park, ra: ra, dec: dec).altitude
            if a > bestAltitude { bestAltitude = a; best = date }
        }
        return (best, bestAltitude, engine.horizontal(date: best, park: park, ra: ra, dec: dec).azimuth)
    }


    /// Sunset to sunrise, or the cloud window under the midnight sun.
    static func nightWindow(_ sky: SkyConditions) -> DateInterval {
        if let sunset = sky.sunset, let sunrise = sky.sunrise, sunrise > sunset { return DateInterval(start: sunset, end: sunrise) }
        let window = sky.cloudWindow
        return DateInterval(start: window.start, end: max(window.start, window.end))
    }
    private func sample(_ window: DateInterval, step: TimeInterval = 300, _ body: (Date) -> Void) {
        var t = window.start
        while t < window.end { body(t); t = t.addingTimeInterval(step) }
        body(window.end)
    }
    /// The longest stretch of `window` where `condition` holds, edges refined to a few seconds.
    func longest(in window: DateInterval, step: TimeInterval = 300, where condition: (Date) -> Bool) -> DateInterval? {
        guard window.duration > 0 else { return condition(window.start) ? nil : nil }
        var best: DateInterval?, start: Date?
        var previous = window.start, previousValue = condition(previous)
        if previousValue { start = previous }
        var t = previous
        while t < window.end {
            t = min(window.end, t.addingTimeInterval(step))
            let value = condition(t)
            if value != previousValue {
                let edge = refine(previous, t, condition: condition, startValue: previousValue)
                if value { start = edge } else if let s = start {
                    let run = DateInterval(start: s, end: edge)
                    if run.duration > (best?.duration ?? 0) { best = run }
                    start = nil
                }
            }
            previous = t; previousValue = value
        }
        if let s = start, window.end > s {
            let run = DateInterval(start: s, end: window.end)
            if run.duration > (best?.duration ?? 0) { best = run }
        }
        return best
    }
    /// Instants where `condition` turns on (rises) or off (sets) inside `window`.
    func transitions(in window: DateInterval, step: TimeInterval = 300, where condition: (Date) -> Bool) -> (rises: [Date], sets: [Date]) {
        var rises: [Date] = [], sets: [Date] = []
        var previous = window.start, previousValue = condition(previous)
        var t = previous
        while t < window.end {
            t = min(window.end, t.addingTimeInterval(step))
            let value = condition(t)
            if value != previousValue {
                let edge = refine(previous, t, condition: condition, startValue: previousValue)
                if value { rises.append(edge) } else { sets.append(edge) }
            }
            previous = t; previousValue = value
        }
        return (rises, sets)
    }
    private func refine(_ a: Date, _ b: Date, condition: (Date) -> Bool, startValue: Bool) -> Date {
        var lo = a, hi = b
        for _ in 0..<9 {
            let mid = lo.addingTimeInterval(hi.timeIntervalSince(lo)/2)
            if condition(mid) == startValue { lo = mid } else { hi = mid }
        }
        return lo.addingTimeInterval(hi.timeIntervalSince(lo)/2)
    }
    private func sinD(_ a: Double) -> Double { sin(a*Self.rad) }
    private func cosD(_ a: Double) -> Double { cos(a*Self.rad) }
    private static func normalizedRadians(_ a: Double) -> Double { let t = 2*Double.pi; return a - floor(a/t)*t }
}

/// The bundled table of meteor showers and lunar eclipses (sources in Research/sky-events.md).
nonisolated struct SkyEvents: Decodable, Sendable {
    let meteorShowers: [SkyAlmanac.MeteorShower]
    let lunarEclipses: [SkyAlmanac.LunarEclipse]
    static let shared: SkyEvents = load() ?? SkyEvents(meteorShowers: [], lunarEclipses: [])
    init(meteorShowers: [SkyAlmanac.MeteorShower], lunarEclipses: [SkyAlmanac.LunarEclipse]) {
        self.meteorShowers = meteorShowers; self.lunarEclipses = lunarEclipses
    }
    static func load(bundle: Bundle = .main) -> SkyEvents? {
        bundle.url(forResource: "sky-events", withExtension: "json").flatMap { load(url: $0) }
    }
    static func load(url: URL) -> SkyEvents? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let date = date(text) else { throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: text)) }
            return date
        }
        guard let events = try? decoder.decode(SkyEvents.self, from: data) else { return nil }
        let showers = events.meteorShowers.map { shower in
            var parsed = shower
            parsed.publishedPeaks = (shower.peaks ?? [:]).reduce(into: [:]) { result, entry in
                if let year = Int(entry.key), let date = date(entry.value) { result[year] = date }
            }
            return parsed
        }
        return SkyEvents(meteorShowers: showers, lunarEclipses: events.lunarEclipses)
    }
    /// ISO 8601 instants, with or without seconds ("2026-01-03T21:00Z").
    static func date(_ text: String) -> Date? {
        let full = ISO8601DateFormatter()
        if let date = full.date(from: text) { return date }
        let parts = text.split(separator: "T")
        guard parts.count == 2, parts[1].hasSuffix("Z") else { return nil }
        let clock = parts[1].dropLast()
        return clock.split(separator: ":").count == 2 ? full.date(from: "\(parts[0])T\(clock):00Z") : nil
    }
}
