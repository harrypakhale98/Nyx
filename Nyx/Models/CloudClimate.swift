import Foundation

/// How cloudy each park's nights usually are, month by month: ten years (2015–2024) of ERA5
/// reanalysis over each night's true-dark hours (`Scripts/build_cloud_climate.py`, Copernicus
/// Climate Change Service, CC BY 4.0). It is used only where no forecast reaches, to rank nights
/// fairly and to say how often that month's nights are clear. It is never shown as a forecast and
/// never changes a night's Darkness Score.
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
    /// What every ranking of nights compares. With a cloud forecast, the score. Beyond the
    /// forecast, the score this night would have under its park's typical cloud for the month:
    /// an expected value, so a night nobody can forecast yet is neither assumed clear nor
    /// ignored, and a cloudy-climate park does not tie a desert. Without climate data, the score.
    nonisolated var rankScore: Int { rankScore(CloudClimate.shared) }
    nonisolated func rankScore(_ climate: CloudClimate) -> Int {
        guard !score.hasForecast, let typical = climate.typical(park, on: id) else { return score.value }
        return ScoreEngine().score(sky: sky, bortle: park.bortleEstimate, cloudCover: typical.cloud).value
    }
    /// "About 8 in 10 November nights here are mostly clear." for a night without a forecast.
    nonisolated var typicalClouds: String? { score.hasForecast ? nil : CloudClimate.shared.sentence(park, on: id) }
    /// A "clouds unknown" caption followed by the month's typical clouds, when known.
    nonisolated func withTypicalClouds(_ caption: String) -> String { typicalClouds.map { caption+" "+$0 } ?? caption }
}
