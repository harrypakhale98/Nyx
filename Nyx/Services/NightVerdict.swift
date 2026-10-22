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
    /// A darker night counts only this many points above the one shown, and from "Good" up.
    static let darkerMargin=10
    static let darkerFloor=60
    /// A Moon-free stretch of the core shorter than this is said as brief.
    static let briefCore: TimeInterval=1800

    static func line(sky: SkyConditions, core: SkyAlmanac.CoreNight, park: Park, darker: Night?=nil) -> Line? {
        guard sky.darkHours>0 else { return nil }
        let moon=moonSentence(sky: sky, park: park)
        let milkyWay=coreSentence(core, sky: sky, park: park)
        let ahead=darker.map { String(localized: "Darker on \($0.park.dayLabel($0.id)): \($0.score.value).") }
        let text=Sentences.join([moon, milkyWay?.text, ahead].compactMap { $0 })
        let spoken=Sentences.join([moon, milkyWay?.spoken, ahead].compactMap { $0 })
        return text.isEmpty ? nil : Line(text: text, spoken: spoken)
    }
    /// Where the Moon is during true darkness, with how much of it is lit.
    static func moonSentence(sky: SkyConditions, park: Park) -> String? {
        let lit=sky.moon.illumination.formatted(.percent.precision(.fractionLength(0)))
        if sky.moon.illumination<0.05 || sky.moonBelowFraction>=0.99 { return String(localized: "No Moon in the way.") }
        if sky.moonBelowFraction<=0.01 { return String(localized: "Moon up all night, \(lit) lit.") }
        guard let start=sky.darkStart, let end=sky.darkEnd else { return nil }
        let dark=DateInterval(start: start, end: max(start, end))
        if let set=sky.moonset, dark.contains(set) { return String(localized: "Moon up until \(park.time(set)), \(lit) lit.") }
        if let rise=sky.moonrise, dark.contains(rise) { return String(localized: "Moon rises at \(park.time(rise)), \(lit) lit.") }
        return nil
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
            return Line(text: String(localized: "Milky Way core with the Moon down, \(park.time(free.start)) – \(park.time(free.end))."),
                        spoken: String(localized: "Milky Way core with the Moon down from \(park.time(free.start)) to \(park.time(free.end))."))
        }
        if let dark=core.dark {
            let text=dark.duration<3600 ? String(localized: "Milky Way core only briefly, under the Moon.") : String(localized: "Milky Way core up, but under the Moon.")
            return Line(text: text, spoken: text)
        }
        let text=String(localized: "Milky Way core not up in true darkness.")
        return Line(text: text, spoken: text)
    }
    /// The darkest of the nights ahead when it clears the one shown by `darkerMargin` and reaches
    /// "Good"; the earliest on a tie.
    static func darker(than night: Night, among ahead: [Night]) -> Night? {
        let best=ahead.filter { $0.id>night.id }.max { a, b in a.score.value != b.score.value ? a.score.value<b.score.value : a.id>b.id }
        guard let best, best.score.value>=night.score.value+darkerMargin, best.score.value>=darkerFloor else { return nil }
        return best
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
