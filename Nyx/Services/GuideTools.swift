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
    var details: [String: ForecastDetail] = [:]
    /// Cities and towns a question may start from (`places.json`).
    var places: [StartingPlace] = StartingPlaces.all
    private var planner: NightPlanner { NightPlanner(forecasts: forecasts, details: details) }

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
        let basis=Self.basis(night)
        let dark=night.sky.darkHours>0 ? String(localized: "\(String(format: "%.1f", night.sky.darkHours)) hours of true darkness") : String(localized: "no true darkness")
        return String(localized: "\(park.shortName); \(park.dayLabel(night.id)) (\(park.isoDay(night.id))); score \(night.score.value)/100 \(night.score.band.label); \(basis); \(night.sky.moon.name) \(Int((night.sky.moon.illumination*100).rounded()))% lit; \(dark)")+access(park)
    }
    /// What a record's clouds rest on, in the app's words.
    static func basis(_ night: Night) -> String {
        switch night.basis {
        case .forecast: return String(localized: "cloud forecast included, \(Int((night.cloudCover ?? 0).rounded()))% cloud")
        case .blended(_, let lead): return String(localized: "early look: a \(Int((night.cloudCover ?? 0).rounded()))% cloud forecast \(max(1, Int(lead.rounded()))) days out, eased toward usual clouds")
        case .usual: return String(localized: "no cloud forecast yet; scored with the park's usual clouds for the month")+(night.typicalClouds.map { "; "+String(localized: "typically: \($0)") } ?? "")
        }
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
    /// Where "near" is measured from: a park by its exact name, then a US city or town from the
    /// bundled Census list ("Denver", "Denver, CO"), then any park the app's search finds.
    func origin(named name: String) -> (label: String, latitude: Double, longitude: Double)? {
        let folded=Park.folded(name)
        if let park=parks.first(where: { Park.folded($0.shortName)==folded || Park.folded($0.name)==folded }) { return (park.shortName, park.latitude, park.longitude) }
        if let place=StartingPlaces.named(name, in: places) { return (place.label, place.latitude, place.longitude) }
        return park(named: name).map { ($0.shortName, $0.latitude, $0.longitude) }
    }
    /// Parks within a straight-line radius of a starting park or place, best tonight first. Never a drive time.
    func parksNear(park name: String, radiusMiles: Int, limit: Int = 6) -> [String] {
        guard let origin=origin(named: name) else { return [String(localized: "No national park or US city matched \"\(name.prefix(60))\". Nyx knows the 63 US national parks and about 1,000 US cities and towns.")] }
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
        guard !ranked.isEmpty else { return [String(localized: "No national parks within \(Int(radius)) miles of \(origin.label), straight-line.")] }
        return ranked.map { park, miles in
            let night=tonight[park.id]
            let basis=night.map(Self.basis) ?? ""
            return String(localized: "\(park.shortName), \(park.state); \(Int(miles.rounded())) miles straight-line from \(origin.label); tonight \(night?.score.value ?? 0)/100 \(night?.score.band.label ?? "")")+(basis.isEmpty ? "" : "; "+basis)+access(park)
        }
    }
}

/// Numbers every record the model sees, injected or looked up, so a citation can be checked, and
/// keeps the lookups the tools made in plain words, so Ask Nyx can show its work as it happens.
/// Made with a session (its tools hold it) and reset for each question, so a session prepared
/// ahead of the question answers from the records and the lookup of the moment it is asked.
nonisolated final class GuideLedger: Sendable {
    private struct State {
        var firstID: Int
        var records: [String]=[]
        var lookups: [String]=[]
        var lookup: NightLookup?
        var onAdd: (@Sendable ([String]) -> Void)?
    }
    private let state: Mutex<State>
    init(firstID: Int, lookup: NightLookup?=nil) { state=Mutex(State(firstID: firstID, lookup: lookup)) }
    var firstID: Int { state.withLock { $0.firstID } }
    /// What the tools look up in: the parks, forecasts and clock of the question being answered.
    var lookup: NightLookup? { state.withLock { $0.lookup } }
    /// A new question: records numbered from `firstID`, no lookups yet, and `onAdd` told of each
    /// lookup (with the whole list so far) as a tool makes it.
    func reset(firstID: Int, lookup: NightLookup?, onAdd: (@Sendable ([String]) -> Void)?=nil) {
        state.withLock { $0=State(firstID: firstID, lookup: lookup, onAdd: onAdd) }
    }
    /// Adds records and returns them as "ID n: …" lines for the model. `lookup` is what was looked
    /// up, in plain words ("Best nights · Arches · 30 nights from Oct 9"), for the person.
    func add(_ lines: [String], lookup: String?=nil) -> String {
        let (numbered, lookups, onAdd)=state.withLock { state -> (String, [String], (@Sendable ([String]) -> Void)?) in
            let numbered=lines.map { line in state.records.append(line); return "ID \(state.firstID+state.records.count-1): \(line)" }.joined(separator: "\n")
            if let lookup { state.lookups.append(lookup) }
            return (numbered, state.lookups, lookup == nil ? nil : state.onAdd)
        }
        onAdd?(lookups)
        return numbered
    }
    var all: [String] { state.withLock { $0.records } }
    var lookups: [String] { state.withLock { $0.lookups } }
    var ids: Set<Int> { state.withLock { Set($0.firstID..<($0.firstID+$0.records.count)) } }
}

nonisolated extension NightLookup {
    /// The day a tool was asked about, as the person reads it: "Oct 9", or "tonight" for "tonight",
    /// empty or unreadable text (the tools then use tonight too).
    func lookupDay(_ text: String, at park: Park?) -> String? {
        guard let day=TripDay(iso: text) else { return nil }
        let zone=park?.timeZone ?? .current
        var calendar=Calendar(identifier: .gregorian)
        calendar.timeZone=zone
        guard let date=calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12)) else { return nil }
        var style=Date.FormatStyle().month(.abbreviated).day()
        style.timeZone=zone
        return date.formatted(style)
    }
    /// A park as the person knows it, or the words the model used when none matched.
    private func lookupName(_ name: String) -> String {
        park(named: name)?.shortName ?? String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
    }
    /// "Best nights · Arches · 30 nights from Oct 9", from the tool's own arguments.
    func bestNightsLookup(park name: String, from first: String, nights: Int) -> String {
        let count=min(30, max(1, nights)), place=lookupName(name)
        guard let day=lookupDay(first, at: park(named: name)) else { return String(localized: "Best nights · \(place) · \(count) nights from tonight") }
        return String(localized: "Best nights · \(place) · \(count) nights from \(day)")
    }
    /// "What's up · Arches · Oct 9".
    func whatsUpLookup(park name: String, on day: String) -> String {
        let place=lookupName(name)
        guard let date=lookupDay(day, at: park(named: name)) else { return String(localized: "What's up · \(place) · tonight") }
        return String(localized: "What's up · \(place) · \(date)")
    }
    /// "Parks near · Joshua Tree · within 200 mi", in the device's units, straight-line as the tool is.
    func parksNearLookup(park name: String, radiusMiles: Int) -> String {
        let place=origin(named: name)?.label ?? lookupName(name)
        let radius=Measurement(value: Double(min(1500, max(10, radiusMiles))), unit: UnitLength.miles)
            .formatted(.measurement(width: .abbreviated, usage: .road, numberFormatStyle: .number.precision(.fractionLength(0))))
        return String(localized: "Parks near · \(place) · within \(radius)")
    }
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
    let ledger: GuideLedger
    @concurrent func call(arguments: Arguments) async throws -> String {
        guard let lookup=ledger.lookup else { return "" }
        return ledger.add(lookup.bestNights(park: arguments.park, from: arguments.firstNight, nights: arguments.nights),
                          lookup: lookup.bestNightsLookup(park: arguments.park, from: arguments.firstNight, nights: arguments.nights))
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
    let ledger: GuideLedger
    @concurrent func call(arguments: Arguments) async throws -> String {
        guard let lookup=ledger.lookup else { return "" }
        return ledger.add(lookup.whatsUp(park: arguments.park, on: arguments.night), lookup: lookup.whatsUpLookup(park: arguments.park, on: arguments.night))
    }
}
nonisolated struct ParksNearTool: Tool {
    let name="parksNear"
    let description="National parks within a straight-line radius of a starting park or US city, with tonight's score. Distances are straight-line miles, never drive times."
    @Generable struct Arguments {
        @Guide(description: "The starting national park, or a US city or town such as Denver")
        var park: String
        @Guide(description: "Straight-line radius in miles", .range(10...1500))
        var radiusMiles: Int
    }
    let ledger: GuideLedger
    @concurrent func call(arguments: Arguments) async throws -> String {
        guard let lookup=ledger.lookup else { return "" }
        return ledger.add(lookup.parksNear(park: arguments.park, radiusMiles: arguments.radiusMiles),
                          lookup: lookup.parksNearLookup(park: arguments.park, radiusMiles: arguments.radiusMiles))
    }
}
