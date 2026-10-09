import Foundation
import Testing
@testable import Nyx

/// The score reveal: one plan for every way a dial can be asked to show a score, the session's
/// memory of reveals already seen, an interrupted count that still ends with its word, the model
/// range drawn only where it is honest, and the rim that thins with a small dial.
@MainActor @Suite(.serialized) struct GaugeRevealTests {
    typealias Plan=CelestialGauge.RevealPlan
    func plan(seen:Bool=false,held:Bool=false,reduceMotion:Bool=false,export:Bool=false,revealed:Bool=false)->Plan {
        CelestialGauge.plan(seen:seen,held:held,reduceMotion:reduceMotion,export:export,alreadyRevealed:revealed)
    }

    // MARK: Plan

    @Test func anUnseenScoreInFrontOfThePersonCountsUp() {
        #expect(plan() == .odometer)
    }
    @Test func anUnseenScoreWaitsWhileHeld() {
        #expect(plan(held:true) == .hold)
    }
    @Test func aSeenScoreSettlesEvenWhileHeld() {
        #expect(plan(seen:true) == .settle)
        #expect(plan(seen:true,held:true) == .settle)
    }
    @Test func reduceMotionAndExportShowTheScoreAtOnceAndIgnoreTheHold() {
        for held in [false,true] {
            for seen in [false,true] {
                #expect(plan(seen:seen,held:held,reduceMotion:true) == .instant)
                #expect(plan(seen:seen,held:held,export:true) == .instant)
                #expect(plan(seen:seen,held:held,reduceMotion:true,revealed:true) == .instant)
            }
        }
    }
    @Test func aDialThatAnsweredOnceSweepsAndNeverBlanks() {
        // Control Center pulled down over a settled dial must not empty it.
        #expect(plan(held:true,revealed:true) == .sweep)
        #expect(plan(seen:true,revealed:true) == .sweep)
    }

    // MARK: Interrupted counts

    @Test func aScoreChangeMidCountSweepsToTheNewScoreWithItsWord() {
        // Cached 81, computed 97: the count for 81 was under way.
        #expect(CelestialGauge.alreadyRevealed(revealedOnce:false,countedScore:81,score:97))
        let next=plan(revealed:CelestialGauge.alreadyRevealed(revealedOnce:false,countedScore:81,score:97))
        #expect(next == .sweep)
    }
    @Test func theSameScoreAfterAHoldCountsAgainFromTheStart() {
        // The count was cut short by the hold (or the dial leaving the screen) and never landed.
        #expect(!CelestialGauge.alreadyRevealed(revealedOnce:false,countedScore:97,score:97))
        #expect(!CelestialGauge.alreadyRevealed(revealedOnce:false,countedScore:nil,score:97))
        #expect(CelestialGauge.alreadyRevealed(revealedOnce:true,countedScore:nil,score:97))
    }
    typealias Face=CelestialGauge.Face
    @Test func everyPlanButTheCountEndsOnTheWholeAnswer() {
        for score in [0,23,59,60,74,75,89,90,97,100] {
            for plan:Plan in [.instant,.sweep,.settle] { #expect(CelestialGauge.face(after:plan,score:score) == .answer(score)) }
            #expect(CelestialGauge.face(after:.hold,score:score) == .empty)
            #expect(CelestialGauge.face(after:.odometer,score:score) == .empty)
            #expect(Face.answer(score).settled && Face.answer(score).shown==score && Face.answer(score).arc==Double(score))
        }
    }
    @Test func aCountCutShortWithNothingAfterItEndsOnTheWholeAnswer() {
        // Counting 97, at 51: the dial scrolls away and no reveal follows.
        let midCount=Face(arc:53,shown:51,settled:false)
        #expect(CelestialGauge.cancelled(midCount,score:97,generation:4,mine:4) == .answer(97))
    }
    /// SwiftUI cancels the old count and starts the next reveal at once; the old count's cleanup
    /// can run on either side of it. Cached 81 overtaken by a computed 97, both orders.
    @Test func anOvertakenCountEndsOnTheNewScoreWithItsWordInEitherOrder() {
        let midCount=Face(arc:53,shown:51,settled:false)
        let sweep=plan(revealed:CelestialGauge.alreadyRevealed(revealedOnce:false,countedScore:81,score:97))
        #expect(sweep == .sweep)
        // The cleanup first, while the old count is still the latest (generation 4)…
        var face=CelestialGauge.cancelled(midCount,score:81,generation:4,mine:4)
        // …then the new reveal (generation 5) writes its own answer.
        face=CelestialGauge.face(after:sweep,score:97)
        #expect(face == .answer(97))
        // The new reveal first, then the old count's cleanup: it must not write 81 back.
        face=CelestialGauge.face(after:sweep,score:97)
        face=CelestialGauge.cancelled(face,score:81,generation:5,mine:4)
        #expect(face == .answer(97))
        #expect(face.settled && face.shown==97)
    }
    @Test func aHoldAfterACountLeavesTheDialEmptyInEitherOrder() {
        // The same score, held mid-count (another tab): the dial waits empty, word and all.
        let midCount=Face(arc:53,shown:51,settled:false)
        let held=plan(held:true,revealed:CelestialGauge.alreadyRevealed(revealedOnce:false,countedScore:nil,score:97))
        #expect(held == .hold)
        var face=CelestialGauge.cancelled(midCount,score:97,generation:4,mine:4)
        face=CelestialGauge.face(after:held,score:97)
        #expect(face == .empty)
        face=CelestialGauge.face(after:held,score:97)
        face=CelestialGauge.cancelled(face,score:97,generation:5,mine:4)
        #expect(face == .empty)
    }

    // MARK: Session memory

    @Test func onlyALandedCountUpMarksItsKey() {
        let key=ScoreReveals.key(parkID:"test-only",night:"2026-10-08",score:97)
        ScoreReveals.seen.remove(key)
        defer { ScoreReveals.seen.remove(key) }
        ScoreReveals.note(key,plan:.odometer,landed:false)
        ScoreReveals.note(key,plan:.hold,landed:false)
        ScoreReveals.note(key,plan:.sweep,landed:true)
        ScoreReveals.note(key,plan:.settle,landed:true)
        ScoreReveals.note(key,plan:.instant,landed:true)
        #expect(!ScoreReveals.seen.contains(key))
        ScoreReveals.note(key,plan:.odometer,landed:true)
        #expect(ScoreReveals.seen.contains(key))
        ScoreReveals.note(nil,plan:.odometer,landed:true)
    }
    @Test func keysSeparateParkNightAndScore() {
        let a=ScoreReveals.key(parkID:"deva",night:"2026-10-08",score:97)
        #expect(a=="deva|2026-10-08|97")
        #expect(a != ScoreReveals.key(parkID:"deva",night:"2026-10-08",score:96))
        #expect(a != ScoreReveals.key(parkID:"deva",night:"2026-10-09",score:97))
        #expect(a != ScoreReveals.key(parkID:"jotr",night:"2026-10-08",score:97))
    }

    // MARK: Model range

    func outlook(_ range:ClosedRange<Int>?,cloud:(Double,Double)?=(10,60))->NightOutlook {
        NightOutlook(agreement:cloud.map { ModelAgreement(low:$0.0,high:$0.1) },scoreRange:range)
    }
    @Test func theDialDrawsTheOutlooksOwnRange() {
        // The outlook already holds the score (`PlanModel.outlook`); the dial draws it unchanged,
        // so the dial, the time river and VoiceOver give one range.
        #expect(CelestialGauge.modelRange(outlook(70...84),basis:.forecast)==70...84)
        #expect(CelestialGauge.modelRange(outlook(60...90,cloud:(10,40)),basis:.forecast)==60...90)
    }
    @Test func aSpreadOfFourOrLessIsNotDrawn() {
        #expect(CelestialGauge.modelRange(outlook(78...82),basis:.forecast)==nil)
        #expect(CelestialGauge.modelRange(outlook(80...80),basis:.forecast)==nil)
        #expect(CelestialGauge.modelRange(outlook(77...82),basis:.forecast)==77...82)
    }
    @Test func modelsThatAgreeDrawNoRange() {
        // The river and the Clouds tile say "Forecast models agree" at 15 points of cloud or less;
        // the dial must not then show a 13-point spread of scores.
        #expect(CelestialGauge.modelRange(outlook(78...91,cloud:(0,15)),basis:.forecast)==nil)
        #expect(CelestialGauge.modelRange(outlook(78...91,cloud:(0,16)),basis:.forecast)==78...91)
        #expect(CelestialGauge.modelRange(outlook(78...91,cloud:nil),basis:.forecast)==nil)
    }
    @Test func onlyAFullForecastShowsTheRange() {
        #expect(CelestialGauge.modelRange(outlook(60...90),basis:.usual)==nil)
        #expect(CelestialGauge.modelRange(outlook(60...90),basis:.blended(weight:0.6,leadDays:5))==nil)
        #expect(CelestialGauge.modelRange(outlook(nil),basis:.forecast)==nil)
        #expect(CelestialGauge.modelRange(nil,basis:.forecast)==nil)
        #expect(CelestialGauge.modelRange(outlook(60...90),basis:.forecast)==60...90)
    }

    // MARK: The rim

    @Test func theRimThinsWithASmallDialButNeverBelowSixteen() {
        #expect(DialMetrics.ringWidth(side:300)==26)
        #expect(DialMetrics.ringWidth(side:354)==26)
        #expect(DialMetrics.ringWidth(side:188)>=16 && DialMetrics.ringWidth(side:188)<26)
        #expect(DialMetrics.ringWidth(side:120)==16)
        #expect(DialMetrics.inset(side:300)==18)
        #expect(abs(DialMetrics.inset(side:150)-9)<0.001)
    }
    /// Half the diagonal of a two-digit numeral's box (each digit about 0.55 em wide, cap height
    /// about 0.7 em), measured from the dial's centre.
    func corner(_ numeral:Double)->Double { let w=numeral*0.55, h=numeral*0.35; return (w*w+h*h).squareRoot() }
    func innerTick(_ side:Double)->Double { side/2-DialMetrics.inset(side:side)-17*DialMetrics.scale(side:side) }
    @Test func theSmallDialsNumeralClearsItsTicks() {
        for side in [176.0,188,240,300] { #expect(corner(side*0.36)<innerTick(side)) }
    }
    @Test func theAccessibleDialStillClearsItsNumeral() {
        for band in [20.0,28,40,53] {
            let side=CelestialGauge.accessibleSide(band:band,width:345)
            #expect(corner(CelestialGauge.accessibleNumeral(band:band,side:side))<innerTick(side))
        }
        #expect(corner(CelestialGauge.accessibleNumeral(band:53,side:160))<innerTick(160))
    }

    // MARK: A sweep moves as one

    @Test func aSweepKeepsTheOldWordUntilTheArcLands() {
        for plan:Plan in [.sweep,.settle] {
            #expect(CelestialGauge.bandShown(plan:plan,previous:.excellent,target:.pristine,completed:false) == .excellent)
            #expect(CelestialGauge.bandShown(plan:plan,previous:.excellent,target:.pristine,completed:true) == .pristine)
        }
    }
    @Test func withoutMotionTheNewWordShowsAtOnce() {
        #expect(CelestialGauge.bandShown(plan:.instant,previous:.excellent,target:.pristine,completed:false) == .pristine)
        #expect(CelestialGauge.bandShown(plan:.instant,previous:.excellent,target:.pristine,completed:true) == .pristine)
        // The count hides its word until it lands, so it may carry the answer's word from the start.
        #expect(CelestialGauge.bandShown(plan:.odometer,previous:.poor,target:.pristine,completed:false) == .pristine)
        #expect(CelestialGauge.bandShown(plan:.hold,previous:.good,target:.pristine,completed:false) == .good)
    }
    /// Cached 81 overtaken by a computed 97: at every point of the travel the word on show (the old
    /// one until the landing, the new one after) stands only beside a number of its own band.
    @Test func theOvertakeNeverPairsANumberWithAnotherBandsWord() {
        let target=97
        for start in [51.0,81] {
            // Every point of the travel, the spring's small overshoot past 97 included.
            for step in 0...400 {
                let value=start+(98.2-start)*Double(step)/400
                let numeral=CelestialGauge.numeral(value:value,target:target)
                let word=CelestialGauge.bandShown(plan:.sweep,previous:.excellent,target:.pristine,completed:false)
                if CelestialGauge.wordFits(word,numeral:numeral) { #expect(ScoreBand.band(numeral) == word) }
            }
            let landed=CelestialGauge.bandShown(plan:.sweep,previous:.excellent,target:.pristine,completed:true)
            #expect(CelestialGauge.wordFits(landed,numeral:CelestialGauge.numeral(value:Double(target),target:target)))
        }
    }
    @Test func aSweepingNumeralNeverOvershootsTheAnswer() {
        #expect(CelestialGauge.numeral(value:97.9,target:97)==97)
        #expect(CelestialGauge.numeral(value:95.7,target:97)==96)
        #expect(CelestialGauge.numeral(value:89.4,target:90)==90)
        #expect(CelestialGauge.numeral(value:60.6,target:97)==61)
        #expect(CelestialGauge.numeral(value:101.4,target:99)==100)
        #expect(CelestialGauge.numeral(value:-1.4,target:30)==0)
    }
    @Test func theWordStandsOnlyBesideItsOwnBand() {
        #expect(CelestialGauge.wordFits(.excellent,numeral:89))
        #expect(!CelestialGauge.wordFits(.excellent,numeral:90))
        #expect(CelestialGauge.wordFits(.pristine,numeral:90))
        #expect(!CelestialGauge.wordFits(.good,numeral:75))
    }
}
