import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Where Apple Watch's dial (`WatchGauge`) puts its numeral and band word: the word sits under the
/// numeral, inside an arc open at the bottom, and must never touch a tick or the track. Worked out
/// from the fonts' real metrics rather than by trial, so the word is never drawn across the ticks
/// and never dropped while a smaller numeral would make room for it. Pure geometry, shared with
/// the tests; points, measured downward from the dial's centre.
nonisolated enum WatchDialFace {
    /// One line of text at its full size: what the layout needs to know of it.
    struct Line: Equatable, Sendable {
        var height: Double
        /// Baseline below the line's top.
        var ascent: Double
        /// The tallest glyph above the baseline.
        var cap: Double
        /// How far glyphs reach below the baseline (0 for a word without descenders).
        var drop: Double
        var width: Double
        func scaled(_ k: Double) -> Line { Line(height: height*k, ascent: ascent*k, cap: cap*k, drop: drop*k, width: width*k) }
    }
    /// The numeral's and the word's sizes, as fractions of their full sizes; `word` nil leaves the
    /// numeral alone on the dial.
    struct Choice: Equatable, Sendable {
        var numeral: Double
        var word: Double?
    }
    /// The arc as `WatchGauge` draws it: from 140° through 260°, ticks every tenth, with room for
    /// the glow outside the track.
    static let start = 140.0, sweep = 260.0
    static func radius(side: Double) -> Double { side/2 - 10 }
    /// Proportions of the face, as `WatchGauge` lays it out.
    static func numeralSize(side: Double) -> Double { side*0.36 }
    static func wordSize(side: Double) -> Double { max(10, side*0.11) }
    static func spacing(side: Double) -> Double { -side*0.02 }
    static func lift(side: Double) -> Double { side*0.045 }
    /// The word is never set smaller than this.
    static let smallestWord = 8.5
    /// In order of preference: the numeral is the dial's face, so the word gives way first, then
    /// both a little.
    static let choices: [Choice] = [Choice(numeral: 1, word: 1), Choice(numeral: 1, word: 0.85), Choice(numeral: 0.85, word: 0.85),
                                    Choice(numeral: 0.72, word: 0.85), Choice(numeral: 0.85, word: 0.72), Choice(numeral: 0.72, word: 0.72)]

    /// The widest a centred word may be between `top` and `foot` and still clear every tick by a
    /// point and stay 2 pt inside the track.
    static func clearWidth(side: Double, top: Double, foot: Double) -> Double {
        let r = radius(side: side)
        let far = max(abs(top), abs(foot))
        guard far < r-2 else { return 0 }
        var half = ((r-2)*(r-2) - far*far).squareRoot()
        for tick in 0...10 {
            let angle = (start + Double(tick)*sweep/10) * .pi/180
            let inner = r - (tick%5 == 0 ? 10 : 8), outer = r - 5
            let s = sin(angle), c = abs(cos(angle))
            // The tick is radial: the part of it level with the word is what the word must clear.
            let near: Double
            if abs(s) < 1e-9 {
                guard top-1 <= 0, 0 <= foot+1 else { continue }
                near = inner
            } else {
                let a = (top-1)/s, b = (foot+1)/s
                let from = max(inner, min(a, b)), to = min(outer, max(a, b))
                guard from <= to else { continue }
                near = from
            }
            half = min(half, near*c - 1)
        }
        return max(0, 2*half)
    }
    /// Where the word's glyphs reach, top and foot, for this choice.
    static func wordSpan(side: Double, numeral: Line, word: Line, choice: Choice) -> (top: Double, foot: Double) {
        let n = numeral.scaled(choice.numeral), w = word.scaled(choice.word ?? 0)
        let stack = n.height + spacing(side: side) + w.height
        let lineTop = -lift(side: side) - stack/2 + n.height + spacing(side: side)
        let baseline = lineTop + w.ascent
        return (baseline - w.cap, baseline + max(0.5, w.drop))
    }
    /// The first choice whose word fits: clear of the ticks and the track, inside the face's side
    /// margins, above the Moon and no smaller than `smallestWord`. Else the numeral alone.
    static func choose(side: Double, numeral: Line, word: Line, wordSize: Double) -> Choice {
        for choice in choices {
            guard let k = choice.word, wordSize*k >= smallestWord - 0.001 else { continue }
            let span = wordSpan(side: side, numeral: numeral, word: word, choice: choice)
            let width = word.width*k
            if span.foot <= side*0.31, width <= side*0.68, width <= clearWidth(side: side, top: span.top, foot: span.foot) { return choice }
        }
        return Choice(numeral: 1, word: nil)
    }
}

#if canImport(UIKit)
nonisolated extension WatchDialFace.Line {
    /// A line of New York (the system serif) as SwiftUI sets it, from the font's own metrics, a
    /// little wider than measured to allow for rendering. With Bold Text on, SwiftUI draws the next
    /// weight up, and so is the word measured.
    static func serif(_ text: String, size: Double, weight: UIFont.Weight, bold: Bool) -> Self {
        let heavier: UIFont.Weight = !bold ? weight : weight == .light ? .regular : weight == .regular ? .semibold : .bold
        let system = UIFont.systemFont(ofSize: size, weight: heavier)
        let font = system.fontDescriptor.withDesign(.serif).map { UIFont(descriptor: $0, size: size) } ?? system
        let width = (text as NSString).size(withAttributes: [.font: font]).width
        let descends = text.rangeOfCharacter(from: CharacterSet(charactersIn: "gjpqyQ,")) != nil
        // Accented capitals ("Prístino" has none, but a translation might) reach above the cap height.
        let cap = max(font.capHeight, font.ascender*0.8)
        return Self(height: font.lineHeight, ascent: font.ascender, cap: cap, drop: descends ? -font.descender*0.85 : 0, width: width*1.04 + 1)
    }
}
#endif

/// Which layout Apple Watch's Tonight face takes. At the standard text sizes (each watch's
/// default and below, `largestStandard`) the face never scrolls: the dial takes what the words
/// leave, as it always has. At accessibility sizes it always scrolls. In between, the words keep every line whole (wrapped, never shrunk or cut)
/// and the face stays fixed only while the dial keeps at least `dialMinimum` points; otherwise it
/// scrolls, so a large text size on the smallest watch never collapses the instrument.
nonisolated enum WatchTonightLayout: Equatable, Sendable {
    case fixed
    case scrolling
    /// The largest of the standard sizes on a screen this wide (points): each watch's default
    /// text size, Extra Large on the widest (the Ultra's 205) and Large on the others (the 40 mm's
    /// 162). Up to it the face stays exactly as designed.
    static func largestStandard(screenWidth: Double) -> DynamicTypeSize {
        screenWidth >= 200 ? .xLarge : .large
    }
    /// The smallest dial that still reads as the instrument: numeral, band word and Moon.
    static let dialMinimum = 80.0
    /// The dial of the scrolling face at the large sizes: the instrument whole, with the first
    /// words under it on the first screen of the smallest watch.
    static let scrollingDial = 96.0
    /// The gap between the dial and the words under it.
    static let spacing = 3.0
    /// `room`: the face's height; `words`: the height of the words under the dial with every line
    /// whole. Either still 0 means not yet measured, and the face stays fixed until it is.
    static func choose(room: Double, words: Double, standardSize: Bool, accessibilitySize: Bool) -> Self {
        if accessibilitySize { return .scrolling }
        if standardSize || room <= 0 || words <= 0 { return .fixed }
        return room - words - spacing >= dialMinimum ? .fixed : .scrolling
    }
}
