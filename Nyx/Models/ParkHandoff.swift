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
    /// Accepts the place ids Nyx offers (a park's code, a world catalogue place's `wd:` id; `PlaceIDText`),
    /// in their stored form, and nothing else.
    init?(userInfo: [AnyHashable: Any]?) {
        guard let raw=userInfo?["park"] as? String, let id=PlaceIDText.validated(raw) else { return nil }
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

/// A place id from outside the app (a Handoff from another device), in its stored form, or nil for
/// anything else: a park's letters (`jotr`, any case), a Wikidata item (`wd:Q123456`) or a saved spot
/// (`pin:` and a UUID, stored lowercase). The colon may arrive percent-encoded. The same rule as links
/// (`DeepLink.placeID`), here because the Vision Pro app compiles this file and not the links.
nonisolated enum PlaceIDText {
    static func validated(_ raw: String) -> String? {
        let raw=raw.contains("%") ? (raw.removingPercentEncoding ?? raw) : raw
        let parts=raw.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        if parts.count==1 {
            guard (2...8).contains(raw.count), raw.allSatisfy({ $0.isLetter && $0.isASCII }) else { return nil }
            return raw.lowercased()
        }
        let rest=parts[1]
        switch parts[0].lowercased() {
        case "wd":
            let digits=rest.dropFirst()
            guard rest.first?.lowercased()=="q", (1...12).contains(digits.count), digits.first != "0", digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
            return "wd:Q\(digits)"
        case "pin":
            guard rest.count==36, let uuid=UUID(uuidString: String(rest)) else { return nil }
            return "pin:\(uuid.uuidString.lowercased())"
        default: return nil
        }
    }
}
