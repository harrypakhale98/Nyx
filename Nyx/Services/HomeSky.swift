import Foundation

/// "From home tonight": the sky over the place someone starts from, for people who cannot travel
/// to a park tonight. The Moon (phase, rise and set), the hours of true darkness, the planets and
/// a meteor shower or lunar eclipse worth stepping outside for, worked out on this device from the
/// same engine as every park. No cloud forecast is asked for, so no request ever carries the
/// person's coordinates; the panel says to check a local forecast instead.
///
/// The bundled world grids (`SkyGrid`, read on this device) add what they hold for the starting
/// point: the usual clouds for the month, and, when the sky layer is bundled, the sky's brightness
/// as a Bortle class "estimated from satellite data", which also scores the night (on the usual
/// clouds, never a forecast). Without the sky layer nothing about light is claimed: shower rates
/// assume a suburban sky, Bortle 7, and say so, and the panel says Nyx has no light map for homes.
nonisolated struct HomeSky: Sendable {
    enum Source: Sendable, Equatable { case device, place, park }
    /// Where the starting point's light level comes from.
    enum Light: Sendable, Equatable {
        /// The park's own hand-checked Bortle estimate.
        case park
        /// The sky grid's modelled zenith brightness, mag/arcsec².
        case satellite(magnitude: Double)
        /// No light map here: `assumedBortle`.
        case assumed
    }
    struct Origin: Sendable {
        let name: String
        let state: String
        let latitude: Double
        let longitude: Double
        let timeZone: TimeZone
        let source: Source
        /// The country the starting point is in: the place's own, else the device's region (no lookup is made).
        var countryCode = Locale.current.region?.identifier ?? "US"
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
    let light: Light
    /// The usual clouds for this month at a starting point that is not a park, from the cloud
    /// grid (an estimate, never a forecast); nil for a park, at sea, or without the grid.
    let usualClouds: CloudClimate.Typical?
    /// Tonight scored on the usual clouds, only where the light is known (a park's estimate or the
    /// sky grid): an assumed Bortle 7 never becomes a score.
    let estimate: Night?

    init(origin: Origin, now: Date, engine: AstronomyEngine = AstronomyEngine(), table: SkyEvents = .shared, grid: SkyGrid = .shared) {
        self.origin=origin
        let magnitude=origin.park == nil ? grid.skyBrightness(latitude: origin.latitude, longitude: origin.longitude) : nil
        light=origin.park != nil ? .park : magnitude.map { .satellite(magnitude: $0) } ?? .assumed
        let place=origin.park ?? Park(id: "home", nps: nil, name: origin.name, countryCode: origin.countryCode, region: origin.state, kind: .custom, curated: false,
                                      latitude: origin.latitude, longitude: origin.longitude, timeZoneID: origin.timeZone.identifier, darkSkyDesignated: false,
                                      bortleEstimate: magnitude.map(SkyGrid.bortle(fromMagnitude:)) ?? Self.assumedBortle,
                                      description: "", sourceURL: "", sourceNote: "", viewingSpots: [])
        self.place=place
        let sky=engine.conditions(for: place, on: place.evening(place.currentNight(at: now)))
        self.sky=sky
        var climate=CloudClimate.shared
        climate.grid=grid
        usualClouds=origin.park == nil ? climate.typical(place, on: sky.evening) : nil
        estimate=light == .assumed ? nil : NightPlanner.night(park: place, sky: sky, forecast: nil, detail: nil, now: now, climate: climate)
        let whatsUp=WhatsUp(park: place, sky: sky, isTonight: true, table: table, highlights: false)
        planets=whatsUp.planets
        eclipse=whatsUp.events.eclipse?.visible == nil ? nil : whatsUp.eclipse
        let showerNight=whatsUp.events.shower.flatMap { night in night.hourlyRate>=5 || (night.isPeakNight && WhatsUp.Events.isMajor(night.shower)) ? night : nil }
        // A park keeps the park's own words; anywhere else the rate is for the grid's sky or, without
        // one, a suburban sky, and says which.
        let skyLight=self.light
        shower=origin.park != nil ? (showerNight == nil ? nil : whatsUp.shower) : showerNight.map { Self.showerItem($0, place: place, sky: sky, light: skyLight) }
        moonFree=Self.moonFree(sky: sky, place: place, engine: engine)
    }
    /// What's up's shower row, worded for a home sky rather than a park's.
    static func showerItem(_ night: SkyAlmanac.ShowerNight, place: Park, sky: SkyConditions, light: Light = .assumed) -> WhatsUp.Item {
        let shower=night.shower, note=WhatsUp.peakNote(night, park: place, sky: sky, isTonight: true)
        let value: String, lead: String
        if let best=night.best {
            value=WhatsUp.rateText(night.hourlyRate)
            let moon=night.moonDownAtBest ? String(localized: "Moon down") : String(localized: "Moon up, \(Int((sky.moon.illumination*100).rounded()))% lit")
            var poor=""
            if night.isPeakNight && Double(night.hourlyRate)<0.25*shower.zhr {
                let reason=WhatsUp.poorReason(night, park: place, sky: sky)
                // The fallback sentence names a park; under city lights the next sentence already says why.
                if reason != String(localized: "A weak return from this park; a rough guide.") { poor=reason }
            }
            let observer=light == .assumed ? String(localized: "For one observer under a suburban sky; a rough guide. A darker yard shows more.")
                : String(localized: "For one observer under a Bortle \(place.bortleEstimate) sky, estimated from satellite data; a rough guide.")
            lead=Sentences.join([String(localized: "Best \(WhatsUp.whenPhrase(best, sky: sky, park: place)), \(moon)."), poor, observer])
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
            // The zone stored with the place (`places.json`); Nyx has no time-zone map, and asking a service would send the place.
            return Origin(name: place.name, state: place.state, latitude: place.latitude, longitude: place.longitude, timeZone: place.timeZone, source: .place, countryCode: place.countryCode)
        }
        guard let park else { return nil }
        return Origin(name: park.shortName, state: park.region, latitude: park.latitude, longitude: park.longitude, timeZone: park.timeZone, source: .park, countryCode: park.countryCode, park: park)
    }
    // MARK: Words

    /// "Waxing crescent, 18% lit"
    var moonPhase: String {
        String(localized: "\(sky.moon.name), \((sky.moon.illumination).formatted(.percent.precision(.fractionLength(0)))) lit")
    }
    /// "Sets 8:53 PM · Rises 4:42 AM" in time order, from noon to sunrise (a rise late the next
    /// morning is not tonight's news), or "Up all night" / "Below the horizon all night". Without a
    /// rise or set the Moon stays put, so its altitude midway through the night decides (the share of
    /// darkness it spends down says nothing on a night with no true darkness).
    var moonTimes: String {
        let morning=sky.sunrise ?? sky.end
        var events: [(Date, String)] = []
        if let rise=sky.moonrise, rise<morning { events.append((rise, String(localized: "Rises \(place.time(rise))"))) }
        if let set=sky.moonset, set<morning { events.append((set, String(localized: "Sets \(place.time(set))"))) }
        if events.isEmpty {
            let evening=sky.sunset ?? sky.evening, middle=evening.addingTimeInterval(morning.timeIntervalSince(evening)/2)
            // The upper limb on a refracted horizon, as the engine times rises and sets.
            let below=AstronomyEngine().lunarAltitude(at: middle, park: place) < -0.833
            return below ? String(localized: "Below the horizon all night") : String(localized: "Up all night")
        }
        return events.sorted { $0.0<$1.0 }.map(\.1).joined(separator: " · ")
    }
    /// "8:05 PM – 5:10 AM", or the no-darkness sentence the parks use.
    var darkness: String {
        if let start=sky.darkStart, let end=sky.darkEnd, end>start { return String(localized: "\(place.time(start)) – \(place.time(end))") }
        return SkyConditions.noDarknessMessage(tonight: true)
    }
    var hasDarkness: Bool { sky.darkHours>0 }
    /// "Usual clouds for November", the cloud row's title; nil without the grid's clouds.
    var usualCloudsTitle: String? {
        guard usualClouds != nil else { return nil }
        var format=Date.FormatStyle().month(.wide)
        format.timeZone=place.timeZone
        return String(localized: "Usual clouds for \(sky.evening.formatted(format))")
    }
    /// "About 8 in 10 November nights here are mostly clear." (an estimate from the grid).
    var usualCloudsLine: String? {
        guard let usualClouds else { return nil }
        var format=Date.FormatStyle().month(.wide)
        format.timeZone=place.timeZone
        return usualClouds.sentence(monthName: sky.evening.formatted(format))
    }
    /// The sky grid's class: "Bortle 4"; nil unless the light comes from the grid.
    var skyClass: String? {
        guard case .satellite=light else { return nil }
        return String(localized: "Bortle \(place.bortleEstimate)")
    }
    /// "Rural to suburban transition. Estimated from satellite data. …"; nil unless from the grid.
    var skyLine: String? {
        guard case .satellite=light else { return nil }
        return BortleScale.name(place.bortleEstimate)+". "+String(localized: "Estimated from satellite data. A light close by can make your own sky brighter.")
    }
    /// How the Moon shares the dark hours, in one sentence.
    var moonlightLine: String? {
        guard hasDarkness else { return nil }
        if sky.moon.illumination<0.05 { return String(localized: "No moonlight to speak of: a good night for faint stars.") }
        // "All" and "none" by the one Moon rule every surface uses (`SkyConditions.moonDownPercent`), in its words.
        if sky.moonDownPercent==100 { return Sentences.end(String(localized: "Moon-free through all of true darkness")) }
        guard let free=moonFree, sky.moonDownPercent>0 else { return Sentences.end(String(localized: "Moon up all through true darkness")) }
        return String(localized: "Moon-free from \(place.time(free.start)) to \(place.time(free.end)).")
    }
    /// The whole panel as one VoiceOver summary.
    var summary: String {
        var parts=[String(localized: "Moon: \(moonPhase). \(moonTimes)."),
                   hasDarkness ? String(localized: "True darkness: \(darkness).") : darkness]
        if let moonlightLine { parts.append(moonlightLine) }
        if let usualCloudsTitle, let usualCloudsLine { parts.append(usualCloudsTitle+". "+usualCloudsLine) }
        if let skyClass, let skyLine { parts.append(String(localized: "Sky brightness: \(skyClass).")+" "+skyLine) }
        if let eclipse { parts.append(eclipse.spoken) }
        if let shower { parts.append(shower.spoken) }
        parts.append(planets.isEmpty ? String(localized: "No bright planets up in true darkness.") : planets.map(\.spoken).joined(separator: " "))
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
