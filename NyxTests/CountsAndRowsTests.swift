import Foundation
import Testing
@testable import Nyx

/// Counts said from the catalogue rather than a literal 63, and the park row's
/// "More content" with room for everything a row can say.
@MainActor @Suite struct CountsAndRowsTests {
    let engine=AstronomyEngine()
    func parks() throws -> [Park] { try ParkData.load() }
    func park(_ id:String) throws -> Park { try #require(try parks().first { $0.id==id }) }
    func night(_ park:Park,_ day:String) throws -> Night {
        let at=try #require(try? Date(day+"T20:00:00Z",strategy:.iso8601))
        let sky=engine.conditions(for:park,on:park.evening(at))
        return Night(park:park,sky:sky,score:ScoreEngine().score(sky:sky,bortle:park.bortleEstimate,cloudCover:5),cloudCover:5,forecastUpdated:.now)
    }

    // MARK: Counts from the catalogue

    @Test func parksEyebrowSaysTheCatalogueCount() throws {
        let count=try parks().count
        #expect(count>12)
        #expect(ParksView.countLine(shown:count,of:count,narrowed:false)=="\(count) places to look up")
        #expect(ParksView.countLine(shown:12,of:count,narrowed:true)=="12 of \(count) parks")
        #expect(ParksView.countLine(shown:1,of:count,narrowed:true)=="1 of \(count) parks")
        // A larger catalogue is said as it is, never as a fixed number.
        #expect(ParksView.countLine(shown:70,of:70,narrowed:false)=="70 places to look up")
        #expect(ParksView.countLine(shown:5,of:70,narrowed:true)=="5 of 70 parks")
    }

    /// The lower 48's map draws the national parks there and says so, with no count it cannot keep;
    /// any other map names the parks and dark-sky places around.
    @Test func emptyConstellationNamesWhatItDraws() throws {
        let all=try parks()
        let empty=ConstellationLayout(nights:[],parks:all)
        #expect(empty.summary()=="Your constellation. A map of the national parks in the lower 48 states, drawn as faint stars. Your first night will be your first star.")
        #expect(empty.summary(unavailable:true).hasSuffix("Your journal could not be opened, so your nights are not shown."))
        let paris=ConstellationLayout(nights:[],parks:all,empty:SkyMap.frame(.around,origin:GeoPoint(latitude:48.85,longitude:2.35),radiusMeters:400_000))
        #expect(paris.summary()=="Your constellation. A map of the parks and dark-sky places near you, drawn as faint stars. Your first night will be your first star.")
    }

    // MARK: Park row "More content"

    /// The fullest row (closure, clouds, the Little Dipper, a week, step-free, no road, state) fits the modifier's slots,
    /// so nothing a row says is dropped.
    @Test func fullestRowFitsTheCustomContentSlots() throws {
        let isro=try park("isro")
        #expect(!isro.drivable)
        let days=["2026-10-05","2026-10-06","2026-10-07","2026-10-08","2026-10-09","2026-10-10","2026-10-11"]
        let week=try days.map { try night(isro,$0) }
        let more=ParkRow.moreContent(night:week[0],closure:"Ferry not running",week:week,stepFree:true)
        #expect(more.map(\.label)==["Closure alert","Clouds","Little Dipper","This week","Step-free viewing","Getting there","State"])
        #expect(more.count==ParkRowContent.slots)
        #expect(more.map(\.high)==[true,false,false,false,false,false,false])
        // The quietest row: clouds, the Little Dipper and state only.
        let zion=try park("zion")
        let plain=ParkRow.moreContent(night:try night(zion,"2026-10-05"),closure:nil,week:[],stepFree:false)
        #expect(plain.map(\.label)==["Clouds","Little Dipper","State"])
        #expect(plain.count<=ParkRowContent.slots)
    }
}
