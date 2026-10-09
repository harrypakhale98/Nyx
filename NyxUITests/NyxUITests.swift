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
    /// AX-03: activating the river the way VoiceOver, Voice Control ("Tap River") and Switch Control
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
        /// The visible page's nights: a night of the month named by the header is on screen.
        func pageMatches(_ title:String,file:StaticString=#filePath,line:UInt=#line) {
            let short=String(title.prefix(3))
            let night=app.buttons.matching(NSPredicate(format:"label CONTAINS %@",short+" 15")).firstMatch
            XCTAssertTrue(night.waitForExistence(timeout:5),"No night of \(title) in the tree",file:file,line:line)
            XCTAssertTrue(night.isHittable,"\(title)'s nights are not on screen",file:file,line:line)
            XCTAssertEqual(app.buttons.matching(NSPredicate(format:"label CONTAINS %@"," 15.")).count,1,"More than one month in the tree",file:file,line:line)
        }
        func waitChange(from old:String,file:StaticString=#filePath,line:UInt=#line)->String {
            let changed=NSPredicate { _,_ in header.label != old }
            XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:changed,object:nil)],timeout:5),.completed,"The month did not change",file:file,line:line)
            sleep(1)
            return month()
        }
        /// A quick horizontal drag across the month's middle row, most of the screen's width.
        func drag(left:Bool) {
            let row=app.buttons.matching(NSPredicate(format:"label CONTAINS %@"," 15")).firstMatch
            let y=row.frame.midY/app.frame.height
            let from=app.coordinate(withNormalizedOffset:CGVector(dx:left ? 0.85 : 0.15,dy:y))
            from.press(forDuration:0.05,thenDragTo:app.coordinate(withNormalizedOffset:CGVector(dx:left ? 0.15 : 0.85,dy:y)),withVelocity:.fast,thenHoldForDuration:0)
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
        let night=app.buttons.matching(NSPredicate(format:"label CONTAINS %@",String(first.prefix(3))+" 20")).firstMatch
        XCTAssertTrue(night.waitForExistence(timeout:5))
        night.press(forDuration:1.2)
        XCTAssertTrue(app.buttons["Why this score"].waitForExistence(timeout:5),"No peek on the visible month")
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
    func testOfflineLaunchResponsiveness() {
        let app=offlineApp()
        let options=XCTMeasureOptions()
        options.iterationCount=3
        measure(metrics:[XCTApplicationLaunchMetric(waitUntilResponsive:true)],options:options) {
            app.launch()
        }
    }
}
