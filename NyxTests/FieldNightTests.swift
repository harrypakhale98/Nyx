import Foundation
import Testing
@testable import Nyx

/// Field mode says each fact once: no card for the milestone the Now card is counting toward
/// (true darkness while waiting, its end while dark, sunrise at dawn), every other milestone
/// kept, a different milestone at the same moment kept too.
@Suite struct FieldNightTests {
    let engine=AstronomyEngine()
    func park(_ id:String) throws -> Park { try #require(try ParkData.load().first(where:{ $0.id==id })) }
    func night(_ id:String,_ day:String) throws -> FieldNight {
        let park=try park(id)
        let sky=engine.conditions(for:park,on:park.evening(try #require(try? Date(day+"T20:00:00Z",strategy:.iso8601))))
        return FieldNight(park:park,sky:sky)
    }
    /// The cards are the milestones ahead minus exactly the one counted toward.
    func expectOneDropped(_ night:FieldNight,at now:Date,phase:FieldNight.Status.Phase,kind:FieldNight.Kind) {
        let status=night.status(at:now)
        #expect(status.phase==phase)
        let cards=night.cards(after:now,status:status), ahead=night.upcoming(after:now)
        #expect(!cards.contains { $0.kind==kind && $0.date==status.target })
        #expect(ahead.contains { $0.kind==kind && $0.date==status.target })
        #expect(cards.map(\.id)==ahead.filter { !($0.kind==kind && $0.date==status.target) }.map(\.id))
    }
    @Test func waitingDropsTrueDarkness() throws {
        let night=try night("jotr","2026-12-13")
        let start=try #require(night.sky.darkStart)
        let now=start.addingTimeInterval(-33*60)
        expectOneDropped(night,at:now,phase:.waiting,kind:.darkness)
        // The clock time the dropped card showed moves to the Now card.
        let status=night.status(at:now)
        #expect(status.trailing.hasPrefix("at ") && status.trailing.contains(night.park.time(start)) && status.trailing.contains(", then "))
    }
    @Test func darkDropsTheEndOfDarkness() throws {
        let night=try night("jotr","2026-12-13")
        let start=try #require(night.sky.darkStart)
        expectOneDropped(night,at:start.addingTimeInterval(3600),phase:.dark,kind:.dawn)
        // Passed milestones are unchanged: true darkness is in "Earlier tonight" with its explanation.
        #expect(night.milestones.contains { $0.kind == .darkness && $0.date<=start.addingTimeInterval(3600) && $0.detail.contains("18°") })
    }
    @Test func dawnDropsSunrise() throws {
        let night=try night("jotr","2026-12-13")
        let end=try #require(night.sky.darkEnd)
        expectOneDropped(night,at:end.addingTimeInterval(120),phase:.dawn,kind:.sunrise)
    }
    @Test func aDifferentMilestoneAtTheSameMomentStays() throws {
        // The October Draconids are at their best as true darkness begins at Joshua Tree.
        var found=false
        for day in ["2026-10-07","2026-10-08","2026-10-09","2026-10-10"] {
            let night=try night("jotr",day)
            guard let start=night.sky.darkStart, night.milestones.contains(where:{ $0.kind != .darkness && $0.date==start }) else { continue }
            found=true
            let now=start.addingTimeInterval(-600), status=night.status(at:now)
            let cards=night.cards(after:now,status:status)
            #expect(cards.contains { $0.kind != .darkness && $0.date==start })
            #expect(!cards.contains { $0.kind == .darkness })
        }
        #expect(found)
    }
    @Test func noDarknessKeepsEveryMilestone() throws {
        // Denali at midsummer: nothing is counted toward, so nothing is dropped.
        let night=try night("dena","2026-06-21")
        let now=try #require(night.milestones.first?.date).addingTimeInterval(-60)
        let status=night.status(at:now)
        #expect(status.phase == .noDarkness)
        #expect(night.cards(after:now,status:status).map(\.id)==night.upcoming(after:now).map(\.id))
    }
}
