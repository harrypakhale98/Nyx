import Foundation
import Synchronization

/// A place Nyx scores: today the 63 US national parks, later any catalogue place or a spot someone
/// saves. `Park` stays as the name most code uses during the move.
typealias Park = Place

nonisolated struct Place: Codable, Identifiable, Hashable, Sendable {
    /// Stable for the 63 parks (`jotr`, …) so saved parks, journal entries, intents, Spotlight and links
    /// survive. New kinds of place are namespaced: `wd:Q123456` (a Wikidata item), `pin:<uuid>` (a saved spot).
    let id: String
    /// The National Park Service's code where the NPS runs the place (alerts, programs, campgrounds); nil elsewhere.
    let nps: String?
    let name: String
    /// ISO 3166-1 alpha-2.
    let countryCode: String
    /// The first-level region as people write it there: a US state's postal code (several for a park across states, "CA,NV").
    let region: String
    let kind: Kind
    /// Hand-checked: viewing spots, access notes and the Bortle estimate come from a person, not a grid.
    let curated: Bool
    let latitude: Double
    let longitude: Double
    let timeZoneID: String
    let darkSkyDesignated: Bool
    let bortleEstimate: Int
    let description: String
    let sourceURL: String
    let sourceNote: String
    let viewingSpots: [ViewingSpot]
    /// How a visitor reaches the night sky, for parks a car cannot simply drive to (nps.gov "Getting there").
    var access: Access?
    /// True for a viewing summit above the trade-wind inversion (Haleakalā): low cloud there lies
    /// below the observer, so the score counts mid and high cloud when the layer forecast has them.
    var aboveInversion: Bool?
    /// The place's own website (a catalogue place's official site, Wikidata P856), for the line that
    /// asks people to check closures there. HTTPS only: a site offered only over plain HTTP is not
    /// linked. Nil for the curated parks, whose closures come from the NPS.
    var website: URL?
    /// The name and region as the bundle writes them (English), kept when `name` and `region` show a
    /// world catalogue place in the app's language (`PlaceNames`); nil when they are the same.
    /// Search reads both, so "Eifel National Park" still finds "Nationalpark Eifel".
    var englishName: String? = nil
    var englishRegion: String? = nil
    /// The short name in the app's language, set with a localized name: the English stripping in
    /// `shortName` never applies to it ("Nationalpark Eifel" shows "Eifel" in lists).
    var localShortName: String? = nil
    /// What a place is: a national park, one of DarkSky International's five designations, or a place
    /// of the person's own (`custom`). `urbanNightSky` (an Urban Night Sky Place) came with 2.0; a build
    /// before it reads the case as `custom`, as it reads any kind it does not know.
    nonisolated enum Kind: String, Codable, Hashable, Sendable {
        case nationalPark, darkSkyPark, reserve, sanctuary, community, urbanNightSky, custom
    }
    /// The place's DarkSky designation exactly as DarkSky International names it ("International Dark
    /// Sky Reserve", "Urban Night Sky Place"), or nil without one. A curated park keeps the kind
    /// `nationalPark` with the flag, and every designated US national park is an International Dark Sky Park.
    /// Shared by the app's pages, Siri, Shortcuts and Spotlight (`ParkEntity`), which the widgets compile too.
    var designationName: String? {
        switch kind {
        case .darkSkyPark: String(localized: "International Dark Sky Park")
        case .reserve: String(localized: "International Dark Sky Reserve")
        case .sanctuary: String(localized: "International Dark Sky Sanctuary")
        case .community: String(localized: "International Dark Sky Community")
        case .urbanNightSky: String(localized: "Urban Night Sky Place")
        case .nationalPark, .custom: darkSkyDesignated ? String(localized: "International Dark Sky Park") : nil
        }
    }
    /// The catalogue's place when nothing else chooses one: no saved park, no starting point, no night under way.
    static let defaultID = "jotr"
    /// A world catalogue place's id begins with this (`wd:Q123456`, a Wikidata item; `catalog.json`).
    static let catalogPrefix = "wd:"
    /// A saved spot's id begins with this (`pin:` and a UUID), on the iPhone, the widgets and the watch.
    static let spotPrefix = "pin:"
    /// True for a world catalogue place (`catalog.json`), as opposed to a curated park or a saved spot.
    /// The watch and the widgets bundle no catalogue, so such a place travels to them whole.
    var isCatalogPlace: Bool { id.hasPrefix(Self.catalogPrefix) }
    /// South of the equator the Milky Way's core rides high and the Moon is seen turned over.
    var southern: Bool { latitude < 0 }
    /// A park's states as one line under its name, on every device: "CA · NV". The iPhone's
    /// `regionLine` words a saved spot its own way.
    var statesLine: String { region.replacingOccurrences(of: ",", with: " · ") }
    /// The eyebrow over a park's name, on every device: its states and its Dark Sky status (data,
    /// not a slogan), "UT · International Dark Sky Park".
    var parkEyebrow: String { darkSkyDesignated ? String(localized: "\(statesLine) · International Dark Sky Park") : statesLine }
    nonisolated struct Access: Codable, Hashable, Sendable {
        let note: String
        /// False when the night sky here needs a boat or a plane from the road network you drove on.
        let road: Bool
        let sourceURL: String
    }
    /// The access note in the reader's language (catalog `access.<id>`), falling back to the
    /// bundled English.
    var accessNote: String? { access.map { Bundle.main.localizedString(forKey: "access.\(id)", value: $0.note, table: nil) } }
    /// Whether a car reaches somewhere in the park to watch the sky. Parks without a note are.
    var drivable: Bool { access?.road ?? true }
    var shortName: String { localShortName ?? Self.shortened(name) }
    /// An English name without its designation: "Etosha National Park" is "Etosha", and "National Park
    /// of American Samoa" is "American Samoa" on every device. A name that would end in a number keeps
    /// it ("Constitution 1857 National Park"): alone, the year reads as a figure.
    static func shortened(_ name: String) -> String {
        // The one U.S. park named designation first; abroad, "National Park of Upper Niger" alone would read as a region.
        if name == "National Park of American Samoa" { return "American Samoa" }
        let short=name
            .replacingOccurrences(of: " National Park & Preserve", with: "")
            .replacingOccurrences(of: " National Park", with: "")
            .replacingOccurrences(of: " National and State Parks", with: "")
        guard let last=short.split(separator: " ").last, last.allSatisfy(\.isNumber) else { return short }
        return name
    }
    /// The names search matches: as shown, and as bundled in English when the place is shown in another language.
    var searchNames: [String] { [name, shortName]+(englishName.map { [$0, Self.shortened($0)] } ?? []) }
    /// The regions search matches, likewise.
    var searchRegions: [String] { [region]+(englishRegion.map { [$0] } ?? []) }
    var timeZone: TimeZone { TimeZone(identifier: timeZoneID) ?? .gmt }
    /// Search should forgive spelling: "Hawaii Volcanoes" finds Hawaiʻi, "Wrangell St Elias" finds the en dash.
    func matches(_ query: String) -> Bool { matches(folded: Self.folded(query)) }
    /// With the query already `folded`: the list folds it once for all 63 parks.
    func matches(folded needle: String) -> Bool {
        guard !needle.isEmpty else { return true }
        return searchTerms.contains { $0.contains(needle) }
    }
    /// The name, region and aliases, folded once per park and kept.
    private var searchTerms: [String] {
        let key = id+"|"+name+"|"+region
        if let kept = Self.foldedTerms.withLock({ $0[key] }) { return kept }
        let terms = ([name, region] + [englishName, englishName.map(Self.shortened), englishRegion].compactMap { $0 } + (Self.aliases[id] ?? [])).map(Self.folded)
        Self.foldedTerms.withLock { $0[key] = terms }
        return terms
    }
    private static let foldedTerms = Mutex<[String: [String]]>([:])
    /// Marks that join the parts of one name, dropped rather than read as a space so a name is found
    /// typed with or without them: "サン・ディエゴ" as "サンディエゴ", "ラ＝ロシェル", Catalan "l·l".
    nonisolated static let joiners: Set<Unicode.Scalar> = ["・", "･", "゠", "＝", "·"]
    nonisolated static func folded(_ text: String) -> String {
        transliterated(String(String.UnicodeScalarView(text.unicodeScalars.filter { !joiners.contains($0) }))
            .replacingOccurrences(of: "ʻ", with: "").replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "&", with: " and "))
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }
    /// What diacritic folding leaves alone, spelled as it is typed on any keyboard, for search on both
    /// sides (the index and the query): Latin letters with no accent to drop ("Tromsø" as "Tromso",
    /// "Łódź" as "Lodz", "Đà Lạt" as "Da Lat", "Þingvellir" as "Thingvellir"); full-width letters and
    /// digits as plain ones; half-width katakana as full width, a voiced mark joined to its letter
    /// (ｶﾞ as ガ); and hiragana as katakana, so "よせ" finds "ヨセミテ". Plain ASCII returns at once.
    nonisolated static func transliterated(_ text: String) -> String {
        guard text.utf8.contains(where: { $0 >= 0x80 }) else { return text }
        var out = String.UnicodeScalarView()
        for scalar in text.precomposedStringWithCompatibilityMapping.unicodeScalars {
            if let latin = latinASCII[scalar] { out.append(contentsOf: latin.unicodeScalars) }
            else if (0x3041...0x3096).contains(scalar.value) || scalar.value == 0x309D || scalar.value == 0x309E,
                    let katakana = Unicode.Scalar(scalar.value + 0x60) { out.append(katakana) }
            else { out.append(scalar) }
        }
        return String(out)
    }
    /// Latin letters that are letters of their own rather than a letter and an accent (ß already
    /// folds to "ss" with case).
    private nonisolated static let latinASCII: [Unicode.Scalar: String] = [
        "ø": "o", "Ø": "O", "ł": "l", "Ł": "L", "đ": "d", "Đ": "D", "ð": "d", "Ð": "D", "þ": "th", "Þ": "Th", "æ": "ae", "Æ": "Ae",
        "œ": "oe", "Œ": "Oe", "ı": "i", "ħ": "h", "Ħ": "H", "ŧ": "t", "Ŧ": "T", "ŋ": "ng", "Ŋ": "Ng", "ĸ": "k", "ſ": "s", "ƒ": "f",
        "ŀ": "l", "Ŀ": "L", "ɨ": "i", "ƚ": "l", "ƀ": "b", "ǥ": "g", "Ǥ": "G",
    ]
    static let aliases: [String: [String]] = [
        "grsm": ["Smokies", "Smoky Mountains"], "jeff": ["St. Louis Arch", "Gateway Arch"], "deva": ["Death Valley"],
        "wrst": ["Wrangell Saint Elias"], "havo": ["Volcanoes", "Kilauea"], "hale": ["Haleakala"], "npsa": ["American Samoa"],
        "viis": ["Virgin Islands", "St. John"], "thro": ["Teddy Roosevelt", "TR"], "grte": ["Tetons"], "romo": ["Rocky Mountain", "RMNP"],
        "blca": ["Black Canyon"], "kica": ["Kings Canyon", "Sequoia and Kings Canyon"], "sequ": ["Sequoia and Kings Canyon"],
        "redw": ["Redwoods"], "neri": ["New River"], "cuva": ["Cuyahoga"], "drto": ["Fort Jefferson"], "jotr": ["Joshua Tree", "JT"],
    ]
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        // Weeks begin where the person's region begins them (Monday in much of the world).
        calendar.locale = .current
        calendar.firstWeekday = Calendar.current.firstWeekday
        return calendar
    }
    func evening(_ date: Date) -> Date {
        calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
    }
    /// The night someone standing in the park at `now` is in. After midnight it is still last night,
    /// until the Sun rises; from sunrise on, "tonight" is the coming evening. Without a sunrise
    /// (polar night) the switch happens at local noon.
    func currentNight(at now: Date) -> Date {
        let today = evening(now)
        guard now < today else { return today }
        let morning = calendar.component(.hour, from: now) >= 3
        if morning, AstronomyEngine().solarAltitude(at: now, park: self) > -0.833 { return today }
        return self.date(today, addingDays: -1)
    }
    /// The moments after `start` and before `end` at which `currentNight(at:)` moves on to the
    /// next night: a second past the sunrise that ends it (3 AM when the Sun is already up by
    /// then), else local noon. A widget or complication redraws at each, so "tonight" turns over
    /// at the park's sunrise rather than at the next hourly entry.
    func nightTurnovers(from start: Date, to end: Date) -> [Date] {
        var moments: [Date] = [], now = start
        while moments.count < 4 {
            let night = currentNight(at: now), noon = date(night, addingDays: 1)
            // The rule's own moments, earliest first: the sunrise, 3 AM (a sunrise before it, or a Sun
            // that never sets), local noon (a Sun that never rises).
            let sunrise = AstronomyEngine().conditions(for: self, on: night).sunrise?.addingTimeInterval(1)
            let candidates = ([sunrise, calendar.date(bySettingHour: 3, minute: 0, second: 0, of: noon), noon].compactMap { $0 }).sorted()
            let next = candidates.first { $0 > now && currentNight(at: $0) != night } ?? noon
            guard next < end else { break }
            moments.append(next)
            now = next
        }
        return moments
    }
    /// The latest night that has begun at `now`: tonight once the Sun has set, otherwise last
    /// night. A journal entry records a night already seen, so one written at 1 AM or over
    /// breakfast belongs to the evening before. Without a sunset (midnight sun), 6 PM stands in.
    func lastNightBegun(at now: Date) -> Date {
        let today = evening(now)
        let dusk = AstronomyEngine().conditions(for: self, on: today).sunset ?? today.addingTimeInterval(6*3600)
        return now >= dusk ? today : self.date(today, addingDays: -1)
    }
    func date(_ date: Date, addingDays days: Int) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date
    }
    func time(_ date: Date?) -> String {
        guard let date else { return String(localized: "No crossing") }
        var format = Date.FormatStyle.dateTime.hour().minute()
        format.timeZone = timeZone
        return date.formatted(format)
    }
    func weekdayInitial(_ date: Date) -> String {
        var format = Date.FormatStyle.dateTime.weekday(.narrow)
        format.timeZone = timeZone
        return date.formatted(format)
    }
    func dayLabel(_ date: Date) -> String {
        var format = Date.FormatStyle.dateTime.weekday(.abbreviated).month(.abbreviated).day()
        format.timeZone = timeZone
        return date.formatted(format)
    }
    func dateLabel(_ date: Date) -> String {
        var format = Date.FormatStyle.dateTime.month(.wide).day().year()
        format.timeZone = timeZone
        return date.formatted(format)
    }
    /// NPS event days arrive as "yyyy-MM-dd"; show them as park-local dates.
    func programDate(_ day: String) -> String {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)) else { return day }
        var format = Date.FormatStyle.dateTime.weekday(.wide).month(.wide).day()
        format.timeZone = timeZone
        return date.formatted(format)
    }
    /// "Pacific Time" rather than "America/Los_Angeles".
    var timeZoneName: String { timeZone.localizedName(for: .generic, locale: .current) ?? timeZoneID }
    func timestamp(_ date: Date) -> String {
        var format = Date.FormatStyle.dateTime.month(.abbreviated).day().hour().minute()
        format.timeZone = timeZone
        return date.formatted(format)
    }
    /// "November 2026", a month grid's title: Gregorian like the grid, whatever calendar the device uses.
    func monthLabel(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(calendar: calendar, timeZone: timeZone).month(.wide).year())
    }
    /// "November": the month a night's usual clouds and month grids count in (Gregorian, in the
    /// place's zone), in the reader's language, whatever calendar the device uses.
    func monthName(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(calendar: calendar, timeZone: timeZone).month(.wide))
    }
    func isoDay(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 2000, parts.month ?? 1, parts.day ?? 1)
    }
    func distanceMeters(latitude lat: Double, longitude lon: Double) -> Double {
        Self.distance(latitude, longitude, lat, lon)
    }
    /// The mean radius of Earth (IUGG), in metres: every distance and map in Nyx uses it.
    static let earthRadius = 6_371_008.8
    /// Great-circle distance in metres between two coordinates (degrees).
    static func distance(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let r = Double.pi / 180
        let a = pow(sin((lat1-lat2)*r/2),2) + cos(lat2*r)*cos(lat1*r)*pow(sin((lon1-lon2)*r/2),2)
        return earthRadius * 2 * atan2(sqrt(max(0,a)), sqrt(max(0,1-a)))
    }
}

nonisolated struct ViewingSpot: Codable, Hashable, Sendable {
    let name: String
    let latitude: Double
    let longitude: Double
    let sourceURL: String
    let note: String
    /// The note in the reader's language. Every spot ends with the same caveat, a catalog key; the
    /// park-specific leads (Theodore Roosevelt's North Unit, Great Basin's Baker site outside the park)
    /// have their own keys. Anything else stays as bundled.
    var localizedNote: String {
        let caveat="Approximate coordinates. Check current access, opening hours and closures with a ranger. This is not a navigation guide."
        guard note.hasSuffix(caveat) else { return note }
        let local=String(localized:"Approximate coordinates. Check current access, opening hours and closures with a ranger. This is not a navigation guide.")
        let lead=String(note.dropLast(caveat.count)).trimmingCharacters(in:.whitespaces)
        if lead.isEmpty { return local }
        let localLead: String = switch lead {
        case "The North Unit keeps Central Time, one hour ahead of the times Nyx shows for this park.":
            String(localized:"The North Unit keeps Central Time, one hour ahead of the times Nyx shows for this park.")
        case "Outside the park, on Bureau of Land Management land north of Baker.":
            String(localized:"Outside the park, on Bureau of Land Management land north of Baker.")
        default: lead
        }
        return Sentences.join([localLead, local])
    }
}
nonisolated struct ParkAlert: Codable, Identifiable, Sendable, Equatable {
    let id: String
    let title: String
    let description: String
    let category: String
}
nonisolated struct RangerProgram: Codable, Identifiable, Sendable, Equatable {
    let id: String
    let title: String
    let date: String
    let description: String
    /// NPS's own wording of the time ("7:00 PM – 8:30 PM"), park-local; nil in older caches.
    var time: String?=nil
    /// Where it meets, as NPS lists it.
    var location: String?=nil
    /// "7:00 PM – 8:30 PM", or the start alone; nil when NPS gives neither.
    static func timeRange(start: String?, end: String?) -> String? {
        let start=start?.trimmingCharacters(in: .whitespacesAndNewlines), end=end?.trimmingCharacters(in: .whitespacesAndNewlines)
        switch (start?.isEmpty == false ? start : nil, end?.isEmpty == false ? end : nil) {
        case (let a?, let b?): return a==b ? a : "\(a) – \(b)"
        case (let a?, nil): return a
        default: return nil
        }
    }
    static func place(_ text: String?) -> String? {
        guard let text=text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
}
nonisolated extension Place {
    fileprivate enum CodingKeys: String, CodingKey {
        case id, nps, name, countryCode, region, kind, curated, latitude, longitude, timeZoneID, darkSkyDesignated,
             bortleEstimate, description, sourceURL, sourceNote, viewingSpots, access, aboveInversion, website
        case englishName, englishRegion, localShortName
        // 1.4.1 and earlier: kept so a shared snapshot written by an older build still reads.
        case apiCode, state, hemisphere
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        nps = try c.decodeIfPresent(String.self, forKey: .nps) ?? c.decodeIfPresent(String.self, forKey: .apiCode)
        name = try c.decode(String.self, forKey: .name)
        countryCode = try c.decodeIfPresent(String.self, forKey: .countryCode) ?? "US"
        region = try c.decodeIfPresent(String.self, forKey: .region) ?? c.decode(String.self, forKey: .state)
        // A kind added by a later build reads as a place without a kind of its own, never as an unreadable park.
        kind = c.contains(.kind) ? ((try? c.decode(Kind.self, forKey: .kind)) ?? .custom) : .nationalPark
        curated = try c.decodeIfPresent(Bool.self, forKey: .curated) ?? true
        latitude = try c.decode(Double.self, forKey: .latitude)
        longitude = try c.decode(Double.self, forKey: .longitude)
        timeZoneID = try c.decode(String.self, forKey: .timeZoneID)
        darkSkyDesignated = try c.decode(Bool.self, forKey: .darkSkyDesignated)
        bortleEstimate = try c.decode(Int.self, forKey: .bortleEstimate)
        description = try c.decode(String.self, forKey: .description)
        sourceURL = try c.decode(String.self, forKey: .sourceURL)
        sourceNote = try c.decode(String.self, forKey: .sourceNote)
        viewingSpots = try c.decode([ViewingSpot].self, forKey: .viewingSpots)
        access = try c.decodeIfPresent(Access.self, forKey: .access)
        aboveInversion = try c.decodeIfPresent(Bool.self, forKey: .aboveInversion)
        website = Self.website((try? c.decodeIfPresent(String.self, forKey: .website)) ?? nil)
        englishName = try c.decodeIfPresent(String.self, forKey: .englishName)
        englishRegion = try c.decodeIfPresent(String.self, forKey: .englishRegion)
        localShortName = try c.decodeIfPresent(String.self, forKey: .localShortName)
    }
    /// A website as Nyx links it: an absolute HTTPS URL with a host, else nil (a plain-HTTP site is not linked).
    static func website(_ text: String?) -> URL? {
        guard let text, let url = URL(string: text), url.scheme?.lowercased() == "https", let host = url.host(), !host.isEmpty else { return nil }
        return url
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encodeIfPresent(nps, forKey: .nps); try c.encode(name, forKey: .name)
        try c.encode(countryCode, forKey: .countryCode); try c.encode(region, forKey: .region); try c.encode(kind, forKey: .kind)
        try c.encode(curated, forKey: .curated); try c.encode(latitude, forKey: .latitude); try c.encode(longitude, forKey: .longitude)
        try c.encode(timeZoneID, forKey: .timeZoneID); try c.encode(darkSkyDesignated, forKey: .darkSkyDesignated)
        try c.encode(bortleEstimate, forKey: .bortleEstimate); try c.encode(description, forKey: .description)
        try c.encode(sourceURL, forKey: .sourceURL); try c.encode(sourceNote, forKey: .sourceNote)
        try c.encode(viewingSpots, forKey: .viewingSpots); try c.encodeIfPresent(access, forKey: .access)
        try c.encodeIfPresent(aboveInversion, forKey: .aboveInversion); try c.encodeIfPresent(website?.absoluteString, forKey: .website)
        try c.encodeIfPresent(englishName, forKey: .englishName); try c.encodeIfPresent(englishRegion, forKey: .englishRegion)
        try c.encodeIfPresent(localShortName, forKey: .localShortName)
        // Written for a release or two so a build from before 2.0, installed again, still reads the shared snapshot.
        try c.encodeIfPresent(nps, forKey: .apiCode); try c.encode(region, forKey: .state)
        try c.encode(southern ? "south" : "north", forKey: .hemisphere)
    }
}
nonisolated enum ParkData {
    /// The main bundle's parks, decoded once per process: widgets, intents and views all ask, and
    /// the bundled file never changes while Nyx runs. Another bundle is read each time; a failed
    /// read is never kept, so the next call tries again.
    static func load(bundle: Bundle = .main) throws -> [Park] {
        let main = bundle === Bundle.main
        if main, let kept = bundled.withLock({ $0 }) { return kept }
        guard let url = bundle.url(forResource: "parks", withExtension: "json") else { throw CocoaError(.fileNoSuchFile) }
        let parks = try JSONDecoder().decode([Park].self, from: Data(contentsOf: url))
        if main { bundled.withLock { $0 = parks } }
        return parks
    }
    private static let bundled = Mutex<[Park]?>(nil)
}
/// The world catalogue (`catalog.json`): national parks worldwide and the certified dark-sky
/// places, from Wikidata, never repeating a curated park. Only the iPhone app bundles it; elsewhere
/// (the widgets, the watch, Vision Pro) it is absent and a catalogue place arrives whole instead.
nonisolated enum CatalogData {
    /// Decoded once per process for the main bundle (about 1.5 MB of JSON: call it off the main
    /// thread, as `PlanModel.prepareCatalog` does). A failed read is never kept. Places are named in
    /// the app's language (`PlaceNames`, read with the catalogue); `language` asks for another ("en"
    /// for the bundled English), read each time, never kept.
    static func load(bundle: Bundle = .main, language: String? = nil) throws -> [Park] {
        let main = bundle === Bundle.main && language == nil
        if main, let kept = bundled.withLock({ $0 }) { return kept }
        guard let url = bundle.url(forResource: "catalog", withExtension: "json") else { throw CocoaError(.fileNoSuchFile) }
        let places = try JSONDecoder().decode([Park].self, from: Data(contentsOf: url))
        let names = main ? PlaceNames.current : PlaceNames.load(language: language ?? PlaceNames.appLanguage, bundle: bundle)
        let shown = names.isEmpty ? places : places.map { $0.named(in: names) }
        if main { bundled.withLock { $0 = $0 ?? shown } }
        return shown
    }
    private static let bundled = Mutex<[Park]?>(nil)
}

// MARK: Place names in the app's language

/// Names of world catalogue places, their regions and the starting towns in one language, from
/// Wikidata's labels (CC0), bundled as `names-<lang>.json` (only
/// the names that differ from the English). The language is the app's own (`appLanguage`), so a
/// per-app language choice in Settings is followed. English, or a language without a file, has none.
/// The curated US parks are never renamed. Only the iPhone app bundles the files.
nonisolated struct PlaceNames: Sendable {
    /// A name and the part of it that lists show ("Nationalpark Eifel", "Eifel").
    nonisolated struct Name: Hashable, Sendable {
        let name: String
        let short: String
    }
    let language: String
    /// Catalogue place id (`wd:Q…`) to its name.
    let places: [String: Name]
    /// "CC|English region" to the region's name: "DE|Bavaria" is "Bayern".
    let regions: [String: String]
    /// How many starting towns the file was built against; its towns apply only to a list that long.
    let townCount: Int
    /// The towns' names, unparsed until `townNames` (see the script for the format).
    private let townText: String

    static let empty = PlaceNames(language: "en", places: [:], regions: [:], townCount: 0, townText: "")
    var isEmpty: Bool { places.isEmpty && regions.isEmpty && townText.isEmpty }
    /// The languages with a names file.
    static let languages: Set<String> = ["es", "de", "fr", "ja"]
    /// The language code of the app's own localization: "es" for es-419, "ja", or "en".
    static var appLanguage: String { code(Bundle.main.preferredLocalizations.first) }
    /// A place and the larger area it lies in, as the app's language writes them: "Ontario, Canada",
    /// "鹿児島県、日本" (Japanese joins with the ideographic comma).
    static func joined(_ place: String, _ area: String, language: String = appLanguage) -> String {
        language == "ja" ? "\(place)、\(area)" : "\(place), \(area)"
    }
    static func code(_ identifier: String?) -> String {
        guard let identifier, let first = identifier.split(whereSeparator: { $0 == "-" || $0 == "_" }).first else { return "en" }
        return first.lowercased()
    }
    /// The main bundle's names in the app's language, read once, on first use: off the main thread,
    /// with the catalogue or the starting places.
    static let current: PlaceNames = load(language: appLanguage)

    init(language: String, places: [String: Name], regions: [String: String], townCount: Int, townText: String) {
        self.language = language; self.places = places; self.regions = regions; self.townCount = townCount; self.townText = townText
    }
    /// A language's names from `bundle`; empty for English, for a language without a file, or for a file that does not read.
    static func load(language: String, bundle: Bundle = .main) -> PlaceNames {
        let language = code(language)
        guard languages.contains(language), let url = bundle.url(forResource: "names-\(language)", withExtension: "json"),
              let data = try? Data(contentsOf: url), let file = try? JSONDecoder().decode(File.self, from: data) else { return .empty }
        return PlaceNames(language: language, places: file.places.mapValues(Self.name(braced:)), regions: file.regions,
                          townCount: file.towns.count, townText: file.towns.names)
    }
    private struct File: Decodable {
        struct Towns: Decodable { let count: Int; let names: String }
        let places: [String: String]
        let regions: [String: String]
        let towns: Towns
    }
    /// "Parc national des {Cévennes}": the name without the braces, and the braced part as its short name.
    static func name(braced text: String) -> Name {
        guard let open = text.firstIndex(of: "{"), let close = text[open...].firstIndex(of: "}") else { return Name(name: text, short: text) }
        let short = String(text[text.index(after: open)..<close])
        let name = String(text[..<open]) + short + String(text[text.index(after: close)...])
        return Name(name: name, short: short.isEmpty ? name : short)
    }
    /// A region's name, nil where it has none or the region is a US state (written as postal codes).
    func region(countryCode: String, region: String) -> String? {
        guard !regions.isEmpty, !region.isEmpty, countryCode.uppercased() != "US" else { return nil }
        return regions[countryCode+"|"+region]
    }
    /// One entry per starting town, in the bundled order: the town's name where this language has its
    /// own, else nil. All nil when the file was built against another list (`townCount`).
    func townNames(count: Int) -> [String?] {
        var out = [String?](repeating: nil, count: count)
        guard count == townCount, !townText.isEmpty else { return out }
        var index = -1
        for line in townText.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let tab = line.firstIndex(of: "\t"), let gap = Int(line[..<tab]), gap >= 0 else { continue }
            index += gap+1
            guard index < count else { break }
            out[index] = String(line[line.index(after: tab)...])
        }
        return out
    }
}
nonisolated extension Place {
    /// This place as `names` names it: a world catalogue place in that language, its English name and
    /// region kept for search (`englishName`, `englishRegion`). Anything else, or a place without a
    /// name there, unchanged.
    func named(in names: PlaceNames) -> Place {
        guard isCatalogPlace, englishName == nil, englishRegion == nil else { return self }
        let local = names.places[id], area = names.region(countryCode: countryCode, region: region)
        guard local != nil || area != nil else { return self }
        return Place(id: id, nps: nps, name: local?.name ?? name, countryCode: countryCode, region: area ?? region, kind: kind, curated: curated,
                     latitude: latitude, longitude: longitude, timeZoneID: timeZoneID, darkSkyDesignated: darkSkyDesignated,
                     bortleEstimate: bortleEstimate, description: description, sourceURL: sourceURL, sourceNote: sourceNote,
                     viewingSpots: viewingSpots, access: access, aboveInversion: aboveInversion, website: website,
                     englishName: local == nil ? nil : name, englishRegion: area == nil ? nil : region, localShortName: local?.short ?? localShortName)
    }
}

/// A night's day as a link carries it ("YYYY-MM-DD"), read the same way on every device: a real
/// Gregorian day between 1900 and 2200 (the iPhone's link rule), else nil, which opens tonight.
/// Never month 13, February 30 or a year no night is planned in.
nonisolated enum LinkDay {
    static func components(_ text: String) -> DateComponents? {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1900...2200).contains(year), (1...12).contains(month), (1...31).contains(day) else { return nil }
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = .gmt
        let components = DateComponents(year: year, month: month, day: day)
        guard let noon = gregorian.date(from: DateComponents(year: year, month: month, day: day, hour: 12)),
              gregorian.dateComponents([.year, .month, .day], from: noon) == components else { return nil }
        return components
    }
}
/// A value that decodes to nil instead of failing the whole document.
nonisolated struct Lenient<T:Decodable>:Decodable {
    let value:T?
    init(from decoder:any Decoder) throws { value=try? T(from:decoder) }
}

/// The United States and its territories (Puerto Rico, the U.S. Virgin Islands, Guam, American Samoa,
/// the Northern Mariana Islands, the minor outlying islands): home to the national parks Nyx was made
/// for, so a device set to any of them is never told the parks are abroad.
nonisolated enum HomeRegion {
    static func isUS(_ region: String?) -> Bool { ["US", "PR", "VI", "GU", "AS", "MP", "UM"].contains(region?.uppercased() ?? "") }
}
