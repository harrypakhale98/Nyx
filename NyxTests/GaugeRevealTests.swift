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
    @Test func aCancelledCountEndsOnTheWholeAnswer() {
        for score in [0,23,59,60,74,75,89,90,97,100] {
            let end=CelestialGauge.interrupted(score:score)
            #expect(end.settled)
            #expect(end.shown==score)
            #expect(end.arc==Double(score))
        }
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

    @Test func theRangeAlwaysHoldsTheScore() {
        let models:[ClosedRange<Int>]=[70...90,80...95,60...70,95...99,0...3,40...41]
        for m in models {
            for score in stride(from:0,through:100,by:7) {
                if let range=CelestialGauge.modelRange(score:score,models:m,basis:.forecast) {
                    #expect(range.contains(score))
                    #expect(range.lowerBound>=0 && range.upperBound<=100)
                }
            }
        }
    }
    @Test func aSpreadOfFourOrLessIsNotDrawn() {
        #expect(CelestialGauge.modelRange(score:80,models:78...82,basis:.forecast)==nil)
        #expect(CelestialGauge.modelRange(score:80,models:80...80,basis:.forecast)==nil)
        #expect(CelestialGauge.modelRange(score:80,models:77...82,basis:.forecast)==77...82)
        // The score just outside the models widens the range past the threshold.
        #expect(CelestialGauge.modelRange(score:85,models:80...82,basis:.forecast)==80...85)
    }
    @Test func onlyAFullForecastShowsTheRange() {
        #expect(CelestialGauge.modelRange(score:80,models:60...90,basis:.usual)==nil)
        #expect(CelestialGauge.modelRange(score:80,models:60...90,basis:.blended(weight:0.6,leadDays:5))==nil)
        #expect(CelestialGauge.modelRange(score:80,models:nil,basis:.forecast)==nil)
        #expect(CelestialGauge.modelRange(score:80,models:60...90,basis:.forecast)==60...90)
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
}
