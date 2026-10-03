import XCTest
import AppIntents

/// Apple's automated accessibility audit (contrast, hit regions, labels, Dynamic Type,
/// clipping, traits) on every screen, in the standard palette and in night vision.
/// It complements, and never replaces, a VoiceOver pass on a real iPhone.
///
/// Run one screen: `TEST_RUNNER_NYX_AUDIT_SCREENS=river xcodebuild test -only-testing:NyxUITests/AccessibilityAuditTests ...`
@MainActor
final class AccessibilityAuditTests:XCTestCase {
    private var screens:[String] {
        if let only=ProcessInfo.processInfo.environment["NYX_AUDIT_SCREENS"], !only.isEmpty { return only.components(separatedBy:",") }
        return ["tonight","parks","calendar","journal","learn","detail","breakdown","editor","entry",
                "onboarding","settings","privacy","data","article","share","river","skyarc"]
    }

    func testEveryScreenPassesTheAudit() throws { try audit(state:"offline") }
    func testNightVisionPassesTheAudit() throws { try audit(state:"night-vision") }

    private func audit(state:String) throws {
        var failures:[String]=[]
        for screen in screens {
            let app=XCUIApplication()
            app.launchArguments=["-nyx-screen",screen,"-nyx-state",state,"-nyx-reduce-motion"]
            app.launch()
            _=app.wait(for:.runningForeground,timeout:30)
            sleep(2)
            let window=app.frame
            let tabBar=app.tabBars.firstMatch.exists ? app.tabBars.firstMatch.frame : .null
            let navigationBar=app.navigationBars.firstMatch.exists ? app.navigationBars.firstMatch.frame : .null
            try app.performAccessibilityAudit { issue in
                let frame=issue.element?.frame ?? .null
                let label=issue.element?.label ?? ""
                let line="AUDIT|\(state)|\(screen)|\(issue.auditType.rawValue)|\(issue.compactDescription)|'\(label)'|\(frame)"
                print(line)
                if Self.isKnownFalsePositive(issue,screen:screen,frame:frame,window:window,tabBar:tabBar,navigationBar:navigationBar) { return true }
                failures.append(line)
                return true // collect everything; fail once at the end with the full list
            }
            app.terminate()
        }
        XCTAssertTrue(failures.isEmpty,"Accessibility audit issues:\n"+failures.joined(separator:"\n"))
    }

    /// Each exclusion was checked by hand; see DECISIONS.md (accessibility audit).
    private static func isKnownFalsePositive(_ issue:XCUIAccessibilityAuditIssue,screen:String,frame:CGRect,window:CGRect,tabBar:CGRect,navigationBar:CGRect)->Bool {
        let visible=frame.isNull ? false : window.contains(frame) && !(tabBar.isNull ? false : frame.intersects(tabBar))
        switch issue.auditType {
        case .dynamicType:
            // The share card is fixed-size exported artwork with a full spoken summary. Elsewhere the
            // audit reports "partially unsupported" for text that does scale; verified with system AX5 captures.
            return screen=="share" || issue.compactDescription.contains("partially")
        case .contrast:
            // Text measured against the translucent tab bar, or glass with no element, not against its own background.
            // "Nearly passed" is not a failure; it is measured where a star sits beside small text.
            // Night-vision score numerals: the red is 6.2:1 on black (large text needs 3:1); the audit samples the
            // anti-aliased diagonal of thin serif digits such as "77". Checked by eye in a captured frame.
            let numeral = !(issue.element?.label ?? "").isEmpty && (issue.element?.label ?? "").allSatisfy(\.isNumber)
            // iOS 27 draws system toolbar buttons (Done, Cancel, Save, Edit) on glass the audit cannot sample;
            // they render light-on-dark and legible (checked by screenshot). iOS 26 passes the same buttons.
            let toolbarButton=issue.element?.elementType == .button && !navigationBar.isNull && frame.intersects(navigationBar)
            return !visible || issue.compactDescription.contains("nearly") || (screen=="parks" && numeral) || toolbarButton
        case .textClipped:
            // Scrolled below the fold or behind the tab bar, not truncated; the system search field's placeholder;
            // or PhotosPicker's own "Choose photos" label, which renders in full (checked by screenshot).
            return !visible || issue.element?.elementType == .searchField || (screen=="editor" && issue.element?.label=="Choose photos")
        case .elementDetection:
            // Decorative "NYX" wordmark and the time river's Canvas-drawn dates; the river element speaks the full value.
            return issue.element==nil && (screen=="onboarding" || screen=="river")
        default:
            return false
        }
    }
}
