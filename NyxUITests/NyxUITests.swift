import XCTest
// Xcode runs App Intents metadata extraction for the UI test bundle too.
import AppIntents

/// Native XCTest is required for UI automation; unit tests remain Swift Testing.
@MainActor
final class NyxUITests:XCTestCase {
    private func offlineApp()->XCUIApplication {
        let app=XCUIApplication()
        app.launchArguments=["-nyx-screen","tonight","-nyx-state","no-forecast","-nyx-reduce-motion"]
        return app
    }
    func testOfflineTabNavigation() {
        continueAfterFailure=false
        let app=offlineApp()
        app.launch()
        XCTAssertTrue(app.navigationBars["Tonight"].waitForExistence(timeout:15))
        for title in ["Parks","Plan","Journal","Tonight"] {
            // iPhone: the tab bar. iPad: the same tabs at the top of the window (or in its sidebar).
            let inBar=app.tabBars.buttons[title]
            let button=inBar.exists ? inBar : app.buttons.matching(identifier:title).firstMatch
            XCTAssertTrue(button.exists,"Missing tab: \(title)")
            button.tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout:10),"Missing screen: \(title)")
        }
    }
    /// A hardware keyboard: ⌘2 opens Parks, ⌘F its search. On iPad, where Parks shows the park
    /// beside the list, ⌘→ moves its river to the next night.
    func testKeyboardCommands() throws {
        continueAfterFailure=false
        let app=offlineApp()
        app.launch()
        XCTAssertTrue(app.navigationBars["Tonight"].waitForExistence(timeout:15))
        app.typeKey("2",modifierFlags:.command)
        XCTAssertTrue(app.navigationBars["Parks"].waitForExistence(timeout:10),"⌘2 did not open Parks")
        guard UIDevice.current.userInterfaceIdiom == .pad else { return }
        let river=app.descendants(matching:.any)["Thirty-night darkness timeline"].firstMatch
        XCTAssertTrue(river.waitForExistence(timeout:15),"No park beside the list")
        let before=river.value as? String
        app.typeKey(.rightArrow,modifierFlags:.command)
        let moved=NSPredicate { _,_ in (river.value as? String) != before }
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:moved,object:nil)],timeout:5),.completed,"⌘→ did not move to the next night")
        app.typeKey("f",modifierFlags:.command)
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout:5))
        XCTAssertTrue(app.keyboards.firstMatch.exists || (app.searchFields.firstMatch.value(forKey:"hasKeyboardFocus") as? Bool ?? false),"⌘F did not focus search")
        // ⌘N records a night (not the system's New Window, which Nyx keeps on ⌘⇧N); ⌘, opens Settings.
        app.typeKey(XCUIKeyboardKey.escape.rawValue,modifierFlags:[])
        let parksBars=app.navigationBars.matching(identifier:"Parks").count
        app.typeKey("n",modifierFlags:.command)
        let editor=app.navigationBars["Record a night"]
        XCTAssertTrue(editor.waitForExistence(timeout:5),"⌘N did not open Record a night")
        // A new window would open on Tonight beside this one.
        XCTAssertFalse(app.navigationBars["Tonight"].exists,"⌘N opened a window")
        XCTAssertEqual(app.navigationBars.matching(identifier:"Parks").count,parksBars)
        editor.buttons["Cancel"].tap()
        XCTAssertTrue(editor.waitForNonExistence(timeout:5))
        app.typeKey(",",modifierFlags:.command)
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout:5),"⌘, did not open Settings")
    }
    /// The Sky glow comparison: the segments read "Here · Class 2" and "City · Class 8" for VoiceOver as
    /// on screen (the bridge to the segmented control ignores per-segment accessibility labels, so the
    /// figure's own label carries "estimated"). Choosing the city's sky selects that segment.
    func testCityLightSegmentsSpeakAsShown() {
        continueAfterFailure=false
        let app=XCUIApplication()
        app.launchArguments=["-nyx-screen","light","-nyx-park","deva","-nyx-state","offline","-nyx-reduce-motion"]
        app.launch()
        let picker=app.segmentedControls.firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout:15),"No segmented control on the Sky glow panel")
        let labels=picker.buttons.allElementsBoundByIndex.map(\.label)
        XCTAssertEqual(labels.count,2,"Segments: \(labels)")
        XCTAssertTrue(labels.first?.hasPrefix("Here · Class ") == true,"Segments: \(labels)")
        XCTAssertEqual(labels.last,"City · Class 8","Segments: \(labels)")
        let figure=app.images.matching(NSPredicate(format:"label BEGINSWITH 'Illustration: this park'")).firstMatch
        XCTAssertTrue(figure.exists,"The figure does not name the park's estimated class")
        XCTAssertTrue(figure.label.contains("estimated Class"),figure.label)
        let city=picker.buttons["City · Class 8"]
        city.tap()
        XCTAssertTrue(city.isSelected,"The city's segment is not selected after a tap")
    }
    /// At accessibility text sizes Parks searches from a field in the page (the bar's field draws
    /// nothing at AX5 on iOS 27). Typing in it narrows the list.
    func testAccessibilitySizeSearch() {
        continueAfterFailure=false
        let app=XCUIApplication()
        app.launchArguments=["-nyx-screen","parks","-nyx-state","offline","-nyx-reduce-motion","-nyx-ax5"]
        app.launch()
        let field=app.textFields["Search parks"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout:15),"No search field at AX5")
        field.tap()
        field.typeText("Zion")
        let gone=NSPredicate { _,_ in !app.staticTexts["Acadia"].exists }
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:gone,object:nil)],timeout:5),.completed,"Search did not narrow the list")
        XCTAssertTrue(app.descendants(matching:.any).matching(NSPredicate(format:"label BEGINSWITH 'Zion'")).firstMatch.exists,"Zion is not in the results")
    }
    /// Activating the river the way VoiceOver, Voice Control ("Tap River") and Switch Control
    /// do (`accessibilityActivate`, through a DEBUG button, since XCTest's `tap()` is a real touch)
    /// keeps the chosen night. A real touch at the far end still moves it, so the check can fail.
    func testRiverActivationKeepsTheNight() {
        continueAfterFailure=false
        let app=XCUIApplication()
        app.launchArguments=["-nyx-screen","river","-nyx-state","offline","-nyx-reduce-motion","-nyx-activate-river"]
        app.launch()
        let river=app.descendants(matching:.any)["Thirty-night darkness timeline"].firstMatch
        XCTAssertTrue(river.waitForExistence(timeout:20),"No river")
        let before=river.value as? String
        XCTAssertNotNil(before)
        let activate=app.buttons["Activate the river"].firstMatch
        XCTAssertTrue(activate.waitForExistence(timeout:5))
        activate.tap()
        sleep(1)
        XCTAssertEqual(river.value as? String,before,"Activating the river changed the night")
        river.coordinate(withNormalizedOffset:CGVector(dx:0.97,dy:0.5)).tap()
        let moved=NSPredicate { _,_ in (river.value as? String) != before }
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:moved,object:nil)],timeout:5),.completed,"A touch did not move the river")
    }
    /// The month follows the finger: a swipe pages to the next month and back, the arrows slide the
    /// same pager, the page in view is the one VoiceOver finds (only the current month is in the
    /// tree, and its nights are on screen), and the long-press peek opens on the visible page.
    func testMonthFollowsTheFinger() {
        continueAfterFailure=false
        let app=XCUIApplication()
        app.launchArguments=["-nyx-screen","plan","-nyx-state","no-forecast"]
        app.launch()
        let next=app.buttons["Next month"].firstMatch
        XCTAssertTrue(next.waitForExistence(timeout:20),"No month bar")
        let header=app.staticTexts.matching(NSPredicate(format:"label MATCHES %@","^[A-Z][a-z]+ [0-9]{4}$")).firstMatch
        XCTAssertTrue(header.waitForExistence(timeout:5))
        func month()->String { header.label }
        let tonightsMonth=month()
        /// A night that stands for the page: the 15th, or the 28th in tonight's month, whose past weeks fold away.
        func day(_ title:String)->String { title == tonightsMonth ? " 28" : " 15" }
        /// The visible page's nights: a night of the month named by the header is on screen.
        func pageMatches(_ title:String,file:StaticString=#filePath,line:UInt=#line) {
            let short=String(title.prefix(3))
            let night=app.buttons.matching(NSPredicate(format:"label CONTAINS %@",short+day(title))).firstMatch
            XCTAssertTrue(night.waitForExistence(timeout:5),"No night of \(title) in the tree",file:file,line:line)
            XCTAssertTrue(night.isHittable,"\(title)'s nights are not on screen",file:file,line:line)
            XCTAssertEqual(app.buttons.matching(NSPredicate(format:"label CONTAINS %@",day(title)+".")).count,1,"More than one month in the tree",file:file,line:line)
        }
        func waitChange(from old:String,file:StaticString=#filePath,line:UInt=#line)->String {
            let changed=NSPredicate { _,_ in header.label != old }
            XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:changed,object:nil)],timeout:5),.completed,"The month did not change",file:file,line:line)
            sleep(1)
            return month()
        }
        /// A quick horizontal drag across the month's middle row, most of the month's width. The month bar's
        /// arrows mark the month's column: on a wide iPad the column is centred and the night's breakdown
        /// stands beside it in an inspector, so a drag across the window's width would start in the inspector.
        func drag(left:Bool) {
            let row=app.buttons.matching(NSPredicate(format:"label CONTAINS %@",day(month()))).firstMatch
            let column=app.buttons["Previous month"].firstMatch.frame.union(next.frame)
            let y=row.frame.midY/app.frame.height
            func x(_ share:Double)->Double { (column.minX+column.width*share)/app.frame.width }
            let from=app.coordinate(withNormalizedOffset:CGVector(dx:x(left ? 0.85 : 0.15),dy:y))
            from.press(forDuration:0.05,thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:x(left ? 0.15 : 0.85),dy:y)),withVelocity:.fast,thenHoldForDuration:0)
        }
        let first=month()
        pageMatches(first)
        drag(left:true)
        let second=waitChange(from:first)
        pageMatches(second)
        drag(left:true)
        let third=waitChange(from:second)
        XCTAssertNotEqual(third,first)
        pageMatches(third)
        drag(left:false)
        XCTAssertEqual(waitChange(from:third),second,"Swiping back did not return to the month before")
        pageMatches(second)
        app.buttons["Previous month"].firstMatch.tap()
        XCTAssertEqual(waitChange(from:second),first,"The arrow did not return to the first month")
        pageMatches(first)
        // The peek on the visible page.
        let night=app.buttons.matching(NSPredicate(format:"label CONTAINS %@",String(first.prefix(3))+" 28")).firstMatch
        XCTAssertTrue(night.waitForExistence(timeout:5))
        night.press(forDuration:1.2)
        XCTAssertTrue(app.buttons["Why this score"].waitForExistence(timeout:5),"No peek on the visible month")
    }
    /// A night that has begun offers "Record this night" in its menu, which opens the journal's
    /// editor for it (on iPad the same night can be dragged onto the Journal); a night still
    /// ahead does not, since a journal keeps nights that happened.
    func testRecordThisNightFromTheMonth() {
        continueAfterFailure=false
        let app=XCUIApplication()
        app.launchArguments=["-nyx-screen","plan","-nyx-state","no-forecast","-nyx-reduce-motion"]
        app.launch()
        let tonight=app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@","Tonight, ")).firstMatch
        XCTAssertTrue(tonight.waitForExistence(timeout:20),"No tonight in the month")
        tonight.press(forDuration:1.2)
        let record=app.buttons["Record this night"].firstMatch
        XCTAssertTrue(record.waitForExistence(timeout:5),"Tonight's menu has no Record this night")
        record.tap()
        XCTAssertTrue(app.navigationBars["Record a night"].waitForExistence(timeout:10),"Record this night did not open the editor")
        app.navigationBars["Record a night"].buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Record a night"].waitForNonExistence(timeout:10))
        // Tomorrow, still ahead: its menu has no Record this night.
        let tomorrow=app.buttons.matching(NSPredicate(format:"label CONTAINS %@ AND NOT (label BEGINSWITH %@)","No cloud forecast yet","Tonight")).firstMatch
        if tomorrow.waitForExistence(timeout:5) {
            tomorrow.press(forDuration:1.2)
            XCTAssertTrue(app.buttons["Why this score"].waitForExistence(timeout:5),"No menu on a night ahead")
            XCTAssertFalse(app.buttons["Record this night"].exists,"A night still ahead offers Record this night")
        }
    }
    /// iPad: a night lifted from the month and held over the Journal's row in the sidebar opens
    /// the Journal, whose screen takes the drop ("Record a night" for that night). On iPhone a long
    /// press stays the night's menu alone.
    func testANightHeldOverTheJournalOpensIt() {
        guard UIDevice.current.userInterfaceIdiom == .pad else { return }
        continueAfterFailure=false
        // Landscape, where the sidebar stands beside the month rather than over it.
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app=XCUIApplication()
        app.launchArguments=["-nyx-screen","plan","-nyx-state","no-forecast","-nyx-reduce-motion"]
        app.launch()
        let tonight=app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@","Tonight, ")).firstMatch
        XCTAssertTrue(tonight.waitForExistence(timeout:20),"No tonight in the month")
        let sidebar=app.buttons.matching(NSPredicate(format:"identifier ==[c] %@","ToggleSidebar")).firstMatch
        if sidebar.exists { sidebar.tap(); sleep(2) }
        let journal=app.descendants(matching:.any).matching(NSPredicate(format:"label == %@ AND elementType != %d","Journal",XCUIElement.ElementType.navigationBar.rawValue)).firstMatch
        XCTAssertTrue(journal.waitForExistence(timeout:5),"No Journal in the sidebar")
        XCTAssertTrue(tonight.isHittable,"Tonight is covered")
        tonight.press(forDuration:1.0,thenDragTo:journal,withVelocity:.slow,thenHoldForDuration:3.0)
        XCTAssertTrue(app.navigationBars["Journal"].waitForExistence(timeout:10),"A night held over the Journal did not open it")
    }
    /// The night-vision switch is a lamp (`NightVisionLamp`): a tap turns the red on under a black
    /// cover, two quick taps turn back and forth from wherever the cover is, and once the lamp has
    /// settled the switch shows the stored setting again. Ends with night vision off, as it began.
    func testNightVisionLamp() {
        continueAfterFailure=false
        let app=XCUIApplication()
        app.launchArguments=["-nyx-screen","tonight","-nyx-state","offline"]
        app.launch()
        let toggle=app.buttons["Night vision"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout:15))
        if toggle.identifier != "flashlight.off.circle" { toggle.tap(); sleep(2) }
        XCTAssertEqual(toggle.identifier,"flashlight.off.circle")
        toggle.tap()
        sleep(2)
        XCTAssertEqual(toggle.identifier,"flashlight.on.circle.fill","The lamp did not turn night vision on")
        toggle.tap(); toggle.tap()
        sleep(2)
        XCTAssertEqual(toggle.identifier,"flashlight.on.circle.fill","Two quick taps did not end where they began")
        toggle.tap()
        sleep(2)
        XCTAssertEqual(toggle.identifier,"flashlight.off.circle","The lamp did not turn night vision off")
    }
    /// The shape of the night answers a held finger: touch and hold the picture, then slide, and the
    /// park page holds still while the finger reads the hours; a plain swipe over it still scrolls.
    func testSkyArcHoldKeepsThePage() {
        continueAfterFailure=false
        let app=XCUIApplication()
        app.launchArguments=["-nyx-screen","detail","-nyx-park","deva","-nyx-state","offline","-nyx-reduce-motion","-nyx-chapter","sky"]
        app.launch()
        let arc=app.descendants(matching:.any).matching(NSPredicate(format:"label BEGINSWITH %@","Sun and Moon paths")).firstMatch
        XCTAssertTrue(arc.waitForExistence(timeout:20),"No sky arc")
        sleep(2)
        let before=arc.frame
        XCTAssertGreaterThan(before.height,0)
        // On the picture, a third of the way across and 60 pt down; then up and to the right, the way
        // a page scroll would carry it.
        let from=arc.coordinate(withNormalizedOffset:.zero).withOffset(CGVector(dx:before.width*0.3,dy:60))
        from.press(forDuration:0.5,thenDragTo:from.withOffset(CGVector(dx:before.width*0.5,dy:-140)),withVelocity:.slow,thenHoldForDuration:0.3)
        sleep(1)
        XCTAssertEqual(arc.frame.minY,before.minY,accuracy:1,"The page scrolled under a held finger")
        // A plain swipe over the same spot scrolls at once.
        from.press(forDuration:0.05,thenDragTo:from.withOffset(CGVector(dx:0,dy:-260)),withVelocity:.fast,thenHoldForDuration:0)
        let moved=NSPredicate { _,_ in abs(arc.frame.minY-before.minY)>20 }
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:moved,object:nil)],timeout:5),.completed,"A swipe over the arc did not scroll the page")
    }
    /// A checked answer shows the record it cites first, under its own number, and folds the rest
    /// under one disclosure that opens to them.
    func testAskNyxCitesFirst() {
        continueAfterFailure=false
        let app=XCUIApplication()
        app.launchArguments=["-nyx-screen","ask","-nyx-state","answered","-nyx-reduce-motion"]
        app.launch()
        let others=app.buttons.matching(NSPredicate(format:"label ENDSWITH %@","other records")).firstMatch
        XCTAssertTrue(others.waitForExistence(timeout:20),"No folded records")
        // The fixture cites the first record it looked up, numbered after the records Nyx sends, whose
        // count follows the date's nights and parks: any record shown before the disclosure opens is it.
        XCTAssertTrue(app.descendants(matching:.any).matching(NSPredicate(format:"label MATCHES %@","Record [0-9]+.*")).firstMatch.exists,"The cited record is not shown")
        XCTAssertFalse(app.descendants(matching:.any).matching(NSPredicate(format:"label BEGINSWITH %@","Record 1,")).firstMatch.exists,"An uncited record is not folded")
        others.tap()
        XCTAssertTrue(app.descendants(matching:.any).matching(NSPredicate(format:"label BEGINSWITH %@","Record 1")).firstMatch.waitForExistence(timeout:5),"The disclosure did not open")
    }
    func testOfflineLaunchResponsiveness() {
        let app=offlineApp()
        let options=XCTMeasureOptions()
        options.iterationCount=3
        measure(metrics:[XCTApplicationLaunchMetric(waitUntilResponsive:true)],options:options) {
            app.launch()
        }
    }
}
