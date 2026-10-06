import XCTest
import AppIntents

/// Screenshot scenarios in either orientation (the simulator cannot be turned from the command
/// line). Skipped unless asked for:
/// `TEST_RUNNER_NYX_SHOTS_DIR=/tmp/shots TEST_RUNNER_NYX_SHOTS="tonight:landscape:-nyx-screen tonight -nyx-state live;…"`
/// Each item is `name:portrait|landscape:launch arguments`.
@MainActor
final class ScreenshotTests:XCTestCase {
    func testCaptureScenarios() throws {
        let environment=ProcessInfo.processInfo.environment
        guard let directory=environment["NYX_SHOTS_DIR"], let list=environment["NYX_SHOTS"], !list.isEmpty else { throw XCTSkip("No screenshot scenarios requested") }
        let settle=Double(environment["NYX_SHOTS_SETTLE"] ?? "8") ?? 8
        for item in list.components(separatedBy:";") where !item.isEmpty {
            let parts=item.components(separatedBy:":")
            guard parts.count>=3 else { continue }
            XCUIDevice.shared.orientation=parts[1]=="landscape" ? .landscapeLeft : .portrait
            let app=XCUIApplication()
            app.launchArguments=parts[2...].joined(separator:":").components(separatedBy:" ").filter { !$0.isEmpty }
            app.launch()
            _=app.wait(for:.runningForeground,timeout:30)
            Thread.sleep(forTimeInterval:settle)
            let data=XCUIScreen.main.screenshot().pngRepresentation
            try data.write(to:URL(fileURLWithPath:directory).appendingPathComponent(parts[0]+".png"))
            app.terminate()
        }
        XCUIDevice.shared.orientation = .portrait
    }
}
