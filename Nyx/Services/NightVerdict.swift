import Foundation

/// The night in one or two plain sentences under the dial, from facts already worked out for it:
/// where the Moon is during true darkness, whether the Milky Way's core is up and clear of it, and
/// (on a park's page) a clearly darker night soon at the same place. Nothing here is new data; it
/// only says first what the page says further down, so a "Good" night poor for the Milky Way never
/// reads as a promise. Nil when there is no true darkness (the hero says that on its own).
nonisolated enum NightVerdict {
    struct Line: Equatable {
        let text: String
        /// The same, with ranges read as "from … to …".
        let spoken: String
    }
    /// A darker night counts only this many points above the one shown, and from "Good" up: one rule
    /// for the park page and for Tonight, so the two never name "darker" nights by different measures.
    static let darkerMargin=10
    static let darkerFloor=ScoreBand.good.minimum
    /// Whether `ahead` clears `night` by the margin and reaches the floor.
    static func clearlyDarker(_ ahead: Night, than night: Night) -> Bool {
        ahead.score.value>=night.score.value+darkerMargin && ahead.score.value>=darkerFloor
    }
    /// A Moon-free stretch of the core shorter than this is said as brief.
    static let briefCore: TimeInterval=1800

    static func line(sky: SkyConditions, core: SkyAlmanac.CoreNight, park: Park, darker: Night?=nil) -> Line? {
        guard sky.darkHours>0 else { return nil }
        let moon=sky.moonSentence(park: park)
        let milkyWay=coreSentence(core, sky: sky, park: park)
        // In the capsule's own words (`capsule`), so "Darker on…" is said one way wherever it is said.
        let ahead=darker.map { Sentences.end(capsule($0, here: true)) }
        let text=Sentences.join([moon, milkyWay?.text, ahead].compactMap { $0 })
        let spoken=Sentences.join([moon, milkyWay?.spoken, ahead].compactMap { $0 })
        return text.isEmpty ? nil : Line(text: text, spoken: spoken)
    }
    /// The core in true darkness: its Moon-free stretch, briefly, under the Moon, or not up at all.
    /// Nil where the core is never usefully up (far north), as What's up explains it there.
    static func coreSentence(_ core: SkyAlmanac.CoreNight, sky: SkyConditions, park: Park) -> Line? {
        guard core.peakPossible>=3, !core.neverUp else { return nil }
        if let free=core.moonFree {
            if free.duration<briefCore {
                let text=String(localized: "Milky Way core only briefly.")
                return Line(text: text, spoken: text)
            }
            return Line(text: String(localized: "Milky Way core clear of moonlight, \(park.time(free.start)) – \(park.time(free.end))."),
                        spoken: String(localized: "Milky Way core clear of moonlight from \(park.time(free.start)) to \(park.time(free.end))."))
        }
        if let dark=core.dark {
            let text=dark.duration<3600 ? String(localized: "Milky Way core only briefly, under the Moon.") : String(localized: "Milky Way core up, but under the Moon.")
            return Line(text: text, spoken: text)
        }
        let text=String(localized: "Milky Way core not up in true darkness.")
        return Line(text: text, spoken: text)
    }
    /// A night's score as a line may name it, with what it rests on in the words every list uses
    /// (`DarknessScore.withBasis`): "82" on a full forecast, "82, early look", "82, usual clouds" (or
    /// "82, Moon and darkness only" where the place has no usual clouds), and ", haze or smoke" when
    /// smoke holds it down. A later night is never set beside tonight's as if both were forecasts.
    static func scored(_ night: Night) -> String { night.score.withBasis(String(night.score.value)) }
    /// The park page's "Darker on…": the place's best night (`best` over its nights from tonight),
    /// when it falls after the night shown, clears it by `darkerMargin` and reaches "Good". Never a
    /// nearer night that is merely darker than this one, so the page and every list name one night.
    static func darker(than night: Night, among nights: [Night]) -> Night? {
        guard let best=NightPlanner.best(nights), best.id>night.id, clearlyDarker(best,than:night) else { return nil }
        return best
    }
    /// Tonight's "Darker on…" under the answer: first the answer's own park, its best night by the
    /// park page's rule (`darker`), so the capsule and that page name the same night; otherwise the
    /// best night across the places in reach as Best nights ranks them (`BestNightsInReach.make`, a
    /// closure counting against its park), when it clears tonight's answer by the same margin.
    /// `here`: the answer's park's nights from tonight; `across`: each place's nights from tonight.
    static func darkerAhead(than tonight: Night, here: [Night], across: [[Night]], closures: [String: String]) -> Night? {
        if let own=darker(than: tonight, among: here) { return own }
        // The answer's park leading here is a night already turned down above (none clears tonight).
        guard let best=BestNightsInReach.make(across, closures: closures, limit: 1).best, best.park.id != tonight.park.id, clearlyDarker(best, than: tonight) else { return nil }
        return best
    }
    /// The capsule under a dial, Tonight's and a park page's, two short lines: when, then where and
    /// how dark ("Darker on Mon, Nov 2" / "Anza-Borrego Desert State Park · 77, usual clouds"). At the
    /// answer's own park the place goes unsaid: the name is right above ("Darker on Thu, Nov 5 · 80").
    static func capsule(_ night: Night, here: Bool) -> String {
        let when=String(localized: "Darker on \(night.park.dayLabel(night.id))")
        return here ? "\(when) · \(scored(night))" : "\(when)\n\(night.park.shortName) · \(scored(night))"
    }
}

/// How sure the forecast is, said one way under every dial for the same night: the models' cloud
/// spread when they disagree (it says what to do), else the range of scores they give.
nonisolated enum ForecastSpread {
    static func line(agreement: ModelAgreement?, range: ClosedRange<Int>?, tonight: Bool) -> String? {
        if let agreement, agreement.band == .disagree { return agreement.sentence(tonight: tonight) }
        return range.map(ShareCard.rangeLine)
    }
}
