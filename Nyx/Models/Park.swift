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
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
    func evening(_ date: Date) -> Date {
        calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
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
