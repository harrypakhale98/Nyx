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
                "onboarding","settings","privacy","data","article","share","river","skyarc","whatsup",
                "field","field-compass","alarm-explainer","listen","accessibility"]
        // Not "live-activity": that DEBUG page redraws Lock Screen and Dynamic Island faces outside the
        // system containers that host, scale and tint them, so its findings do not transfer. Reviewed by screenshot.
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
            // Field mode's milestones fade into the dark above the eye's clock and footer (a scroll-edge fade, by
            // design): the lowest 30% of the window, where cards scroll out under the clock.
            let fieldFade=screen=="field" ? CGRect(x:0,y:window.height*0.7,width:window.width,height:window.height*0.3) : .null
            let tabBar=app.tabBars.firstMatch.exists ? app.tabBars.firstMatch.frame : .null
            let navigationBar=app.navigationBars.firstMatch.exists ? app.navigationBars.firstMatch.frame : .null
            try app.performAccessibilityAudit { issue in
                let frame=issue.element?.frame ?? .null
                let label=issue.element?.label ?? ""
                let line="AUDIT|\(state)|\(screen)|\(issue.auditType.rawValue)|\(issue.compactDescription)|'\(label)'|\(frame)"
                print(line)
                if Self.isKnownFalsePositive(issue,screen:screen,frame:frame,window:window,tabBar:tabBar,navigationBar:navigationBar) { return true }
                if !fieldFade.isNull, frame.intersects(fieldFade), issue.auditType == .contrast || issue.auditType == .textClipped { return true }
                failures.append(line)
                return true // collect everything; fail once at the end with the full list
            }
            app.terminate()
        }
        XCTAssertTrue(failures.isEmpty,"Accessibility audit issues:\n"+failures.joined(separator:"\n"))
    }

    /// Each exclusion was checked by hand; see DECISIONS.md (accessibility audit).
    private static func isKnownFalsePositive(_ issue:XCUIAccessibilityAuditIssue,screen:String,frame:CGRect,window:CGRect,tabBar:CGRect,navigationBar:CGRect)->Bool {
        // The tab bar plus the scroll-edge fade the system draws just above it (about 56 pt): content
        // scrolling through that band is dimmed by design, whatever the app's colours.
        let fadeZone=tabBar.isNull ? CGRect.null : tabBar.insetBy(dx:0,dy:-56).offsetBy(dx:0,dy:-28)
        let visible=frame.isNull ? false : window.contains(frame) && !(fadeZone.isNull ? false : frame.intersects(fadeZone))
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
            // Parks band labels under each score ("Pristine", "Estimate"): starlight at 72% on black is about 11:1; the audit
            // samples a real star that can fall inside the glyph box. Checked by eye in a zoomed iOS 26.5 capture (2026-10-05).
            let bandLabel=["Pristine","Excellent","Good","Fair","Poor","Estimate"].contains(issue.element?.label ?? "")
            // iOS 27 draws system toolbar buttons (Done, Cancel, Save, Edit) on glass the audit cannot sample;
            // they render light-on-dark and legible (checked by screenshot). iOS 26 passes the same buttons.
            // The same glass, unsampled, on a sheet's own top-corner "Close" (permission explainers), checked by screenshot.
            let toolbarButton=issue.element?.elementType == .button && ((!navigationBar.isNull && frame.intersects(navigationBar)) || (screen.hasSuffix("explainer") && frame.maxY<120))
            return !visible || issue.compactDescription.contains("nearly") || (screen=="parks" && (numeral || bandLabel)) || toolbarButton
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
