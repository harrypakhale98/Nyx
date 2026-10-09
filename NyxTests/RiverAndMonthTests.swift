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
    }

    // MARK: Month pager

    @Test func everyPageHasItsOwnKey() throws {
        let jotr=try park("jotr"), deva=try park("deva")
        let keys=[-1,0,1].map { CalendarView.pageKey(jotr,$0) }+[CalendarView.pageKey(deva,0)]
        #expect(Set(keys).count==4)
    }
}
