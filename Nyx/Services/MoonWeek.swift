import Foundation

/// The Moon over the coming week, from the date alone: each of the next nights' phase at 10 PM
/// local time, and the next new moon, the start of the darkest nights. No park, forecast or
/// shared data, so the Vision Pro widget's large face can show it without an App Group or a
/// request. The phase is the same everywhere on Earth; only the evening it is drawn for is local.
nonisolated struct MoonWeek: Sendable, Equatable {
    /// The Moon's look at one moment.
    nonisolated struct Glance: Sendable, Equatable, Identifiable {
        let date: Date
        let phaseName: String
        /// The lit fraction, from the true phase angle.
        let illumination: Double
        let waxing: Bool
        let phaseAngle: Double
        var id: Date { date }
        var percent: Int { Int((illumination*100).rounded()) }
        init(at date: Date, engine: AstronomyEngine = AstronomyEngine()) {
            let phase = engine.moonPhase(at: date)
            self.date = date
            phaseName = phase.name
            waxing = phase.waxing
            // Elongation from the phase cycle; the phase angle is its supplement to within a few
            // hundredths of a degree, so the lit fraction agrees with the planner's.
            phaseAngle = Double.pi-2*Double.pi*(phase.fraction < 0.5 ? phase.fraction : 1-phase.fraction)
            illumination = (1+cos(phaseAngle))/2
        }
    }
    /// The local hour each night's Moon is drawn for: well into the evening, when people look.
    static let hour = 22
    /// The nights after tonight, in order.
    let nights: [Glance]
    let nextNewMoon: Date
    /// Which of `nights` is the new moon's night (its 10 PM within twelve hours of the new moon), if any.
    let newMoonNight: Int?

    init(at date: Date, count: Int = 7, calendar: Calendar = .current) {
        let tonight = Self.tonight(at: date, calendar: calendar), engine = AstronomyEngine()
        let glances = (1...max(1, count)).compactMap { day in
            calendar.date(byAdding: .day, value: day, to: tonight)
                .flatMap { calendar.date(bySettingHour: Self.hour, minute: 0, second: 0, of: $0) }
                .map { Glance(at: $0, engine: engine) }
        }
        let newMoon = Self.newMoon(after: date)
        nights = glances
        nextNewMoon = newMoon
        newMoonNight = glances.indices.first { abs(glances[$0].date.timeIntervalSince(newMoon)) <= 12*3600 }
    }
    /// The local day whose night `date` falls in: before 6 AM it is still last night.
    static func tonight(at date: Date, calendar: Calendar) -> Date {
        let day = calendar.startOfDay(for: date)
        guard calendar.component(.hour, from: date) < 6 else { return day }
        return calendar.date(byAdding: .day, value: -1, to: day) ?? day
    }
    /// The first new moon after `date`: the phase cycle wraps from 1 to 0 there. Found by
    /// six-hour steps, then halving to under a minute.
    static func newMoon(after date: Date) -> Date {
        let engine = AstronomyEngine()
        var before = date, previous = engine.moonPhase(at: date).fraction
        for step in 1...130 {
            let next = date.addingTimeInterval(Double(step)*6*3600), fraction = engine.moonPhase(at: next).fraction
            if fraction < previous {
                var low = before, high = next
                while high.timeIntervalSince(low) > 30 {
                    let middle = low.addingTimeInterval(high.timeIntervalSince(low)/2)
                    if engine.moonPhase(at: middle).fraction > 0.5 { low = middle } else { high = middle }
                }
                return high
            }
            before = next; previous = fraction
        }
        return date.addingTimeInterval(AstronomyEngine.synodicDays*86400)
    }
}
