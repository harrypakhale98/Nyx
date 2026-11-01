import Foundation
import Testing
import UniformTypeIdentifiers
import UIKit
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
    /// A saved spot lives in the person's store, not the bundle: dropped on Plan or the Journal, its id is
    /// found through the app's model, as a park's is.
    @MainActor @Test func aDroppedSpotIsFoundThroughTheModel() async throws {
        let model=PlanModel(weather:WeatherService(transport:StubHTTP([:]),persist:false),parkStore:ParkStore(transport:StubHTTP([:]),persist:false),
                            detail:ForecastDetailService(transport:StubHTTP([:]),persist:false))
        let id="pin:3f2a8c1e-5b7d-4e9a-8c6f-1d2e3f4a5b6c"
        let spot=Place(spotID:id,name:"Spot",latitude:38.9,longitude:-106.9,timeZoneID:"America/Denver",countryCode:"US",region:"CO",grid:SkyGrid(bundle:.main,layers:[]))
        model.setSpots(places:[spot])
        let data=try await spot.exported(as:.nyxPark)
        // The bundle alone cannot name it; the model can.
        await #expect(throws:(any Error).self) { try await Park(importing:data,contentType:.nyxPark) }
        let dropped=try await DroppedPark(importing:data,contentType:.nyxPark)
        #expect(dropped.id==id && dropped.place(in:model)==spot)
        let journal=try await JournalDrop(importing:data,contentType:.nyxPark)
        #expect(journal == .park(id) && journal.prefill(model:model)?.parkID==id)
        // A park still arrives the same way; a spot deleted since, or an id far too long, does not.
        let jotr=try #require(park("jotr"))
        #expect(try await DroppedPark(importing:jotr.exported(as:.nyxPark),contentType:.nyxPark).place(in:model)?.id=="jotr")
        #expect(DroppedPark(id:"pin:9a8b7c6d-5e4f-4a3b-8c2d-1e0f9a8b7c6d").place(in:model)==nil)
        #expect(DroppedPark(id:" JOTR\n").id=="jotr")
        await #expect(throws:(any Error).self) { try await DroppedPark(importing:Data(repeating:0x61,count:4096),contentType:.nyxPark) }
    }
    @Test func theTypeIsDeclaredInTheApp() {
        #expect(UTType.nyxPark.identifier=="com.harrypakhale.nyx.park")
        #expect(ParkLibrary.place("acad",snapshot:nil) != nil && ParkLibrary.place("pin:abc",snapshot:nil) == nil)
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

    /// "Open in New Window" where a second window can sit beside the first: a screen regular both ways
    /// (an iPad, iPhone Duo's open inner display), never one compact either way (its closed outer display).
    @MainActor @Test func aNewWindowNeedsRoomBeside() {
        #expect(SceneCommands.roomBeside(horizontal:.regular,vertical:.regular))
        #expect(!SceneCommands.roomBeside(horizontal:.compact,vertical:.regular))
        #expect(!SceneCommands.roomBeside(horizontal:.regular,vertical:.compact))
        #expect(SceneCommands.roomBeside(horizontal:.unspecified,vertical:.unspecified))
        let commands=SceneCommands()
        #expect(SceneCommands.opensParkWindows(multipleWindows:true,commands) && !SceneCommands.opensParkWindows(multipleWindows:false,commands))
        commands.screenChanged(UITraitCollection(horizontalSizeClass:.compact))
        #expect(!SceneCommands.opensParkWindows(multipleWindows:true,commands))
        #expect(!SceneCommands.opensParkWindows(multipleWindows:true,SceneCommands(parkWindow:true)))
        #expect(SceneCommands.opensParkWindows(multipleWindows:true,nil))
    }
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
    @Test func aWindowReopensOnTheNightLastChosenUnlessItHasPassed() throws {
        let jotr=try #require(park("jotr"))
        let tonight=jotr.evening(Date(timeIntervalSince1970:1_791_400_000))
        let opened=jotr.date(tonight,addingDays:1), chosen=jotr.date(tonight,addingDays:3)
        #expect(ParkWindowRoot.night(stored:chosen.timeIntervalSince1970,opened:opened,tonight:tonight)==chosen)
        #expect(ParkWindowRoot.night(stored:0,opened:opened,tonight:tonight)==opened)
        #expect(ParkWindowRoot.night(stored:0,opened:nil,tonight:tonight)==nil)
        // Tonight itself stays.
        #expect(ParkWindowRoot.night(stored:tonight.timeIntervalSince1970,opened:nil,tonight:tonight)==tonight)
        // Restored a week later: tonight, not a night gone by.
        #expect(ParkWindowRoot.night(stored:chosen.timeIntervalSince1970,opened:opened,tonight:jotr.date(tonight,addingDays:9))==nil)
    }
    @Test func lastNightGivesWayAtSunriseNotADayAndAHalfLater() throws {
        let jotr=try #require(park("jotr"))
        let evening=jotr.evening(Date(timeIntervalSince1970:1_791_400_000))
        // At 1 AM it is still that night; by mid-morning the park has moved on to the next one.
        let small=evening.addingTimeInterval(13*3600), morning=evening.addingTimeInterval(22*3600)
        #expect(ParkWindowRoot.night(stored:evening.timeIntervalSince1970,opened:nil,tonight:jotr.currentNight(at:small))==evening)
        #expect(ParkWindowRoot.night(stored:evening.timeIntervalSince1970,opened:nil,tonight:jotr.currentNight(at:morning))==nil)
    }
    @Test func theCalendarCountsMonthsFromTonightsMonth() throws {
        let jotr=try #require(park("jotr"))
        // 1 AM on November 1 at the park: tonight is still October 31, so October is month zero.
        let small=try #require(jotr.calendar.date(from:DateComponents(year:2026,month:11,day:1,hour:1)))
        let tonight=jotr.currentNight(at:small)
        #expect(jotr.calendar.component(.month,from:tonight)==10)
        #expect(jotr.calendar.component(.month,from:CalendarView.baseMonth(jotr,tonight:tonight))==10)
        #expect(CalendarView.monthOffset(jotr,tonight:tonight,to:tonight)==0)
        #expect(CalendarView.monthOffset(jotr,tonight:tonight,to:jotr.evening(small))==1)
        // A link's month counts from the same base as the arrows.
        #expect(CalendarView.monthOffset(jotr,tonight:tonight,year:2026,month:10)==0)
        #expect(CalendarView.monthOffset(jotr,tonight:tonight,year:2027,month:1)==3)
        #expect(CalendarView.monthOffset(jotr,tonight:tonight,year:nil,month:nil)==0)
    }
    @MainActor @Test func aCalendarRequestBelongsToOneWindow() {
        let one=SceneCommands(), two=SceneCommands()
        one.calendarRequest=CalendarRequest(parkID:"jotr",year:nil,month:nil)
        #expect(one.calendarRequest?.parkID=="jotr" && two.calendarRequest==nil)
    }
    @MainActor @Test func aLaunchedParkIsOneValueWithItsNight() throws {
        let jotr=try #require(park("jotr"))
        let night=jotr.evening(Date(timeIntervalSince1970:1_791_400_000))
        let plain=LaunchPark(park:jotr), dated=LaunchPark(park:jotr,night:night), whatsUp=LaunchPark(park:jotr,night:night,whatsUp:true)
        // Another night or What's up is another sheet; the same request twice is the same one.
        #expect(Set([plain.id,dated.id,whatsUp.id]).count==3)
        #expect(LaunchPark(park:jotr,night:night).id==dated.id)
    }
    /// A link, reminder or Handoff for a night already past opens tonight (What's up kept when asked for).
    @Test func aPastNightFromALinkOpensTonight() {
        let tonight=Date(timeIntervalSince1970:1_791_400_000), later=tonight.addingTimeInterval(2*86_400), earlier=tonight.addingTimeInterval(-86_400)
        #expect(LaunchPark.night(later,tonight:tonight,whatsUp:false)?.date==later)
        #expect(LaunchPark.night(tonight,tonight:tonight,whatsUp:true).map { $0.date==tonight && $0.whatsUp }==true)
        #expect(LaunchPark.night(earlier,tonight:tonight,whatsUp:false)==nil)
        #expect(LaunchPark.night(earlier,tonight:tonight,whatsUp:true).map { $0.date==tonight && $0.whatsUp }==true)
    }
    /// A park presented over a window takes the keys while it is up: ⌘⇧N names its park, ⌘← ⌘→ its
    /// night, never the tab's page under it; closing it gives them back.
    @MainActor @Test func aParkOverTheWindowTakesTheKeys() {
        let commands=SceneCommands()
        commands.tab = .parks
        commands.show(park:"jotr",tab:1)
        let layer=SceneCommands.newLayer()
        #expect(layer>=AppTab.allCases.count && SceneCommands.newLayer() != layer)
        commands.layer(layer,shown:true)
        commands.show(park:"deva",tab:layer)
        #expect(commands.visiblePark=="deva")
        commands.stepNight(1)
        #expect(commands.step?.tab==layer)
        commands.layer(layer,shown:false)
        #expect(commands.visiblePark=="jotr")
        commands.stepNight(1)
        #expect(commands.step?.tab==1)
    }
    /// A tapped reminder opens in the window used last that is still open.
    @MainActor @Test func aReminderOpensInTheWindowUsedLast() {
        let router=NotificationRouter.shared
        let one=UUID(), two=UUID()
        var opened:[String]=[]
        router.connect(one) { _ in opened.append("one") }
        router.connect(two) { _ in opened.append("two") }
        router.connect(one) { _ in opened.append("one") }
        router.disconnect(one)
        router.deliver(ReminderRoute(parkID:"jotr"))
        #expect(opened==["two"])
        router.disconnect(two)
    }
    @Test func eachZoomSourceOnTonightIsUnique() throws {
        let jotr=try #require(park("jotr"))
        let sources=[ZoomRoute.pill(jotr),.pillList(jotr),.row(jotr)].map(\.source)
        #expect(Set(sources).count==3 && [ZoomRoute.pill(jotr),.pillList(jotr),.row(jotr)].allSatisfy { $0.park==jotr })
    }
    @MainActor @Test func eachTabReportsItsOwnPark() {
        let commands=SceneCommands()
        commands.show(park:"jotr",tab:1)
        #expect(commands.visiblePark==nil)
        commands.tab = .parks
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
    /// Nyx's upkeep runs once each time it comes forward, from whichever window that is: a second
    /// window active beside the first adds nothing, and the same window reporting again adds nothing.
    @MainActor @Test func upkeepRunsOncePerComingForward() {
        let windows=ActiveWindows()
        let main=UUID(), park=UUID()
        let steps=[windows.update(main,active:true),windows.update(main,active:true),windows.update(park,active:true),
                   windows.update(main,active:false),windows.update(park,active:false),
                   // A park's window alone in front (the main one in the background) comes forward by itself.
                   windows.update(park,active:true)]
        #expect(steps==[true,false,false,false,false,true])
    }
    /// One active window at a time ticks "tonight" and follows At dusk: the first to become active, then
    /// the next when it leaves, so a park's window restored alone keeps both, and two side by side never double.
    @MainActor @Test func oneActiveWindowKeepsTheNight() {
        let windows=ActiveWindows()
        let main=UUID(), park=UUID()
        #expect(windows.keeper==nil)
        _=windows.update(park,active:true)
        #expect(windows.keeper==park)
        _=windows.update(main,active:true)
        #expect(windows.keeper==park)
        _=windows.update(park,active:false)
        #expect(windows.keeper==main)
        _=windows.update(park,active:true)
        #expect(windows.keeper==main)
        _=windows.update(main,active:false); _=windows.update(park,active:false)
        #expect(windows.keeper==nil)
    }
    /// "Show Main Window" finds the main window's session by Nyx's own mark, and a session from before
    /// the mark by SwiftUI's window group; a park's window is never taken for it.
    @Test func theMainWindowIsFoundByItsMark() {
        #expect(MainWindows.isMain([MainWindows.kindKey:"main"]))
        #expect(!MainWindows.isMain([MainWindows.kindKey:"park"]))
        // The mark wins over the group's name.
        #expect(!MainWindows.isMain([MainWindows.kindKey:"park","com.apple.SwiftUI.sceneID":"Nyx.ContentScene"]))
        #expect(MainWindows.isMain(["com.apple.SwiftUI.sceneID":"Nyx.ContentScene"]))
        #expect(!MainWindows.isMain(["com.apple.SwiftUI.sceneID":"park"]))
        #expect(!MainWindows.isMain(nil) && !MainWindows.isMain([:]))
    }
    /// ⌘⇧N opens the night on screen: a page on a later night reports it, tonight reports none,
    /// and the night leaves with its page.
    @MainActor @Test func eachTabReportsItsNightForANewWindow() {
        let commands=SceneCommands()
        commands.tab = .parks
        let later=Date(timeIntervalSince1970:1_800_000_000)
        commands.show(park:"jotr",night:later,tab:1)
        #expect(commands.visiblePark=="jotr" && commands.visibleNight==later)
        commands.show(park:"jotr",tab:1)
        #expect(commands.visibleNight==nil)
        commands.show(park:"jotr",night:later,tab:1)
        commands.hide(park:"jotr",tab:1)
        #expect(commands.visiblePark==nil && commands.visibleNight==nil)
        // Another tab's night never answers for this one.
        commands.show(park:"deva",night:later,tab:0)
        #expect(commands.visibleNight==nil)
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
    /// The caption says what the rows were chosen from: in the US the parks in reach; abroad places, and
    /// when more are in reach than the weeks given, that the weeks are the darkest tonight.
    @Test func theWeekCaptionCountsWhatTheRowsCameFrom() {
        let start=Date(timeIntervalSince1970:1_791_400_000)
        let ten=WeekAcrossParks.make(weeks(["cuva","jotr","grba","deva","grca","bibe","indu","acad","romo","yell"],from:start))
        let three=WeekAcrossParks.make(weeks(["cuva","jotr","grba"],from:start))
        let reach="within 200 mi of Sydney"
        #expect(ten.caption(reach:reach) == "The 8 parks with the darkest nights this week, of 10 within 200 mi of Sydney.")
        #expect(three.caption(reach:reach) == "Every park within 200 mi of Sydney, darkest week first.")
        #expect(ten.caption(reach:reach,inReach:128) == "The 8 places with the darkest nights this week, of the 10 darkest tonight within 200 mi of Sydney.")
        #expect(ten.caption(reach:reach,inReach:10) == "The 8 places with the darkest nights this week, of 10 within 200 mi of Sydney.")
        #expect(three.caption(reach:reach,inReach:3) == "Every place within 200 mi of Sydney, darkest week first.")
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
