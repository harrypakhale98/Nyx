import Foundation

/// The night's sky beyond the score, in calm sentences: the Milky Way's bright center, the
/// planets, a meteor shower and a lunar eclipse, and the night's highlights (the Moon or two planets
/// close together, a Full Moon at its nearest, Mercury or Venus at their best, a solstice, the
/// gegenschein). Built from `SkyAlmanac`; which items show, in
/// what order and in what words is decided here so it can be tested without a screen. None of it
/// changes the Darkness Score: these are reasons to go, never points.
nonisolated struct WhatsUp: Sendable {
    enum Kind: String, Sendable { case core, planet, meteors, eclipse, aurora, pairing, moon, planetBest, season, gegenschein, deepSky }
    struct Item: Sendable, Identifiable, Equatable {
        let id: String
        let kind: Kind
        let title: String
        /// A word or two beside the title: "very bright", "peak tonight".
        var note: String?=nil
        /// The figure to read at a glance: a time range or a rate.
        var value: String?=nil
        let detail: String
        /// Everything above as one or two sentences, with ranges said as "from … to …".
        let spoken: String
        /// Where a figure comes from, in smaller type: the published rate behind a shower's estimate.
        var footnote: String?=nil
        /// True when the figure is a time the core or an event is up (drawn in amber), not a state.
        var timed=false
    }
    let core: Item
    /// The core's night as computed, for the clear window and the light-dome note.
    let coreNight: SkyAlmanac.CoreNight
    let planets: [Item]
    let shower: Item?
    let eclipse: Item?
    /// Aurora within reach tonight by NOAA's Kp forecast (`AuroraForecast.item`), passed in by the
    /// surfaces that have the forecast; nil otherwise.
    let aurora: Item?
    /// Pairings (closest first), a Full Moon at its nearest, Mercury or Venus at its best, a
    /// solstice, the gegenschein: the order `Layout` and every surface show them in.
    let highlights: [Item]
    let events: Events
    /// Everything, in exactly the order every screen shows it (`layout`), for Siri and Ask Nyx, which
    /// read the first few: the rows above the planets (a shower or eclipse that earns a row among
    /// them), the planets, the other rows, and last what the screens give one line (a weak shower,
    /// an eclipse the park cannot see). So a Geminid peak is said before the planets, a shower of
    /// two an hour after them, on the iPhone, iPad, the watch, Vision Pro and Siri alike.
    var items: [Item] {
        let layout=layout
        return layout.first + planets + layout.after + layout.mentions
    }
    /// The rows above the planets, which the panel groups under one heading.
    var leading: [Item] { [eclipse, shower].compactMap { $0 } + [core] }

    /// `highlights` false skips the pairings, binocular sights and the rest, for a reader that shows none of them.
    init(park: Park, sky: SkyConditions, isTonight: Bool, table: SkyEvents = .shared, almanac: SkyAlmanac = SkyAlmanac(), aurora: Item? = nil, highlights: Bool = true) {
        self.aurora=aurora
        let events=Events(park: park, sky: sky, table: table, almanac: almanac)
        self.events=events
        coreNight=almanac.core(for: park, sky: sky)
        core=Self.coreItem(coreNight, park: park, sky: sky, almanac: almanac)
        let planetNights=almanac.planets(for: park, sky: sky)
        planets=planetNights.map { Self.planetItem($0, park: park, sky: sky) }
        shower=events.shower.map { Self.showerItem($0, park: park, sky: sky, isTonight: isTonight) }
        eclipse=events.eclipse.map { Self.eclipseItem($0, park: park) }
        self.highlights=highlights ? Self.highlightItems(park: park, sky: sky, planets: planetNights, almanac: almanac) : []
    }

    // MARK: Layout: the one rule for the iPhone card, the watch page and every list

    /// Where each item goes: `first` above the planets, `after` below them, `mentions` a line each.
    /// A total lunar eclipse the park can see leads, then aurora in reach; then the core; then the rare
    /// things that earn a row, a shower of ten or more an hour and a partial eclipse, before the planets
    /// that are up most nights; after the planets, pairings, a Full Moon at its nearest and the
    /// gegenschein. Weaker showers, a penumbral eclipse or one the park cannot see, Mercury or Venus
    /// at its best (the planet already has its row) and a solstice are mentions.
    struct Layout: Equatable { var first: [Item]; var after: [Item]; var mentions: [Item] }
    /// Showers under this many an hour are a mention, not a row.
    static let showerRow=10
    var layout: Layout {
        var layout=Layout(first: [core], after: [], mentions: [])
        if let shower {
            if (events.shower?.hourlyRate ?? 0)>=Self.showerRow { layout.first.append(shower) } else { layout.mentions.append(shower) }
        }
        if let eclipse, let night=events.eclipse {
            if night.visible == nil || night.eclipse.type == "penumbral" { layout.mentions.append(eclipse) }
            else if night.eclipse.type == "total" { layout.first.insert(eclipse, at: 0) }
            else { layout.first.append(eclipse) }
        }
        // Aurora in reach comes just before the core (after a total eclipse, before the rare rows after the core).
        if let aurora { layout.first.insert(aurora, at: layout.first.firstIndex { $0.id == core.id } ?? 0) }
        for item in highlights {
            switch item.kind {
            case .planetBest, .season: layout.mentions.append(item)
            default: layout.after.append(item)
            }
        }
        return layout
    }

    // MARK: Events: what earns a glyph, a reminder or a line on Tonight

    /// The shower and eclipse worth mentioning on a night, without the core and planets, so
    /// calendars and reminders can ask about many nights cheaply.
    struct Events: Sendable, Equatable {
        enum Glyph: Sendable, Equatable { case eclipse, meteors }
        let shower: SkyAlmanac.ShowerNight?
        let eclipse: SkyAlmanac.EclipseNight?
        init(shower: SkyAlmanac.ShowerNight?, eclipse: SkyAlmanac.EclipseNight?) { self.shower=shower; self.eclipse=eclipse }
        init(park: Park, sky: SkyConditions, table: SkyEvents = .shared, almanac: SkyAlmanac = SkyAlmanac()) {
            shower=Self.featured(almanac.showers(table.meteorShowers, for: park, sky: sky, bortle: park.bortleEstimate))
            eclipse=almanac.lunarEclipse(table.lunarEclipses, for: park, sky: sky).flatMap { Self.worthShowing($0.eclipse) ? $0 : nil }
        }
        /// One mark per night at most: an eclipse the park can see, else the peak night of a
        /// notable shower (whatever the score; a washed-out peak is still worth knowing about).
        var glyph: Glyph? {
            if eclipse?.visible != nil { return .eclipse }
            if let shower, shower.isPeakNight, Self.isNotable(shower.shower), shower.best != nil { return .meteors }
            return nil
        }
        /// Showers whose rate rounds to under two an hour are left out, except on a notable
        /// shower's peak night, where saying plainly that it will be poor here is useful.
        static func featured(_ nights: [SkyAlmanac.ShowerNight]) -> SkyAlmanac.ShowerNight? {
            nights.filter { $0.hourlyRate>=2 || ($0.isPeakNight && isNotable($0.shower)) }
                .max { ($0.hourlyRate, $0.isPeakNight ? 1 : 0) < ($1.hourlyRate, $1.isPeakNight ? 1 : 0) }
        }
        /// Published peak rate of 15 or more: the showers people plan around.
        static func isNotable(_ shower: SkyAlmanac.MeteorShower) -> Bool { shower.zhr>=15 }
        /// The big three, and anything with a published rate of 50 or more.
        static func isMajor(_ shower: SkyAlmanac.MeteorShower) -> Bool { shower.zhr>=50 || ["GEM","PER","QUA"].contains(shower.code) }
        /// Penumbral eclipses shallower than 0.7 are not noticeable to the eye (NASA).
        static func worthShowing(_ eclipse: SkyAlmanac.LunarEclipse) -> Bool { eclipse.type != "penumbral" || (eclipse.penumbralMagnitude ?? 0)>=0.7 }
        /// A shower peak worth a reminder or a line on Tonight: a major shower's peak night with
        /// at least 20 an hour expected at its best moment, and the Moon down then.
        var reminderShower: SkyAlmanac.ShowerNight? {
            guard let shower, shower.isPeakNight, Self.isMajor(shower.shower), shower.hourlyRate>=20, shower.moonDownAtBest, shower.best != nil else { return nil }
            return shower
        }
        /// The mark a calendar night or river night carries, with its short name.
        struct Marker: Sendable, Equatable { let glyph: Glyph; let name: String }
        func marker(park: Park) -> Marker? { glyph.flatMap { glyph in headline(park: park).map { Marker(glyph: glyph, name: $0) } } }
        /// The full line for the marked event, for a calendar peek or the score breakdown.
        func item(park: Park, sky: SkyConditions, isTonight: Bool) -> Item? {
            switch glyph {
            case .eclipse: eclipse.map { WhatsUp.eclipseItem($0, park: park) }
            case .meteors: shower.map { WhatsUp.showerItem($0, park: park, sky: sky, isTonight: isTonight) }
            case nil: nil
            }
        }
        /// "Geminids peak", "Total lunar eclipse": the short name used beside calendar nights.
        func headline(park: Park) -> String? {
            switch glyph {
            case .eclipse: eclipse.map { WhatsUp.eclipseName($0.eclipse) }
            case .meteors: shower.map { String(localized: "\($0.shower.localizedName) peak") }
            case nil: nil
            }
        }
    }

    // MARK: The Milky Way's bright center

    static func coreItem(_ core: SkyAlmanac.CoreNight, park: Park, sky: SkyConditions, almanac: SkyAlmanac = SkyAlmanac()) -> Item {
        let title=String(localized: "Milky Way core")
        func item(_ value: String, _ detail: String) -> Item {
            Item(id: "core", kind: .core, title: title, value: value, detail: detail, spoken: "\(title): \(value). \(detail)")
        }
        // The seasonal guidance's own words where nothing can be timed: far north, or no true darkness.
        if core.peakPossible<3 { return item(String(localized: "Below the horizon"), AstronomyEngine().milkyWayGuidance(for: sky, park: park)) }
        if core.neverUp {
            return item(String(localized: "Low on the horizon"), String(localized: "At this latitude the bright center never climbs more than \(Int(core.peakPossible.rounded()))° up. An open view to the south matters most."))
        }
        if sky.darkHours==0 { return item(String(localized: "No true darkness"), AstronomyEngine().milkyWayGuidance(for: sky, park: park)) }
        guard let dark=core.dark else {
            if core.highestAltitude>=SkyAlmanac.coreMinimumAltitude, let start=sky.darkStart, let end=sky.darkEnd {
                if let sets=core.sets, sets<=start.addingTimeInterval(60) {
                    return item(String(localized: "Sets before darkness"), String(localized: "The bright center sets at \(park.time(sets)), before true darkness begins at \(park.time(start))."))
                }
                if let rises=core.rises, rises>=end.addingTimeInterval(-60) {
                    return item(String(localized: "Rises after darkness"), String(localized: "The bright center rises at \(park.time(rises)), after true darkness ends at \(park.time(end))."))
                }
            }
            return item(String(localized: "Out of the night sky"), String(localized: "The bright center is near the Sun this season. The Milky Way's fainter band still crosses dark skies."))
        }
        let peak=almanac.highest(ra: SkyAlmanac.coreRA, dec: SkyAlmanac.coreDec, park: park, in: dark)
        let range=String(localized: "\(park.time(dark.start)) – \(park.time(dark.end))")
        // Highest at an edge of the dark window means it is sinking all night, or still climbing at dawn.
        let degrees=Int(peak.altitude.rounded()), direction=Compass.name(peak.azimuth)
        var detail=peak.date.timeIntervalSince(dark.start)<600 && dark.duration>1800 ? String(localized: "\(degrees)° up in the \(direction) as true darkness begins, then sinking.")
            : dark.end.timeIntervalSince(peak.date)<600 && dark.duration>1800 ? String(localized: "Still climbing: \(degrees)° up in the \(direction) as true darkness ends.")
            : String(localized: "Highest at \(park.time(peak.date)), \(degrees)° up in the \(direction).")
        if peak.altitude<20 { detail=Sentences.join([detail, String(localized: "Low: an open view toward the horizon matters.")]) }
        detail=Sentences.join([detail, moonSentence(dark: dark, free: core.moonFree, sky: sky, park: park)])
        if let terrain=terrainSentence(dark: dark, park: park, almanac: almanac) { detail=Sentences.join([detail, terrain]) }
        let spokenRange=String(localized: "up in true darkness from \(park.time(dark.start)) to \(park.time(dark.end))")
        return Item(id: "core", kind: .core, title: title, value: range, detail: detail, spoken: "\(title): \(spokenRange). \(detail)", timed: true)
    }
    /// When the real terrain at the park's main viewing spot (`Horizon.Table.main`) changes when the
    /// core can be seen: it must stand a degree above the skyline as well as 10° up. Said only when
    /// that moves a time by 15 minutes or more, rounded to ten minutes (the profile's 5° bins and the
    /// terrain model's metre-scale elevations make anything finer false precision). Nil where the
    /// terrain changes nothing, or no profile exists.
    static func terrainSentence(dark: DateInterval, park: Park, almanac: SkyAlmanac, table: Horizon.Table = .shared) -> String? {
        guard let (horizon, spot)=table.main(park) else { return nil }
        let place=spot ?? park.shortName
        let clear={ (date: Date) -> Bool in
            let p=almanac.engine.horizontal(date: date, park: park, ra: SkyAlmanac.coreRA, dec: SkyAlmanac.coreDec)
            return p.altitude>=max(SkyAlmanac.coreMinimumAltitude, horizon.altitude(toward: p.azimuth)+Horizon.clearance)
        }
        guard let seen=almanac.longest(in: dark, where: clear) else {
            return String(localized: "From \(place), the terrain hides it all through true darkness.")
        }
        let later=seen.start.timeIntervalSince(dark.start)>=900, earlier=dark.end.timeIntervalSince(seen.end)>=900
        switch (later, earlier) {
        case (true, true): return String(localized: "From \(place), it clears the terrain around \(around(seen.start, park: park)) and drops behind it around \(around(seen.end, park: park)).")
        case (true, false): return String(localized: "From \(place), it clears the terrain around \(around(seen.start, park: park)).")
        case (false, true): return String(localized: "From \(place), it drops behind the terrain around \(around(seen.end, park: park)).")
        case (false, false): return nil
        }
    }
    /// How the Moon shares the core's dark hours.
    static func moonSentence(dark: DateInterval, free: DateInterval?, sky: SkyConditions, park: Park) -> String {
        if sky.moon.negligible { return String(localized: "No moonlight to wash it out.") }
        guard let free else { return String(localized: "The Moon is up all that time, \(sky.moon.percentLit)% lit.") }
        let tolerance=120.0
        let fromStart=abs(free.start.timeIntervalSince(dark.start))<tolerance, toEnd=abs(free.end.timeIntervalSince(dark.end))<tolerance
        switch (fromStart, toEnd) {
        case (true, true): return String(localized: "The Moon is down all that time.")
        case (false, true): return String(localized: "Moon-free from \(park.time(free.start)).")
        case (true, false): return String(localized: "Moon-free until \(park.time(free.end)).")
        case (false, false): return String(localized: "Moon-free from \(park.time(free.start)) to \(park.time(free.end)).")
        }
    }

    // MARK: Planets

    /// Magnitude as a word: Schlyter's Mercury can be 0.7 magnitudes off, so no number is shown.
    /// "Faint" only past +1.5: Mars at +1 is as bright as Spica.
    static func brightness(_ magnitude: Double) -> String {
        magnitude <= -1.5 ? String(localized: "very bright") : magnitude <= 1.5 ? String(localized: "bright") : String(localized: "faint")
    }
    static func planetItem(_ planet: SkyAlmanac.PlanetNight, park: Park, sky: SkyConditions) -> Item {
        let engine=AstronomyEngine(), almanac=SkyAlmanac()
        func direction(_ date: Date) -> String {
            let p=almanac.position(of: planet.planet, at: date)
            return Compass.name(engine.horizontal(date: date, park: park, ra: p.ra, dec: p.dec).azimuth)
        }
        let bestDirection=Compass.name(planet.bestAzimuth)
        let height=planet.bestAltitude>=30 ? String(localized: "high in the \(bestDirection)") : planet.bestAltitude<15 ? String(localized: "low in the \(bestDirection)") : String(localized: "in the \(bestDirection)")
        // Where the best moment falls: near dawn, near dusk, or in the middle of the night.
        let beforeDawn=planet.visible.end.timeIntervalSince(planet.best)<1800 && planet.sets == nil
        let value: String, detail: String
        switch (planet.rises, planet.sets) {
        case (nil, nil):
            value=String(localized: "All night")
            detail=String(localized: "Up all night, highest around \(around(planet.best, park: park)) in the \(bestDirection).")
        case (nil, let sets?):
            value=String(localized: "Until \(park.time(sets))")
            detail=planet.bestAltitude<15 ? String(localized: "Low in the \(direction(planet.visible.start)) after dusk; sets at \(park.time(sets)).")
                : String(localized: "In the \(direction(planet.visible.start)) after dusk; sets at \(park.time(sets)).")
        case (let rises?, nil):
            value=String(localized: "Rises \(park.time(rises))")
            let riseDirection=direction(rises)
            if !beforeDawn {
                detail=String(localized: "Rises at \(park.time(rises)) in the \(riseDirection); highest around \(around(planet.best, park: park)) in the \(bestDirection).")
            } else if riseDirection != bestDirection {
                detail=String(localized: "Rises at \(park.time(rises)) in the \(riseDirection); \(height) before dawn.")
            } else {
                detail=planet.bestAltitude>=30 ? String(localized: "Rises at \(park.time(rises)) in the \(riseDirection) and climbs high before dawn.")
                    : planet.bestAltitude<15 ? String(localized: "Rises at \(park.time(rises)) in the \(riseDirection); still low at dawn.")
                    : String(localized: "Rises at \(park.time(rises)) in the \(riseDirection); well up by dawn.")
            }
        case (let rises?, let sets?):
            value=String(localized: "\(park.time(rises)) – \(park.time(sets))")
            detail=String(localized: "Rises at \(park.time(rises)) in the \(direction(rises)), highest around \(around(planet.best, park: park)), sets at \(park.time(sets)).")
        }
        let note=brightness(planet.magnitude)
        return Item(id: planet.planet.rawValue, kind: .planet, title: planet.planet.name, note: note, value: value, detail: detail,
            spoken: "\(planet.planet.name), \(note). \(detail)")
    }

    // MARK: Meteor showers

    /// Rates are rounded to what they can honestly claim: units under 10, fives under 50, tens above.
    static func rounded(rate: Int) -> Int { rate<10 ? rate : rate<50 ? Int((Double(rate)/5).rounded())*5 : Int((Double(rate)/10).rounded())*10 }
    /// A range, because the published rate is a trained observer's ceiling: casual watchers see
    /// about half. "60–130 an hour"; "about 2 an hour" where the two ends meet.
    static func rateText(_ rate: Int) -> String {
        guard rate>=1 else { return String(localized: "fewer than 1 an hour") }
        let high=rounded(rate: rate), low=rounded(rate: max(1, Int((Double(rate)/2).rounded())))
        return low>=high ? String(localized: "about \(high) an hour") : String(localized: "\(low)–\(high) an hour")
    }
    /// The peak's night relative to this one: "peak tonight", "peak in 3 nights", "peak was last night".
    static func peakNote(_ shower: SkyAlmanac.ShowerNight, park: Park, sky: SkyConditions, isTonight: Bool) -> String {
        if shower.isPeakNight { return isTonight ? String(localized: "peak tonight") : String(localized: "peak this night") }
        // Local noon to noon: a morning peak belongs to the night before.
        var peakNight=park.evening(shower.peak)
        if shower.peak<peakNight { peakNight=park.date(peakNight, addingDays: -1) }
        let days=park.calendar.dateComponents([.day], from: park.evening(sky.evening), to: peakNight).day ?? 0
        // Counted from the night shown, which may be a scrubbed one, so never "ago".
        switch days {
        case 1: return isTonight ? String(localized: "peak tomorrow night") : String(localized: "peak the next night")
        case 2...: return String(localized: "peak in \(days) nights")
        case -1: return String(localized: "the night after the peak")
        default: return String(localized: "\(-days) nights after the peak")
        }
    }
    /// "before dawn" when the best moment is within two hours of true darkness ending; otherwise a time.
    static func whenPhrase(_ date: Date, sky: SkyConditions, park: Park) -> String {
        if let end=sky.darkEnd, end.timeIntervalSince(date)<2*3600 { return String(localized: "before dawn") }
        return String(localized: "around \(around(date, park: park))")
    }
    /// A shower's row. `homeObserver`: the sky a home's rate is for (`HomeSky.showerItem`), which
    /// replaces the park's observer line, leaves out the published rate and a poor return's
    /// park-worded fallback (the observer line already says why under city lights).
    static func showerItem(_ night: SkyAlmanac.ShowerNight, park: Park, sky: SkyConditions, isTonight: Bool, homeObserver: String? = nil) -> Item {
        let shower=night.shower, note=peakNote(night, park: park, sky: sky, isTonight: isTonight)
        let published=shower.variable == true ? String(localized: "The published peak rate is \(Int(shower.zhr)) an hour under a perfect sky, with the radiant, the point the meteors seem to come from, overhead (International Meteor Organization); it varies from year to year.")
            : String(localized: "The published peak rate is \(Int(shower.zhr)) an hour under a perfect sky, with the radiant, the point the meteors seem to come from, overhead (International Meteor Organization).")
        let value: String, lead: String
        if let best=night.best {
            value=rateText(night.hourlyRate)
            let moon=night.moonDownAtBest ? String(localized: "Moon down") : String(localized: "Moon up, \(sky.moon.percentLit)% lit")
            // A peak night far below the published rate says why, plainly.
            var poor=night.isPeakNight && Double(night.hourlyRate)<0.25*shower.zhr ? poorReason(night, park: park, sky: sky) : ""
            if homeObserver != nil, poor == String(localized: "A weak return from this park; a rough guide.") { poor="" }
            lead=Sentences.join([String(localized: "Best \(whenPhrase(best, sky: sky, park: park)), \(moon)."), poor, homeObserver ?? String(localized: "For one observer under this park's sky; a rough guide.")])
        } else {
            value=String(localized: "No true darkness")
            lead=String(localized: "Without true darkness at this latitude, few meteors will show.")
        }
        let home=homeObserver != nil
        return Item(id: "shower-\(shower.code)", kind: .meteors, title: shower.localizedName, note: note, value: value, detail: lead,
            spoken: home ? "\(shower.localizedName), \(note): \(value). \(lead)" : "\(shower.localizedName), \(note): \(value). \(lead) \(published)",
            footnote: home ? nil : published, timed: night.best != nil)
    }
    /// Why a peak night will be poor from this park, in one honest sentence.
    static func poorReason(_ night: SkyAlmanac.ShowerNight, park: Park, sky: SkyConditions) -> String {
        let engine=AstronomyEngine(), rad=Double.pi/180
        let radiant=engine.horizontal(date: night.peak, park: park, ra: night.shower.radiantRA*rad, dec: night.shower.radiantDec*rad).altitude
        if !night.moonDownAtBest && sky.moon.illumination>0.5 { return String(localized: "A bright Moon hides all but the brightest meteors.") }
        if engine.solarAltitude(at: night.peak, park: park) > -12 { return String(localized: "The peak falls in daylight or twilight here, so only the edges of it reach a dark sky.") }
        if radiant<20 { return String(localized: "The peak falls while the radiant is low here, so few meteors reach this sky.") }
        return String(localized: "A weak return from this park; a rough guide.")
    }

    // MARK: Lunar eclipses

    static func eclipseName(_ eclipse: SkyAlmanac.LunarEclipse) -> String {
        switch eclipse.type {
        case "total": String(localized: "Total lunar eclipse")
        case "partial": String(localized: "Partial lunar eclipse")
        default: String(localized: "Penumbral lunar eclipse")
        }
    }
    static func eclipseItem(_ night: SkyAlmanac.EclipseNight, park: Park) -> Item {
        let eclipse=night.eclipse, title=eclipseName(eclipse)
        guard let visible=night.visible else {
            let detail=String(localized: "Not visible from this park: the Moon is below the horizon.")
            return Item(id: "eclipse", kind: .eclipse, title: title, note: String(localized: "not visible here"), detail: detail, spoken: "\(title). \(detail)")
        }
        // Only the partial phase is up here: the Moon rises already in Earth's shadow, or sets
        // during it. Said plainly, with the times it can be seen.
        if eclipse.type=="total", night.stage == .umbral {
            let range=String(localized: "\(park.time(visible.start)) – \(park.time(visible.end))")
            let rises=eclipse.u1.map { visible.start.timeIntervalSince($0)>120 } ?? false
            let detail=rises ? String(localized: "Rises already in Earth's shadow; partial phase visible \(park.time(visible.start))–\(park.time(visible.end)). Totality is over before moonrise here.")
                : String(localized: "Sets during the partial phase; visible \(park.time(visible.start))–\(park.time(visible.end)). Totality comes after moonset here.")
            return Item(id: "eclipse", kind: .eclipse, title: title, note: String(localized: "partial phase here"), value: range, detail: detail, spoken: "\(title). \(detail)", timed: true)
        }
        let engine=AstronomyEngine()
        let moment=night.greatestVisible ? eclipse.greatest : visible.start.addingTimeInterval(visible.duration/2)
        let moon=engine.equatorial(of: .moon, at: moment)
        let position=engine.horizontal(date: moment, park: park, ra: moon.ra, dec: moon.dec)
        let place=position.altitude>=45 ? String(localized: "Moon high in the \(Compass.name(position.azimuth))")
            : position.altitude<15 ? String(localized: "Moon low in the \(Compass.name(position.azimuth))")
            : String(localized: "Moon \(Int(position.altitude.rounded()))° up in the \(Compass.name(position.azimuth))")
        let stage: String = switch night.stage ?? (eclipse.type=="total" ? .total : eclipse.type=="partial" ? .umbral : .penumbral) {
        case .total: String(localized: "Totality")
        case .umbral: String(localized: "In Earth's shadow")
        case .penumbral: String(localized: "A faint dimming")
        }
        let range=String(localized: "\(park.time(visible.start)) – \(park.time(visible.end))")
        // The figure carries the times; the sentence says what and where. VoiceOver hears both.
        let spokenStage=String(localized: "\(stage) from \(park.time(visible.start)) to \(park.time(visible.end)), \(place).")
        var detail=String(localized: "\(stage), \(place).")
        var extras: [String]=[]
        let full=[eclipse.u2 ?? eclipse.u1 ?? eclipse.p1, eclipse.u3 ?? eclipse.u4 ?? eclipse.p4]
        if let start=full[0], visible.start.timeIntervalSince(start)>120 { extras.append(String(localized: "The Moon rises already eclipsed.")) }
        if let end=full[1], end.timeIntervalSince(visible.end)>120 { extras.append(String(localized: "The Moon sets before it ends.")) }
        if eclipse.type=="partial" { extras.append(String(localized: "At most \(Int((eclipse.umbralMagnitude*100).rounded()))% of the Moon's width is in shadow.")) }
        if eclipse.type=="penumbral" { extras.append(String(localized: "Subtle: the Moon's edge darkens slightly.")) }
        detail=Sentences.join([detail]+extras)
        return Item(id: "eclipse", kind: .eclipse, title: title, value: range, detail: detail, spoken: "\(title). \(Sentences.join([spokenStage]+extras))", timed: true)
    }

    // MARK: Highlights

    static func highlightItems(park: Park, sky: SkyConditions, planets: [SkyAlmanac.PlanetNight], almanac: SkyAlmanac) -> [Item] {
        var items: [Item]=[]
        // Two pairings at most: the closest are the ones worth stepping out for.
        items+=almanac.pairings(planets: planets, park: park, sky: sky).prefix(2).map { pairingItem($0, park: park) }
        if let distance=almanac.nearFullMoon(sky: sky) { items.append(nearFullMoonItem(distance: distance)) }
        for night in planets {
            if let day=almanac.greatestElongation(of: night.planet, near: SkyAlmanac.nightWindow(sky).start) {
                items.append(planetBestItem(night, day: day, park: park, sky: sky))
            }
        }
        if let solstice=almanac.solstice(park: park, sky: sky) { items.append(solsticeItem(solstice, sky: sky)) }
        if let point=almanac.gegenschein(park: park, sky: sky) { items.append(gegenscheinItem(point, park: park)) }
        let sights=DeepSky.shared.sights(park: park, sky: sky)
        if !sights.isEmpty { items.append(deepSkyItem(sights, park: park)) }
        return items
    }
    /// "about 2° apart": whole degrees, never under one, since the planets are placed within about a degree.
    static func apart(_ degrees: Double) -> String { String(localized: "about \(max(1, Int(degrees.rounded())))° apart") }
    /// Where something stands, in the planets' words: high, low or simply in a direction.
    static func placed(altitude: Double, azimuth: Double) -> String {
        let direction=Compass.name(azimuth)
        return altitude>=30 ? String(localized: "high in the \(direction)") : altitude<15 ? String(localized: "low in the \(direction)") : String(localized: "in the \(direction)")
    }
    static func pairingItem(_ pairing: SkyAlmanac.Pairing, park: Park) -> Item {
        let title=pairing.other.map { String(localized: "\($0.name) and \(pairing.planet.name)") } ?? String(localized: "The Moon and \(pairing.planet.name)")
        let note=apart(pairing.separation), when=around(pairing.at, park: park)
        // The time is the figure; the sentence says where to look, so nothing is said twice.
        let place=placed(altitude: pairing.altitude, azimuth: pairing.azimuth)
        let detail=String(localized: "Closest then, \(place). A fine sight by eye or in binoculars.")
        return Item(id: "pairing-\(pairing.id)", kind: .pairing, title: title, note: note, value: when, detail: detail,
            spoken: "\(title), \(note). "+String(localized: "Closest around \(when), \(place). A fine sight by eye or in binoculars."), timed: true)
    }
    static func nearFullMoonItem(distance: Double) -> Item {
        let title=String(localized: "Full Moon at its nearest")
        let km=Measurement(value: (distance/1000).rounded()*1000, unit: UnitLength.kilometers)
            .formatted(.measurement(width: .abbreviated, usage: .road, numberFormatStyle: .number.precision(.fractionLength(0))))
        let detail=String(localized: "About \(km) away, so a little larger and brighter than most Full Moons. Its light hides all but the brightest stars.")
        return Item(id: "moon-near", kind: .moon, title: title, detail: detail, spoken: "\(title). \(detail)")
    }
    static func planetBestItem(_ night: SkyAlmanac.PlanetNight, day: Date, park: Park, sky: SkyConditions) -> Item {
        let window=SkyAlmanac.nightWindow(sky)
        // An evening planet is best soon after sunset; a morning one before dawn.
        let evening=night.best<window.start.addingTimeInterval(window.duration/2)
        let title=String(localized: "\(night.planet.name) at its best")
        var format=Date.FormatStyle.dateTime.month(.abbreviated).day()
        format.timeZone=park.timeZone
        let place=placed(altitude: night.bestAltitude, azimuth: night.bestAzimuth)
        let detail=evening ? String(localized: "Farthest from the Sun's glare around \(day.formatted(format)): the best evenings to find it, \(place) after sunset.")
            : String(localized: "Farthest from the Sun's glare around \(day.formatted(format)): the best mornings to find it, \(place) before sunrise.")
        let note=String(localized: "this week")
        return Item(id: "best-\(night.planet.rawValue)", kind: .planetBest, title: title, note: note, detail: detail, spoken: "\(title), \(note). \(detail)")
    }
    static func solsticeItem(_ solstice: SkyAlmanac.Solstice, sky: SkyConditions) -> Item {
        let title=solstice == .longestNight ? String(localized: "The longest night of the year") : String(localized: "The shortest night of the year")
        let hours=Duration.seconds(sky.darkHours*3600).formatted(.units(allowed: [.hours, .minutes], width: .wide))
        let detail=sky.darkHours>0 ? String(localized: "The solstice falls this night. True darkness lasts \(hours).")
            : String(localized: "The solstice falls this night. At this latitude there is no true darkness.")
        return Item(id: "solstice", kind: .season, title: title, detail: detail, spoken: "\(title). \(detail)")
    }
    static func gegenscheinItem(_ point: SkyAlmanac.Gegenschein, park: Park) -> Item {
        let title=String(localized: "Gegenschein"), when=around(point.at, park: park)
        let detail=String(localized: "A very faint, broad glow opposite the Sun, around \(when), \(Int(point.altitude.rounded()))° up in the \(Compass.name(point.azimuth)). Only from the darkest skies, with eyes fully adapted; easy to miss.")
        let note=String(localized: "very faint")
        return Item(id: "gegenschein", kind: .gegenschein, title: title, note: note, value: when, detail: detail,
            spoken: "\(title), \(note). \(detail)", timed: true)
    }

    /// Tonight's best-placed binocular sights (`DeepSky.sights`), one sentence each.
    static func deepSkyItem(_ sights: [DeepSky.Sight], park: Park) -> Item {
        let title=String(localized: "Through binoculars")
        let lines=sights.map { sight in
            let place=placed(altitude: sight.altitude, azimuth: sight.azimuth), when=around(sight.at, park: park)
            return sight.toTheEye ? String(localized: "\(sight.object.label): \(place) around \(when), visible to the eye too.")
                : String(localized: "\(sight.object.label): \(place) around \(when).")
        }
        let detail=Sentences.join(lines)
        return Item(id: "deepsky", kind: .deepSky, title: title, detail: detail, spoken: "\(title). \(detail)")
    }

    /// A time rounded to ten minutes on the park's clock, for moments that are only ever "around"
    /// (9:20 in Kathmandu, never 9:25, though its clock is 5:45 from UTC).
    static func around(_ date: Date, park: Park) -> String {
        let offset=TimeInterval(park.timeZone.secondsFromGMT(for:date))
        return park.time(Date(timeIntervalSince1970: ((date.timeIntervalSince1970+offset)/600).rounded()*600-offset))
    }
}

/// Eight compass points as words, for "up in the southeast".
nonisolated enum Compass {
    static func name(_ azimuth: Double) -> String {
        let index=Int(((azimuth.truncatingRemainder(dividingBy: 360)+360).truncatingRemainder(dividingBy: 360)/45).rounded())%8
        return [String(localized: "north"), String(localized: "northeast"), String(localized: "east"), String(localized: "southeast"),
                String(localized: "south"), String(localized: "southwest"), String(localized: "west"), String(localized: "northwest")][index]
    }
}
