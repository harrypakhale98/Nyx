import Foundation

/// Best nights, month grids and dusk windows straight from the engine, shared by the widgets,
/// the "Find the best night" intent and Ask Nyx's tools. Pure: parks, forecasts and "now" come
/// in, nothing is fetched, and missing clouds are never treated as clear.
nonisolated struct NightPlanner: Sendable {
    let forecasts: [String: Forecast]
    /// Smoke, cloud layers and model agreement, where known; optional everywhere.
    var details: [String: ForecastDetail] = [:]
    var astronomy = AstronomyEngine()
    var scoring = ScoreEngine()

    /// One park's night, scored with the cached forecast when it covers the dark window.
    func night(_ park: Park, on evening: Date, now: Date) -> Night { night(park, sky: astronomy.conditions(for: park, on: evening), now: now) }
    /// The same, for a sky already computed (a widget reuses each night's sky across entries).
    func night(_ park: Park, sky: SkyConditions, now: Date) -> Night {
        Self.night(park: park, sky: sky, forecast: forecasts[park.id], detail: details[park.id], now: now, scoring: scoring)
    }

    // MARK: The one way a night is built

    /// The only constructor of a `Night` from a sky and what is known about its clouds; the app,
    /// widgets, Siri, the trip planner, Ask Nyx, the watch and Vision Pro all come through here,
    /// so a rule changed once changes everywhere.
    ///
    /// **Clouds.** cloud = w·forecast + (1 − w)·usual, with `usual` the park's ERA5 cloud for the
    /// month and w = `CloudBasis.forecastWeight` of the lead from the forecast's issue to the
    /// middle of the night's cloud window. No forecast covering the window: the usual clouds
    /// alone. A park flagged `aboveInversion` (Haleakalā's summit) counts mid and high cloud only
    /// when the layer forecast covers the night: low cloud there lies below the observer.
    /// **Smoke.** The aerosol forecast's average over the window, whenever it covers it (it can
    /// only lower a score, so its age never hides it). **Ties.** The three models' cloud spread.
    /// `now` decides only whether the model spread is recent enough to describe (36 hours).
    static func night(park: Park, sky: SkyConditions, forecast: Forecast?, detail: ForecastDetail?, now: Date,
                      climate: CloudClimate = .shared, scoring: any ScoreProviding = ScoreEngine()) -> Night {
        let window = sky.cloudWindow
        let usual = climate.typical(park, on: sky.evening)?.cloud
        var predicted = forecast?.mean(from: window.start, to: window.end), issued = forecast?.updated, upper = false
        if park.aboveInversion == true, let layers = detail?.layers,
           let mid = layers.mean("cloud_cover_mid", from: window.start, to: window.end, valid: 0...100),
           let high = layers.mean("cloud_cover_high", from: window.start, to: window.end, valid: 0...100) {
            // Random overlap of the two layers above the summit.
            predicted = 100*(1-(1-mid/100)*(1-high/100)); issued = layers.updated; upper = true
        }
        let middle = window.start.addingTimeInterval(window.end.timeIntervalSince(window.start)/2)
        let lead = issued.map { middle.timeIntervalSince($0)/86400 } ?? .infinity
        let weight = predicted == nil ? 0 : CloudBasis.forecastWeight(leadDays: lead)
        let counted: Double? = switch (predicted, usual) {
        case let (f?, u?): weight*f + (1-weight)*u
        case let (f?, nil): f
        case let (nil, u): u
        }
        let aerosol = detail?.air?.mean("aerosol_optical_depth", from: window.start, to: window.end, valid: 0...10)
        var spread: Double?
        if let models = detail?.models, models.usable(now: now) {
            let means = ForecastDetail.modelKeys.compactMap { models.mean($0, from: window.start, to: window.end, valid: 0...100) }
            if means.count == ForecastDetail.modelKeys.count, let low = means.min(), let high = means.max() { spread = high-low }
        }
        let used = weight > 0
        let score = scoring.score(sky: sky, bortle: park.bortleEstimate, cloud: counted, basis: CloudBasis.from(weight: weight, leadDays: lead), aerosol: aerosol)
        return Night(park: park, sky: sky, score: score, cloudCover: used ? predicted : nil, forecastUpdated: used ? issued : nil,
                     usualCloud: usual, upperCloudOnly: upper && used, modelSpread: spread)
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
    /// The best nights across parks, ranked by `better`.
    func bestNights(_ parks: [Park], from start: Date, count: Int, now: Date, limit: Int = 3) -> [Night] {
        Array(Self.ranked(parks.flatMap { nights($0, from: start, count: count, now: now) }).prefix(max(0, limit)))
    }
    /// The same, from a picked day.
    func bestNights(_ parks: [Park], day: DateComponents, count: Int, now: Date, limit: Int = 3) -> [Night] {
        Array(Self.ranked(parks.flatMap { nights($0, day: day, count: count, now: now) }).prefix(max(0, limit)))
    }
    /// Best first, by score. Every night's score already counts clouds (forecast, early look or
    /// the park's usual clouds), so scores compare directly. Ties, which are common near new moon,
    /// go to the darker measured sky (Black Marble glow, `glowRank`), then the longer true
    /// darkness, then the forecast models that agree more closely, then the surer cloud basis,
    /// then the earlier night and the park's name. The numbers shown never change.
    static func better(_ a: Night, _ b: Night) -> Bool {
        if a.score.value != b.score.value { return a.score.value > b.score.value }
        let ga = glowRank(a.park.id), gb = glowRank(b.park.id)
        if ga != gb { return ga < gb }
        if abs(a.sky.darkHours-b.sky.darkHours) >= 1.0/60 { return a.sky.darkHours > b.sky.darkHours }
        let sa = a.modelSpread ?? .infinity, sb = b.modelSpread ?? .infinity
        if abs(sa-sb) >= 0.5 { return sa < sb }
        if certainty(a.basis) != certainty(b.basis) { return certainty(a.basis) > certainty(b.basis) }
        if a.id != b.id { return a.id < b.id }
        return a.park.name < b.park.name
    }
    private static func certainty(_ basis: CloudBasis) -> Double {
        switch basis { case .forecast: 1; case .blended(let w, _): w; case .usual: 0 }
    }
    static func ranked(_ nights: [Night]) -> [Night] { nights.sorted(by: better) }
    static func best(_ nights: [Night]) -> Night? { ranked(nights).first }
    /// Where a park's measured sky glow sits among the 63 park centres, 0 (darkest) to 1
    /// (brightest); 1 when unknown. NASA Black Marble (`skyglow.json`) separates the 35 parks a
    /// hand estimate calls Bortle 2, which the score cannot.
    static func glowRank(_ id: String) -> Double { glowRanks[id] ?? 1 }
    private static let glowRanks: [String: Double] = {
        struct Site: Decodable { let glow: Double }
        struct File: Decodable { let parks: [String: Site] }
        guard let url = Bundle.main.url(forResource: "skyglow", withExtension: "json"), let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data), file.parks.count > 1 else { return [:] }
        let order = file.parks.sorted { ($0.value.glow, $0.key) < ($1.value.glow, $1.key) }.map(\.key)
        return Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, Double($0)/Double(order.count-1)) })
    }()

    // MARK: Smart Stack

    /// The hours a night is worth surfacing: from 90 minutes before sunset until an hour into
    /// true darkness (or sunrise when there is none). Good or better only; a night without a full
    /// cloud forecast must reach Excellent, because the real clouds may still take it away.
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
        for night in ranked(nights) {
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
