import Foundation

nonisolated protocol AstronomyProviding: Sendable {
    func conditions(for park: Park, on date: Date) -> SkyConditions
}

/// Local-noon to local-noon night, with actual UTC instants through DST changes.
/// Solar coordinates: NOAA / Meeus equations (geometric altitude; -0.833° rise/set).
/// Lunar position: truncated Meeus periodic series plus topocentric parallax.
/// Roots bracketed every 5 minutes, bisected to <1 second. Terrain/refraction are
/// not modeled. Target: Sun ±2 min, Moon ±15 min; see Research/accuracy.md.
nonisolated struct AstronomyEngine: AstronomyProviding {
    static let synodicDays = 29.530588853
    static let epoch = Date(timeIntervalSince1970: 947_182_440) // 2000-01-06 18:14 UTC
    private let rad = Double.pi / 180
    /// Start with the synodic epoch cycle, then correct its phase angle with
    /// Meeus lunar/solar elongation. The uncorrected mean can miss a new Moon
    /// by >17 hours in 2026, which is too coarse for a date-scrubbing planner.
    func meanMoonPhase(at date: Date) -> MoonPhase {
        let cycles = date.timeIntervalSince(Self.epoch) / (86_400 * Self.synodicDays)
        return MoonPhase(fraction: cycles - floor(cycles))
    }
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
        let moon = crossings(start: start, end: end) { lunarAltitude(at: $0, park: park) + 0.3 }
        var below = 0.0
        if let a = darkStart, let b = darkEnd, b > a {
            // Integrate exact horizon-crossing intervals, not a Boolean moon bonus.
            let edges = ([a] + (moon.up + moon.down).filter { $0 > a && $0 < b }.sorted() + [b])
            for index in 0..<(edges.count-1) {
                let middle = edges[index].addingTimeInterval(edges[index+1].timeIntervalSince(edges[index])/2)
                if lunarAltitude(at: middle, park: park) < -0.3 { below += edges[index+1].timeIntervalSince(edges[index]) }
            }
            below /= b.timeIntervalSince(a)
        }
        return SkyConditions(evening: start, end: end, sunset: sun.down.first, sunrise: sun.up.first,
            civilDusk: civil.down.first, nauticalDusk: nautical.down.first, darkStart: darkStart, darkEnd: darkEnd,
            state: state, moon: moonPhase(at: start.addingTimeInterval(10*3600)),
            moonrise: moon.up.first, moonset: moon.down.first, moonBelowFraction: min(1,max(0,below)), darkHours: hours)
    }
    private func julian(_ date: Date) -> Double { date.timeIntervalSince1970/86400 + 2440587.5 }
    private func normalized(_ value: Double) -> Double { value - floor(value/360)*360 }
    private func sinD(_ a: Double) -> Double { sin(a*rad) }
    private func cosD(_ a: Double) -> Double { cos(a*rad) }
    private func altitude(date: Date, park: Park, ra: Double, dec: Double) -> Double {
        let jd = julian(date)
        let t = (jd-2451545)/36525
        let sidereal = normalized(280.46061837 + 360.98564736629*(jd-2451545) + 0.000387933*t*t - t*t*t/38710000)
        let h = (sidereal + park.longitude)*rad - ra
        let lat = park.latitude*rad
        return asin(max(-1,min(1,sin(lat)*sin(dec)+cos(lat)*cos(dec)*cos(h))))/rad
    }
    func solarAltitude(at date: Date, park: Park) -> Double {
        let t = (julian(date)-2451545)/36525
        let l = normalized(280.46646 + t*(36000.76983 + t*0.0003032))
        let m = 357.52911 + t*(35999.05029-0.0001537*t)
        let c = sinD(m)*(1.914602-t*(0.004817+0.000014*t)) + sinD(2*m)*(0.019993-0.000101*t)+sinD(3*m)*0.000289
        let omega = 125.04-1934.136*t
        let lambda = (l+c-0.00569-0.00478*sinD(omega))*rad
        let epsilon = (23+(26+(21.448-t*(46.815+t*(0.00059-t*0.001813)))/60)/60+0.00256*cosD(omega))*rad
        return altitude(date: date, park: park, ra: atan2(cos(epsilon)*sin(lambda),cos(lambda)), dec: asin(sin(epsilon)*sin(lambda)))
    }
    func lunarAltitude(at date: Date, park: Park) -> Double {
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
        let geo = altitude(date: date, park: park, ra: atan2(y,x), dec: asin(z))
        return geo - asin(6378.14/distance)/rad * cosD(geo)
    }
    func milkyWayGuidance(for park: Park, on date: Date) -> String {
        let month = park.calendar.component(.month, from: date)
        if abs(park.latitude)>60 { return String(localized: "The bright center stays low on the horizon at this latitude.") }
        // The sky's right ascension gives both hemispheres the same calendar
        // season; its name inverts: June–August is southern winter.
        if (6...8).contains(month) {
            return park.latitude < 0
                ? String(localized: "Southern winter favors the bright center. Look toward the southern sky; timing and terrain matter.")
                : String(localized: "Summer favors the bright center. Look toward the southern sky; timing and terrain matter.")
        }
        return (3...10).contains(month)
            ? String(localized: "The bright center may be visible late at night or near dusk. Timing and terrain matter.")
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
