import Foundation
import Testing
import SwiftUI
@testable import Nyx

/// The river and the month under the finger: the scrub's detents, the loupe's place, directions
/// where the night is decided, and the month pager's pages.
@MainActor @Suite struct RiverAndMonthTests {
    func park(_ id:String) throws -> Park { try #require(try ParkData.load().first { $0.id==id }) }

    // MARK: Detents

    @Test func aFastScrubFeelsEachNightCrossedUpToThree() {
        #expect(RiverDetents.crossed(from:3,to:4)==[4])
        #expect(RiverDetents.crossed(from:3,to:5)==[4,5])
        #expect(RiverDetents.crossed(from:3,to:9)==[5,7,9])
        #expect(RiverDetents.crossed(from:9,to:3)==[7,5,3])
        #expect(RiverDetents.crossed(from:nil,to:5)==[5])
        #expect(RiverDetents.crossed(from:5,to:5)==[5])
        for from in 0..<30 { for to in 0..<30 where to != from {
            let ticks=RiverDetents.crossed(from:from,to:to)
            #expect(ticks.count==min(3,abs(to-from)))
            #expect(ticks.last==to)
            // Every tick lies on the way, in order, and none repeats.
            #expect(Set(ticks).count==ticks.count)
            #expect(ticks.allSatisfy { to>from ? ($0>from && $0<=to) : ($0<from && $0>=to) })
        } }
        #expect(RiverDetents.spacing == .milliseconds(40))
    }

    // MARK: Loupe

    @Test func theLoupeLiftsAboveTheNightAndStaysInThePanel() {
        let river=TimeRiver(nights:[],selected:.constant(.now))
        let width=330.0
        // A low score: lifted the full 34 pt.
        let low=river.loupeCenter(CGPoint(x:200,y:128),width:width)
        #expect(low.x==200 && low.y==94)
        // A Pristine night near the top: the loupe rises at most 24 pt above the river.
        let high=river.loupeCenter(CGPoint(x:14,y:42),width:width)
        #expect(high.y-28 >= -24)
        #expect(high.x-28 >= 0)
        let right=river.loupeCenter(CGPoint(x:316,y:60),width:width)
        #expect(right.x+28 <= width)
        // The Moon sits beside the loupe, never under it, and inside the river's width.
        for point in [CGPoint(x:14,y:42),CGPoint(x:165,y:80),CGPoint(x:316,y:128)] {
            let loupe=river.loupeCenter(point,width:width), moon=river.moonBeside(loupe,point:point,width:width)
            #expect(abs(moon.x-loupe.x) >= 28+15)
            #expect(moon.x-15 >= 0 && moon.x+15 <= width)
        }
    }
    @Test func theLoupeTickGrowsWithTheBand() {
        let widths=[ScoreBand.poor,.fair,.good,.excellent,.pristine].map(TimeRiver.tickWidth)
        #expect(widths==widths.sorted() && Set(widths).count==widths.count)
    }

    // MARK: Directions

    @Test func directionsPreferAStepFreeSpot() throws {
        // The park's first spot is undocumented; a later one is step-free.
        let meve=try park("meve")
        let choice=try #require(MapsHandOff.spot(for:meve))
        #expect(choice.spot.name=="Far View Lodge" && choice.stepFree == .yes)
        // Partly step-free first, step-free later: the step-free one.
        #expect(try MapsHandOff.spot(for:park("shen"))?.spot.name=="Skyland Amphitheater")
        // Only partly step-free spots: the first of them, said as such.
        let jotr=try #require(try MapsHandOff.spot(for:park("jotr")))
        #expect(jotr.spot.name=="Cap Rock" && jotr.stepFree == .partial)
        let url=try #require(MapsHandOff.directions(choice.spot))
        #expect(url.scheme=="maps" && url.absoluteString.contains("daddr=\(choice.spot.latitude),\(choice.spot.longitude)") && url.absoluteString.contains("dirflg=d"))
    }
    @Test func directionsSayTheSpotTheParkAndMaps() {
        #expect(MapsHandOff.spokenLabel(spot:"Far View Lodge",park:"Mesa Verde",stepFree:.yes)=="Directions to Far View Lodge, step-free, Mesa Verde, in Maps")
        #expect(MapsHandOff.spokenLabel(spot:"Cap Rock",park:"Joshua Tree",stepFree:.partial)=="Directions to Cap Rock, partly step-free, Joshua Tree, in Maps")
        #expect(MapsHandOff.spokenLabel(spot:"Seawall",park:"Acadia",stepFree:nil)=="Directions to Seawall, Acadia, in Maps")
        #expect(MapsHandOff.spokenLabel(spot:"Seawall",park:"Acadia",stepFree:.no)=="Directions to Seawall, Acadia, in Maps")
    }
    @Test func roadlessParksShowTheirAccessNoteInstead() throws {
        let drto=try park("drto")
        #expect(!drto.drivable && drto.accessNote != nil)
        #expect(NightDirections.offer(for:drto) == .accessNote)
        // A drivable park with a step-free spot offers directions there, said as step-free.
        let meve=try park("meve")
        guard case .directions(let spot,let url,let stepFree)=NightDirections.offer(for:meve) else { Issue.record("Mesa Verde offers no directions"); return }
        #expect(spot=="Far View Lodge" && stepFree == .yes && url.scheme=="maps")
        // Joshua Tree's spot is only partly step-free, and the row says "partly" (never the step-free glyph alone).
        guard case .directions(_,_,let jotrAccess)=NightDirections.offer(for:try park("jotr")) else { Issue.record("Joshua Tree offers no directions"); return }
        #expect(jotrAccess == .partial)
    }

    // MARK: Month pager

    @Test func aSettledSlideBecomesTheMonthAndThePagerReturnsToTheMiddle() {
        #expect(MonthPager.commit(offset:0,position:1) == (1,0))
        #expect(MonthPager.commit(offset:3,position:-1) == (2,0))
        #expect(MonthPager.commit(offset:2,position:0) == (2,0))
        #expect(MonthPager.commit(offset:2,position:nil) == (2,0))
    }
    @Test func aStepAcrossAMonthsEdgeStartsFromTheMonthInView() throws {
        let jotr=try park("jotr")
        // Tonight is 9 October at Joshua Tree.
        var components=DateComponents(); components.year=2026; components.month=10; components.day=9; components.hour=21
        let tonight=jotr.evening(try #require(jotr.calendar.date(from:components)))
        let october=MonthPager.evenings(jotr,tonight:tonight,offset:0), november=MonthPager.evenings(jotr,tonight:tonight,offset:1)
        #expect(october.count==31 && november.count==30)
        let lastOfOctober=try #require(october.last), firstOfNovember=try #require(november.first)
        // ⌘→ on 31 October slides one month on and lands on 1 November.
        let first=try #require(MonthPager.step(jotr,tonight:tonight,offset:0,chosen:lastOfOctober,delta:1))
        #expect(first.night==firstOfNovember && first.move==1)
        // A second ⌘→ while that slide is still under way: read from October (the stale month), the
        // chosen night is not in it and focus falls back to tonight, the bug the review found.
        #expect(MonthPager.focus(october,chosen:firstOfNovember,tonight:tonight)==tonight)
        // Settling the slide first, as the calendar now does, steps on from 1 November to the 2nd.
        let settled=MonthPager.commit(offset:0,position:1)
        let second=try #require(MonthPager.step(jotr,tonight:tonight,offset:settled.offset,chosen:firstOfNovember,delta:1))
        #expect(second.night==jotr.date(firstOfNovember,addingDays:1) && second.move==0)
        // ⌘← on 1 November slides back to 31 October.
        let back=try #require(MonthPager.step(jotr,tonight:tonight,offset:1,chosen:firstOfNovember,delta:-1))
        #expect(back.night==lastOfOctober && back.move == -1)
        // A night chosen elsewhere: the step starts from tonight in tonight's month.
        let fromTonight=try #require(MonthPager.step(jotr,tonight:tonight,offset:0,chosen:nil,delta:1))
        #expect(fromTonight.night==jotr.date(tonight,addingDays:1) && fromTonight.move==0)
    }
    @Test func everyPageHasItsOwnKey() throws {
        let jotr=try park("jotr"), deva=try park("deva")
        let keys=[-1,0,1].map { CalendarView.pageKey(jotr,$0) }+[CalendarView.pageKey(deva,0)]
        #expect(Set(keys).count==4)
    }
}
