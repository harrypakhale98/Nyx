import Foundation

/// How cloudy each park's nights usually are, month by month: ten years (2015–2024) of ERA5
/// reanalysis over each night's true-dark hours (`Scripts/build_cloud_climate.py`, Copernicus
/// Climate Change Service, CC BY 4.0). Where no forecast reaches, a night is scored with its park's
/// usual cloud for the month, and a forecast more than three days ahead is eased toward it
/// (`CloudBasis`), so a night nobody can forecast yet is neither assumed clear nor ignored. It is
/// never shown as a forecast: such nights say "No cloud forecast yet" or "Early look".
nonisolated struct CloudClimate: Decodable, Sendable {
    struct Months: Decodable, Sendable {
        /// Mean cloud over the dark hours, percent, January first.
        let cloud: [Int?]
        /// Share of nights under 30% cloud ("mostly clear"), percent.
        let clear: [Int?]
    }
    /// One park's month.
    struct Typical: Sendable, Equatable {
        let month: Int
        let cloud: Double
        let clear: Double
        /// "About 8 in 10 November nights here are mostly clear."
        func sentence(monthName: String) -> String {
            let tenths = Int((clear/10).rounded())
            switch tenths {
            case ...0: return String(localized: "\(monthName) nights here are rarely clear.")
            case 10...: return String(localized: "\(monthName) nights here are nearly always clear.")
            default: return String(localized: "About \(tenths) in 10 \(monthName) nights here are mostly clear.")
            }
        }
    }
    let parks: [String: Months]

    static let shared: CloudClimate = load() ?? CloudClimate(parks: [:])
    static func load(_ bundle: Bundle = .main) -> CloudClimate? {
        guard let url = bundle.url(forResource: "cloud-climate", withExtension: "json"), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CloudClimate.self, from: data)
    }
    /// The month of the night that begins on `evening`, at `park`.
    func typical(_ park: Park, on evening: Date) -> Typical? {
        let month = park.calendar.component(.month, from: evening)
        guard let entry = parks[park.id], entry.cloud.count == 12, entry.clear.count == 12,
              let cloud = entry.cloud[month-1], let clear = entry.clear[month-1] else { return nil }
        return Typical(month: month, cloud: Double(cloud), clear: Double(clear))
    }
    /// The plain line beside a night that has no cloud forecast; nil without data.
    func sentence(_ park: Park, on evening: Date) -> String? {
        guard let typical = typical(park, on: evening) else { return nil }
        var format = Date.FormatStyle().month(.wide)
        format.timeZone = park.timeZone
        return typical.sentence(monthName: evening.formatted(format))
    }
}

extension Night {
    /// What every ranking of nights compares: the score itself, which already counts the park's
    /// usual clouds where no forecast reaches. Ties are broken by `NightPlanner.better`.
    nonisolated var rankScore: Int { score.value }
    /// "About 8 in 10 November nights here are mostly clear." for a night without a forecast.
    nonisolated var typicalClouds: String? { basis == .usual ? CloudClimate.shared.sentence(park, on: id) : nil }
    /// A caption followed by the month's typical clouds, for a night without a forecast.
    nonisolated func withTypicalClouds(_ caption: String) -> String { typicalClouds.map { caption+" "+$0 } ?? caption }
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
    nonisolated var bandWithBasis: String {
        switch basis {
        case .forecast: score.band.label
        case .blended: String(localized: "\(score.band.label), early look")
        case .usual: String(localized: "\(score.band.label), usual clouds")
        }
    }
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
            let line = first+" "+(usualCloud == nil ? String(localized: "This score counts the Moon and darkness only.")
                : String(localized: "This score uses the usual \(id.formatted(format)) clouds at \(park.shortName)."))
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
        /// Siri, the best of the next `count` nights.
        case siriBest(count: Int, voiceOnly: Bool)
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
                : String(localized:"Darkness score \(score.value) out of 100 (\(score.band.label)).")+" "+(basisCaption(typical:true) ?? "")
        case .siriTonight(let voiceOnly):
            if sky.darkHours==0 { return String(localized:"No true darkness tonight at \(park.shortName). The darkness score is \(score.value) out of 100.") }
            if voiceOnly { return voiceAnswer(String(localized:"Tonight")) }
            if let caption=basisCaption() { return String(localized:"\(park.shortName): \(score.value) out of 100, \(score.band.label). \(caption) Confirm conditions and park access before traveling.") }
            return String(localized:"\(park.shortName): \(score.value) out of 100, \(score.band.label). Includes a cached cloud forecast. Confirm conditions and park access before traveling.")
        case .siriBest(let count,let voiceOnly):
            let day=park.programDate(park.isoDay(id))
            if voiceOnly { return voiceAnswer(day) }
            if sky.darkHours==0 { return String(localized:"No true darkness at \(park.shortName) in the next \(count) nights. The best is \(day), \(score.value) out of 100.") }
            let basis=basisCaption(typical:true) ?? String(localized:"Includes a cached cloud forecast.")
            return String(localized:"The best of the next \(count) nights: \(day) at \(park.shortName), \(score.value) out of 100, \(score.band.label). \(basis) Confirm park access before you go.")
        case .snippet:
            return String(localized:"\(park.shortName) tonight: \(score.value) out of 100, \(score.band.label). \(sky.moon.name), \(Int((sky.moon.illumination*100).rounded())) percent lit.")
        }
    }
    /// Siri with no screen in view: "Tonight at Arches: 94, Pristine." and, without a full
    /// forecast, the one caveat about the clouds.
    private nonisolated func voiceAnswer(_ day: String) -> String {
        let caveat=score.hasForecast ? "" : " "+(basis.isEarlyLook ? String(localized:"An early look at the clouds.") : withTypicalClouds(String(localized:"Clouds aren't forecast yet.")))
        return String(localized:"\(day) at \(park.shortName): \(score.value), \(score.band.label).")+caveat
    }
}
#endif
