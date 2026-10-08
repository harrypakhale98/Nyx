import XCTest
import AppIntents

/// Apple's automated accessibility audit (contrast, hit regions, labels, Dynamic Type,
/// clipping, traits) on every screen, in the standard palette and in night vision, and on the key
/// screens at the largest accessibility text size with Increase Contrast and Bold Text.
/// It complements, and never replaces, a VoiceOver pass on a real iPhone.
///
/// Run one screen: `TEST_RUNNER_NYX_AUDIT_SCREENS=river xcodebuild test -only-testing:NyxUITests/AccessibilityAuditTests ...`
@MainActor
final class AccessibilityAuditTests:XCTestCase {
    private var screens:[String] {
        if let only=ProcessInfo.processInfo.environment["NYX_AUDIT_SCREENS"], !only.isEmpty { return only.components(separatedBy:",") }
        return ["tonight","parks","calendar","journal","learn","detail","breakdown","editor","entry",
                "onboarding","settings","privacy","data","article","share","river","skyarc","whatsup",
                "field","field-compass","alarm-explainer","light","listen","accessibility","trip","constellation","recap","icons","first-light"]
        // Not "live-activity": that DEBUG page redraws Lock Screen and Dynamic Island faces outside the
        // system containers that host, scale and tint them, so its findings do not transfer. Reviewed by screenshot.
    }

    /// The screens people live in, for the heavier passes.
    private var keyScreens:[String] {
        if let only=ProcessInfo.processInfo.environment["NYX_AUDIT_SCREENS"], !only.isEmpty { return only.components(separatedBy:",") }
        return ["tonight","parks","detail","plan","journal","settings","field"]
    }

    func testEveryScreenPassesTheAudit() throws { try audit(state:"offline",screens:screens) }
    func testNightVisionPassesTheAudit() throws { try audit(state:"night-vision",screens:screens) }
    /// AX5 (the system's own content size, so system controls grow too), Increase Contrast and Bold
    /// Text together: the states the Larger Text and Sufficient Contrast labels claim.
    func testLargestTextPassesTheAudit() throws {
        try audit(state:"offline",screens:keyScreens,extra:["-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL","-nyx-contrast","-nyx-bold"],pass:"ax5")
    }
    func testLargestTextInNightVisionPassesTheAudit() throws {
        try audit(state:"night-vision",screens:keyScreens,extra:["-UIPreferredContentSizeCategoryName","UICTContentSizeCategoryAccessibilityXXXL","-nyx-contrast","-nyx-bold"],pass:"ax5")
    }

    private func audit(state:String,screens:[String],extra:[String]=[],pass:String="default") throws {
        var failures:[String]=[]
        for screen in screens {
            let app=XCUIApplication()
            app.launchArguments=["-nyx-screen",screen,"-nyx-state",state,"-nyx-reduce-motion"]+extra
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
                let line="AUDIT|\(pass)|\(state)|\(screen)|\(issue.auditType.rawValue)|\(issue.compactDescription)|'\(label)'|\(frame)"
                print(line)
                if Self.isKnownFalsePositive(issue,screen:screen,pass:pass,frame:frame,window:window,tabBar:tabBar,navigationBar:navigationBar) { return true }
                if !fieldFade.isNull, frame.intersects(fieldFade), issue.auditType == .contrast || issue.auditType == .textClipped { return true }
                failures.append(line)
                return true // collect everything; fail once at the end with the full list
            }
            app.terminate()
        }
        XCTAssertTrue(failures.isEmpty,"Accessibility audit issues:\n"+failures.joined(separator:"\n"))
    }

    /// Elements the audit calls "partially" Dynamic Type, each checked by hand at AX5 (screen, label
    /// prefix). Replaces a blanket exemption, so a new element that stops scaling fails the audit.
    /// An empty label matches only an element without one.
    private static let partialDynamicType:[(screen:String,label:String)]=[
        // The park's name in the navigation bar once the serif title scrolls away: a system bar, which caps its own type.
        ("detail","Joshua Tree"),
        // Plan's park menu steps from largeTitle down to title2 at accessibility sizes, by design, so long names wrap
        // in two lines rather than six; title2 still grows to about 42 pt at AX5 (checked in a system AX5 capture).
        ("plan","Joshua Tree"),
        // An unlabelled element of the system search bar (no frame; reported at AX5 only).
        ("parks",""),
    ]
    /// Each exclusion was checked by hand; see DECISIONS.md (accessibility audit).
    private static func isKnownFalsePositive(_ issue:XCUIAccessibilityAuditIssue,screen:String,pass:String,frame:CGRect,window:CGRect,tabBar:CGRect,navigationBar:CGRect)->Bool {
        // The tab bar plus the scroll-edge fade the system draws just above it (about 56 pt): content
        // scrolling through that band is dimmed by design, whatever the app's colours.
        // On iPad the tab bar floats at the top of the window and the edge effect runs below it (to about 84 pt).
        let topBar = !tabBar.isNull && tabBar.midY<window.height/2
        var fadeZone=tabBar.isNull ? CGRect.null : tabBar.insetBy(dx:0,dy:-56).offsetBy(dx:0,dy:topBar ? 28 : -28)
        // iPad: the navigation bar's own scroll-edge effect at the top of the window, whatever the tab bar reports.
        if UIDevice.current.userInterfaceIdiom == .pad, !navigationBar.isNull { fadeZone=fadeZone.union(CGRect(x:0,y:0,width:window.width,height:navigationBar.maxY+56)) }
        let visible=frame.isNull ? false : window.contains(frame) && !(fadeZone.isNull ? false : frame.intersects(fadeZone))
        switch issue.auditType {
        case .dynamicType:
            // The share card is fixed-size exported artwork with a full spoken summary. "Fully
            // unsupported" always fails. At the default size the audit calls dozens of scaling texts
            // "partially unsupported", system controls included (Done, Cancel, Form headers): noise.
            // At AX5, where it matters, only the elements below (each checked in a system AX5 capture) may.
            let label=issue.element?.label ?? ""
            guard issue.compactDescription.contains("partially") else { return screen=="share" }
            if pass != "ax5" { return true }
            return screen=="share" || partialDynamicType.contains { $0.screen==screen && ($0.label.isEmpty ? label.isEmpty : label.hasPrefix($0.label)) }
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
            // Year recap (2026-10-06): its light serif tile numerals ("7") in night vision and the serif heading over the row of
            // Moons sample as low contrast on the same anti-aliased strokes; starlight on solid indigo is about 13:1, red on
            // night-vision black 6.2:1. Checked by eye in zoomed iOS 27 captures in both palettes.
            let recapSerif=screen=="recap" && (numeral || issue.element?.label=="The Moon's phases you met")
            // iPad Learn grid (2026-10-06): the right-hand cards' "2 minute read" captions, starlight at 86% on the indigo
            // panel (about 12:1); the audit samples the glass over the Milky Way behind them. Checked in a zoomed capture.
            let learnCaption=screen=="learn" && (issue.element?.label ?? "").hasSuffix("minute read")
            return !visible || issue.compactDescription.contains("nearly") || (screen=="parks" && (numeral || bandLabel)) || toolbarButton || recapSerif || learnCaption
        case .textClipped:
            // Scrolled below the fold or behind the tab bar, not truncated; the system search field's placeholder;
            // or PhotosPicker's own "Choose photos" label, which renders in full (checked by screenshot).
            // On iPad the Parks search field sits in the split view's list column; its placeholder is reported as its own element.
            return !visible || issue.element?.elementType == .searchField || issue.element?.label=="Park or state" || (screen=="editor" && issue.element?.label=="Choose photos")
        case .elementDetection:
            // Decorative "NYX" wordmark and the time river's Canvas-drawn dates; the river element speaks the full value.
            // The sky map's Canvas-drawn inset names (Alaska, Hawaiʻi, Am. Samoa, Virgin Is.): decoration; each star is a
            // labelled button and the map has a spoken summary.
            // iPad (2026-10-06): the river is on screen on Tonight (wide) and in the detail's hero column.
            return issue.element==nil && ["onboarding","river","constellation","journal","recap","tonight","detail"].contains(screen)
        default:
            return false
        }
    }
}
