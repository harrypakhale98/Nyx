import Foundation
import Testing
import UniformTypeIdentifiers
@testable import Nyx

/// iPad windowing, drag and drop, the inspector's room, and the week across parks on wide Tonight.
@Suite struct IPadWindowingTests {
    private static let parks=(try? ParkData.load()) ?? []
    private func park(_ id:String)->Park? { Self.parks.first { $0.id==id } }

    // MARK: Drag and drop

    @Test func aParkSurvivesATripThroughItsOwnType() async throws {
        let jotr=try #require(park("jotr"))
        let data=try await jotr.exported(as:.nyxPark)
        // Only the id travels.
        #expect(String(decoding:data,as:UTF8.self)=="jotr")
        let back=try await Park(importing:data,contentType:.nyxPark)
        #expect(back.id=="jotr" && back.name==jotr.name)
    }
    @Test func otherAppsGetTheNameAndALink() async throws {
        let deva=try #require(park("deva"))
        let types=deva.exportedContentTypes()
        #expect(types.first == .nyxPark)
        #expect(types.contains { $0.conforms(to:.plainText) })
        #expect(types.contains { $0.conforms(to:.url) })
        let text=try await deva.exported(as:.utf8PlainText)
        #expect(String(decoding:text,as:UTF8.self)==deva.name)
        #expect(try deva.link().absoluteString=="nyx://park/deva")
        // A dropped link is a park too; anything else is refused.
        let link=try #require(URL(string:"nyx://park/grba")), tonight=try #require(URL(string:"nyx://tonight"))
        #expect(try Park.transferred(url:link).id=="grba")
        #expect(throws:ParkTransferError.self) { try Park.transferred(url:tonight) }
        #expect(throws:ParkTransferError.self) { try Park.transferred(id:"zzzz") }
        #expect(try Park.transferred(id:" JOTR\n").id=="jotr")
    }
    @Test func theTypeIsDeclaredInTheApp() {
        #expect(UTType.nyxPark.identifier=="com.harrypakhale.nyx.park")
        #expect(ParkCatalog.parks.count==Self.parks.count && ParkCatalog.park("acad") != nil)
    }
    @Test func aDroppedParkStartsAnEntryForTonightNeverAhead() throws {
        let jotr=try #require(park("jotr"))
        let tonight=jotr.evening(Date(timeIntervalSince1970:1_791_400_000))
        // After tonight's evening began: tonight's date.
        let later=JournalPrefill.dropped(park:jotr,tonight:tonight,now:tonight.addingTimeInterval(8*3600))
        #expect(later.date==tonight && later.parkID=="jotr" && later.observedBortle==jotr.bortleEstimate && later.notes.isEmpty)
        // Before it: now, since the editor accepts no date still ahead.
        let morning=tonight.addingTimeInterval(-3*3600)
        #expect(JournalPrefill.dropped(park:jotr,tonight:tonight,now:morning).date==morning)
    }

    // MARK: Windows

    @Test func aParkWindowRestoresFromItsValue() throws {
        let night=Date(timeIntervalSince1970:1_791_400_000)
        let value=ParkWindow(parkID:"jotr",night:night)
        let decoded=try JSONDecoder().decode(ParkWindow.self,from:JSONEncoder().encode(value))
        #expect(decoded==value)
        // A window opened for tonight carries no night; older encodings without one still decode.
        let bare=try JSONDecoder().decode(ParkWindow.self,from:Data(#"{"parkID":"deva"}"#.utf8))
        #expect(bare.parkID=="deva" && bare.night==nil)
        #expect(ParkWindow(parkID:"jotr") != value)
    }
    @Test func aWindowReopensOnTheNightLastChosenUnlessItHasPassed() {
        let now=Date(timeIntervalSince1970:1_791_400_000)
        let opened=now.addingTimeInterval(86_400), chosen=now.addingTimeInterval(3*86_400)
        #expect(ParkWindowRoot.night(stored:chosen.timeIntervalSince1970,opened:opened,now:now)==chosen)
        #expect(ParkWindowRoot.night(stored:0,opened:opened,now:now)==opened)
        #expect(ParkWindowRoot.night(stored:0,opened:nil,now:now)==nil)
        // Restored a week later: tonight, not a night gone by.
        #expect(ParkWindowRoot.night(stored:chosen.timeIntervalSince1970,opened:opened,now:now.addingTimeInterval(9*86_400))==nil)
    }
    @MainActor @Test func eachTabReportsItsOwnPark() {
        let commands=SceneCommands()
        commands.show(park:"jotr",tab:1)
        #expect(commands.visiblePark==nil)
        commands.tab=1
        #expect(commands.visiblePark=="jotr")
        // Another tab's page leaving does not clear this one; this one leaving does.
        commands.hide(park:"jotr",tab:0)
        #expect(commands.visiblePark=="jotr")
        commands.hide(park:"jotr",tab:1)
        #expect(commands.visiblePark==nil)
        // A park's own window answers from its one page.
        let window=SceneCommands(parkWindow:true)
        window.show(park:"deva",tab:0)
        #expect(window.parkWindow && window.visiblePark=="deva")
    }

    // MARK: Layout

    @Test func theInspectorOpensOnlyWithRoomAndKeepsItWhileOpen() {
        // 13-inch portrait (1032) and landscape (1376), regular width: room.
        #expect(WideLayout.inspector(width:1032,open:false,regular:true,largeText:false))
        #expect(WideLayout.inspector(width:1376,open:false,regular:true,largeText:false))
        // 11-inch portrait (834), compact windows and accessibility sizes: a sheet.
        #expect(!WideLayout.inspector(width:834,open:false,regular:true,largeText:false))
        #expect(!WideLayout.inspector(width:1376,open:false,regular:false,largeText:false))
        #expect(!WideLayout.inspector(width:1376,open:false,regular:true,largeText:true))
        // Once open, the page beside it is narrower by the inspector; it stays until the page is cramped.
        #expect(WideLayout.inspector(width:1032-380,open:true,regular:true,largeText:false))
        #expect(!WideLayout.inspector(width:500,open:true,regular:true,largeText:false))
    }
    @Test func fieldModeSplitsOnlyInWideLandscape() {
        #expect(WideLayout.sideBySide(width:1376,height:1032,largeText:false))
        #expect(!WideLayout.sideBySide(width:1032,height:1376,largeText:false))
        #expect(!WideLayout.sideBySide(width:688,height:1032,largeText:false))
        #expect(!WideLayout.sideBySide(width:1100,height:834,largeText:true))
        #expect(WideLayout.sideBySide(width:1376,height:1032,largeText:true))
    }
    @Test func theSkyArcKeepsItsShapeOnAWideColumn() {
        // iPhone: 168 pt, as before.
        #expect(SkyArc.height(width:354)==168)
        // A wide iPad column: about 2.4:1, up to 300 pt.
        #expect(SkyArc.height(width:600)==250)
        #expect(SkyArc.height(width:1000)==300)
    }

    // MARK: The week across parks

    private func weeks(_ ids:[String],from start:Date)->[[Night]] {
        let engine=AstronomyEngine(), scoring=ScoreEngine()
        return ids.compactMap { park($0) }.map { park in
            (0..<WeekAcrossParks.nights).map { day in
                let sky=engine.conditions(for:park,on:park.evening(park.date(start,addingDays:day)))
                return Night(park:park,sky:sky,score:scoring.score(sky:sky,bortle:park.bortleEstimate,cloudCover:nil),cloudCover:nil,forecastUpdated:nil)
            }
        }
    }
    @Test func theWeekOrdersParksByTheirBestNight() throws {
        let start=Date(timeIntervalSince1970:1_791_400_000)
        let input=weeks(["cuva","jotr","grba","deva","grca","bibe","indu","acad","romo","yell"],from:start)
        let week=WeekAcrossParks.make(input)
        #expect(week.rows.count==WeekAcrossParks.rowLimit && week.total==10)
        #expect(week.rows.allSatisfy { $0.nights.count==7 })
        func top(_ row:WeekAcrossParks.Row)->Night? { row.nights.min { NightPlanner.better($0,$1) } }
        for (a,b) in zip(week.rows,week.rows.dropFirst()) {
            let x=try #require(top(a)), y=try #require(top(b))
            #expect(!NightPlanner.better(y,x))
        }
        // The ring marks the best night of the rows shown, and it is in the first row.
        let best=try #require(week.best)
        let ringed=week.rows[best.row].nights[best.night]
        #expect(best.row==0)
        #expect(week.rows.allSatisfy { row in row.nights.allSatisfy { !NightPlanner.better($0,ringed) } })
        // Parks left out never beat the last row shown.
        let shown=Set(week.rows.map(\.park.id))
        let lastRow=try #require(week.rows.last)
        let lastTop=try #require(top(lastRow))
        for left in input where !shown.contains(left[0].park.id) {
            let leftTop=try #require(left.min { NightPlanner.better($0,$1) })
            #expect(!NightPlanner.better(leftTop,lastTop))
        }
    }
    @Test func aWeekWithOneParkOrNoneStillReads() {
        let start=Date(timeIntervalSince1970:1_791_400_000)
        let one=WeekAcrossParks.make(weeks(["jotr"],from:start))
        #expect(one.rows.count==1 && one.total==1 && one.best?.row==0)
        let none=WeekAcrossParks.make([])
        #expect(none.rows.isEmpty && none.best==nil && none.total==0)
        // A cell speaks its park and night, as a table's row and column would.
        if let night=one.rows.first?.nights.first {
            let spoken=WeekAcrossParks.spoken(night,isBest:false)
            #expect(spoken.hasPrefix("Joshua Tree. "+night.park.dayLabel(night.id)))
            #expect(spoken.contains("\(night.score.value)"))
        }
    }
}
