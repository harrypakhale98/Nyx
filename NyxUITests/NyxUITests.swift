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
        for title in ["Parks","Calendar","Journal","Learn","Tonight"] {
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
    func testOfflineLaunchResponsiveness() {
        let app=offlineApp()
        let options=XCTMeasureOptions()
        options.iterationCount=3
        measure(metrics:[XCTApplicationLaunchMetric(waitUntilResponsive:true)],options:options) {
            app.launch()
        }
    }
}
