import Foundation

/// Best nights, month grids and dusk windows straight from the engine, shared by the widgets,
/// the "Find the best night" intent and Ask Nyx's tools. Pure: parks, forecasts and "now" come
/// in, nothing is fetched, and missing clouds are never treated as clear.
nonisolated struct NightPlanner: Sendable {
    let forecasts: [String: Forecast]
    var astronomy = AstronomyEngine()
    var scoring = ScoreEngine()

    /// One park's night, scored with the cached forecast when it covers the dark window.
    func night(_ park: Park, on evening: Date, now: Date) -> Night { night(park, sky: astronomy.conditions(for: park, on: evening), now: now) }
    /// The same, for a sky already computed (a widget reuses each night's sky across entries).
    func night(_ park: Park, sky: SkyConditions, now: Date) -> Night {
        let forecast = forecasts[park.id]
        let clouds = forecast?.mean(from: sky.cloudWindow.start, to: sky.cloudWindow.end, now: now)
        return Night(park: park, sky: sky, score: scoring.score(sky: sky, bortle: park.bortleEstimate, cloudCover: clouds),
                     cloudCover: clouds, forecastUpdated: clouds == nil ? nil : forecast?.updated)
    }
    /// `count` nights from the park-local night that contains `start` (clamped to 1...60).
    func nights(_ park: Park, from start: Date, count: Int, now: Date) -> [Night] {
        nights(park, first: park.currentNight(at: start), count: count, now: now)
    }
    /// `count` nights from the evening of `day` (year, month, day), a date someone picked (a
    /// Shortcuts date, a date Ask Nyx names). The picked day is the night, whatever its time of
    /// day; never before tonight.
    func nights(_ park: Park, day: DateComponents, count: Int, now: Date) -> [Night] {
        let tonight = park.currentNight(at: now)
        let picked = park.calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12)) ?? tonight
        return nights(park, first: max(picked, tonight), count: count, now: now)
    }
    private func nights(_ park: Park, first: Date, count: Int, now: Date) -> [Night] {
        (0..<min(60, max(1, count))).map { night(park, on: park.date(first, addingDays: $0), now: now) }
    }
    /// The best nights across parks: highest score first; on a tie, a night with a cloud forecast
    /// before one without (it is the surer number), then the earlier night, then the park's name.
    func bestNights(_ parks: [Park], from start: Date, count: Int, now: Date, limit: Int = 3) -> [Night] {
        Array(parks.flatMap { nights($0, from: start, count: count, now: now) }.sorted(by: Self.better).prefix(max(0, limit)))
    }
    /// The same, from a picked day.
    func bestNights(_ parks: [Park], day: DateComponents, count: Int, now: Date, limit: Int = 3) -> [Night] {
        Array(parks.flatMap { nights($0, day: day, count: count, now: now) }.sorted(by: Self.better).prefix(max(0, limit)))
    }
    static func better(_ a: Night, _ b: Night) -> Bool {
        if a.score.value != b.score.value { return a.score.value > b.score.value }
        if a.score.hasForecast != b.score.hasForecast { return a.score.hasForecast }
        if a.id != b.id { return a.id < b.id }
        return a.park.name < b.park.name
    }
    static func best(_ nights: [Night]) -> Night? { nights.sorted(by: better).first }

    // MARK: Smart Stack

    /// The hours a night is worth surfacing: from 90 minutes before sunset until an hour into
    /// true darkness (or sunrise when there is none). Good or better only; a night whose score is
    /// moon and darkness alone must reach Excellent, because clouds may still take it away.
    static func duskWindow(_ night: Night) -> DateInterval? {
        guard night.score.value >= (night.score.hasForecast ? 60 : 75), night.sky.darkHours > 0,
              let sunset = night.sky.sunset else { return nil }
        let start = sunset.addingTimeInterval(-90*60)
        let end = night.sky.darkStart.map { $0.addingTimeInterval(3600) } ?? night.sky.sunrise ?? sunset.addingTimeInterval(3*3600)
        return end > start ? DateInterval(start: start, end: end) : nil
    }
    /// How strongly the widget should rise at `date`: 0 outside every dusk window, else the
    /// night's score (0.6...1.0) and the time left in its window. WidgetKit compares scores only
    /// among one widget's own entries, so the scale only has to rank Nyx's nights.
    static func relevance(at date: Date, nights: [Night]) -> (score: Float, duration: TimeInterval) {
        for night in nights.sorted(by: better) {
            if let window = duskWindow(night), window.contains(date) {
                return (Float(night.score.value)/100, window.end.timeIntervalSince(date))
            }
        }
        return (0, 0)
    }

    // MARK: Month of nights

    /// A calendar-style run of nights for the large widget: 35 cells in weeks that start on the
    /// locale's first weekday, beginning with the week of tonight. Nights before tonight are
    /// `nil` (blank), so tonight sits under its own weekday.
    struct Month: Sendable {
        let nights: [Night?]
        let best: Date?
        /// Shower peaks and eclipses, by night.
        let events: [Date: WhatsUp.Events.Glyph]
        var tonight: Night? { nights.compactMap { $0 }.first }
    }
    func month(_ park: Park, at now: Date, cells: Int = 35, events withEvents: Bool = true, table: SkyEvents = .shared) -> Month {
        let tonight = park.currentNight(at: now)
        var calendar = park.calendar
        calendar.firstWeekday = Calendar.current.firstWeekday
        let weekday = calendar.component(.weekday, from: tonight)
        let lead = (weekday - calendar.firstWeekday + 7) % 7
        let run = nights(park, from: now, count: cells - lead, now: now)
        var marks: [Date: WhatsUp.Events.Glyph] = [:]
        if withEvents {
            for night in run { if let glyph = WhatsUp.Events(park: park, sky: night.sky, table: table).glyph { marks[night.id] = glyph } }
        }
        return Month(nights: Array(repeating: nil, count: lead) + run.map { Optional($0) }, best: Self.best(run)?.id, events: marks)
    }
}
