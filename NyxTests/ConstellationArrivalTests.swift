import Foundation
import Testing
import UIKit
@testable import Nyx

/// A night just recorded arrives as a star: only when exactly one night is new, never at launch,
/// for an import or for a deletion; the figures draw themselves once per launch; the arrival's
/// motion lands exactly on the star as it is always drawn, before the rating request may ask.
@MainActor struct ConstellationArrivalTests {
    @Test func firstAppearanceSeedsWithoutAnArrival() {
        let step=ConstellationArrivals.step(known:nil,ids:["a","b","c"])
        #expect(step.known==["a","b","c"] && step.arriving==nil)
    }
    @Test func oneNewNightArrives() {
        #expect(ConstellationArrivals.step(known:["a","b"],ids:["a","b","c"]).arriving=="c")
        // The very first night in an empty journal is the first star.
        #expect(ConstellationArrivals.step(known:[],ids:["a"]).arriving=="a")
    }
    @Test func anImportOfManyArrivesSilently() {
        let step=ConstellationArrivals.step(known:["a"],ids:["a","b","c","d"])
        #expect(step.arriving==nil && step.known==["a","b","c","d"])
    }
    @Test func aDeletionDoesNotArrive() {
        #expect(ConstellationArrivals.step(known:["a","b","c"],ids:["a","b"]).arriving==nil)
        // One night deleted and another added in the same change is not a new star.
        #expect(ConstellationArrivals.step(known:["a","b"],ids:["a","c"]).arriving==nil)
    }
    @Test func aStarWaitsUntilItIsDrawn() {
        let known=ConstellationArrivals.known, pending=ConstellationArrivals.pending
        defer { ConstellationArrivals.known=known; ConstellationArrivals.pending=pending }
        ConstellationArrivals.known=nil; ConstellationArrivals.pending=nil
        ConstellationArrivals.note(["a","b"])
        #expect(ConstellationArrivals.pending==nil)
        // Recorded while the Journal is out of sight: it waits for the next visit.
        ConstellationArrivals.note(["a","b","c"])
        #expect(ConstellationArrivals.waiting(in:["a","b","c"])=="c")
        // A second watcher noting the same journal does not lose it.
        ConstellationArrivals.note(["a","b","c"])
        #expect(ConstellationArrivals.waiting(in:["a","b","c"])=="c")
        ConstellationArrivals.landed("c")
        #expect(ConstellationArrivals.waiting(in:["a","b","c"])==nil)
        // A waiting star whose night is deleted is forgotten.
        ConstellationArrivals.note(["a","b","c","d"])
        ConstellationArrivals.note(["a","b","c"])
        #expect(ConstellationArrivals.pending==nil)
    }
    @Test func figuresDrawAgainOnlyWhenTheyGrow() {
        let now=SkyMapDrawIns.Signature(figures:3,edges:7)
        #expect(now.grows(from:nil))
        #expect(!now.grows(from:now))
        #expect(!now.grows(from:SkyMapDrawIns.Signature(figures:3,edges:9)))
        #expect(SkyMapDrawIns.Signature(figures:3,edges:8).grows(from:now))
        #expect(SkyMapDrawIns.Signature(figures:4,edges:7).grows(from:now))
    }
    @Test func theArrivalLandsOnTheStarAsDrawn() {
        #expect(StarArrival.core(0)==0 && StarArrival.halo(0)==0 && StarArrival.edge(0)==0)
        #expect(StarArrival.core(1)==1 && StarArrival.halo(1)==1 && StarArrival.edge(1)==1)
        let samples=stride(from:0.0,through:1.0,by:0.005)
        // The halo blooms to about 1.8× and settles; the core never shrinks below nothing.
        let peak=samples.map(StarArrival.halo).max() ?? 0
        #expect((1.6...2.0).contains(peak))
        #expect(samples.allSatisfy { StarArrival.core($0)>=0 })
        #expect(abs(StarArrival.halo(0.98)-1)<0.02 && abs(StarArrival.core(0.98)-1)<0.02)
        // The edge reaches the star as its core begins.
        #expect(StarArrival.edge(StarArrival.coreStart/StarArrival.duration)>0.9 && StarArrival.core(StarArrival.coreStart/StarArrival.duration)==0)
        // The rating request after a journal entry waits for the star to settle; other moments keep their beat.
        #expect(ReviewPrompt.journalDelay>=StarArrival.delay+StarArrival.duration+0.5)
        #expect(ReviewPrompt.momentDelay==1.5)
    }
}

/// The inset names under the sky map: each has its own room before the next frame, at every
/// panel width, so Hawaiʻi never runs into Am. Samoa, in English or Spanish.
struct SkyMapNameRoomTests {
    @Test func roomsArePositiveAndNeverOverlap() {
        for width in stride(from:300.0,through:700,by:10) {
            let rooms=SkyMap.nameRooms(width:width)
            #expect(rooms.count==4)
            #expect(rooms.allSatisfy { $0.room>0 && $0.minX<=$0.x && $0.minX>0 },"\(width)")
            for (a,b) in zip(rooms,rooms.dropFirst()) { #expect(a.minX+a.room<b.minX,"\(width)") }
            #expect((rooms.last.map { $0.minX+$0.room } ?? .infinity)<=width)
        }
    }
    @Test func namesAtTheFloorFitInEnglishAndSpanish() {
        let font=UIFont.systemFont(ofSize:9,weight:.medium)
        func width(_ name:String)->Double { (name as NSString).size(withAttributes:[.font:font]).width }
        for names in [["Alaska","Hawaiʻi","Am. Samoa","Virgin Is."],["Alaska","Hawaiʻi","Samoa Am.","I. Vírgenes"]] {
            for canvas in stride(from:300.0,through:700,by:20) {
                for (room,name) in zip(SkyMap.nameRooms(width:canvas),names) { #expect(width(name)<=room.room,"\(name) at \(canvas)") }
            }
        }
    }
}
