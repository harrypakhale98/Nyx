import Foundation

/// The one Handoff Nyx offers: a park on a night, from park detail on iPhone or iPad to Nyx on
/// another of the person's devices (iPhone, iPad, Apple Vision Pro). The system carries it
/// between devices signed in to the same Apple Account; Nyx has no server, and the payload is a
/// public park code and a date. Shared by the iPhone app and the Vision Pro app.
nonisolated struct ParkHandoff: Equatable, Sendable {
    static let type="com.harrypakhale.nyx.park"
    let parkID: String
    /// The night as the park's own calendar names it ("2026-10-09").
    let night: String?
    init(parkID: String, night: String?) { self.parkID=parkID; self.night=night }
    init(park: Park, night: Date) { self.init(parkID: park.id, night: Self.iso(night, in: park)) }
    init?(userInfo: [AnyHashable: Any]?) {
        guard let id=userInfo?["park"] as? String, !id.isEmpty, id.count<=8, id.allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }
        let night=userInfo?["night"] as? String
        self.init(parkID: id, night: night.flatMap { Self.components($0) == nil ? nil : $0 })
    }
    var userInfo: [String: String] {
        var info=["park": parkID]
        if let night { info["night"]=night }
        return info
    }
    /// The night's evening at that park (local noon, as `Park.evening`), or nil without a night.
    func evening(in park: Park) -> Date? {
        guard let night, let parts=Self.components(night) else { return nil }
        return park.calendar.date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day, hour: 12))
    }
    static func iso(_ evening: Date, in park: Park) -> String {
        let parts=park.calendar.dateComponents([.year, .month, .day], from: evening)
        return String(format: "%04d-%02d-%02d", parts.year ?? 2000, parts.month ?? 1, parts.day ?? 1)
    }
    private static func components(_ iso: String) -> (year: Int, month: Int, day: Int)? {
        let parts=iso.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count==3, parts[0].count==4, parts[1].count==2, parts[2].count==2,
              let y=Int(parts[0]), let m=Int(parts[1]), let d=Int(parts[2]), (1...12).contains(m), (1...31).contains(d) else { return nil }
        return (y, m, d)
    }
}
