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
    @Test func theRangesEndsStayOnTheTrackAndClearOfTheStar() {
        let cap=0.5, clear=4.0
        // Far from the star and the ends: the ticks sit at the range's own scores.
        #expect(ModelRangeBand.tickAngles(60...90,score:75,cap:cap,clearance:clear)==[ModelRangeBand.angle(60),ModelRangeBand.angle(90)])
        // At 100 the upper tick is held inside the end of the track, as is the span's round end.
        let top=ModelRangeBand.tickAngles(80...100,score:88,cap:cap,clearance:clear)
        #expect(top.count==2 && top[1]==ModelRangeBand.angle(100)-cap)
        #expect(ModelRangeBand.spanAngles(80...100,cap:2).to==ModelRangeBand.angle(100)-2)
        #expect(ModelRangeBand.spanAngles(0...20,cap:2).from==ModelRangeBand.angle(0)+2)
        // Two points from the star (98 against 100): the upper tick would sit under its glow, and
        // the track has no room beyond it, so the star stands for that end.
        let near=ModelRangeBand.tickAngles(90...100,score:98,cap:cap,clearance:6)
        #expect(near==[ModelRangeBand.angle(90)])
        // One point from the star with room beyond: the tick moves outward, just clear of it.
        let moved=ModelRangeBand.tickAngles(70...91,score:90,cap:cap,clearance:clear)
        #expect(moved[1]==ModelRangeBand.angle(90)+clear)
        // Every drawn tick is on the track and clear of the star.
        for score in stride(from:0.0,through:100,by:0.5) {
            for range in [0...100,max(0,Int(score)-8)...min(100,Int(score)+8),Int(score)...Int(score)] {
                for tick in ModelRangeBand.tickAngles(range,score:score,cap:cap,clearance:clear) {
                    #expect(tick>=ModelRangeBand.angle(0)+cap-0.0001 && tick<=ModelRangeBand.angle(100)-cap+0.0001)
                    #expect(abs(tick-ModelRangeBand.angle(score))>=clear-0.0001)
                }
            }
        }
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

    /// The words on show while a sweep's numeral travels from `from` to `to` (the spring's small
    /// overshoot past the target included), one entry per frame, nil while no word shows.
    private func words(sweeping start:Face,to target:Int,overshoot:Double=1.2)->[(numeral:Int,word:ScoreBand?)] {
        let sweep=CelestialGauge.sweepStart(from:start,to:target)
        let from=Double(start.shown), past=Double(target)+(Double(target)>from ? overshoot : -overshoot)
        return (0...400).map { step in
            let value=from+(past-from)*Double(step)/400
            let numeral=CelestialGauge.numeral(value:value,target:target)
            return (numeral,CelestialGauge.wordShown(numeral:numeral,leaving:sweep.leaving,target:ScoreBand.band(target)))
        }
    }
    @Test func aSweepHeadsForTheWholeAnswer() {
        let start=CelestialGauge.sweepStart(from:.answer(97),to:72)
        #expect(start.face == .answer(72))
        #expect(start.leaving == [.pristine])
    }
    /// Cached 81 overtaken by a computed 97 while its count was under way: the count had hidden its
    /// word, so nothing is left behind, "Excellent" never flashes as the number passes 75 to 89,
    /// and "Pristine" arrives with the first 90.
    @Test func theOvertakeNeverShowsTheBandsItPasses() {
        for counted in [0,51,81] {
            let midCount=Face(arc:Double(counted),shown:counted,settled:false)
            #expect(CelestialGauge.sweepStart(from:midCount,to:97).leaving.isEmpty)
            let frames=words(sweeping:midCount,to:97)
            #expect(frames.allSatisfy { $0.word == nil || $0.word == ScoreBand.band($0.numeral) })
            #expect(!frames.contains { $0.word == .excellent })
            #expect(frames.first { $0.word == .pristine }?.numeral == 90)
            #expect(frames.last?.word == .pristine)
        }
    }
    /// 97 down to 72 and back up to 92, as the capture route does: the old word stays while its
    /// number does, steps away as the number leaves its band, and the new word arrives as the
    /// number enters its own, before the spring has come to rest.
    @Test func aSweepAcrossBandsChangesTheWordAtTheBorder() {
        let down=words(sweeping:.answer(97),to:72)
        #expect(down.allSatisfy { $0.word == nil || $0.word == ScoreBand.band($0.numeral) })
        #expect(down.filter { $0.word == .pristine }.map(\.numeral).min() == 90)
        #expect(down.first { $0.word == .good }?.numeral == 74)
        #expect(!down.contains { $0.word == .excellent })
        let up=words(sweeping:.answer(72),to:92)
        #expect(up.filter { $0.word == .good }.map(\.numeral).max() == 74)
        #expect(up.first { $0.word == .pristine }?.numeral == 90)
    }
    /// A sweep inside one band keeps its word the whole way.
    @Test func aSweepWithinABandKeepsItsWord() {
        #expect(words(sweeping:.answer(91),to:97).allSatisfy { $0.word == .pristine })
    }
    @Test func aWordFromNoBandLeftBehindNeverShows() {
        #expect(CelestialGauge.wordShown(numeral:82,leaving:[],target:.pristine) == nil)
        #expect(CelestialGauge.wordShown(numeral:82,leaving:[.excellent],target:.pristine) == .excellent)
        #expect(CelestialGauge.wordShown(numeral:62,leaving:[.excellent],target:.pristine) == nil)
        #expect(CelestialGauge.wordShown(numeral:93,leaving:[.excellent],target:.pristine) == .pristine)
    }
    /// A scrub outruns the spring: 80, 77, 74, 71 a detent apart, with the number still at 77 when
    /// 71 is asked for. The sweep to 71 carries the bands of the nights still in flight, so
    /// "Excellent" stays beside 77 instead of blinking out at every border; a sweep that had come
    /// to rest carries nothing, and an overtaken count carries nothing either.
    @Test func aScrubKeepsTheWordsOfTheNightsItPasses() {
        var leaving=Set<ScoreBand>()
        var face=Face.answer(83)
        for detent in [80,77,74,71] {
            let start=CelestialGauge.sweepStart(from:face,to:detent,carrying:leaving)
            leaving=start.leaving; face=start.face
        }
        #expect(leaving == [.excellent,.good])
        #expect(CelestialGauge.wordShown(numeral:77,leaving:leaving,target:ScoreBand.band(71)) == .excellent)
        #expect(CelestialGauge.wordShown(numeral:73,leaving:leaving,target:ScoreBand.band(71)) == .good)
        // Came to rest at 74, then one detent to 71: only Good may show.
        #expect(CelestialGauge.sweepStart(from:.answer(74),to:71).leaving == [.good])
        #expect(CelestialGauge.sweepStart(from:Face(arc:60,shown:58,settled:false),to:97,carrying:[]).leaving.isEmpty)
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
