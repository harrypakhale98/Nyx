import Foundation

/// How cloudy each park's nights usually are, month by month: ten years (2015–2024) of ERA5
/// reanalysis over each night's true-dark hours (`Scripts/build_cloud_climate.py`, Copernicus
/// Climate Change Service, CC BY 4.0). Where no forecast reaches, a night is scored with its park's
/// usual cloud for the month, and a forecast more than three days ahead is eased toward it
/// (`CloudBasis`), so a night nobody can forecast yet is neither assumed clear nor ignored. It is
/// never shown as a forecast: such nights say "No cloud forecast yet" or "Early look". A place
/// the file does not hold reads the world grid's usual clouds instead (`SkyGrid`, G2).
nonisolated struct CloudClimate: Decodable, Sendable {
    struct Months: Codable, Sendable, Equatable {
        /// Mean cloud over the dark hours, percent, January first.
        let cloud: [Int?]
        /// Share of nights under 30% cloud ("mostly clear"), percent.
        let clear: [Int?]
        /// One month of the twelve, or nil when either value is missing.
        func month(_ month: Int) -> (cloud: Double, clear: Double)? {
            guard cloud.count == 12, clear.count == 12, (1...12).contains(month), let mean = cloud[month-1], let share = clear[month-1] else { return nil }
            return (Double(mean), Double(share))
        }
    }
    /// One park's month.
    struct Typical: Sendable, Equatable {
        let month: Int
        let cloud: Double
        let clear: Double
        /// True when the month comes from the world grid (`SkyGrid`), whose share of clear nights is
        /// estimated from the month's cloud rather than counted night by night: its sentences say so.
        var estimated = false
        /// "About 8 in 10 November nights here are mostly clear."
        func sentence(monthName: String) -> String {
            let tenths = Int((clear/10).rounded())
            switch tenths {
            case ...0: return estimated ? String(localized: "\(monthName) nights here are rarely clear, by an estimate.") : String(localized: "\(monthName) nights here are rarely clear.")
            case 10...: return estimated ? String(localized: "Nearly every \(monthName) night here is mostly clear, by an estimate.") : String(localized: "Nearly every \(monthName) night here is mostly clear.")
            default: return String(localized: "About \(tenths) in 10 \(monthName) nights here are mostly clear.")
            }
        }
    }
    private enum CodingKeys: String, CodingKey { case parks }
    let parks: [String: Months]
    /// The world grid, for a place the per-park file does not hold (any place that is not one of
    /// the 63 parks). nil keeps to the file alone: `load` and every hand-built climate, so a test's
    /// empty climate still means no usual clouds at all.
    var grid: SkyGrid? = nil
    /// Usual clouds handed over by the iPhone for places the per-park file does not hold (followed
    /// world places and saved spots), read from its world grid: the widgets and Apple Watch bundle no
    /// grid tiles, so without these they would score those places with no usual clouds at all.
    /// Keyed by place id; the values are the grid's own, so the score matches the iPhone's.
    var carried: [String: Months] = [:]

    /// The bundled per-park file, with the world grid behind it.
    static let shared: CloudClimate = {
        var climate = load() ?? CloudClimate(parks: [:])
        climate.grid = .shared
        return climate
    }()
    static func load(_ bundle: Bundle = .main) -> CloudClimate? {
        guard let url = bundle.url(forResource: "cloud-climate", withExtension: "json"), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CloudClimate.self, from: data)
    }
    /// The month of the night that begins on `evening`, at `park`. A park in the file keeps its
    /// own ten years of ERA5 at its coordinates (the 63 parks never take the grid's value);
    /// anywhere else, the grid's cell, marked `estimated`.
    /// Anywhere else, the months the iPhone carried for the place (off the phone), marked `estimated`
    /// as the grid's are.
    func typical(_ park: Park, on evening: Date) -> Typical? {
        let month = park.calendar.component(.month, from: evening)
        if let entry = parks[park.id] {
            guard let value = entry.month(month) else { return nil }
            return Typical(month: month, cloud: value.cloud, clear: value.clear)
        }
        if let value = carried[park.id]?.month(month) { return Typical(month: month, cloud: value.cloud, clear: value.clear, estimated: true) }
        guard let cell = grid?.cloudNight(latitude: park.latitude, longitude: park.longitude, month: month) else { return nil }
        return Typical(month: month, cloud: cell.mean, clear: cell.clear, estimated: true)
    }
    /// This climate with months handed over from the iPhone (`carried`); the per-park file still comes first.
    func carrying(_ months: [String: Months]?) -> CloudClimate {
        guard let months, !months.isEmpty else { return self }
        var climate = self
        climate.carried.merge(months) { _, new in new }
        return climate
    }
    /// The twelve months to hand over with a place the per-park file does not hold, from the world
    /// grid (the iPhone's): nil for one of the 63 parks (bundled everywhere), without the grid's
    /// tiles (off the phone), or where the grid has no month at all (at sea).
    func months(for park: Park) -> Months? {
        guard parks[park.id] == nil, let grid else { return nil }
        let cells = (1...12).map { grid.cloudNight(latitude: park.latitude, longitude: park.longitude, month: $0) }
        guard cells.contains(where: { $0 != nil }) else { return nil }
        return Months(cloud: cells.map { $0.map { Int($0.mean.rounded()) } }, clear: cells.map { $0.map { Int($0.clear.rounded()) } })
    }
    /// The months to hand over for these places, by id (`months(for:)`); empty on the watch and in widgets.
    func carriedMonths(for places: [Park]) -> [String: Months] {
        var months: [String: Months] = [:]
        for place in places where months[place.id] == nil { if let value = self.months(for: place) { months[place.id] = value } }
        return months
    }
    /// The plain line beside a night that has no cloud forecast; nil without data.
    func sentence(_ park: Park, on evening: Date) -> String? {
        guard let typical = typical(park, on: evening) else { return nil }
        var format = Date.FormatStyle().month(.wide)
        format.timeZone = park.timeZone
        return typical.sentence(monthName: evening.formatted(format))
    }
}

extension DarknessScore {
    /// The band with what its clouds rest on, wherever a score stands without room for a caption
    /// (a widget, the Live Activity, a spoken summary): "Excellent", "Excellent, early look",
    /// "Excellent, usual clouds". One place, so the basis never drops off a surface again.
    nonisolated var bandWithBasis: String {
        switch basis {
        case .forecast: band.label
        case .blended: String(localized: "\(band.label), early look")
        case .usual: String(localized: "\(band.label), usual clouds")
        }
    }
    /// "94 · Excellent, early look": the score and its band with basis, for one short line.
    nonisolated var withBand: String { String(localized: "\(value) · \(bandWithBasis)") }
}

extension Night {
    /// What every ranking of nights compares: the score itself, which already counts the park's
    /// usual clouds where no forecast reaches. Ties are broken by `NightPlanner.better`.
    nonisolated var rankScore: Int { score.value }
    /// "About 8 in 10 November nights here are mostly clear." for a night without a forecast.
    nonisolated var typicalClouds: String? { basis == .usual ? CloudClimate.shared.sentence(park, on: id) : nil }
    /// A caption followed by the month's typical clouds, for a night without a forecast.
    nonisolated func withTypicalClouds(_ caption: String) -> String { typicalClouds.map { Sentences.join([caption, $0]) } ?? caption }
    /// The short label for what a night's clouds rest on: nil with a forecast, else "Early look"
    /// or "No cloud forecast yet".
    nonisolated var basisLabel: String? {
        switch basis {
        case .forecast: nil
        case .blended: String(localized: "Early look")
        case .usual: String(localized: "No cloud forecast yet")
        }
    }
    /// The band where room is short: "Excellent", "Excellent, early look", "Excellent, usual clouds".
    nonisolated var bandWithBasis: String { score.bandWithBasis }
    /// The word under a score where one word fits: the band, "Early look" or "Estimate".
    nonisolated var compactBandLabel: String {
        switch basis {
        case .forecast: score.band.label
        case .blended: String(localized: "Early look")
        case .usual: String(localized: "Estimate")
        }
    }
    /// The long form; nil with a forecast. `unavailable` is for a forecast that should reach this
    /// night but could not be read. `typical` adds "About 8 in 10 … nights here are mostly clear."
    nonisolated func basisCaption(unavailable: Bool = false, typical: Bool = false) -> String? {
        switch basis {
        case .forecast: return nil
        case .blended(_, let lead):
            return String(localized: "Early look: forecast \(max(1, Int(lead.rounded()))) days out, eased toward usual clouds.")
        case .usual:
            var format = Date.FormatStyle().month(.wide)
            format.timeZone = park.timeZone
            let first = unavailable ? String(localized: "Cloud forecast unavailable.") : String(localized: "No cloud forecast yet.")
            // Never "Arches's": the park follows the month rather than taking a possessive.
            let line = Sentences.join([first, usualCloud == nil ? String(localized: "This score counts the Moon and darkness only.")
                : String(localized: "This score uses the usual \(id.formatted(format)) clouds at \(park.shortName).")])
            return typical ? withTypicalClouds(line) : line
        }
    }
}

#if os(iOS)
// Only the iPhone and iPad app and its widgets say a night's score as a sentence; the guard keeps
// these keys out of the watch's and Vision Pro's string extraction.
extension Night {
    /// Every sentence that says a night's score ("Fri, Oct 9, 94 out of 100, Pristine. …") in one
    /// place, so the surfaces cannot drift apart. Each style is its own String Catalog key.
    nonisolated enum SpokenSummary: Sendable {
        /// The time river: "Fri, Oct 9, 94 out of 100, Pristine." then the long caption with the
        /// month's usual clouds, or "Forecast included".
        case river
        /// The calendar's list: as `river`, then the night's sky event, under its own key.
        case calendar(event: String?)
        /// The Tonight widget: the park, the score and band, then the short caption or "Cached forecast included".
        case widget
        /// The Tonight widget moved to another night of the week: as `widget`, with the night's date.
        case widgetNight
        /// The chart's summary: "Best night: Fri, Oct 9, 94 out of 100, Pristine."
        case chartBest
        /// One night of a stay: "Fri, Oct 9, 94 out of 100, Pristine, usual clouds".
        case dayWithBasis
        /// The score alone: "94 out of 100, Pristine, early look".
        case scoreWithBasis
        /// A shared trip, one line a night: "Fri, Oct 9: Arches, 94 out of 100, Pristine. New moon, …."
        case tripLine(reason: String)
        /// A stay's calendar notes, one line a night: "Fri, Oct 9: darkness score 94 out of 100 (Pristine). …."
        case stayNote(reason: String)
        /// A calendar event's first line, with what the clouds rest on.
        case eventNote
        /// Siri, tonight at the park (the intent puts any closure first). Voice-only keeps the one caveat that matters.
        case siriTonight(voiceOnly: Bool)
        /// Siri, the best of the next `count` nights. `noDarkness`: none of them has any true darkness.
        case siriBest(count: Int, voiceOnly: Bool, noDarkness: Bool)
        /// Siri's card, for VoiceOver: the score, the band and the Moon.
        case snippet
    }
    nonisolated func spokenSummary(_ style: SpokenSummary) -> String {
        switch style {
        case .river:
            let clouds=basisCaption(typical:true) ?? String(localized:"Forecast included")
            return String(localized:"\(park.dayLabel(id)), \(score.value) out of 100, \(score.band.label). \(clouds)")
        case .calendar(let event):
            return String(localized:"\(park.dayLabel(id)), \(score.value) out of 100, \(score.band.label). \(basisCaption(typical:true) ?? String(localized:"Forecast included"))\(event.map { ". "+$0 } ?? "")")
        case .widget:
            return String(localized:"\(park.shortName), \(score.value) out of 100, \(score.band.label). \(basisCaption() ?? String(localized:"Cached forecast included"))")
        case .widgetNight:
            return String(localized:"\(park.shortName), \(park.dayLabel(id)): \(score.value) out of 100, \(score.band.label). \(basisCaption() ?? String(localized:"Cached forecast included"))")
        case .chartBest:
            return String(localized:"Best night: \(park.dayLabel(id)), \(score.value) out of 100, \(score.band.label).")
        case .dayWithBasis:
            return String(localized:"\(park.dayLabel(id)), \(score.value) out of 100, \(bandWithBasis)")
        case .scoreWithBasis:
            return String(localized:"\(score.value) out of 100, \(bandWithBasis)")
        case .tripLine(let reason):
            return String(localized:"\(park.dayLabel(id)): \(park.shortName), \(score.value) out of 100, \(bandWithBasis). \(reason).")
        case .stayNote(let reason):
            return String(localized:"\(park.dayLabel(id)): darkness score \(score.value) out of 100 (\(bandWithBasis)). \(reason).")
        case .eventNote:
            return score.hasForecast
                ? String(localized:"Darkness score \(score.value) out of 100 (\(score.band.label)), with the cloud forecast as Nyx last saw it.")
                : Sentences.join([String(localized:"Darkness score \(score.value) out of 100 (\(score.band.label))."), basisCaption(typical:true) ?? ""])
        case .siriTonight(let voiceOnly):
            if sky.darkHours==0 { return String(localized:"No true darkness tonight at \(park.shortName). The darkness score is \(score.value) out of 100.") }
            if voiceOnly { return voiceAnswer(String(localized:"Tonight")) }
            if let caption=basisCaption() { return String(localized:"\(park.shortName): \(score.value) out of 100, \(score.band.label). \(caption) Confirm conditions and park access before traveling.") }
            return String(localized:"\(park.shortName): \(score.value) out of 100, \(score.band.label). Includes a cached cloud forecast. Confirm conditions and park access before traveling.")
        case .siriBest(let count,let voiceOnly,let noDarkness):
            let day=park.programDate(park.isoDay(id))
            if voiceOnly { return voiceAnswer(day) }
            // Said only when no night searched has true darkness; a best night without it among
            // nights that have some is named as the best, as any other.
            if noDarkness { return String(localized:"No true darkness at \(park.shortName) in the next \(count) nights. The best is \(day), \(score.value) out of 100.") }
            let basis=basisCaption(typical:true) ?? String(localized:"Includes a cached cloud forecast.")
            return String(localized:"The best of the next \(count) nights: \(day) at \(park.shortName), \(score.value) out of 100, \(score.band.label). \(basis) Confirm park access before you go.")
        case .snippet:
            return String(localized:"\(park.shortName) tonight: \(score.value) out of 100, \(bandWithBasis). \(sky.moon.name), \(Int((sky.moon.illumination*100).rounded())) percent lit.")
        }
    }
    /// Siri with no screen in view: "Tonight at Arches: 94, Pristine." and, without a full
    /// forecast, the one caveat about the clouds.
    private nonisolated func voiceAnswer(_ day: String) -> String {
        let caveat=score.hasForecast ? "" : (basis.isEarlyLook ? String(localized:"An early look at the clouds.") : withTypicalClouds(String(localized:"No cloud forecast yet.")))
        return Sentences.join([String(localized:"\(day) at \(park.shortName): \(score.value), \(score.band.label)."), caveat])
    }
}
#endif
