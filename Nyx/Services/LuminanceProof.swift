import Foundation
import MetricKit

/// The last average screen brightness iOS measured while Nyx was on screen (MetricKit's average
/// pixel luminance: 0 is an all-black screen, 100 all white). Kept on this iPhone only, and shown
/// only once a real report has arrived: never estimated, never a placeholder.
nonisolated struct LuminanceReading: Codable, Sendable, Equatable {
    /// Average pixel luminance, 0–100.
    let percent: Double
    /// The end of the period the report covers (MetricKit reports about once a day).
    let end: Date
    var isFixture=false
    static let key="luminanceReading"
    static func load(_ defaults: UserDefaults = .standard) -> LuminanceReading? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(LuminanceReading.self, from: $0) }
    }
    func save(_ defaults: UserDefaults = .standard) {
        if let data=try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key) }
    }
    /// A reading only from a plausible value; MetricKit omits it on displays without the measurement.
    static func make(percent: Double?, end: Date) -> LuminanceReading? {
        guard let percent, percent.isFinite, (0...100).contains(percent) else { return nil }
        return LuminanceReading(percent: percent, end: end)
    }
    /// Whole percent, but never "0%" for a screen that was not black.
    var rounded: Int { percent>0 && percent<1 ? 1 : Int(percent.rounded()) }
    var sentence: String {
        let day=end.formatted(.dateTime.month(.wide).day())
        let line=String(localized: "On this iPhone, Nyx's screen averaged \(rounded)% of full brightness in the day iOS last reported, ending \(day).")
        return isFixture ? String(localized: "Debug fixture, not a measurement.")+" "+line : line
    }
    #if DEBUG
    static let fixture=LuminanceReading(percent: 6.4, end: Date(timeIntervalSince1970: 1_791_158_400), isFixture: true)
    #endif
}

/// Subscribes to MetricKit's daily reports and keeps only the screen's average pixel luminance.
/// iOS 27 uses the Swift `MetricManager`; iOS 26 the older `MXMetricManager`. Nothing is sent
/// anywhere: Nyx has no analytics and no server, and this value stays in the app's defaults.
@MainActor final class LuminanceProof: NSObject, MXMetricManagerSubscriber {
    static let shared=LuminanceProof()
    private var started=false
    private var listener: Task<Void, Never>?
    /// The reading to show: a real one, or in DEBUG the clearly labelled fixture for `-nyx-screen metric`.
    static var current: LuminanceReading? {
        #if DEBUG
        if DebugScenario.screen=="metric" { return .fixture }
        if DebugScenario.screen != nil { return nil }
        #endif
        return LuminanceReading.load()
    }
    func start() {
        guard !started else { return }
        started=true
        if #available(iOS 27.0, *) {
            let manager=MetricManager()
            listener=Task.detached(priority: .utility) {
                for await report in manager.metricReports { Self.reading(from: report)?.save() }
            }
        } else {
            MXMetricManager.shared.add(self)
        }
    }
    @available(iOS 27.0, *)
    nonisolated static func reading(from report: MetricReport) -> LuminanceReading? {
        var total=0.0, count=0
        for values in report.intervalEntries.map(\.values)+report.stateEntries.map(\.values) {
            for case .pixelLuminance(let metric) in values {
                let n=max(1, metric.value.count)
                total+=metric.value.average.value*Double(n); count+=n
            }
        }
        return count>0 ? LuminanceReading.make(percent: total/Double(count), end: report.timeRange.end) : nil
    }
    nonisolated func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads.sorted(by: { $0.timeStampEnd<$1.timeStampEnd }) {
            LuminanceReading.make(percent: payload.displayMetrics?.averagePixelLuminance?.averageMeasurement.value, end: payload.timeStampEnd)?.save()
        }
    }
}
