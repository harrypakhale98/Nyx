import Foundation

/// Best nights, month grids and dusk windows straight from the engine, shared by the widgets,
/// the "Find the best night" intent and Ask Nyx's tools. Pure: parks, forecasts and "now" come
/// in, nothing is fetched, and missing clouds are never treated as clear.
nonisolated struct NightPlanner: Sendable {
    let forecasts: [String: Forecast]
    /// Smoke, cloud layers and model agreement, where known; optional everywhere.
    var details: [String: ForecastDetail] = [:]
    /// Usual clouds: the bundled file and world grid, plus any months the iPhone handed over for
    /// places off the file (`CloudClimate.carried`), which the widgets and the watch read this way.
    var climate: CloudClimate = .shared
    var astronomy = AstronomyEngine()
    var scoring = ScoreEngine()

    /// One park's night, scored with the cached forecast when it covers the dark window.
    func night(_ park: Park, on evening: Date, now: Date) -> Night { night(park, sky: astronomy.conditions(for: park, on: evening), now: now) }
    /// The same, for a sky already computed (a widget reuses each night's sky across entries).
    func night(_ park: Park, sky: SkyConditions, now: Date) -> Night {
        Self.night(park: park, sky: sky, forecast: forecasts[park.id], detail: details[park.id], now: now, climate: climate, scoring: scoring)
    }

    // MARK: The one way a night is built

    /// The only constructor of a `Night` from a sky and what is known about its clouds; the app,
    /// widgets, Siri, the trip planner, Ask Nyx, the watch and Vision Pro all come through here,
    /// so a rule changed once changes everywhere.
    ///
    /// **Clouds.** cloud = w·forecast + (1 − w)·usual, with `usual` the park's ERA5 cloud for the
    /// month and w = `CloudBasis.forecastWeight` of the lead from the forecast's issue to the
    /// middle of the night's cloud window. No forecast covering the window: the usual clouds
    /// alone. A park flagged `aboveInversion` (Haleakalā's summit) counts mid and high cloud only,
    /// from the layer forecast, and never its total cloud: the low cloud of the trade-wind
    /// inversion, which dominates the total there, lies below the observer, so the total would
    /// score a clear summit night as overcast. Layers that cover the night are weighed by their own
    /// issue, as any forecast (an older one eases toward the usual clouds); with none covering it
    /// (not asked for yet, failed, or past their seven days), the usual clouds alone.
    /// **Smoke.** The aerosol forecast's average over the window, whenever it covers it (it can
    /// only lower a score, so its age never hides it); kept on the night (`aerosol`) so the
    /// outlook's smoke words always describe the smoke the score used. **Ties.** The three models'
    /// cloud spread. `now` decides only whether the model spread is recent enough to describe (`Forecast.recentFor`).
    static func night(park: Park, sky: SkyConditions, forecast: Forecast?, detail: ForecastDetail?, now: Date,
                      climate: CloudClimate = .shared, scoring: any ScoreProviding = ScoreEngine()) -> Night {
        let window = sky.cloudWindow
        let typical = climate.typical(park, on: sky.evening), usual = typical?.cloud
        var predicted = forecast?.mean(from: window.start, to: window.end), issued = forecast?.updated, upper = false
        if park.aboveInversion == true {
            // The summit's total cloud is never its cloud: the layers when they cover the night, else nothing.
            predicted = nil; issued = nil
            if let layers = detail?.layers,
               let mid = layers.mean("cloud_cover_mid", from: window.start, to: window.end, valid: 0...100),
               let high = layers.mean("cloud_cover_high", from: window.start, to: window.end, valid: 0...100) {
                // Random overlap of the two layers above the summit.
                predicted = 100*(1-(1-mid/100)*(1-high/100)); issued = layers.updated; upper = true
            }
        }
        let middle = window.start.addingTimeInterval(window.end.timeIntervalSince(window.start)/2)
        let lead = issued.map { middle.timeIntervalSince($0)/86400 } ?? .infinity
        let weight = predicted == nil ? 0 : CloudBasis.forecastWeight(leadDays: lead)
        // With no usual clouds to ease toward, a forecast counts as it stands while it counts at all;
        // once its weight reaches 0 the cloud term is dropped and the other parts renormalised.
        let counted: Double? = switch (predicted, usual) {
        case let (f?, u?): weight*f + (1-weight)*u
        case let (f?, nil): weight > 0 ? f : nil
        case let (nil, u): u
        }
        let aerosol = detail?.air?.mean("aerosol_optical_depth", from: window.start, to: window.end, valid: 0...10)
        let spread = detail?.agreement(from: window.start, to: window.end, now: now)?.spread
        let used = weight > 0
        let score = scoring.score(sky: sky, bortle: park.bortleEstimate, cloud: counted, basis: CloudBasis.from(weight: weight, leadDays: lead), aerosol: aerosol)
        var night = Night(park: park, sky: sky, score: score, cloudCover: used ? predicted : nil, forecastUpdated: used ? issued : nil,
                          usualCloud: usual, usualClear: typical?.clear, usualEstimated: typical?.estimated == true,
                          upperCloudOnly: upper && used, modelSpread: spread, aerosol: aerosol)
        night.beyondForecast = beyondForecast(night, forecast: forecast, detail: detail, now: now)
        return night
    }
    /// How many days of hours a layer forecast holds (`forecast_days=7`, from 00:00 UTC on the day
    /// it is asked for), on iPhone (forecast detail) and on Vision Pro (`SummitLayerService`).
    static let layerDays = 7
    /// True when a night scored on the usual clouds simply lies beyond what a cloud forecast
    /// reaches: past the forecast's last hour, or so far ahead of a recent forecast (or, with none
    /// recent, of `now`) that it counts for nothing (`CloudBasis.forecastWeight` is 0, ten days
    /// out). False when a forecast should have reached the night but could not be read or is too
    /// old, which the captions call "Cloud forecast unavailable". One rule for iPhone, iPad and Vision Pro.
    /// A summit above the inversion reads its layers (`detail`), never its total cloud: with them
    /// unknown, a night past the seven days they would reach is "not yet", a nearer one "unavailable".
    static func beyondForecast(_ night: Night, forecast: Forecast?, detail: ForecastDetail? = nil, now: Date) -> Bool {
        guard night.basis == .usual else { return false }
        let window = night.sky.cloudWindow
        var forecast = forecast
        if night.park.aboveInversion == true {
            guard let upper = detail?.layers?.upperCloud else {
                var utc = Calendar(identifier: .gregorian)
                utc.timeZone = TimeZone(identifier: "UTC") ?? .gmt
                let reach = utc.startOfDay(for: now).addingTimeInterval(Double(layerDays)*86400)
                return window.end > reach
            }
            forecast = upper
        }
        let middle = window.start.addingTimeInterval(window.end.timeIntervalSince(window.start)/2)
        // A recent forecast is measured from its issue, as the score measures it; a stale one from now.
        let recent = forecast.flatMap { now.timeIntervalSince($0.updated) < Forecast.recentFor ? $0 : nil }
        if CloudBasis.forecastWeight(leadDays: middle.timeIntervalSince(recent?.updated ?? now)/86400) == 0 { return true }
        // Past the last hour of a recent forecast only: a stale one that ends before the night should
        // have been replaced by now, so a night within reach of today's is "unavailable".
        if let last = recent?.times.last { return window.end.timeIntervalSince1970 > last+3600 }
        return false
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
    /// The best nights across parks, ranked by `better`, a closure counting against its park's nights.
    func bestNights(_ parks: [Park], from start: Date, count: Int, now: Date, limit: Int = 3, closures: [String: String] = [:]) -> [Night] {
        Array(Self.ranked(parks.flatMap { nights($0, from: start, count: count, now: now) }, closures: closures).prefix(max(0, limit)))
    }
    /// The same, from a picked day.
    func bestNights(_ parks: [Park], day: DateComponents, count: Int, now: Date, limit: Int = 3, closures: [String: String] = [:]) -> [Night] {
        Array(Self.ranked(parks.flatMap { nights($0, day: day, count: count, now: now) }, closures: closures).prefix(max(0, limit)))
    }
    /// How many nights from tonight every best night is chosen over, wherever one is named: the park
    /// page's "Darker on…", Tonight's capsule, Best nights, the river's "Best night", With the lights
    /// out, Siri and Vision Pro's nights ahead. A whole lunar cycle, so the next new Moon is always in it.
    static let horizon = 30
    /// Best first, by score. Every night's score already counts clouds (forecast, early look or
    /// the park's usual clouds), so scores compare directly. Ties, which are common near new moon,
    /// go to the darker measured sky (Black Marble glow, `glowRank`), then the higher sum of parts
    /// beneath a cap (a park's usual clouds can hold a whole month at one score, and the new Moon
    /// must still outrank a gibbous one), then the longer true darkness, then the forecast models
    /// that agree more closely, then the surer cloud basis, then the earlier night and the park's
    /// name. The numbers shown never change.
    ///
    /// Near-equal sums, darkness and spreads tie: each is first rounded to its grid (`tieGrid`:
    /// half a point, a minute, half a percent) and then compared exactly. A tolerance instead
    /// ("within half a point") is not transitive, so a sort could name a different best night
    /// for the same nights given in another order.
    static func better(_ a: Night, _ b: Night) -> Bool {
        if a.score.value != b.score.value { return a.score.value > b.score.value }
        let ga = glowRank(a.park.id), gb = glowRank(b.park.id)
        if ga != gb { return ga < gb }
        let ra = tieGrid(a.score.rawPartsSum, 0.5), rb = tieGrid(b.score.rawPartsSum, 0.5)
        if ra != rb { return ra > rb }
        let da = tieGrid(a.sky.darkHours, 1.0/60), db = tieGrid(b.sky.darkHours, 1.0/60)
        if da != db { return da > db }
        let sa = tieGrid(a.modelSpread ?? .infinity, 0.5), sb = tieGrid(b.modelSpread ?? .infinity, 0.5)
        if sa != sb { return sa < sb }
        if certainty(a.basis) != certainty(b.basis) { return certainty(a.basis) > certainty(b.basis) }
        if a.id != b.id { return a.id < b.id }
        return a.park.name < b.park.name
    }
    /// `value` rounded to the nearest multiple of `step`, as a count of steps: two values tie
    /// exactly when they share a step. Infinity stays infinite.
    static func tieGrid(_ value: Double, _ step: Double) -> Double { value.isFinite ? (value/step).rounded() : value }
    static func certainty(_ basis: CloudBasis) -> Double {
        switch basis { case .forecast: 1; case .blended(let w, _): w; case .usual: 0 }
    }
    static func ranked(_ nights: [Night]) -> [Night] { nights.sorted(by: better) }
    /// A closure in its park's last update costs a night this many points wherever a night is
    /// recommended as the best (the trip planner, Siri's best night, the week's ring, which night a
    /// reminder announces), so every such surface picks the same night; the score shown never changes. A
    /// closed road beats a slightly darker sky every time. What claims the darkest (Tonight's answer,
    /// the map's darkest, the watch, the Tonight control, Ask Nyx's parks nearby) ranks the sky alone
    /// with `better(_:_:)` and shows the closure beside the score.
    static let closurePenalty = 10
    /// `better`, with each closed park's nights `closurePenalty` points down (`closures`: park id →
    /// closure, as the app words it).
    static func better(_ a: Night, _ b: Night, closures: [String: String]) -> Bool {
        let va = a.rankScore-(closures[a.park.id] == nil ? 0 : closurePenalty), vb = b.rankScore-(closures[b.park.id] == nil ? 0 : closurePenalty)
        if va != vb { return va > vb }
        return better(a, b)
    }
    static func ranked(_ nights: [Night], closures: [String: String]) -> [Night] {
        closures.isEmpty ? ranked(nights) : nights.sorted { better($0, $1, closures: closures) }
    }
    /// The first of `nights` by `better`: the night every surface names as a place's best. `better` is
    /// a strict total order (it falls through to the night and the park's name), so this is the night
    /// `ranked` puts first, found without sorting.
    static func best(_ nights: [Night]) -> Night? { nights.min(by: better) }
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
        guard worthSurfacing(night), let sunset = night.sky.sunset else { return nil }
        let start = sunset.addingTimeInterval(-90*60)
        let end = night.sky.darkStart.map { $0.addingTimeInterval(3600) } ?? night.sky.sunrise ?? sunset.addingTimeInterval(3*3600)
        return end > start ? DateInterval(start: start, end: end) : nil
    }
    /// Whether a night is worth surfacing in a Smart Stack at all, on iPhone and on the watch alike:
    /// some true darkness, and Good or better with a full cloud forecast, Excellent without one.
    static func worthSurfacing(_ night: Night) -> Bool {
        night.sky.darkHours > 0 && night.score.value >= (night.score.hasForecast ? ScoreBand.good : ScoreBand.excellent).minimum
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
    /// `firstWeekday`: 1 Sunday … 7 Saturday, the person's own by default.
    func month(_ park: Park, at now: Date, cells: Int = 35, events withEvents: Bool = true, table: SkyEvents = .shared,
               firstWeekday: Int = Calendar.current.firstWeekday) -> Month {
        let tonight = park.currentNight(at: now)
        var calendar = park.calendar
        calendar.firstWeekday = firstWeekday
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
nonisolated extension HourlySeries {
    /// Mid and high cloud combined hour by hour as the score combines their averages (random
    /// overlap), as a cloud forecast issued when the layers were: what the sky over a summit above
    /// the inversion draws. Nil without both layers for every hour.
    var upperCloud: Forecast? {
        guard let mid=values["cloud_cover_mid"], let high=values["cloud_cover_high"], mid.count == times.count, high.count == times.count else { return nil }
        let clouds=zip(mid, high).map { m, h -> Double? in
            guard let m, let h, (0...100).contains(m), (0...100).contains(h) else { return nil }
            return 100*(1-(1-m/100)*(1-h/100))
        }
        return Forecast(updated: updated, times: times, clouds: clouds)
    }
}

/// The week's best night in one short line, said as the week's, on every surface that looks seven
/// nights ahead (a Parks row, the medium widget, the watch's week): the park page and Best nights
/// name the best of thirty, so "best" alone would name two nights. The best is `NightPlanner.best`'s,
/// ties broken by its ranking. Every night scoring alike (usual clouds all week) singles none out:
/// "Best this week: every night". Else the first night is "Best this week: tonight", and any other
/// "Best this week: Thu · 62" (its abbreviated weekday in park time, and its score). Nil for no nights.
nonisolated enum WeekBest {
    /// `scored: false` leaves the score out ("Best this week: Sat"), for a surface that sets it as a numeral beside it.
    static func label(_ week: [Night], scored: Bool = true) -> String? {
        guard let best = NightPlanner.best(week), let first = week.first else { return nil }
        if week.count > 1, week.allSatisfy({ $0.score.value == best.score.value }) { return String(localized: "Best this week: every night") }
        return label(best, first: first, scored: scored)
    }
    /// The same for a best night already found, without the "every night" case, which needs the week.
    static func label(_ best: Night, first: Night, scored: Bool = true) -> String {
        if best.id == first.id { return String(localized: "Best this week: tonight") }
        let day = best.id.formatted(Date.FormatStyle(timeZone: best.park.timeZone).weekday(.abbreviated))
        return scored ? String(localized: "Best this week: \(day) · \(best.score.value)") : String(localized: "Best this week: \(day)")
    }
}
