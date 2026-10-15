import Foundation

/// What the Park Service says about reaching a park's dark skies at night and through the year,
/// bundled as `night-access.json`: night gate and road closures, seasonal road closures that cut off
/// a viewing spot, and reservations that bear on arriving after dark, each with the nps.gov page and
/// the exact sentence it rests on (retrieved 2026-10-15, every sentence re-checked against its page).
/// Usual patterns, not live status: closures in force tonight come from the park alerts.
nonisolated struct NightAccess: Sendable {
    nonisolated struct Rule: Codable, Sendable, Equatable, Identifiable {
        var id: String { title }
        /// seasonalRoad, nightClosure, reservation.
        let kind: String
        let title: String
        /// Exact viewing-spot names it affects; empty or absent for the park as a whole.
        var spots: [String]?=nil
        /// Months (1–12) a road is usually closed, or a rule applies; absent when all year or unstated.
        var months: [Int]?=nil
        let note: String
        let sourceURL: String
        let evidence: String
        /// Usually in effect in this month (1–12): a listed month, or any month when none is listed.
        func applies(inMonth month: Int) -> Bool { months.map { $0.contains(month) } ?? true }
        var source: URL? {
            guard let url = URL(string: sourceURL), url.scheme == "https", url.host?.hasSuffix("nps.gov") == true else { return nil }
            return url
        }
    }
    let parks: [String: [Rule]]
    static let shared: NightAccess = load() ?? NightAccess(parks: [:])
    static func load(bundle: Bundle = .main) -> NightAccess? {
        guard let url = bundle.url(forResource: "night-access", withExtension: "json"), let data = try? Data(contentsOf: url) else { return nil }
        struct File: Decodable { let parks: [String: [Rule]] }
        return (try? JSONDecoder().decode(File.self, from: data)).map { NightAccess(parks: $0.parks) }
    }
    func rules(_ park: String) -> [Rule] { parks[park] ?? [] }
    /// The rules that name this viewing spot.
    func rules(_ park: String, spot: String) -> [Rule] { rules(park).filter { $0.spots?.contains(spot) == true } }
}

/// Recreation visits counted by the National Park Service, month by month, averaged over 2021–2025
/// (`nps-visits.json`, NPS Visitor Use Statistics, CC0), for a plain sense of busy and quiet months.
/// Counting methods changed during those years at a few parks, so the pattern is more reliable than
/// the totals, and only the pattern is shown.
nonisolated struct ParkVisits: Sendable {
    nonisolated struct Months: Codable, Sendable, Equatable {
        let visits: [Int]
        var overnight: [Int]?=nil
        /// Busy, quiet or in between for a month (1–12): the three busiest months by visits, the three quietest, the rest.
        enum Level: Sendable, Equatable { case busy, quiet, between }
        func level(month: Int) -> Level {
            guard visits.count == 12, (1...12).contains(month) else { return .between }
            let ranked = visits.indices.sorted { (visits[$0], $0) > (visits[$1], $1) }
            let place = ranked.firstIndex(of: month-1) ?? 6
            return place < 3 ? .busy : place >= 9 ? .quiet : .between
        }
        /// The busiest month (1–12), and the three quietest in calendar order.
        var busiest: Int { (visits.indices.max { visits[$0] < visits[$1] } ?? 0)+1 }
        var quietest: [Int] { visits.indices.sorted { (visits[$0], $0) < (visits[$1], $1) }.prefix(3).map { $0+1 }.sorted() }
    }
    let parks: [String: Months]
    static let shared: ParkVisits = load() ?? ParkVisits(parks: [:])
    static func load(bundle: Bundle = .main) -> ParkVisits? {
        guard let url = bundle.url(forResource: "nps-visits", withExtension: "json"), let data = try? Data(contentsOf: url) else { return nil }
        struct File: Decodable { let parks: [String: Months] }
        return (try? JSONDecoder().decode(File.self, from: data)).map { ParkVisits(parks: $0.parks) }
    }
}
