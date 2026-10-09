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
