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
