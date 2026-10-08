import Foundation

nonisolated protocol AstronomyProviding: Sendable {
    func conditions(for park: Park, on date: Date) -> SkyConditions
}

/// Local-noon to local-noon night, with actual UTC instants through DST changes.
/// Solar coordinates: NOAA / Meeus equations (geometric altitude; -0.833° rise/set).
/// Lunar position: truncated Meeus periodic series plus topocentric parallax.
/// Roots bracketed every 5 minutes, bisected to <1 second. Terrain/refraction are
/// not modeled. Target: Sun ±2 min, Moon ±15 min; see Research/accuracy.md.
/// The Moon as seen from one place and moment. Angles are radians; screen angles are measured
/// counterclockwise from "up", where up is the observer's zenith.
nonisolated struct MoonGeometry: Sendable, Equatable {
    /// 0 at full moon, π at new moon.
    let phaseAngle: Double
    /// Direction of the bright limb on screen.
    let brightLimb: Double
    /// Direction of the Moon's north pole on screen.
    let north: Double
    let librationLongitude: Double
    let librationLatitude: Double
    /// Whether the Moon is waxing; nil for a hand-built geometry (a morph between two nights).
    var waxing: Bool?=nil
    var illumination: Double { (1+cos(phaseAngle))/2 }
    /// The phase as named in words ("Waxing crescent"), when the direction is known.
    var phase: MoonPhase? {
        guard let waxing else { return nil }
        // Phase angle π is new, 0 full; the synodic fraction runs 0 → 0.5 waxing, 0.5 → 1 waning.
        let half=(Double.pi-phaseAngle)/(2*Double.pi)
        return MoonPhase(fraction: waxing ? half : 1-half)
    }
}
nonisolated struct AstronomyEngine: AstronomyProviding {
    static let synodicDays = 29.530588853
    private let rad = Double.pi / 180
    /// Phase from the Moon's true elongation (Meeus lunar and solar longitudes) rather than the
    /// mean 29.53-day cycle from the 2000-01-06 18:14 UTC new moon, which can miss a 2026 new
    /// moon by more than 17 hours: too coarse for a date-scrubbing planner.
    func moonPhase(at date: Date) -> MoonPhase {
        let t=(julian(date)-2451545)/36525
        let l=normalized(218.3164477+481267.88123421*t-0.0015786*t*t)
        let d=normalized(297.8501921+445267.1114034*t-0.0018819*t*t)
        let m=normalized(357.5291092+35999.0502909*t-0.0001536*t*t)
        let mp=normalized(134.9633964+477198.8675055*t+0.0087414*t*t)
        let f=normalized(93.272095+483202.0175233*t-0.0036539*t*t)
        let moon=l+6.288774*sinD(mp)+1.274027*sinD(2*d-mp)+0.658314*sinD(2*d)
            + 0.213618*sinD(2*mp)-0.185116*sinD(m)-0.114332*sinD(2*f)
            + 0.058793*sinD(2*d-2*mp)+0.057066*sinD(2*d-m-mp)+0.053322*sinD(2*d+mp)
            + 0.045758*sinD(2*d-m)+0.041024*sinD(mp-m)-0.034718*sinD(d)-0.030465*sinD(m+mp)
        let sunL=normalized(280.46646+t*(36000.76983+t*0.0003032))
        let sunM=357.52911+t*(35999.05029-0.0001537*t)
        let sunC=sinD(sunM)*(1.914602-t*(0.004817+0.000014*t))+sinD(2*sunM)*(0.019993-0.000101*t)+sinD(3*sunM)*0.000289
        return MoonPhase(fraction:normalized(moon-sunL-sunC)/360)
    }
    func conditions(for park: Park, on date: Date) -> SkyConditions {
        let start = park.evening(date)
        let end = park.date(start, addingDays: 1)
        let sun = crossings(start: start, end: end) { solarAltitude(at: $0, park: park) + 0.833 }
        let civil = crossings(start: start, end: end) { solarAltitude(at: $0, park: park) + 6 }
        let nautical = crossings(start: start, end: end) { solarAltitude(at: $0, park: park) + 12 }
        let dark = crossings(start: start, end: end) { solarAltitude(at: $0, park: park) + 18 }
        let beginsDark = solarAltitude(at: start, park: park) < -18
        let darkStart = dark.down.first ?? (beginsDark ? start : nil)
        let darkEnd = darkStart.flatMap { from in dark.up.first(where: { $0 > from }) ?? (solarAltitude(at: end, park: park) < -18 ? end : nil) }
        let hours = max(0, (darkEnd?.timeIntervalSince(darkStart ?? end) ?? 0)/3600)
        let sunAlwaysUp = sun.down.isEmpty && sun.up.isEmpty && solarAltitude(at: start, park: park) > -0.833
        let sunAlwaysDown = sun.down.isEmpty && sun.up.isEmpty && solarAltitude(at: start, park: park) <= -0.833
        let state: DarknessState = sunAlwaysUp ? .polarDay : hours == 0 ? .noAstronomicalDarkness : sunAlwaysDown ? .polarNight : .normal
        // The Moon's upper limb on a refracted horizon: topocentric centre at -0.833° (34' refraction
        // plus the ~16' semidiameter). A higher threshold delays rises by up to 40 min in Alaska.
        let moon = crossings(start: start, end: end) { lunarAltitude(at: $0, park: park) + 0.833 }
        var below = 0.0
        if let a = darkStart, let b = darkEnd, b > a {
            // Integrate exact horizon-crossing intervals, not a Boolean moon bonus.
            let edges = ([a] + (moon.up + moon.down).filter { $0 > a && $0 < b }.sorted() + [b])
            for index in 0..<(edges.count-1) {
                let middle = edges[index].addingTimeInterval(edges[index+1].timeIntervalSince(edges[index])/2)
                if lunarAltitude(at: middle, park: park) < -0.833 { below += edges[index+1].timeIntervalSince(edges[index]) }
            }
            below /= b.timeIntervalSince(a)
        }
        let light = darkStart.flatMap { a in darkEnd.map { b in moonlight(park: park, from: a, to: b) } } ?? 0
        // Nights run from local noon to noon, but in western Alaska's winter solar noon falls after
        // 13:00, so the Sun can rise after the window closes: look up to six hours further.
        let sunset = sun.down.first
        let sunrise = sun.up.first(where: { $0 > (sunset ?? start) })
            ?? sunset.flatMap { _ in crossings(start: end, end: end.addingTimeInterval(6*3600)) { solarAltitude(at: $0, park: park) + 0.833 }.up.first }
        // Under the midnight sun, the clouds that matter are those around the Sun's lowest point.
        let lowestSun = sunAlwaysUp ? lowestSolarMoment(start: start, end: end, park: park) : nil
        return SkyConditions(evening: start, end: end, sunset: sunset, sunrise: sunrise,
            civilDusk: civil.down.first, nauticalDusk: nautical.down.first, darkStart: darkStart, darkEnd: darkEnd,
            state: state, moon: moonPhase(at: start.addingTimeInterval(10*3600)),
            moonrise: moon.up.first, moonset: moon.down.first, moonBelowFraction: min(1,max(0,below)), darkHours: hours, moonlight: light, lowestSun: lowestSun)
    }

    // MARK: Moonlight

    /// How much a full Moon high in the sky brightens a dark sky: about 30 times, 3.7 magnitudes
    /// per square arcsecond over a 21.7 sky (Krisciunas & Schaefer 1991, Fig. 2 at 45–90°).
    static let fullMoonBrightening = 30.0
    /// Moonlight at one moment, 0 (none) to 1 (a full Moon at the zenith), on a magnitude scale.
    ///
    /// Krisciunas & Schaefer (1991, PASP 103, 1033): the Moon's brightness by phase angle α
    /// (degrees, 0 at full) is 10^(−0.4 (0.026|α| + 4×10⁻⁹ α⁴)) of full (eq. 9), dimmed by
    /// extinction 10^(−0.4 k X) with k = 0.172 (V band) and airmass X = 1/(cos z + 0.025 e^(−11 cos z))
    /// (Rozenberg 1966, finite at the horizon), relative to the Moon at the zenith. What the eye
    /// loses is the sky's brightening in magnitudes, 2.5 log10(1 + 30 b), divided by a full Moon's
    /// at the zenith. So a half Moon high up counts about 38% of a full one, a quarter-lit
    /// crescent 17%, and a full Moon two degrees up about a quarter. Below the horizon, 0.
    static func moonlight(phaseAngle: Double, altitude: Double) -> Double {
        guard altitude > 0, phaseAngle.isFinite else { return 0 }
        let a = min(180, abs(phaseAngle))
        let phase = pow(10, -0.4*(0.026*a + 4e-9*pow(a, 4)))
        func transmitted(_ altitude: Double) -> Double {
            let c = cos((90-min(90, altitude))*Double.pi/180)
            return pow(10, -0.4*0.172/(c + 0.025*exp(-11*c)))
        }
        let brightness = phase*transmitted(altitude)/transmitted(90)
        return log10(1 + fullMoonBrightening*brightness)/log10(1 + fullMoonBrightening)
    }
    /// The phase angle (degrees) that gives an illuminated fraction: k = (1 + cos α)/2.
    static func phaseAngle(illumination: Double) -> Double { acos(min(1, max(-1, 2*illumination-1)))*180/Double.pi }
    /// Moonlight averaged over `from`…`to`, sampled every 15 minutes at the middle of each step.
    func moonlight(park: Park, from start: Date, to end: Date) -> Double {
        let duration = end.timeIntervalSince(start)
        guard duration > 0 else { return 0 }
        let steps = max(1, Int((duration/900).rounded(.up))), step = duration/Double(steps)
        var total = 0.0
        for i in 0..<steps {
            let t = start.addingTimeInterval((Double(i)+0.5)*step)
            total += Self.moonlight(phaseAngle: Self.phaseAngle(illumination: moonPhase(at: t).illumination), altitude: lunarAltitude(at: t, park: park))
        }
        return min(1, max(0, total/Double(steps)))
    }

    /// When the Sun is lowest between `start` and `end` (ten-minute steps, refined to a minute).
    private func lowestSolarMoment(start: Date, end: Date, park: Park) -> Date {
        var best = start, lowest = Double.infinity
        var t = start
        while t <= end { let a = solarAltitude(at: t, park: park); if a < lowest { lowest = a; best = t }; t = t.addingTimeInterval(600) }
        var fine = best.addingTimeInterval(-600)
        while fine <= best.addingTimeInterval(600) { let a = solarAltitude(at: fine, park: park); if a < lowest { lowest = a; best = fine }; fine = fine.addingTimeInterval(60) }
        return best
    }
    private func julian(_ date: Date) -> Double { date.timeIntervalSince1970/86400 + 2440587.5 }
    private func normalized(_ value: Double) -> Double { value - floor(value/360)*360 }
    private func sinD(_ a: Double) -> Double { sin(a*rad) }
    private func cosD(_ a: Double) -> Double { cos(a*rad) }
    /// Local hour angle (radians) of a body at right ascension `ra` (radians).
    private func hourAngle(date: Date, park: Park, ra: Double) -> Double {
        let jd = julian(date)
        let t = (jd-2451545)/36525
        let sidereal = normalized(280.46061837 + 360.98564736629*(jd-2451545) + 0.000387933*t*t - t*t*t/38710000)
        return (sidereal + park.longitude)*rad - ra
    }
    /// Altitude and azimuth (degrees; azimuth from north through east) of an equatorial position.
    func horizontal(date: Date, park: Park, ra: Double, dec: Double) -> (altitude: Double, azimuth: Double) {
        let h = hourAngle(date: date, park: park, ra: ra), lat = park.latitude*rad
        let alt = asin(max(-1,min(1,sin(lat)*sin(dec)+cos(lat)*cos(dec)*cos(h))))
        let az = atan2(-sin(h)*cos(dec), cos(lat)*sin(dec)-sin(lat)*cos(dec)*cos(h))
        return (alt/rad, normalized(az/rad))
    }
    private func altitude(date: Date, park: Park, ra: Double, dec: Double) -> Double {
        let h = hourAngle(date: date, park: park, ra: ra)
        let lat = park.latitude*rad
        return asin(max(-1,min(1,sin(lat)*sin(dec)+cos(lat)*cos(dec)*cos(h))))/rad
    }
    func solarAltitude(at date: Date, park: Park) -> Double {
        let sun = solarPosition(at: date)
        return altitude(date: date, park: park, ra: sun.ra, dec: sun.dec)
    }
    /// Geocentric lunar position: ecliptic longitude/latitude (degrees), right ascension and
    /// declination (radians), distance (km) and the argument of latitude F (degrees).
    private func lunarPosition(at date: Date) -> (lon: Double, lat: Double, ra: Double, dec: Double, distance: Double, f: Double, t: Double) {
        let t = (julian(date)-2451545)/36525
        let l = normalized(218.3164477 + 481267.88123421*t - 0.0015786*t*t)
        let d = normalized(297.8501921 + 445267.1114034*t - 0.0018819*t*t)
        let m = normalized(357.5291092 + 35999.0502909*t - 0.0001536*t*t)
        let mp = normalized(134.9633964 + 477198.8675055*t + 0.0087414*t*t)
        let f = normalized(93.272095 + 483202.0175233*t - 0.0036539*t*t)
        let lon = l + 6.288774*sinD(mp)+1.274027*sinD(2*d-mp)+0.658314*sinD(2*d)
            + 0.213618*sinD(2*mp)-0.185116*sinD(m)-0.114332*sinD(2*f)
            + 0.058793*sinD(2*d-2*mp)+0.057066*sinD(2*d-m-mp)+0.053322*sinD(2*d+mp)
            + 0.045758*sinD(2*d-m)+0.041024*sinD(mp-m)-0.034718*sinD(d)-0.030465*sinD(m+mp)
        let lat = 5.128122*sinD(f)+0.280602*sinD(mp+f)+0.277693*sinD(mp-f)
            + 0.173237*sinD(2*d-f)+0.055413*sinD(2*d-mp+f)+0.046271*sinD(2*d-mp-f)
            + 0.032573*sinD(2*d+f)+0.017198*sinD(2*mp+f)
        let distance = 385000.56-20905.355*cosD(mp)-3699.111*cosD(2*d-mp)-2955.968*cosD(2*d)-569.925*cosD(2*mp)
        let eps = (23.439291-0.0130042*t)*rad
        let x = cosD(lon)*cosD(lat)
        let y = sinD(lon)*cosD(lat)*cos(eps)-sinD(lat)*sin(eps)
        let z = sinD(lon)*cosD(lat)*sin(eps)+sinD(lat)*cos(eps)
        return (lon, lat, atan2(y,x), asin(z), distance, f, t)
    }
    /// Apparent solar ecliptic longitude (radians) and equatorial coordinates (radians).
    private func solarPosition(at date: Date) -> (lambda: Double, ra: Double, dec: Double, epsilon: Double) {
        let t = (julian(date)-2451545)/36525
        let l = normalized(280.46646 + t*(36000.76983 + t*0.0003032))
        let m = 357.52911 + t*(35999.05029-0.0001537*t)
        let c = sinD(m)*(1.914602-t*(0.004817+0.000014*t)) + sinD(2*m)*(0.019993-0.000101*t)+sinD(3*m)*0.000289
        let omega = 125.04-1934.136*t
        let lambda = (l+c-0.00569-0.00478*sinD(omega))*rad
        let epsilon = (23+(26+(21.448-t*(46.815+t*(0.00059-t*0.001813)))/60)/60+0.00256*cosD(omega))*rad
        return (lambda, atan2(cos(epsilon)*sin(lambda),cos(lambda)), asin(sin(epsilon)*sin(lambda)), epsilon)
    }
    /// Geocentric right ascension and declination (radians) of the Sun and the Moon.
    func equatorial(of body: Body, at date: Date) -> (ra: Double, dec: Double) {
        switch body {
        case .sun: let sun = solarPosition(at: date); return (sun.ra, sun.dec)
        case .moon: let moon = lunarPosition(at: date); return (moon.ra, moon.dec)
        }
    }
    enum Body { case sun, moon }
    func lunarAltitude(at date: Date, park: Park) -> Double {
        let moon = lunarPosition(at: date)
        let geo = altitude(date: date, park: park, ra: moon.ra, dec: moon.dec)
        return geo - asin(6378.14/moon.distance)/rad * cosD(geo)
    }
    /// How the Moon looks from a park at a moment: its phase angle, where its bright limb and its
    /// north pole point on screen (with the zenith up), and its optical libration.
    /// Bright limb: Meeus (48.5); parallactic angle: Meeus (14.1); axis and libration: Meeus ch. 53,
    /// optical terms only (physical libration is under 0.04°).
    func moonGeometry(for park: Park, at date: Date) -> MoonGeometry {
        let moon = lunarPosition(at: date), sun = solarPosition(at: date)
        let beta = moon.lat*rad, lambda = moon.lon*rad
        let elongation = acos(max(-1,min(1,cos(beta)*cos(lambda-sun.lambda))))
        let phaseAngle = atan2(149_597_870*sin(elongation), moon.distance-149_597_870*cos(elongation))
        let chi = atan2(cos(sun.dec)*sin(sun.ra-moon.ra), sin(sun.dec)*cos(moon.dec)-cos(sun.dec)*sin(moon.dec)*cos(sun.ra-moon.ra))
        let h = hourAngle(date: date, park: park, ra: moon.ra), phi = park.latitude*rad
        let q = atan2(sin(h), tan(phi)*cos(moon.dec)-sin(moon.dec)*cos(h))
        let inclination = 1.54242*rad
        let node = normalized(125.0445479-1934.1362891*moon.t)*rad
        let w = lambda-node
        let a = atan2(sin(w)*cos(beta)*cos(inclination)-sin(beta)*sin(inclination), cos(w)*cos(beta))
        var lPrime = a-moon.f*rad
        lPrime = atan2(sin(lPrime), cos(lPrime))
        let bPrime = asin(max(-1,min(1,-sin(w)*cos(beta)*sin(inclination)-sin(beta)*cos(inclination))))
        let x = sin(inclination)*sin(node)
        let y = sin(inclination)*cos(node)*cos(sun.epsilon)-cos(inclination)*sin(sun.epsilon)
        let omega = atan2(x, y)
        let axis = asin(max(-1,min(1,sqrt(x*x+y*y)*cos(moon.ra-omega)/cos(bPrime))))
        // Waxing while the Moon is less than 180° east of the Sun in ecliptic longitude.
        let east=(lambda-sun.lambda).truncatingRemainder(dividingBy: 2*Double.pi)
        let waxing=(east<0 ? east+2*Double.pi : east)<Double.pi
        return MoonGeometry(phaseAngle: phaseAngle, brightLimb: chi-q, north: axis-q, librationLongitude: lPrime, librationLatitude: bPrime, waxing: waxing)
    }
    /// The moment a night's Moon is best seen: its highest point between sunset and sunrise
    /// (or the local 22:00–02:00 window under the midnight sun). Used for its drawn orientation.
    func moonViewTime(for sky: SkyConditions, park: Park) -> Date {
        var start = sky.cloudWindow.start, end = sky.cloudWindow.end
        if let sunset = sky.sunset, let sunrise = sky.sunrise, sunrise > sunset { start = sunset; end = sunrise }
        var best = start, highest = -Double.infinity
        var moment = start
        while moment <= end {
            let altitude = lunarAltitude(at: moment, park: park)
            if altitude > highest { highest = altitude; best = moment }
            moment = moment.addingTimeInterval(1800)
        }
        return best
    }
    /// Seasonal guidance for the galactic core (declination about −29°), never a timed forecast.
    /// `WhatsUp` times the core with `SkyAlmanac` and keeps these words only where nothing can be
    /// timed (far north, no true darkness).
    /// Its highest possible altitude is 90° − |latitude + 29°|: below about 3° it never clears the
    /// horizon (every Alaska park), and below about 10° it only skims the southern horizon.
    func milkyWayGuidance(for sky: SkyConditions, park: Park) -> String {
        let peak = 90 - abs(park.latitude + 29)
        if peak < 3 { return String(localized: "The Milky Way's bright center stays at or below the horizon this far north. Its fainter band still crosses dark skies.") }
        if sky.darkHours == 0 { return String(localized: "Without true darkness, the Milky Way stays faint.") }
        if peak < 10 { return String(localized: "The bright center stays low on the horizon at this latitude. An open view to the south matters most.") }
        let month = park.calendar.component(.month, from: sky.evening)
        // The sky's right ascension gives both hemispheres the same calendar
        // season; its name inverts: June–August is southern winter.
        if (6...8).contains(month) {
            return park.latitude < 0
                ? String(localized: "Southern winter favors the bright center. Look toward the southern sky; timing and terrain matter.")
                : String(localized: "Summer favors the bright center. Look toward the southern sky; timing and terrain matter.")
        }
        return (2...10).contains(month)
            ? String(localized: "The bright center may be visible before dawn or near dusk. Timing and terrain matter.")
            : String(localized: "The bright center is out of the night sky this season. Bright constellations still reward a dark night.")
    }
    private func crossings(start: Date, end: Date, value: (Date)->Double) -> (up:[Date],down:[Date]) {
        var up:[Date]=[], down:[Date]=[]
        var a = start, va = value(start)
        while a < end {
            let b = min(end,a.addingTimeInterval(300))
            let vb = value(b)
            if (va < 0) != (vb < 0) {
                var lo = a, hi = b
                for _ in 0..<12 {
                    let mid = lo.addingTimeInterval(hi.timeIntervalSince(lo)/2)
                    if (value(mid)<0)==(va<0) { lo=mid } else { hi=mid }
                }
                let root = lo.addingTimeInterval(hi.timeIntervalSince(lo)/2)
                if vb>va { up.append(root) } else { down.append(root) }
            }
            a=b; va=vb
        }
        return (up,down)
    }
}
