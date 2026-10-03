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
    private static let aliases: [String: [String]] = [
        "grsm": ["Smokies", "Smoky Mountains"], "jeff": ["St. Louis Arch", "Gateway Arch"], "deva": ["Death Valley"],
        "wrst": ["Wrangell Saint Elias"], "havo": ["Volcanoes", "Kilauea"], "hale": ["Haleakala"], "npsa": ["American Samoa"],
        "viis": ["Virgin Islands", "St. John"], "thro": ["Teddy Roosevelt", "TR"], "grte": ["Tetons"], "romo": ["Rocky Mountain", "RMNP"],
        "blca": ["Black Canyon"], "kica": ["Kings Canyon", "Sequoia and Kings Canyon"], "sequ": ["Sequoia and Kings Canyon"],
        "redw": ["Redwoods"], "neri": ["New River"], "cuva": ["Cuyahoga"], "drto": ["Fort Jefferson"], "jotr": ["Joshua Tree", "JT"],
    ]
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
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
    func date(_ date: Date, addingDays days: Int) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date
    }
    func time(_ date: Date?) -> String {
        guard let date else { return String(localized: "No crossing") }
        var format = Date.FormatStyle.dateTime.hour().minute()
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
        let r = Double.pi / 180
        let a = pow(sin((latitude-lat)*r/2),2) + cos(lat*r)*cos(latitude*r)*pow(sin((longitude-lon)*r/2),2)
        return 6_371_008.8 * 2 * atan2(sqrt(max(0,a)), sqrt(max(0,1-a)))
    }
}

nonisolated struct ViewingSpot: Codable, Hashable, Sendable {
    let name: String
    let latitude: Double
    let longitude: Double
    let sourceURL: String
    let note: String
}
nonisolated struct ParkAlert: Codable, Identifiable, Sendable {
    let id: String
    let title: String
    let description: String
    let category: String
}
nonisolated struct RangerProgram: Codable, Identifiable, Sendable {
    let id: String
    let title: String
    let date: String
    let description: String
}
nonisolated enum ParkData {
    static func load(bundle: Bundle = .main) throws -> [Park] {
        guard let url = bundle.url(forResource: "parks", withExtension: "json") else { throw CocoaError(.fileNoSuchFile) }
        return try JSONDecoder().decode([Park].self, from: Data(contentsOf: url))
    }
}
