import Foundation

nonisolated struct Park: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let apiCode: String
    let name: String
    let state: String
    let latitude: Double
    let longitude: Double
    let timeZoneID: String
    let hemisphere: String
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
    func matches(_ query: String) -> Bool {
        let needle = Self.folded(query)
        guard !needle.isEmpty else { return true }
        let aliases = Self.aliases[id] ?? []
        return ([name, state] + aliases).contains { Self.folded($0).contains(needle) }
    }
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
nonisolated enum ParkData {
    static func load(bundle: Bundle = .main) throws -> [Park] {
        guard let url = bundle.url(forResource: "parks", withExtension: "json") else { throw CocoaError(.fileNoSuchFile) }
        return try JSONDecoder().decode([Park].self, from: Data(contentsOf: url))
    }
}
