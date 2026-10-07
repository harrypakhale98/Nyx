import Foundation
import FoundationModels
import Synchronization

/// What Ask Nyx's tools can look up: already-computed nights, sky events and nearby parks, from
/// the engine and the cached forecasts. The model chooses what to ask for; it never computes a
/// score, a moonrise or a distance itself, and every answer it gives cites these records' IDs.
nonisolated struct NightLookup: Sendable {
    let parks: [Park]
    let forecasts: [String: Forecast]
    let now: Date
    var table: SkyEvents = .shared
    private var planner: NightPlanner { NightPlanner(forecasts: forecasts) }

    /// A park by name: an exact short name first, then the app's own search (aliases included).
    func park(named name: String) -> Park? {
        let folded=Park.folded(name)
        // An empty name matches every park in search; here it must match none.
        guard !folded.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return parks.first { Park.folded($0.shortName)==folded || Park.folded($0.name)==folded } ?? parks.first { $0.matches(name) }
    }
    /// "2026-11-14" in the park's time zone, or tonight for "tonight", empty or unreadable text.
    func night(_ text: String, at park: Park) -> Date {
        let tonight=park.currentNight(at: now)
        let parts=text.split(separator: "-").compactMap { Int($0) }
        guard parts.count==3, let day=park.calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)) else { return tonight }
        return park.evening(day)
    }
    /// One line per night, worded like the app: score, band, what the score rests on, the Moon.
    func describe(_ night: Night) -> String {
        let park=night.park
        let basis=night.score.hasForecast ? String(localized: "cloud forecast included, \(Int((night.cloudCover ?? 0).rounded()))% cloud") : String(localized: "moon and darkness only, clouds not yet forecast")
        let dark=night.sky.darkHours>0 ? String(localized: "\(String(format: "%.1f", night.sky.darkHours)) hours of true darkness") : String(localized: "no true darkness")
        return String(localized: "\(park.shortName); \(park.dayLabel(night.id)) (\(park.isoDay(night.id))); score \(night.score.value)/100 \(night.score.band.label); \(basis); \(night.sky.moon.name) \(Int((night.sky.moon.illumination*100).rounded()))% lit; \(dark)")+access(park)
    }
    /// The access note, so the model never recommends a ferry-only park as a drive.
    func access(_ park: Park) -> String {
        park.accessNote.map { "; "+String(localized: "getting there: \($0)") } ?? ""
    }
    func bestNights(park name: String, from first: String, nights: Int, limit: Int = 5) -> [String] {
        guard let park=park(named: name) else { return [String(localized: "No national park matched \"\(name.prefix(60))\". Nyx knows the 63 US national parks.")] }
        // A named day is that day's night (never one already past); anything else is tonight.
        let ranked=TripDay(iso: first).map { planner.bestNights([park], day: DateComponents(year: $0.year, month: $0.month, day: $0.day), count: min(30, max(1, nights)), now: now, limit: limit) }
            ?? planner.bestNights([park], from: now, count: min(30, max(1, nights)), now: now, limit: limit)
        return ranked.map(describe)
    }
    func whatsUp(park name: String, on day: String) -> [String] {
        guard let park=park(named: name) else { return [String(localized: "No national park matched \"\(name.prefix(60))\". Nyx knows the 63 US national parks.")] }
        let night=planner.night(park, on: night(day, at: park), now: now)
        let sky=WhatsUp(park: park, sky: night.sky, isTonight: night.id==park.currentNight(at: now), table: table)
        return [describe(night)]+sky.items.prefix(4).map { String(localized: "\(park.shortName); \(park.dayLabel(night.id)); \($0.spoken)") }
    }
    /// Parks within a straight-line radius of a starting park, best tonight first. Never a drive time.
    func parksNear(park name: String, radiusMiles: Int, limit: Int = 6) -> [String] {
        guard let origin=park(named: name) else { return [String(localized: "No national park matched \"\(name.prefix(60))\". Nyx knows the 63 US national parks.")] }
        let radius=Double(min(1500, max(10, radiusMiles)))
        let near=parks.compactMap { park -> (Park, Double)? in
            let miles=Park.distance(origin.latitude, origin.longitude, park.latitude, park.longitude)/1609.344
            return miles<=radius ? (park, miles) : nil
        }
        let tonight=Dictionary(near.map { ($0.0.id, planner.night($0.0, on: $0.0.currentNight(at: now), now: now)) }, uniquingKeysWith: { a, _ in a })
        let ranked=near.sorted { a, b in
            guard let x=tonight[a.0.id], let y=tonight[b.0.id] else { return a.1<b.1 }
            return NightPlanner.better(x, y)
        }.prefix(limit)
        guard !ranked.isEmpty else { return [String(localized: "No national parks within \(Int(radius)) miles of \(origin.shortName), straight-line.")] }
        return ranked.map { park, miles in
            let night=tonight[park.id]
            let basis=night.map { $0.score.hasForecast ? String(localized: "cloud forecast included") : String(localized: "moon and darkness only, clouds not yet forecast") } ?? ""
            return String(localized: "\(park.shortName), \(park.state); \(Int(miles.rounded())) miles straight-line from \(origin.shortName); tonight \(night?.score.value ?? 0)/100 \(night?.score.band.label ?? "")")+(basis.isEmpty ? "" : "; "+basis)+access(park)
        }
    }
}

/// Numbers every record the model sees, injected or looked up, so a citation can be checked.
nonisolated final class GuideLedger: Sendable {
    private let records: Mutex<[String]>
    let firstID: Int
    init(firstID: Int) { self.firstID=firstID; records=Mutex([]) }
    /// Adds records and returns them as "ID n: …" lines for the model.
    func add(_ lines: [String]) -> String {
        records.withLock { list in
            lines.map { line in list.append(line); return "ID \(firstID+list.count-1): \(line)" }.joined(separator: "\n")
        }
    }
    var all: [String] { records.withLock { $0 } }
    var ids: Set<Int> { Set(firstID..<(firstID+all.count)) }
}

nonisolated struct BestNightsTool: Tool {
    let name="bestNights"
    let description="Ranks one national park's coming nights by Nyx's darkness score, best first. Returns computed records with IDs to cite."
    @Generable struct Arguments {
        @Guide(description: "A US national park, for example Joshua Tree")
        var park: String
        @Guide(description: "First night as YYYY-MM-DD, or tonight")
        var firstNight: String
        @Guide(description: "How many nights to compare, 1 to 30", .range(1...30))
        var nights: Int
    }
    let lookup: NightLookup
    let ledger: GuideLedger
    @concurrent func call(arguments: Arguments) async throws -> String {
        ledger.add(lookup.bestNights(park: arguments.park, from: arguments.firstNight, nights: arguments.nights))
    }
}
nonisolated struct WhatsUpTool: Tool {
    let name="whatsUp"
    let description="What is in one park's sky on one night: the score, the Milky Way core, planets, a meteor shower or an eclipse. Returns computed records with IDs."
    @Generable struct Arguments {
        @Guide(description: "A US national park, for example Big Bend")
        var park: String
        @Guide(description: "The night as YYYY-MM-DD, or tonight")
        var night: String
    }
    let lookup: NightLookup
    let ledger: GuideLedger
    @concurrent func call(arguments: Arguments) async throws -> String {
        ledger.add(lookup.whatsUp(park: arguments.park, on: arguments.night))
    }
}
nonisolated struct ParksNearTool: Tool {
    let name="parksNear"
    let description="National parks within a straight-line radius of a starting park, with tonight's score. Distances are straight-line miles, never drive times."
    @Generable struct Arguments {
        @Guide(description: "The starting national park")
        var park: String
        @Guide(description: "Straight-line radius in miles", .range(10...1500))
        var radiusMiles: Int
    }
    let lookup: NightLookup
    let ledger: GuideLedger
    @concurrent func call(arguments: Arguments) async throws -> String {
        ledger.add(lookup.parksNear(park: arguments.park, radiusMiles: arguments.radiusMiles))
    }
}
