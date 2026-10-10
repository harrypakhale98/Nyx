import Foundation
import Testing
@testable import Nyx

/// Apple Watch's dial face (`WatchDialFace`): the band word clears every tick, gives way before
/// the numeral does, and is dropped only where no smaller setting can clear the ticks.
struct WatchDialFaceTests {
    typealias Face = WatchDialFace
    /// The end ticks (at 140° and 40°) run from radius − 10 to radius − 5.
    func endTick(side: Double) -> (top: Double, bottom: Double, x: Double) {
        let r = Face.radius(side: side), s = sin(40 * Double.pi/180), c = cos(40 * Double.pi/180)
        return ((r-10)*s, (r-5)*s, (r-10)*c)
    }

    @Test func aWordLevelWithTheEndTicksStaysBetweenThem() {
        let side = 120.0, tick = endTick(side: side)
        let width = Face.clearWidth(side: side, top: tick.top - 4, foot: tick.top + 1)
        #expect(abs(width - 2*(tick.x - 1)) < 0.001)
    }
    @Test func aWordAboveTheEndTicksMayBeWider() {
        let side = 120.0, tick = endTick(side: side)
        let level = Face.clearWidth(side: side, top: tick.top - 8, foot: tick.top + 1)
        let above = Face.clearWidth(side: side, top: tick.top - 12, foot: tick.top - 3)
        #expect(above > level + 4)
        // Still inside the track.
        #expect(above < 2*Face.radius(side: side))
    }
    @Test func nothingFitsOutsideTheTrack() {
        #expect(Face.clearWidth(side: 100, top: 30, foot: 45) == 0)
    }
    @Test func theRoomShrinksTowardTheEndTicks() {
        // Below the ticks at either side of the centre, a lower word meets the end ticks: the room
        // never grows as the word moves down.
        var last = Double.infinity
        for foot in stride(from: 26.0, through: 40, by: 1) {
            let width = Face.clearWidth(side: 140, top: foot - 10, foot: foot)
            #expect(width <= last + 0.001, "foot \(foot)")
            last = width
        }
    }

    /// Metrics close to New York's: line 1.2 em, ascent 0.95 em, caps 0.7 em, a word about 4.5 em wide.
    func lines(side: Double, wordEm: Double = 4.5) -> (numeral: Face.Line, word: Face.Line) {
        let n = Face.numeralSize(side: side), w = Face.wordSize(side: side)
        return (Face.Line(height: n*1.2, ascent: n*0.95, cap: n*0.7, drop: 0, width: n*1.2),
                Face.Line(height: w*1.2, ascent: w*0.95, cap: w*0.76, drop: 0, width: w*wordEm))
    }
    @Test func aLargeDialKeepsBothAtFullSize() {
        let side = 170.0, l = lines(side: side)
        #expect(Face.choose(side: side, numeral: l.numeral, word: l.word, wordSize: Face.wordSize(side: side)) == .init(numeral: 1, word: 1))
    }
    @Test func aSmallDialKeepsTheWordBySettingBothSmaller() {
        // A dial shrunk by a long glance (Spanish on a small watch): the word survives.
        let side = 92.0, l = lines(side: side)
        let choice = Face.choose(side: side, numeral: l.numeral, word: l.word, wordSize: Face.wordSize(side: side))
        let word = choice.word
        #expect(word != nil)
        #expect(choice.numeral < 1)
        // And whatever is chosen clears the ticks.
        let span = Face.wordSpan(side: side, numeral: l.numeral, word: l.word, choice: choice)
        #expect(l.word.width*(word ?? 0) <= Face.clearWidth(side: side, top: span.top, foot: span.foot))
    }
    @Test func theWordGivesWayBeforeTheNumeral() {
        // Every choice that shrinks the numeral comes after one that shrinks only the word.
        let first = Face.choices.firstIndex { $0.numeral < 1 } ?? Face.choices.count
        #expect(Face.choices[..<first].contains { ($0.word ?? 1) < 1 })
        #expect(Face.choices.first == .init(numeral: 1, word: 1))
    }
    @Test func aWordNoSmallerSettingCanClearLeavesTheNumeralAlone() {
        let side = 60.0, l = lines(side: side, wordEm: 9)
        #expect(Face.choose(side: side, numeral: l.numeral, word: l.word, wordSize: Face.wordSize(side: side)) == .init(numeral: 1, word: nil))
    }
    @Test func theWordIsNeverSetBelowTheSmallestSize() {
        // A word size of 10 allows 85 % (8.5 pt) but not 72 %.
        for side in stride(from: 50.0, through: 180, by: 5) {
            let l = lines(side: side)
            let size = Face.wordSize(side: side)
            if let k = Face.choose(side: side, numeral: l.numeral, word: l.word, wordSize: size).word { #expect(size*k >= Face.smallestWord - 0.001) }
        }
    }
    @Test func realFontMetricsAreSane() {
        let word = Face.Line.serif("Excelente", size: 12, weight: .regular, bold: false)
        let bold = Face.Line.serif("Excelente", size: 12, weight: .regular, bold: true)
        #expect(word.height > 12 && word.height < 20)
        #expect(word.cap > 6 && word.cap < word.ascent + 0.001)
        #expect(word.drop == 0 && word.width > 30)
        #expect(bold.width >= word.width)
        #expect(Face.Line.serif("Regular", size: 12, weight: .regular, bold: false).drop > 0)
    }
}
