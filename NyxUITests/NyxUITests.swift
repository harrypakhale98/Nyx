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
            let button=app.tabBars.buttons[title]
            XCTAssertTrue(button.exists,"Missing tab: \(title)")
            button.tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout:10),"Missing screen: \(title)")
        }
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
