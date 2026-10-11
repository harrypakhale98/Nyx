import Foundation
import Synchronization

/// A place Nyx scores: today the 63 US national parks, later any catalogue place or a spot someone
/// saves (`Research/global-plan.md`, G1). `Park` stays as the name most code uses during the move.
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
    nonisolated enum Kind: String, Codable, Hashable, Sendable {
        case nationalPark, darkSkyPark, reserve, sanctuary, community, custom
    }
    /// The catalogue's place when nothing else chooses one: no saved park, no starting point, no night under way.
    static let defaultID = "jotr"
    /// South of the equator the Milky Way's core rides high and the Moon is seen turned over.
    var southern: Bool { latitude < 0 }
    nonisolated struct Access: Codable, Hashable, Sendable {
        let note: String
        /// False when the night sky here needs a boat or a plane from the road network you drove on.
        let road: Bool
        let sourceURL: String
    }
    /// The access note in the reader's language (catalog `access.<id>`, written by
    /// Scripts/apply_translations.py), falling back to the bundled English.
    var accessNote: String? { access.map { Bundle.main.localizedString(forKey: "access.\(id)", value: $0.note, table: nil) } }
    /// Whether a car reaches somewhere in the park to watch the sky. Parks without a note are.
    var drivable: Bool { access?.road ?? true }
    var shortName: String {
        name.replacingOccurrences(of: " National Park & Preserve", with: "")
            .replacingOccurrences(of: " National Park", with: "")
            .replacingOccurrences(of: " National and State Parks", with: "")
    }
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
        let terms = ([name, region] + (Self.aliases[id] ?? [])).map(Self.folded)
        Self.foldedTerms.withLock { $0[key] = terms }
        return terms
    }
    private static let foldedTerms = Mutex<[String: [String]]>([:])
    nonisolated static func folded(_ text: String) -> String {
        text.replacingOccurrences(of: "ʻ", with: "").replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "&", with: " and ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }
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
    func monthLabel(_ date: Date) -> String {
        var format = Date.FormatStyle.dateTime.month(.wide).year()
        format.timeZone = timeZone
        return date.formatted(format)
    }
    func isoDay(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 2000, parts.month ?? 1, parts.day ?? 1)
    }
    func distanceMeters(latitude lat: Double, longitude lon: Double) -> Double {
        Self.distance(latitude, longitude, lat, lon)
    }
    /// Great-circle distance in metres between two coordinates (degrees).
    static func distance(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let r = Double.pi / 180
        let a = pow(sin((lat1-lat2)*r/2),2) + cos(lat2*r)*cos(lat1*r)*pow(sin((lon1-lon2)*r/2),2)
        return 6_371_008.8 * 2 * atan2(sqrt(max(0,a)), sqrt(max(0,1-a)))
    }
}

nonisolated struct ViewingSpot: Codable, Hashable, Sendable {
    let name: String
    let latitude: Double
    let longitude: Double
    let sourceURL: String
    let note: String
    /// The note in the reader's language. Every spot ends with the same caveat, a catalog key; the one
    /// park-specific lead (Theodore Roosevelt's North Unit) has its own key. Anything else stays as bundled.
    var localizedNote: String {
        let caveat="Approximate coordinates. Check current access, opening hours and closures with a ranger. This is not a navigation guide."
        guard note.hasSuffix(caveat) else { return note }
        let local=String(localized:"Approximate coordinates. Check current access, opening hours and closures with a ranger. This is not a navigation guide.")
        let lead=String(note.dropLast(caveat.count)).trimmingCharacters(in:.whitespaces)
        if lead.isEmpty { return local }
        let northUnit="The North Unit keeps Central Time, one hour ahead of the times Nyx shows for this park."
        return (lead==northUnit ? String(localized:"The North Unit keeps Central Time, one hour ahead of the times Nyx shows for this park.") : lead)+" "+local
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
             bortleEstimate, description, sourceURL, sourceNote, viewingSpots, access, aboveInversion
        // Before G1 (1.4.1 and earlier): kept so a shared snapshot written by an older build still reads.
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
        try c.encodeIfPresent(aboveInversion, forKey: .aboveInversion)
        // Written for a release or two so a build from before G1, installed again, still reads the shared snapshot.
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
