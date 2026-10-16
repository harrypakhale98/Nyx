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
    /// The places beyond the curated parks that a question may name: the saved spots and the world
    /// catalogue (national parks abroad and certified dark-sky places). Empty until the catalogue is read.
    var others: [Park] = []
    /// Places with a closure in the last park update: their lines carry Nyx's fixed closure flag
    /// (`OnDeviceGuide.closureRecord`), never the Park Service's words.
    var closed: Set<String> = []
    /// Where "tonight" is judged from: the app's `today`, so Ask Nyx's tonight is the Tonight tab's even
    /// in the minutes after sunrise before it moves on. `now` stays the clock a forecast's age is read by.
    var today: Date?
    /// NOAA's aurora forecast as the app holds it, so Ask Nyx's What's up names aurora as the park page does.
    var aurora: AuroraOutlook?
    /// The bundled light map, for the nearest dark sky when what is in reach is bright (`DarkerSky`).
    var grid: SkyGrid = .shared
    /// Where a dark area may lie: the bundled land, 5 km inland (`DarkerSky.offer`).
    var onLand: @Sendable (Double, Double) -> Bool = { WorldLand.bundled?.inland(latitude: $0, longitude: $1) ?? false }
    private var tonightClock: Date { today ?? now }
    private var planner: NightPlanner { NightPlanner(forecasts: forecasts, details: details) }

    /// A place by name: a curated park's exact short name, a spot's or catalogue place's exact name, then
    /// the app's own park search (aliases included), then a spot or catalogue place whose name begins
    /// with, or contains, the words asked. Never a place found only by its region or country.
    func park(named name: String) -> Park? {
        let folded=Park.folded(name)
        // An empty name matches every park in search; here it must match none.
        guard !folded.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        func exact(_ park: Park) -> Bool { Park.folded(park.shortName)==folded || Park.folded(park.name)==folded }
        if let park=parks.first(where: exact) { return park }
        // The cached search terms narrow the world first, so only a few names are folded per question.
        let named=others.filter { $0.matches(folded: folded) }
        if let place=named.first(where: exact) { return place }
        if let park=parks.first(where: { $0.matches(folded: folded) }) { return park }
        return named.first { Park.folded($0.shortName).hasPrefix(folded) || Park.folded($0.name).hasPrefix(folded) }
            ?? named.first { Park.folded($0.name).contains(folded) }
    }
    /// Where a place is, for a "parks near" record: a curated park's state as before ("Arches, UT"),
    /// a place abroad's region and country in the reader's language ("Eifel, North Rhine-Westphalia, Germany").
    static func locality(_ park: Park) -> String {
        guard park.isCatalogPlace, !park.countryCode.isEmpty else { return park.region }
        let country=Locale.current.localizedString(forRegionCode: park.countryCode) ?? park.countryCode
        return park.region.isEmpty || park.region==country ? country : "\(park.region), \(country)"
    }
    /// "2026-11-14" in the park's time zone, or tonight for "tonight", empty or unreadable text.
    func night(_ text: String, at park: Park) -> Date {
        day(text, at: park)?.evening(in: park) ?? park.currentNight(at: tonightClock)
    }
    /// A real calendar day within a year of tonight; nil for anything else (February 30, month 13,
    /// year 0, 9999), which the tools read as tonight rather than computing a night no one asked for.
    func day(_ text: String, at park: Park) -> TripDay? {
        guard let day=TripDay(iso: text) else { return nil }
        let tonight=TripDay(park.currentNight(at: tonightClock), calendar: park.calendar)
        return abs(tonight.days(to: day))<=366 ? day : nil
    }
    /// One line per night, worded like the app: score, band, what the score rests on, the Moon.
    func describe(_ night: Night) -> String {
        let park=night.park
        let basis=Self.basis(night)
        // In the reader's own decimal mark: the line is shown with the answer, and the grounding
        // check reads digits whatever separates them ("7,5" and "7.5" are both 7 and 5).
        let hours=night.sky.darkHours.formatted(.number.precision(.fractionLength(1)))
        let dark=night.sky.darkHours>0 ? String(localized: "\(hours) hours of true darkness") : String(localized: "no true darkness")
        let line=String(localized: "\(park.shortName); \(park.dayLabel(night.id)) (\(park.isoDay(night.id))); score \(night.score.value)/100 \(night.score.band.label); \(basis); \(night.sky.moon.name) \(Int((night.sky.moon.illumination*100).rounded()))% lit; \(dark)")+access(park)
        return closed.contains(park.id) ? Phrase.sentences([line, OnDeviceGuide.closureRecord]) : line
    }
    /// What a record's clouds rest on, in the app's words.
    static func basis(_ night: Night) -> String {
        switch night.basis {
        case .forecast: return String(localized: "cloud forecast included, \(Int((night.cloudCover ?? 0).rounded()))% cloud")+smoke(night)
        case .blended(_, let lead): return String(localized: "early look: a \(Int((night.cloudCover ?? 0).rounded()))% cloud forecast \(max(1, Int(lead.rounded()))) days out, eased toward usual clouds")+smoke(night)
        case .usual:
            // "Not yet" beyond the forecast's reach, "unavailable" within it, and never "usual clouds"
            // where none are known, as every surface says it (`Night.basisLine`).
            let words = switch (night.beyondForecast, night.usualCloud == nil) {
            case (true, false): String(localized: "no cloud forecast yet; scored with the park's usual clouds for the month")
            case (false, false): String(localized: "cloud forecast unavailable; scored with the park's usual clouds for the month")
            case (true, true): String(localized: "no cloud forecast yet; scored on the Moon and darkness only")
            case (false, true): String(localized: "cloud forecast unavailable; scored on the Moon and darkness only")
            }
            return words+(night.typicalClouds.map { "; "+String(localized: "typically: \($0)") } ?? "")+smoke(night)
        }
    }
    /// "; Smoke or haze limits this night to 59." when smoke or haze holds the score down.
    private static func smoke(_ night: Night) -> String { night.smokeSentence().map { "; "+$0 } ?? "" }
    /// The access note, so the model never recommends a ferry-only park as a drive.
    func access(_ park: Park) -> String {
        park.accessNote.map { "; "+String(localized: "getting there: \($0)") } ?? ""
    }
    func bestNights(park name: String, from first: String, nights: Int, limit: Int = 5) -> [String] {
        guard let park=park(named: name) else { return [Self.noMatch(name)] }
        // A named day is that day's night (never one already past); anything else is tonight.
        // Tonight named by its date goes the tonight way, so just after sunrise it is still the Tonight tab's night.
        let tonight=TripDay(park.currentNight(at: tonightClock), calendar: park.calendar)
        let ranked=day(first, at: park).flatMap { $0 == tonight ? nil : $0 }.map { planner.bestNights([park], day: DateComponents(year: $0.year, month: $0.month, day: $0.day), count: min(30, max(1, nights)), now: now, limit: limit) }
            ?? planner.bestNights([park], from: tonightClock, count: min(30, max(1, nights)), now: now, limit: limit)
        return ranked.map(describe)
    }
    func whatsUp(park name: String, on day: String) -> [String] {
        guard let park=park(named: name) else { return [Self.noMatch(name)] }
        let night=planner.night(park, on: night(day, at: park), now: now)
        let sky=WhatsUp(park: park, sky: night.sky, isTonight: night.id==park.currentNight(at: tonightClock), table: table,
                        aurora: AuroraForecast.item(aurora, park: park, sky: night.sky, now: now))
        return [describe(night)]+sky.items.prefix(4).map { String(localized: "\(park.shortName); \(park.dayLabel(night.id)); \($0.spoken)") }
    }
    /// Where "near" is measured from: a park by its exact name, then a city or town from the
    /// bundled list ("Denver", "Denver, CO"), then any park the app's search finds.
    func origin(named name: String) -> (label: String, latitude: Double, longitude: Double)? {
        let folded=Park.folded(name)
        if let park=parks.first(where: { Park.folded($0.shortName)==folded || Park.folded($0.name)==folded }) { return (park.shortName, park.latitude, park.longitude) }
        if let place=StartingPlaces.named(name, in: places) { return (place.label, place.latitude, place.longitude) }
        return park(named: name).map { ($0.shortName, $0.latitude, $0.longitude) }
    }
    /// Parks and places within a straight-line radius of a starting park or town, darkest tonight first,
    /// as on Tonight: a closure never moves a place down the list, its line says so. Never a drive time. The radius and distances are in `system`'s unit: miles, or kilometres.
    func parksNear(park name: String, radius asked: Int, system: SearchRadius.System = .init(), limit: Int = 6) -> [String] {
        guard let origin=origin(named: name) else { return [String(localized: "No park, dark-sky place or town matched \"\(name.prefix(60))\".")] }
        let radius=Self.toolRadius(asked, system)
        func inReach(_ places: [Park]) -> [(Park, Double)] {
            places.compactMap { park -> (Park, Double)? in
                let distance=Park.distance(origin.latitude, origin.longitude, park.latitude, park.longitude)/system.meters
                return distance<=radius ? (park, distance) : nil
            }
        }
        // Tonight's rule (`TonightReach`): from a US starting point with only US places in range, the
        // national parks; otherwise every place in range, the darkest skies weighed first when there are many.
        var near=inReach(parks)
        if !others.isEmpty {
            let curated=Set(parks.map(\.id))
            let all=near+inReach(others).filter { !curated.contains($0.0.id) }
            let distances=Dictionary(all.map { ($0.0.id, $0.1) }, uniquingKeysWith: { a, _ in a })
            let chosen=TonightReach.candidates(parks: near.map(\.0), places: all.map(\.0), originInUS: USOutline.contains(latitude: origin.latitude, longitude: origin.longitude))
            let pool=chosen.count>TonightReach.shortlistSize ? TonightReach.shortlist(chosen, latitude: origin.latitude, longitude: origin.longitude) : chosen
            near=pool.compactMap { park in distances[park.id].map { (park, $0) } }
        }
        let tonight=Dictionary(near.map { ($0.0.id, planner.night($0.0, on: $0.0.currentNight(at: tonightClock), now: now)) }, uniquingKeysWith: { a, _ in a })
        // Darkest first, by the sky alone as on Tonight: a closed park keeps its place and its record says it is closed.
        let ranked=near.sorted { a, b in
            guard let x=tonight[a.0.id], let y=tonight[b.0.id] else { return a.1<b.1 }
            return NightPlanner.better(x, y)
        }.prefix(limit)
        // The nearest dark sky on the light map when what is in reach is bright or absent (`DarkerSky`,
        // Tonight's rule and words), as one more record: no name, no score, said as an estimate.
        let darker=DarkerSky.offer(from: (origin.latitude, origin.longitude), radiusMeters: radius*system.meters,
                                   darkestInReach: near.map(\.0.bortleEstimate).min(), system: system, grid: grid, onLand: onLand).map { DarkerSky.record($0, from: origin.label, system: system) }
        guard !ranked.isEmpty else {
            return [system == .miles ? String(localized: "No parks or dark-sky places within \(Int(radius)) miles of \(origin.label), straight-line.")
                                     : String(localized: "No parks or dark-sky places within \(Int(radius)) km of \(origin.label), straight-line.")]+[darker].compactMap { $0 }
        }
        return ranked.map { park, distance in
            let night=tonight[park.id], basis=night.map(Self.basis) ?? "", whole=Int(distance.rounded()), score=night?.score.value ?? 0, band=night?.score.band.label ?? ""
            let region=Self.locality(park)
            let line=system == .miles ? String(localized: "\(park.shortName), \(region); \(whole) miles straight-line from \(origin.label); tonight \(score)/100 \(band)")
                                      : String(localized: "\(park.shortName), \(region); \(whole) km straight-line from \(origin.label); tonight \(score)/100 \(band)")
            let record=line+(basis.isEmpty ? "" : "; "+basis)+access(park)
            return closed.contains(park.id) ? Phrase.sentences([record, OnDeviceGuide.closureRecord]) : record
        }+[darker].compactMap { $0 }
    }
    /// The radius a tool may ask for, kept to 10–1,500 miles or 10–2,500 km.
    static func toolRadius(_ asked: Int, _ system: SearchRadius.System) -> Double { Double(min(system == .miles ? 1500 : 2500, max(10, asked))) }
    /// What a tool says when no place has the name asked for.
    static func noMatch(_ name: String) -> String { String(localized: "No park or dark-sky place matched \"\(name.prefix(60))\".") }
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
    /// "Parks near · Joshua Tree · within 200 mi", in the tool's unit, straight-line as the tool is.
    func parksNearLookup(park name: String, radius asked: Int, system: SearchRadius.System = .init()) -> String {
        let place=origin(named: name)?.label ?? lookupName(name)
        return String(localized: "Parks near · \(place) · within \(SearchRadius.format(Self.toolRadius(asked, system), system))")
    }
}

nonisolated struct BestNightsTool: Tool {
    let name="bestNights"
    let description="Ranks one place's coming nights by Nyx's darkness score, best first. Returns computed records with IDs to cite."
    @Generable struct Arguments {
        @Guide(description: "A park or dark-sky place by name, for example Joshua Tree")
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
    let description="What is in one place's sky on one night: the score, the Milky Way core, planets, a meteor shower or an eclipse. Returns computed records with IDs."
    @Generable struct Arguments {
        @Guide(description: "A park or dark-sky place by name, for example Big Bend")
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
    /// Miles where the person's roads are signed in miles, kilometres elsewhere (`SearchRadius`).
    var description: String {
        "Parks and dark-sky places within a straight-line radius of a starting place or town, with tonight's score. The radius and distances are straight-line \(system == .miles ? "miles" : "kilometers"), never drive times."
    }
    @Generable struct Arguments {
        @Guide(description: "The starting park or place, or a city or town such as Denver")
        var park: String
        @Guide(description: "Straight-line radius, in the unit the tool's description names", .range(10...2500))
        var radius: Int
    }
    let ledger: GuideLedger
    var system=SearchRadius.System()
    @concurrent func call(arguments: Arguments) async throws -> String {
        guard let lookup=ledger.lookup else { return "" }
        return ledger.add(lookup.parksNear(park: arguments.park, radius: arguments.radius, system: system),
                          lookup: lookup.parksNearLookup(park: arguments.park, radius: arguments.radius, system: system))
    }
}
