import Foundation

/// "From home tonight": the sky over the place someone starts from, for people who cannot travel
/// to a park tonight. The Moon (phase, rise and set), the hours of true darkness, the planets and
/// a meteor shower or lunar eclipse worth stepping outside for, worked out on this device from the
/// same engine as every park. No cloud forecast is asked for, so no request ever carries the
/// person's coordinates; the panel says to check a local forecast instead.
///
/// Nyx has no light-pollution model for arbitrary places (its sky-glow data is computed only for
/// the parks and their viewing spots), so no sky brightness is claimed. Shower rates assume a
/// suburban sky, Bortle 7, and say so.
nonisolated struct HomeSky: Sendable {
    enum Source: Sendable, Equatable { case device, place, park }
    struct Origin: Sendable {
        let name: String
        let state: String
        let latitude: Double
        let longitude: Double
        let timeZone: TimeZone
        let source: Source
        /// The real park when the starting point is a park (its own Bortle estimate counts).
        var park: Park?
    }
    /// A suburban sky (naked-eye limit about magnitude 4.8): what most homes have.
    static let assumedBortle = 7
    let origin: Origin
    /// The place as the engine needs it: a park-shaped stand-in with the home's coordinates.
    let place: Park
    let sky: SkyConditions
    let planets: [WhatsUp.Item]
    /// A shower worth stepping outside for from a lit sky: about five an hour or more at its best,
    /// or the peak night of a major shower (said plainly when it will be poor).
    let shower: WhatsUp.Item?
    /// A lunar eclipse visible from here tonight.
    let eclipse: WhatsUp.Item?
    /// The longest stretch of true darkness with the Moon down (nil when there is none, or no Moon to speak of).
    let moonFree: DateInterval?

    init(origin: Origin, now: Date, engine: AstronomyEngine = AstronomyEngine(), table: SkyEvents = .shared) {
        self.origin=origin
        let place=origin.park ?? Park(id: "home", apiCode: "home", name: origin.name, state: origin.state, latitude: origin.latitude, longitude: origin.longitude,
                                      timeZoneID: origin.timeZone.identifier, hemisphere: origin.latitude<0 ? "south" : "north", darkSkyDesignated: false,
                                      bortleEstimate: Self.assumedBortle, description: "", sourceURL: "", sourceNote: "", viewingSpots: [])
        self.place=place
        let sky=engine.conditions(for: place, on: place.evening(place.currentNight(at: now)))
        self.sky=sky
        let whatsUp=WhatsUp(park: place, sky: sky, isTonight: true, table: table)
        planets=whatsUp.planets
        eclipse=whatsUp.events.eclipse?.visible == nil ? nil : whatsUp.eclipse
        let showerNight=whatsUp.events.shower.flatMap { night in night.hourlyRate>=5 || (night.isPeakNight && WhatsUp.Events.isMajor(night.shower)) ? night : nil }
        // A park keeps the park's own words; anywhere else the rate is for a suburban sky, and says so.
        shower=origin.park != nil ? (showerNight == nil ? nil : whatsUp.shower) : showerNight.map { Self.showerItem($0, place: place, sky: sky) }
        moonFree=Self.moonFree(sky: sky, place: place, engine: engine)
    }
    /// What's up's shower row, worded for a home sky rather than a park's.
    static func showerItem(_ night: SkyAlmanac.ShowerNight, place: Park, sky: SkyConditions) -> WhatsUp.Item {
        let shower=night.shower, note=WhatsUp.peakNote(night, park: place, sky: sky, isTonight: true)
        let value: String, lead: String
        if let best=night.best {
            value=WhatsUp.rateText(night.hourlyRate)
            let moon=night.moonDownAtBest ? String(localized: "Moon down") : String(localized: "Moon up, \(Int((sky.moon.illumination*100).rounded()))% lit")
            var poor=""
            if night.isPeakNight && Double(night.hourlyRate)<0.25*shower.zhr {
                let reason=WhatsUp.poorReason(night, park: place, sky: sky)
                // The fallback sentence names a park; under city lights the next sentence already says why.
                if reason != String(localized: "A weak return from this park; a rough guide.") { poor=" "+reason }
            }
            lead=String(localized: "Best \(WhatsUp.whenPhrase(best, sky: sky, park: place)), \(moon).")+poor+" "+String(localized: "For one observer under a suburban sky; a rough guide. A darker yard shows more.")
        } else {
            value=String(localized: "No true darkness")
            lead=String(localized: "Without true darkness at this latitude, few meteors will show.")
        }
        return WhatsUp.Item(id: "shower-\(shower.code)", kind: .meteors, title: shower.localizedName, note: note, value: value, detail: lead,
                            spoken: "\(shower.localizedName), \(note): \(value). \(lead)", timed: night.best != nil)
    }

    // MARK: Where "home" is

    /// The device's location only when Near me is already in use (never asked for here), else the
    /// chosen city or town, else the starting park.
    static func origin(location: (latitude: Double, longitude: Double)?, place: StartingPlace?, park: Park?) -> Origin? {
        if let location {
            return Origin(name: String(localized: "your location"), state: "", latitude: location.latitude, longitude: location.longitude, timeZone: .current, source: .device)
        }
        if let place {
            return Origin(name: place.name, state: place.state, latitude: place.latitude, longitude: place.longitude,
                          timeZone: timeZone(state: place.state, latitude: place.latitude, longitude: place.longitude), source: .place)
        }
        guard let park else { return nil }
        return Origin(name: park.shortName, state: park.state, latitude: park.latitude, longitude: park.longitude, timeZone: park.timeZone, source: .park, park: park)
    }
    /// A US place's time zone from its state, with the split states divided by rough longitude
    /// and latitude lines that put every one of the bundled places on the right side. Nyx has no
    /// time-zone map, and asking a service would send the place.
    static func timeZone(state: String, latitude: Double, longitude: Double) -> TimeZone {
        let id: String
        switch state {
        case "HI": id="Pacific/Honolulu"
        case "AK": id="America/Anchorage"
        case "AZ": id="America/Phoenix"
        case "CA", "WA", "NV": id="America/Los_Angeles"
        // Malheur County keeps Mountain time.
        case "OR": id=longitude > -117.25 && latitude < 44.5 ? "America/Boise" : "America/Los_Angeles"
        // The panhandle north of the Salmon River keeps Pacific time.
        case "ID": id=latitude > 45.6 ? "America/Los_Angeles" : "America/Boise"
        case "CO", "MT", "NM", "UT", "WY": id="America/Denver"
        // El Paso, and Guadalupe Mountains, which keeps Mountain time.
        case "TX": id=longitude < -104.5 ? "America/Denver" : "America/Chicago"
        case "KS": id=longitude < -101.5 ? "America/Denver" : "America/Chicago"
        case "NE": id=longitude < -101.0 ? "America/Denver" : "America/Chicago"
        case "SD": id=longitude < -100.5 ? "America/Denver" : "America/Chicago"
        // Southwest North Dakota keeps Mountain time; the northwest (Williston) does not.
        case "ND": id=longitude < -101.0 && latitude < 47.5 ? "America/Denver" : "America/Chicago"
        case "FL": id=longitude < -85.0 && latitude > 29.6 ? "America/Chicago" : "America/New_York"
        // The northwest corner (Gary) and the southwest corner (Evansville) keep Central time.
        case "IN": id=longitude < -86.9 && (latitude > 40.9 || latitude < 38.6) ? "America/Chicago" : "America/Indiana/Indianapolis"
        case "KY": id=longitude < -85.9 ? "America/Chicago" : "America/Kentucky/Louisville"
        case "TN": id=longitude > -85.4 ? "America/New_York" : "America/Chicago"
        // Four Upper Peninsula counties on the Wisconsin line keep Central time; Isle Royale does not.
        case "MI": id=longitude < -87.6 && latitude > 45 && latitude < 46.6 ? "America/Chicago" : "America/Detroit"
        case "AL", "AR", "IL", "IA", "LA", "MN", "MS", "MO", "OK", "WI": id="America/Chicago"
        case "AS": id="Pacific/Pago_Pago"
        case "VI", "PR": id="America/St_Thomas"
        default: id="America/New_York"
        }
        return TimeZone(identifier: id) ?? .current
    }

    // MARK: Words

    /// "Waxing crescent, 18% lit"
    var moonPhase: String {
        String(localized: "\(sky.moon.name), \((sky.moon.illumination).formatted(.percent.precision(.fractionLength(0)))) lit")
    }
    /// "Sets 8:53 PM · Rises 4:42 AM" in time order, from noon to sunrise (a rise late the next
    /// morning is not tonight's news), or "Up all night" / "Below the horizon all night".
    var moonTimes: String {
        let morning=sky.sunrise ?? sky.end
        var events: [(Date, String)] = []
        if let rise=sky.moonrise, rise<morning { events.append((rise, String(localized: "Rises \(place.time(rise))"))) }
        if let set=sky.moonset, set<morning { events.append((set, String(localized: "Sets \(place.time(set))"))) }
        if events.isEmpty { return sky.moonBelowFraction>=1 ? String(localized: "Below the horizon all night") : String(localized: "Up all night") }
        return events.sorted { $0.0<$1.0 }.map(\.1).joined(separator: " · ")
    }
    /// "8:05 PM – 5:10 AM", or the no-darkness sentence the parks use.
    var darkness: String {
        if let start=sky.darkStart, let end=sky.darkEnd, end>start { return String(localized: "\(place.time(start)) – \(place.time(end))") }
        return SkyConditions.noDarknessMessage(tonight: true)
    }
    var hasDarkness: Bool { sky.darkHours>0 }
    /// How the Moon shares the dark hours, in one sentence.
    var moonlightLine: String? {
        guard hasDarkness else { return nil }
        if sky.moon.illumination<0.05 { return String(localized: "No moonlight to speak of: a good night for faint stars.") }
        guard let free=moonFree else { return String(localized: "The Moon is up through all of it.") }
        if let start=sky.darkStart, let end=sky.darkEnd, abs(free.start.timeIntervalSince(start))<120, abs(free.end.timeIntervalSince(end))<120 {
            return String(localized: "The Moon is down through all of it.")
        }
        return String(localized: "Moon-free from \(place.time(free.start)) to \(place.time(free.end)).")
    }
    /// The whole panel as one VoiceOver summary.
    var summary: String {
        var parts=[String(localized: "Moon: \(moonPhase). \(moonTimes)."),
                   hasDarkness ? String(localized: "True darkness: \(darkness).") : darkness]
        if let moonlightLine { parts.append(moonlightLine) }
        if let eclipse { parts.append(eclipse.spoken) }
        if let shower { parts.append(shower.spoken) }
        parts.append(planets.isEmpty ? String(localized: "No bright planets up in the dark hours.") : planets.map(\.spoken).joined(separator: " "))
        return parts.joined(separator: " ")
    }
    /// The longest moon-down stretch inside true darkness, sampled every five minutes.
    static func moonFree(sky: SkyConditions, place: Park, engine: AstronomyEngine) -> DateInterval? {
        guard sky.moon.illumination>=0.05, let start=sky.darkStart, let end=sky.darkEnd, end>start else { return nil }
        var best: DateInterval?, runStart: Date?
        var t=start
        while t<=end {
            let down=engine.lunarAltitude(at: t, park: place) < -0.833
            if down, runStart == nil { runStart=t }
            if !down || t.addingTimeInterval(300)>end, let s=runStart {
                let e=down ? end : t
                if e>s, (best?.duration ?? 0)<e.timeIntervalSince(s) { best=DateInterval(start: s, end: e) }
                runStart=nil
            }
            t=t.addingTimeInterval(300)
        }
        // The engine's exact moonset and moonrise, where a sampled edge lies within a step of one.
        guard var found=best else { return nil }
        if let set=sky.moonset, abs(set.timeIntervalSince(found.start))<=300, set>=start, set<found.end { found=DateInterval(start: set, end: found.end) }
        if let rise=sky.moonrise, abs(rise.timeIntervalSince(found.end))<=300, rise<=end, rise>found.start { found=DateInterval(start: found.start, end: rise) }
        return found
    }
}
