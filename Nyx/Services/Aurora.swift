import Foundation

/// NOAA's forecast of geomagnetic activity, the planetary Kp index (0 quiet … 9 extreme), in
/// three-hour periods: what has been observed over the last week, NOAA's estimate for the current
/// period, and its forecast for about the next three days. From the Space Weather Prediction
/// Center (services.swpc.noaa.gov, a work of the U.S. Government, public domain), fetched whole,
/// so the request names no place and nothing about the person.
nonisolated struct AuroraOutlook: Codable, Sendable, Equatable {
    nonisolated struct Period: Codable, Sendable, Equatable {
        /// Start of the three-hour period.
        let start: Date
        let kp: Double
        /// NOAA's forecast for a period still ahead; false for an observed or estimated value.
        let predicted: Bool
        var end: Date { start.addingTimeInterval(3*3600) }
    }
    /// When this device received it.
    let updated: Date
    let periods: [Period]

    /// A forecast older than this is not used: NOAA reissues it several times a day.
    static let maximumAge: TimeInterval = 24*3600

    /// NOAA's `noaa-planetary-k-index-forecast.json`: an array of objects with `time_tag` (UTC,
    /// "2026-10-08T00:00:00") and `kp`, `observed` ("observed", "estimated" or "predicted"); older
    /// copies of the product were an array of rows headed by those names. Either is read; nil when
    /// neither is there or no period is valid.
    static func parse(_ data: Data, now: Date) -> AuroraOutlook? {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        var rows: [[String: Any]] = []
        if let objects = json as? [[String: Any]] { rows = objects }
        else if let table = json as? [[Any]], let header = table.first as? [String] {
            rows = table.dropFirst().map { row in Dictionary(zip(header, row), uniquingKeysWith: { first, _ in first }) }
        }
        let periods = rows.compactMap { row -> Period? in
            guard let tag = row["time_tag"] as? String, let start = Self.date(tag) else { return nil }
            let kp: Double? = (row["kp"] as? Double) ?? (row["kp"] as? NSNumber)?.doubleValue ?? (row["kp"] as? String).flatMap(Double.init)
            guard let kp, kp.isFinite, (0...9).contains(kp) else { return nil }
            return Period(start: start, kp: kp, predicted: (row["observed"] as? String) == "predicted")
        }.sorted { $0.start < $1.start }
        return periods.isEmpty ? nil : AuroraOutlook(updated: now, periods: periods)
    }
    /// "2026-10-08T00:00:00" (UTC, with or without a trailing "Z" or fractional seconds).
    static func date(_ tag: String) -> Date? {
        var text = tag.replacingOccurrences(of: " ", with: "T")
        if let dot = text.firstIndex(of: ".") { text = String(text[..<dot]) }
        if !text.hasSuffix("Z") { text += "Z" }
        return try? Date(text, strategy: .iso8601)
    }
    func usable(now: Date) -> Bool { now.timeIntervalSince(updated) < Self.maximumAge }
    /// The highest Kp across a window, observed, estimated or forecast; nil unless the periods
    /// cover the whole window (a night past the forecast's end gets no figure).
    func highest(in window: DateInterval) -> (kp: Double, predicted: Bool)? {
        let overlapping = periods.filter { $0.end > window.start && $0.start < window.end }
        guard let first = overlapping.first, let last = overlapping.last, first.start <= window.start, last.end >= window.end,
              let top = overlapping.max(by: { $0.kp < $1.kp }) else { return nil }
        return (top.kp, overlapping.contains { $0.predicted })
    }
}

/// Whether tonight's forecast brings aurora into a place's sky, by the same view-line table as the
/// standing aurora note (`Geomagnetic.AuroraReach`): the aurora's equatorward view line, the
/// farthest from the pole it is usually seen low on the horizon, lies near 66° − 2·Kp of corrected
/// geomagnetic latitude (Kp 3 near 60°, Kp 5 near 56°, Kp 7 near 52°). Kp forecasts more than a day
/// ahead are often wrong, and the aurora itself comes and goes within the night, so the words stay
/// at "possible".
nonisolated enum AuroraForecast {
    static func viewLine(kp: Double) -> Double { 66 - 2*kp }
    /// Within this many degrees poleward of the view line the aurora stays low on the horizon.
    static let lowMargin = 4.0
    enum Reach: Sendable, Equatable { case low, higher }
    /// Where tonight's highest Kp puts the aurora for a place at geomagnetic latitude `magnetic`; nil
    /// when the view line stays poleward of it.
    static func reach(kp: Double, magnetic: Double) -> Reach? {
        let margin = abs(magnetic) - viewLine(kp: kp)
        guard margin >= 0 else { return nil }
        return margin < lowMargin ? .low : .higher
    }
    /// The What's up item for a night, or nil: no usable forecast, no true darkness (the aurora
    /// needs a dark sky), a night the forecast does not cover, or not enough activity to reach here.
    static func item(_ outlook: AuroraOutlook?, park: Park, sky: SkyConditions, now: Date,
                     magnetic: Double? = nil) -> WhatsUp.Item? {
        guard let outlook, outlook.usable(now: now), let start = sky.darkStart, let end = sky.darkEnd, end > start,
              let tonight = outlook.highest(in: DateInterval(start: start, end: end)) else { return nil }
        let latitude = magnetic ?? Geomagnetic.latitude(of: park)
        guard let reach = reach(kp: tonight.kp, magnetic: latitude) else { return nil }
        // The pole's side: the northern sky in the northern hemisphere, the southern in the southern.
        let north = latitude >= 0
        let kp = Int(tonight.kp.rounded())
        let title = String(localized: "Aurora possible")
        let note = tonight.predicted ? String(localized: "NOAA forecast") : String(localized: "NOAA estimate")
        let value = String(localized: "Kp \(kp)")
        let place = switch (reach, north) {
        case (.low, true): String(localized: "That usually brings aurora low into the northern sky here.")
        case (.low, false): String(localized: "That usually brings aurora low into the southern sky here.")
        case (.higher, true): String(localized: "That usually brings aurora well into the northern sky here, sometimes higher.")
        case (.higher, false): String(localized: "That usually brings aurora well into the southern sky here, sometimes higher.")
        }
        let lead = tonight.predicted ? String(localized: "NOAA forecasts geomagnetic activity up to Kp \(kp) on its 0 to 9 scale during true darkness.")
            : String(localized: "NOAA estimates geomagnetic activity up to Kp \(kp) on its 0 to 9 scale during true darkness.")
        let caveat = String(localized: "Aurora comes and goes within a night, and forecasts a day or more ahead often miss.")
        let detail = Sentences.join([lead, place, caveat])
        return WhatsUp.Item(id: "aurora", kind: .aurora, title: title, note: note, value: value, detail: detail,
                            spoken: "\(title), \(note), Kp \(kp). \(detail)")
    }
}
