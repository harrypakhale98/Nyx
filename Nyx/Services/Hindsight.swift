import Foundation

/// "Looking back": the morning after, what Nyx said about a night beside what the weather models
/// now say happened. A record is kept for Tonight's answer while its clouds are still ahead (what
/// Nyx said by dusk), and checked once a forecast issued after the night arrives: Open-Meteo's
/// hourly clouds always begin the day before (`past_days=1`), so that forecast holds the models'
/// own look back at the night, scored with the same rules. It is the models' hindsight, not a
/// measurement from the ground, and is said so. Nothing is fetched for it and nothing leaves the
/// device: a record holds a place's id and a few numbers.
nonisolated struct HindsightRecord: Codable, Sendable, Equatable {
    struct Looked: Codable, Sendable, Equatable {
        let score: Int
        let cloud: Double
        let issued: Date
    }
    let placeID: String
    /// The night's evening (`Night.id`) and its place-local day, so one record stands for one night.
    let evening: Date
    let day: String
    var said: Int
    var saidCloud: Double
    var issued: Date
    /// The scoring rules it was said under; a record from other rules is never compared.
    let rules: Int
    var looked: Looked?
}

nonisolated enum Hindsight {
    /// Records kept, the newest first; older ones are let go.
    static let limit = 60
    /// A night still unanswered this long after its evening is let go: the forecast that covers it
    /// has moved on (its hours begin only the day before).
    static let patience: TimeInterval = 3*86400
    /// What a night's record says, while its clouds are still ahead: only a full forecast over some
    /// true darkness. A night on usual clouds, or with no darkness, says nothing to compare.
    static func note(_ night: Night, now: Date) -> HindsightRecord? {
        guard night.basis == .forecast, let cloud = night.cloudCover, let issued = night.forecastUpdated,
              night.sky.darkHours > 0, now < night.sky.cloudWindow.start else { return nil }
        return HindsightRecord(placeID: night.park.id, evening: night.id, day: night.park.isoDay(night.id), said: night.score.value,
                               saidCloud: cloud, issued: issued, rules: ScoreEngine.rulesVersion, looked: nil)
    }
    /// The record answered by `night` (the same night, scored now), once its forecast was fetched at
    /// least `settle` after the night's clouds ended (model runs reach Open-Meteo a few hours after
    /// they start, so an earlier fetch can still hold the forecast rather than the look back); nil
    /// until then, or when it cannot be compared.
    static func check(_ record: HindsightRecord, against night: Night) -> HindsightRecord? {
        guard record.looked == nil, record.rules == ScoreEngine.rulesVersion, night.park.id == record.placeID, night.id == record.evening,
              night.basis == .forecast, let cloud = night.cloudCover, let issued = night.forecastUpdated,
              issued >= night.sky.cloudWindow.end.addingTimeInterval(settle) else { return nil }
        var answered = record
        answered.looked = HindsightRecord.Looked(score: night.score.value, cloud: cloud, issued: issued)
        return answered
    }
    static let settle: TimeInterval = 6*3600
    /// `records` without the unanswered records of `record`'s night at other places: Tonight's answer
    /// moved before dusk, and only the answer it settled on is compared.
    static func replacing(_ record: HindsightRecord, in records: [HindsightRecord]) -> [HindsightRecord] {
        records.filter { $0.looked != nil || $0.placeID == record.placeID || abs($0.evening.timeIntervalSince(record.evening)) >= 12*3600 }
    }
    /// `records` with `record` in place of the one for its night, newest first, at most `limit`.
    static func upsert(_ record: HindsightRecord, into records: [HindsightRecord]) -> [HindsightRecord] {
        let others = records.filter { !($0.placeID == record.placeID && $0.day == record.day) }
        return Array(([record]+others).sorted { $0.evening > $1.evening }.prefix(limit))
    }
    /// Unanswered records past `patience` let go; answered ones kept.
    static func pruned(_ records: [HindsightRecord], now: Date) -> [HindsightRecord] {
        records.filter { $0.looked != nil || now.timeIntervalSince($0.evening) < patience }
    }
    /// The newest answered record whose evening was within the last day and a half: last night.
    static func lastNight(_ records: [HindsightRecord], now: Date) -> HindsightRecord? {
        records.filter { $0.looked != nil && now.timeIntervalSince($0.evening) < 36*3600 }.max { $0.evening < $1.evening }
    }
    /// How many of the last `last` answered nights Nyx called within `within` points, once there are three.
    static func tally(_ records: [HindsightRecord], within: Int = 10, last: Int = 10) -> (close: Int, of: Int)? {
        let answered = records.filter { $0.looked != nil }.sorted { $0.evening > $1.evening }.prefix(last)
        guard answered.count >= 3 else { return nil }
        return (answered.filter { abs(($0.looked?.score ?? 0) - $0.said) <= within }.count, answered.count)
    }
    /// "Last night at Joshua Tree, Nyx said 82 with 5% cloud. Looking back, the weather models put
    /// the cloud at 12%: about 78." Percents and scores as whole numbers.
    static func sentence(_ record: HindsightRecord, name: String) -> String? {
        guard let looked = record.looked else { return nil }
        let said = Int(record.saidCloud.rounded()), seen = Int(looked.cloud.rounded())
        if looked.score == record.said {
            return String(localized: "Last night at \(name), Nyx said \(record.said) with \(said)% cloud. Looking back, the weather models put the cloud at \(seen)%, and the score stays \(looked.score).")
        }
        return String(localized: "Last night at \(name), Nyx said \(record.said) with \(said)% cloud. Looking back, the weather models put the cloud at \(seen)%: about \(looked.score).")
    }
}
