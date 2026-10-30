import Foundation

/// How cloudy each park's nights usually are, month by month: ten years (2015–2024) of ERA5
/// reanalysis over each night's true-dark hours (Copernicus
/// Climate Change Service, CC BY 4.0). Where no forecast reaches, a night is scored with its park's
/// usual cloud for the month, and a forecast more than three days ahead is eased toward it
/// (`CloudBasis`), so a night nobody can forecast yet is neither assumed clear nor ignored. It is
/// never shown as a forecast: such nights say "No cloud forecast yet" or "Early look". A place
/// the file does not hold reads the world grid's usual clouds instead (`SkyGrid`).
nonisolated struct CloudClimate: Decodable, Sendable {
    struct Months: Codable, Sendable, Equatable {
        /// Mean cloud over the dark hours, percent, January first.
        let cloud: [Int?]
        /// Share of nights under 30% cloud ("mostly clear"), percent.
        let clear: [Int?]
        /// One month of the twelve, or nil when either value is missing.
        func month(_ month: Int) -> (cloud: Double, clear: Double)? {
            guard cloud.count == 12, clear.count == 12, (1...12).contains(month), let mean = cloud[month-1], let share = clear[month-1] else { return nil }
            return (Double(mean), Double(share))
        }
    }
    /// One park's month.
    struct Typical: Sendable, Equatable {
        let month: Int
        /// The usual cloud for this night: the month's own value on the 15th, eased linearly toward
        /// the neighbouring month's on either side (`typical(_:on:)`).
        var cloud: Double
        /// The month's share of mostly clear nights, for its sentence; never eased.
        let clear: Double
        /// True when the month comes from the world grid (`SkyGrid`), whose share of clear nights is
        /// estimated from the month's cloud rather than counted night by night: its sentences say so.
        var estimated = false
        /// "About 8 in 10 November nights here are mostly clear."
        func sentence(monthName: String) -> String {
            let tenths = Int((clear/10).rounded())
            switch tenths {
            case ...0: return estimated ? String(localized: "\(monthName) nights here are rarely clear, by an estimate.") : String(localized: "\(monthName) nights here are rarely clear.")
            case 10...: return estimated ? String(localized: "Nearly every \(monthName) night here is mostly clear, by an estimate.") : String(localized: "Nearly every \(monthName) night here is mostly clear.")
            default: return String(localized: "About \(tenths) in 10 \(monthName) nights here are mostly clear.")
            }
        }
    }
    private enum CodingKeys: String, CodingKey { case parks }
    let parks: [String: Months]
    /// The world grid, for a place the per-park file does not hold (any place that is not one of
    /// the 63 parks). nil keeps to the file alone: `load` and every hand-built climate, so a test's
    /// empty climate still means no usual clouds at all.
    var grid: SkyGrid? = nil
    /// Usual clouds handed over by the iPhone for places the per-park file does not hold (followed
    /// world places and saved spots), read from its world grid: the widgets and Apple Watch bundle no
    /// grid tiles, so without these they would score those places with no usual clouds at all.
    /// Keyed by place id; the values are the grid's own, so the score matches the iPhone's.
    var carried: [String: Months] = [:]

    /// The bundled per-park file, with the world grid behind it.
    static let shared: CloudClimate = {
        var climate = load() ?? CloudClimate(parks: [:])
        climate.grid = .shared
        return climate
    }()
    static func load(_ bundle: Bundle = .main) -> CloudClimate? {
        guard let url = bundle.url(forResource: "cloud-climate", withExtension: "json"), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CloudClimate.self, from: data)
    }
    /// The month of the night that begins on `evening`, at `park`. A park in the file keeps its
    /// own ten years of ERA5 at its coordinates (the 63 parks never take the grid's value);
    /// anywhere else, the grid's cell, marked `estimated`.
    /// Anywhere else, the months the iPhone carried for the place (off the phone), marked `estimated`
    /// as the grid's are.
    ///
    /// Climate does not step on the first of a month, so neither does the cloud a score reads: it is
    /// the month's value on the 15th and moves linearly to the next month's 15th. Without this, the
    /// last night of a clear October could outrank a new Moon on a cloudier November's first week.
    func typical(_ park: Park, on evening: Date) -> Typical? {
        let calendar = park.calendar
        let month = calendar.component(.month, from: evening), day = calendar.component(.day, from: evening)
        guard var typical = monthly(park, month: month) else { return nil }
        let towards = day < 15 ? (month+10)%12+1 : month%12+1
        // The days between the two 15ths: the earlier month's length.
        let earlier: Date? = day < 15 ? calendar.date(byAdding: .month, value: -1, to: evening) : evening
        let span = Double(earlier.flatMap { calendar.range(of: .day, in: .month, for: $0)?.count } ?? 30)
        if day != 15, let neighbour = monthly(park, month: towards) {
            let fraction = Double(abs(day-15))/span
            typical.cloud = typical.cloud*(1-fraction)+neighbour.cloud*fraction
        }
        return typical
    }
    /// One month's usual clouds at `park`, as recorded.
    private func monthly(_ park: Park, month: Int) -> Typical? {
        if let entry = parks[park.id] {
            guard let value = entry.month(month) else { return nil }
            return Typical(month: month, cloud: value.cloud, clear: value.clear)
        }
        if let value = carried[park.id]?.month(month) { return Typical(month: month, cloud: value.cloud, clear: value.clear, estimated: true) }
        guard let cell = grid?.cloudNight(latitude: park.latitude, longitude: park.longitude, month: month) else { return nil }
        return Typical(month: month, cloud: cell.mean, clear: cell.clear, estimated: true)
    }
    /// This climate with months handed over from the iPhone (`carried`); the per-park file still comes first.
    func carrying(_ months: [String: Months]?) -> CloudClimate {
        guard let months, !months.isEmpty else { return self }
        var climate = self
        climate.carried.merge(months) { _, new in new }
        return climate
    }
    /// The twelve months to hand over with a place the per-park file does not hold, from the world
    /// grid (the iPhone's): nil for one of the 63 parks (bundled everywhere), without the grid's
    /// tiles (off the phone), or where the grid has no month at all (at sea).
    func months(for park: Park) -> Months? {
        guard parks[park.id] == nil, let grid else { return nil }
        let cells = (1...12).map { grid.cloudNight(latitude: park.latitude, longitude: park.longitude, month: $0) }
        guard cells.contains(where: { $0 != nil }) else { return nil }
        return Months(cloud: cells.map { $0.map { Int($0.mean.rounded()) } }, clear: cells.map { $0.map { Int($0.clear.rounded()) } })
    }
    /// The months to hand over for these places, by id (`months(for:)`); empty on the watch and in widgets.
    func carriedMonths(for places: [Park]) -> [String: Months] {
        var months: [String: Months] = [:]
        for place in places where months[place.id] == nil { if let value = self.months(for: place) { months[place.id] = value } }
        return months
    }
    /// The plain line beside a night that has no cloud forecast; nil without data.
    func sentence(_ park: Park, on evening: Date) -> String? {
        guard let typical = typical(park, on: evening) else { return nil }
        return typical.sentence(monthName: park.monthName(evening))
    }
}

extension DarknessScore {
    /// The band with what its clouds rest on, wherever a score stands without room for a caption
    /// (a widget, the Live Activity, a spoken summary): "Excellent", "Excellent, early look",
    /// "Excellent, usual clouds", or "Good, Moon and darkness only" where no usual clouds are known,
    /// then ", haze or smoke" when smoke or haze holds the score down. One place, so the basis
    /// never drops off a surface again.
    nonisolated var bandWithBasis: String { withBasis(band.label) }
    /// The same phrases after another lead in the band's place: "Thu, Nov 5, usual clouds" for a list's
    /// night, "80, usual clouds" for a score. One wording for what a score rests on, already translated.
    nonisolated func withBasis(_ lead: String) -> String {
        let base = switch basis {
        case .forecast: lead
        case .blended: String(localized: "\(lead), early look")
        // Without usual clouds the score counts no clouds at all, and never claims it does.
        case .usual: cloudPoints == nil ? String(localized: "\(lead), Moon and darkness only") : String(localized: "\(lead), usual clouds")
        }
        return isSmokeLimited ? String(localized: "\(base), haze or smoke") : base
    }
    /// True when smoke or haze is what holds the score down (`ScoreLimit.smoke`).
    nonisolated var isSmokeLimited: Bool { if case .smoke = limit { true } else { false } }
}

extension Night {
    /// "About 8 in 10 November nights here are mostly clear." for a night without a forecast, from
    /// the usual clouds the night was scored with (`NightPlanner.night`), so a place whose months the
    /// iPhone handed over says it on the watch and in widgets as it does on the iPhone.
    nonisolated var typicalClouds: String? {
        guard basis == .usual, let cloud = usualCloud, let clear = usualClear else { return nil }
        return CloudClimate.Typical(month: park.calendar.component(.month, from: id), cloud: cloud, clear: clear, estimated: usualEstimated)
            .sentence(monthName: park.monthName(id))
    }
    /// A caption followed by the month's typical clouds, for a night without a forecast.
    nonisolated func withTypicalClouds(_ caption: String) -> String { typicalClouds.map { Sentences.join([caption, $0]) } ?? caption }

    // MARK: What a score rests on, said one way everywhere

    /// The short label for what a night's clouds rest on: nil with a forecast, else "Early look";
    /// on the usual clouds, "No cloud forecast yet" beyond the forecast's reach and "Cloud forecast
    /// unavailable" within it (`beyondForecast`). Every caption below starts from these words.
    nonisolated var basisLabel: String? {
        switch basis {
        case .forecast: nil
        case .blended: String(localized: "Early look")
        case .usual: beyondForecast ? String(localized: "No cloud forecast yet") : String(localized: "Cloud forecast unavailable")
        }
    }
    /// `basisLabel` as a sentence, for a night on the usual clouds: "No cloud forecast yet." or
    /// "Cloud forecast unavailable."; nil otherwise.
    nonisolated var noForecastSentence: String? {
        guard basis == .usual else { return nil }
        return beyondForecast ? String(localized: "No cloud forecast yet.") : String(localized: "Cloud forecast unavailable.")
    }
    /// "Haze or smoke" (or "Heavy smoke or haze") when smoke or haze holds the score down; nil otherwise.
    nonisolated var smokeLabel: String? {
        guard case .smoke(let cap) = score.limit else { return nil }
        return cap < 60 ? String(localized: "Heavy smoke or haze") : String(localized: "Haze or smoke")
    }
    /// "Smoke or haze limits this night to 59." when smoke or haze holds the score down.
    nonisolated func smokeSentence(tonight: Bool = false) -> String? {
        guard score.isSmokeLimited else { return nil }
        return score.limit?.sentence(tonight: tonight)
    }
    /// The short parts a list says beside a score: `basisLabel`, then `smokeLabel`.
    nonisolated var basisLabels: [String] { [basisLabel, smokeLabel].compactMap { $0 } }
    /// `basisLabels` as one line, for the line under a band word that stands alone ("Early look, Haze
    /// or smoke"): nil with a full forecast and clear air. Joined as `Phrase.clauses` joins, which the
    /// widget and watch targets do not compile.
    nonisolated var basisNote: String? {
        basisLabels.reduce(nil) { line, part in line.map { String(localized: "\($0), \(part)") } ?? part }
    }
    /// The band where room is short: "Excellent", "Excellent, early look", "Excellent, usual clouds".
    nonisolated var bandWithBasis: String { score.bandWithBasis }
    /// "94 out of 100, Pristine, early look": the score with its band and what it rests on, where it is
    /// said alone (a row's spoken value, a trip's stay, Vision Pro's dial and lists).
    nonisolated var scoreWithBasis: String { String(localized: "\(score.value) out of 100, \(bandWithBasis)") }
    /// The word under a score where one word fits: the band, "Early look" or "Estimate".
    nonisolated var compactBandLabel: String {
        switch basis {
        case .forecast: score.band.label
        case .blended: String(localized: "Early look")
        case .usual: String(localized: "Estimate")
        }
    }
    /// One short line where a phrase fits but a caption does not (the share card, Ask Nyx's
    /// records): "No cloud forecast yet · usual clouds for the month", "Cloud forecast unavailable ·
    /// Moon and darkness only"; nil with a forecast.
    nonisolated var basisLine: String? {
        switch basis {
        case .forecast: return nil
        case .blended:
            // With no usual clouds for the place there is nothing to ease toward (`NightPlanner.night`).
            return usualCloud == nil ? String(localized: "Early look · forecast counted as it stands")
                : String(localized: "Early look · forecast eased toward usual clouds")
        case .usual:
            switch (beyondForecast, usualCloud == nil) {
            case (true, false): return String(localized: "No cloud forecast yet · usual clouds for the month")
            case (false, false): return String(localized: "Cloud forecast unavailable · usual clouds for the month")
            case (true, true): return String(localized: "No cloud forecast yet · Moon and darkness only")
            case (false, true): return String(localized: "Cloud forecast unavailable · Moon and darkness only")
            }
        }
    }
    /// "62% average cover through true darkness.": the forecast's average, when one counts.
    nonisolated var coverSentence: String? { cloudCover.map { String(localized: "\(Int($0.rounded()))% average cover through true darkness.") } }
    /// Haleakalā's summit, scored from mid and high cloud only (`upperCloudOnly`); nil elsewhere.
    nonisolated var summitSentence: String? {
        upperCloudOnly ? String(localized: "The summit sits above most low cloud, so the score counts mid and high cloud only.") : nil
    }
    /// "Cloud forecasts are off in Your privacy." for a night a forecast should reach (an early look,
    /// or "Cloud forecast unavailable") while that switch is off; nil otherwise.
    nonisolated func forecastsOff(_ forecastsOn: Bool) -> String? {
        guard !forecastsOn, basis != .forecast, !(basis == .usual && beyondForecast) else { return nil }
        return String(localized: "Cloud forecasts are off in Your privacy.")
    }
    /// The clouds a score counted, as one caption under a score: the forecast's average cover, or what
    /// the score uses instead (`basisCaption`); the summit's line where only mid and high cloud count;
    /// and why a forecast that should reach the night is missing, when the switch is off.
    nonisolated func cloudCaption(typical: Bool = true, forecastsOn: Bool = true) -> String {
        switch basis {
        case .forecast: Sentences.join([coverSentence ?? "", summitSentence ?? ""])
        case .blended, .usual: Sentences.join([basisCaption(typical: typical) ?? "", summitSentence ?? "", forecastsOff(forecastsOn) ?? ""])
        }
    }
    /// What the clouds rest on, as one sentence in a spoken answer: the short caption, or with a
    /// full forecast "Includes cloud forecast."; and when the forecasts switch keeps one away, that.
    nonisolated func cloudSentence(forecastsOn: Bool = true) -> String {
        Sentences.join([basisCaption() ?? String(localized: "Includes cloud forecast."), forecastsOff(forecastsOn) ?? ""])
    }
    /// Siri with no screen in view: "Tonight at Arches: 94, Pristine.", smoke that holds the score down
    /// (`smokeCap`), always, since it is why the score is low; and at most one other caveat: the clouds
    /// without a full forecast, else why smoke is not counted (`smokeNote`).
    fileprivate nonisolated func voiceAnswer(_ day: String, smokeCap: String? = nil, smokeNote: String? = nil) -> String {
        let clouds = score.hasForecast ? "" : (basis.isEarlyLook ? String(localized: "An early look at the clouds.") : withTypicalClouds(noForecastSentence ?? ""))
        return Sentences.join([String(localized: "\(day) at \(park.shortName): \(score.value), \(score.band.label)."), smokeCap ?? "", clouds.isEmpty ? smokeNote ?? "" : clouds])
    }
    /// The long form; nil with a forecast: "No cloud forecast yet." or "Cloud forecast
    /// unavailable." (`noForecastSentence`), then what the score uses instead. `typical` adds
    /// "About 8 in 10 … nights here are mostly clear."
    nonisolated func basisCaption(typical: Bool = false) -> String? {
        switch basis {
        case .forecast: return nil
        case .blended: return basis.earlyLookCaption(usualClouds: usualCloud != nil)
        case .usual:
            // Never "Arches's": the park follows the month rather than taking a possessive.
            let line = Sentences.join([noForecastSentence ?? "", usualCloud == nil ? String(localized: "This score counts the Moon and darkness only.")
                : String(localized: "This score uses the usual \(park.monthName(id)) clouds at \(park.shortName).")])
            return typical ? withTypicalClouds(line) : line
        }
    }
}
extension Night {
    // MARK: One wording on every device

    /// A park row's VoiceOver label on the iPhone, Apple Watch and Vision Pro: "Zion. Darkness score
    /// 88, Excellent." then haze or smoke that holds the score down ("Haze or smoke.") and any
    /// closure ("Closure alert: Kolob Canyons Road closed"). `withBasis` says what the clouds rest on
    /// with the band ("Excellent, early look", smoke included), for a row with no other place to say
    /// it (the watch, Vision Pro); the iPhone's rows say it a "More content" swipe away.
    nonisolated func spokenRow(closure: String?, withBasis: Bool = false) -> String {
        let band = withBasis ? bandWithBasis : score.band.label
        let main = Sentences.join([String(localized: "\(park.shortName). Darkness score \(score.value), \(band)."), withBasis ? "" : smokeLabel.map(Sentences.end) ?? ""])
        return Sentences.join([main, closure.map(ClosureLine.spoken) ?? ""])
    }
    /// What VoiceOver says for a night on the iPhone's Tonight widget and the watch's complications,
    /// one wording for both: the place, the score and its band; any closure in full right after the
    /// score it stands beside (a family that shows only its mark still says it); what the clouds rest
    /// on, or "Includes cloud forecast."; and smoke that holds the score down. `ahead`: another night
    /// of the week, said with its date. Each surface adds its own after it.
    nonisolated func widgetSummary(closure: String?, ahead: Bool = false) -> String {
        let lead = ahead ? String(localized: "\(park.shortName), \(park.dayLabel(id)): \(score.value) out of 100, \(score.band.label).")
            : String(localized: "\(park.shortName), \(score.value) out of 100, \(score.band.label).")
        return Sentences.join([lead, closure.map { Sentences.end(ClosureLine.spoken($0)) } ?? "", cloudSentence(), smokeSentence(tonight: !ahead) ?? ""])
    }
}
extension CloudBasis {
    /// An early look's caption, said one way everywhere (`Night.basisCaption`, field mode): the
    /// forecast eased toward the usual clouds, or, where the place has none for the month
    /// (`usualClouds` false), counted as it stands (`NightPlanner.night`). Nil for any other basis.
    nonisolated func earlyLookCaption(usualClouds: Bool) -> String? {
        guard case .blended(_, let lead) = self else { return nil }
        let days = max(1, Int(lead.rounded()))
        return usualClouds ? String(localized: "Early look: forecast \(days) days out, eased toward usual clouds.")
            : String(localized: "Early look: forecast \(days) days out, counted as it stands. There are no usual clouds for this place.")
    }
}

/// Siri's answer about tonight at a place, built once for every device: `DarknessAnswer` on iPhone
/// and iPad, the darkness intent on Vision Pro and on Apple Watch. In order: a closure first, since a
/// long drive to a closed road is the worst outcome Nyx can cause; the score, its band and what its
/// clouds rest on, and to confirm before traveling; smoke that holds the score down, or why smoke is
/// not counted; and why closures are not known, so silence never reads as "nothing is closed".
nonisolated struct TonightAnswer: Sendable {
    let night: Night
    /// The park's closure as Nyx words it beside the score.
    var closure: String? = nil
    /// The clouds' sentence where a device says it its own way (the watch: when its iPhone sent the
    /// forecast); nil for the night's own (`Night.cloudSentence`).
    var clouds: String? = nil
    /// Why smoke is not counted (`ScoreInputs.smokeNote`), said when smoke does not hold the score down.
    var smokeNote: String? = nil
    /// Why a national park's closures are not known (`ScoreInputs.uncheckedNote`): park alerts off,
    /// the Park Service busy, or not checked yet. A place it does not run says so itself (`ClosureLine.unknown`).
    var unchecked: String? = nil
    /// "Cloud forecasts" in Your privacy; off, the answer says why a forecast that should reach the night is missing.
    var forecastsOn = true

    /// `voiceOnly` (iOS 27, no screen in view): the closure, "Tonight at Arches: 94, Pristine.", smoke
    /// that holds the score down, at most one other caveat (the clouds, else why smoke is not counted),
    /// and the closures line, which is never dropped.
    func dialog(voiceOnly: Bool = false) -> String {
        let park = night.park, score = night.score
        let cap = night.smokeSentence(tonight: true), smoke = cap ?? smokeNote
        var parts: [String]
        if night.sky.darkHours == 0 {
            parts = [String(localized: "No true darkness tonight at \(park.shortName). The darkness score is \(score.value) out of 100."), smoke ?? ""]
        } else if voiceOnly {
            parts = [night.voiceAnswer(String(localized: "Tonight"), smokeCap: cap, smokeNote: cap == nil ? smokeNote : nil)]
        } else {
            let clouds = self.clouds ?? night.cloudSentence(forecastsOn: forecastsOn)
            parts = [String(localized: "\(park.shortName): \(score.value) out of 100, \(score.band.label). \(clouds) Confirm conditions and park access before traveling."), smoke ?? ""]
        }
        parts.append(ClosureLine.unknown(park) ?? (closure == nil ? unchecked ?? "" : ""))
        return ClosureLine.first(Sentences.join(parts), closure: closure)
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
        /// month's usual clouds, or "Includes cloud forecast."
        case river
        /// The calendar's list: as `river`, then the night's sky event, under its own key.
        case calendar(event: String?)
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
        /// Siri, the best of the next `count` nights. `noDarkness`: none of them has any true darkness.
        case siriBest(count: Int, voiceOnly: Bool, noDarkness: Bool)
        /// Siri's card, for VoiceOver: the score, the band and the Moon.
        case snippet
    }
    /// Smoke or haze that holds the score down is said wherever the score is said in full; the
    /// styles that say `bandWithBasis` already carry it.
    nonisolated func spokenSummary(_ style: SpokenSummary) -> String {
        let text = spokenText(style)
        switch style {
        case .river, .calendar, .eventNote, .siriBest: return Sentences.join([text, smokeSentence() ?? ""])
        case .chartBest, .dayWithBasis, .scoreWithBasis, .tripLine, .stayNote, .snippet: return text
        }
    }
    private nonisolated func spokenText(_ style: SpokenSummary) -> String {
        switch style {
        case .river:
            let clouds=basisCaption(typical:true) ?? String(localized:"Includes cloud forecast.")
            return String(localized:"\(park.dayLabel(id)), \(score.value) out of 100, \(score.band.label). \(clouds)")
        case .calendar(let event):
            return Sentences.join([String(localized:"\(park.dayLabel(id)), \(score.value) out of 100, \(score.band.label). \(basisCaption(typical:true) ?? String(localized:"Includes cloud forecast."))"),event.map(Sentences.end) ?? ""])
        case .chartBest:
            return String(localized:"Best night: \(park.dayLabel(id)), \(score.value) out of 100, \(score.band.label).")
        case .dayWithBasis:
            return String(localized:"\(park.dayLabel(id)), \(score.value) out of 100, \(bandWithBasis)")
        case .scoreWithBasis:
            return scoreWithBasis
        case .tripLine(let reason):
            return String(localized:"\(park.dayLabel(id)): \(park.shortName), \(score.value) out of 100, \(bandWithBasis). \(reason).")
        case .stayNote(let reason):
            return String(localized:"\(park.dayLabel(id)): darkness score \(score.value) out of 100 (\(bandWithBasis)). \(reason).")
        case .eventNote:
            return score.hasForecast
                ? String(localized:"Darkness score \(score.value) out of 100 (\(score.band.label)), with the cloud forecast as Nyx last saw it.")
                : Sentences.join([String(localized:"Darkness score \(score.value) out of 100 (\(score.band.label))."), basisCaption(typical:true) ?? ""])
        case .siriBest(let count,let voiceOnly,let noDarkness):
            let day=park.programDate(park.isoDay(id))
            if voiceOnly { return voiceAnswer(day) }
            // Said only when no night searched has true darkness; a best night without it among
            // nights that have some is named as the best, as any other.
            if noDarkness { return String(localized:"No true darkness at \(park.shortName) in the next \(count) nights. The best is \(day), \(score.value) out of 100.") }
            let basis=basisCaption(typical:true) ?? String(localized:"Includes cloud forecast.")
            return String(localized:"The best of the next \(count) nights: \(day) at \(park.shortName), \(score.value) out of 100, \(score.band.label). \(basis) Confirm conditions and park access before traveling.")
        case .snippet:
            return String(localized:"\(park.shortName) tonight: \(score.value) out of 100, \(bandWithBasis). \(sky.moon.name), \(sky.moon.percentLit) percent lit.")
        }
    }
}
/// How the early looks shown treat their forecast (`NightPlanner.night`): eased toward the usual
/// clouds, counted as it stands where a place has no usual clouds for the month, or both. One
/// source for the calendar's key and the trip planner's note. Nil when no night is given.
nonisolated struct EarlyLookNote: Equatable, Sendable {
    let eased: Bool, asItStands: Bool
    init?(_ nights: [Night]) {
        guard !nights.isEmpty else { return nil }
        eased=nights.contains { $0.usualCloud != nil }; asItStands=nights.contains { $0.usualCloud == nil }
    }
}
/// What the nights shown on the usual clouds rest on, in the rows' own words: "not yet" or
/// "unavailable" as `basisLabel` says it (`beyondForecast`), the usual clouds or the Moon and
/// darkness only as `basisCaption` says it (`usualCloud`). One source for the note under a list
/// ("Scores marked Estimate: …", where such a row reads "Estimate") and a month's key ("Hollow: …").
/// Nil when no night shown rests on the usual clouds, so nothing is explained that no row shows.
nonisolated struct UsualCloudsNote: Equatable, Sendable {
    let notYet: Bool, unavailable: Bool, usual: Bool, bare: Bool
    init?(_ nights: [Night]) {
        let shown=nights.filter { $0.basis == .usual }
        guard !shown.isEmpty else { return nil }
        notYet=shown.contains { $0.beyondForecast }; unavailable=shown.contains { !$0.beyondForecast }
        usual=shown.contains { $0.usualCloud != nil }; bare=shown.contains { $0.usualCloud == nil }
    }
    /// "cloud forecast unavailable", "no cloud forecast yet", or both.
    var label: String {
        switch (notYet, unavailable) {
        case (true, true): String(localized:"no cloud forecast yet, or unavailable")
        case (true, false): String(localized:"no cloud forecast yet")
        default: String(localized:"cloud forecast unavailable")
        }
    }
    /// Under a list of places' scores (Tonight, Parks, the map).
    var estimate: String {
        switch (usual, bare) {
        case (true, true): String(localized:"Scores marked Estimate: \(label). They use each park's usual clouds, or the Moon and darkness only where those are not known.")
        case (true, false): String(localized:"Scores marked Estimate: \(label). They use each park's usual clouds.")
        default: String(localized:"Scores marked Estimate: \(label). They count the Moon and darkness only.")
        }
    }
    /// One place's nights drawn hollow (the calendar's key, the river's tip).
    var hollow: String {
        switch (usual, bare) {
        case (true, true): String(localized:"Hollow: \(label). Nyx uses the park's usual clouds, or only the Moon and darkness where those are not known.")
        case (true, false): String(localized:"Hollow: \(label). Nyx uses the park's usual clouds.")
        default: String(localized:"Hollow: \(label). Nyx uses only the Moon and darkness.")
        }
    }
    /// The rows' own marks (`basisLabel`), quoted as the language quotes: "No cloud forecast yet",
    /// "Cloud forecast unavailable", or both.
    var marks: String {
        let yet=Self.quoted(String(localized:"No cloud forecast yet")), unavailable=Self.quoted(String(localized:"Cloud forecast unavailable"))
        switch (notYet, self.unavailable) {
        case (true, true): return String(localized:"\(yet) or \(unavailable)")
        case (true, false): return yet
        default: return unavailable
        }
    }
    private static func quoted(_ mark: String) -> String { String(localized:"\"\(mark)\"") }
    /// Under a list whose rows name each night's mark (the trip planner's stays).
    var marked: String {
        switch (usual, bare) {
        case (true, true): String(localized:"Nights marked \(marks) count each park's usual clouds for the month, or the Moon and darkness only where those are not known.")
        case (true, false): String(localized:"Nights marked \(marks) count each park's usual clouds for the month.")
        default: String(localized:"Nights marked \(marks) count the Moon and darkness only.")
        }
    }
    /// The trip planner's note: each mark its stays show (`basisLabel`, "Early look" included) and
    /// what those nights count (an early look eases its forecast toward the usual clouds, or counts
    /// it as it stands where none are known, `EarlyLookNote`); nil when every night has a full forecast.
    /// `unmarked`: a stay's other nights, whose scores its row lists without their marks; when one of
    /// them leans on the usual clouds, the note says so without naming a mark no row shows.
    static func trip(_ nights: [Night], unmarked: [Night] = []) -> String? {
        let mark=quoted(String(localized:"Early look")), note=EarlyLookNote(nights.filter { $0.basis.isEarlyLook })
        let early:String?=switch (note?.eased,note?.asItStands) {
        case (true?,true?): String(localized:"Nights marked \(mark) ease the forecast toward each park's usual clouds for the month, or count it as it stands where those are not known.")
        case (false?,true?): String(localized:"Nights marked \(mark) count the forecast as it stands: there are no usual clouds for those places.")
        case (true?,_): String(localized:"Nights marked \(mark) ease the forecast toward each park's usual clouds for the month.")
        default: nil
        }
        // An early look with no usual clouds counts its forecast as it stands: it leans on none.
        let others=unmarked.contains { $0.basis != .forecast && $0.usualCloud != nil }
            ? String(localized:"In a stay of several nights, nights the forecast does not fully reach lean on each park's usual clouds for the month.") : nil
        let parts=[UsualCloudsNote(nights)?.marked, early, others].compactMap { $0 }
        return parts.isEmpty ? nil : Sentences.join(parts)
    }
}
#endif
