import XCTest
import AppIntents

/// Apple's automated accessibility audit (contrast, hit regions, labels, Dynamic Type,
/// clipping, traits) on every screen, in the standard palette and in night vision, and on the key
/// screens at the largest accessibility text size with Increase Contrast and Bold Text.
/// It complements, and never replaces, a VoiceOver pass on a real iPhone.
///
/// Run one screen: `TEST_RUNNER_NYX_AUDIT_SCREENS=river xcodebuild test -only-testing:NyxUITests/AccessibilityAuditTests ...`
/// A screen may name its fixture state after a colon (`ask:answered`); the palette still follows the pass.
@MainActor
final class AccessibilityAuditTests:XCTestCase {
    private var screens:[String] {
        if let only=ProcessInfo.processInfo.environment["NYX_AUDIT_SCREENS"], !only.isEmpty { return only.components(separatedBy:",") }
        return ["tonight","going","parks","parks-map","calendar","best","journal","learn","detail","breakdown","editor","entry",
                "onboarding","settings","privacy","data","article","share","river","skyarc","whatsup",
                "field","field-compass","alarm-explainer","light","lights-out","long-view","listen","accessibility","trip","constellation","recap","icons","first-light","sky","ask:answered"]
        // Not "live-activity": that DEBUG page redraws Lock Screen and Dynamic Island faces outside the
        // system containers that host, scale and tint them, so its findings do not transfer. Reviewed by screenshot.
    }

    /// The screens people live in, for the heavier passes.
    private var keyScreens:[String] {
        if let only=ProcessInfo.processInfo.environment["NYX_AUDIT_SCREENS"], !only.isEmpty { return only.components(separatedBy:",") }
        // Learn since 2026-10-13: its cards broke titles mid-word at AX5 on a wide iPad, which only this pass would see.
        // "going" (Tonight led by a kept night, `GoingPanel`) since 2026-10-22.
        return ["tonight","going","parks","parks-map","detail","plan","best","journal","settings","field","river","editor","learn"]
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

    /// Tonight scrolled down, with the tab bar minimised (`RootView`'s `.onScrollDown`) and a followed
    /// night's strip beside it when one is under way: the small bar and the accessory pass too.
    func testMinimisedTabBarPassesTheAudit() throws {
        var failures:[String]=[]
        for state in ["offline","night-vision"] {
            let app=XCUIApplication()
            app.launchArguments=["-nyx-screen","tonight","-nyx-state",state,"-nyx-reduce-motion","-nyx-following"]
            app.launch()
            _=app.wait(for:.runningForeground,timeout:30)
            // Regular width (iPad full screen, 2026-10-13): `.sidebarAdaptable` floats the tab bar at the top of the
            // window, and the system minimises only the bottom tab bar of a compact width; the top bar keeps its size
            // and its tabs are not reported as a tab bar at all. Nothing to minimise, so nothing for this pass to
            // audit there; Tonight itself is audited at that width by the other passes. A compact window (iPhone)
            // with no bottom bar still fails below.
            if UIDevice.current.userInterfaceIdiom == .pad, app.windows.firstMatch.frame.width>=700, !app.tabBars.firstMatch.exists || app.tabBars.firstMatch.frame.midY<app.frame.height/2 {
                app.terminate()
                throw XCTSkip("Regular width: the tab bar floats at the top of the window and does not minimise on scroll.")
            }
            let before=Self.span(app,timeout:10) { !$0.isNull }
            // A slow simulator may miss the first swipe's scroll: each swipe gets about five seconds
            // to minimise the bar, and up to three swipes are tried before the bar counts as unchanged.
            var after=before
            for _ in 0..<3 where after.isNull || after.width>=before.width {
                app.swipeUp(velocity:.slow)
                after=Self.span(app,timeout:5) { !$0.isNull && $0.width<before.width }
            }
            print("MINIMISED|\(state)|before \(before)|after \(after)")
            // The bar's own frame keeps the window's width when it minimises; its tabs do not. A bar that
            // no longer shrinks fails here rather than being audited at full size.
            XCTAssertLessThan(after.isNull ? .infinity : after.width,before.width,"The tab bar did not minimise on scrolling Tonight (\(state))")
            let shot=XCTAttachment(screenshot:app.screenshot()); shot.name="minimised-\(state)"; shot.lifetime = .keepAlways; add(shot)
            // The scroll's deceleration and the bar's own animation done before the audit walks the screen.
            Self.settle(app)
            failures+=try auditOpen(app,screen:"tonight",state:state,pass:"minimised")
            app.terminate()
        }
        XCTAssertTrue(failures.isEmpty,"Accessibility audit issues:\n"+failures.joined(separator:"\n"))
    }

    private func audit(state:String,screens:[String],extra:[String]=[],pass:String="default") throws {
        var failures:[String]=[]
        for spec in screens {
            // "ask:answered" opens a screen in its own fixture state; night vision then comes from its flag.
            let parts=spec.split(separator:":",maxSplits:1).map(String.init)
            let screen=parts.first ?? spec
            let fixture=parts.count>1 ? parts[1] : state
            let palette=parts.count>1 && state=="night-vision" ? ["-nyx-night-vision"] : []
            let app=XCUIApplication()
            // The editor opens on the starting park, which the simulator keeps from earlier runs: pin the longest
            // park name, so the row is audited at its widest every time.
            let pinned=screen=="editor" ? ["-homePark","blca"] : []
            app.launchArguments=["-nyx-screen",screen,"-nyx-state",fixture,"-nyx-reduce-motion"]+palette+pinned+extra
            app.launch()
            _=app.wait(for:.runningForeground,timeout:30)
            sleep(2)
            Self.settle(app)
            failures+=try auditOpen(app,screen:screen,state:state,pass:pass)
            app.terminate()
        }
        XCTAssertTrue(failures.isEmpty,"Accessibility audit issues:\n"+failures.joined(separator:"\n"))
    }
    /// The span of the tab bar's buttons that can be tapped now: the whole bar at rest, one tab (and a
    /// followed night's strip) when minimised.
    private static func tabButtonsSpan(_ app:XCUIApplication)->CGRect {
        app.tabBars.firstMatch.buttons.allElementsBoundByIndex.filter { $0.exists && $0.isHittable && !$0.frame.isEmpty }
            .reduce(CGRect.null) { $0.union($1.frame) }
    }
    /// The tab buttons' span once it meets `done` and holds still for one more look (so a bar caught
    /// mid-animation is not measured), or the last span seen when `timeout` runs out.
    private static func span(_ app:XCUIApplication,timeout:TimeInterval,until done:(CGRect)->Bool)->CGRect {
        let deadline=Date.now.addingTimeInterval(timeout)
        var last=tabButtonsSpan(app)
        while Date.now<deadline {
            Thread.sleep(forTimeInterval:0.3)
            let now=tabButtonsSpan(app)
            if done(now), now == last { return now }
            last=now
        }
        return last
    }
    /// Waits until the screen holds still: two captures half a second apart are the same, so no
    /// count-up, loader, scroll or bar animation is running when the audit walks the screen (an audit of
    /// a moving screen is slower and can time out on a loaded simulator). Gives up after `timeout` and
    /// audits anyway: a screen that never rests (a turning sky) is still audited, as before.
    private static func settle(_ app:XCUIApplication,timeout:TimeInterval=6) {
        let deadline=Date.now.addingTimeInterval(timeout)
        var last=app.screenshot().pngRepresentation
        while Date.now<deadline {
            Thread.sleep(forTimeInterval:0.5)
            let now=app.screenshot().pngRepresentation
            if now == last { return }
            last=now
        }
        print("AUDITSETTLE|still moving after \(Int(timeout)) s")
    }
    /// The audit types the full audit runs on iOS, one by one: together exactly `.all` there.
    private static let auditParts:[(name:String,type:XCUIAccessibilityAuditType)]=[
        ("contrast",.contrast),("elementDetection",.elementDetection),("hitRegion",.hitRegion),
        ("sufficientElementDescription",.sufficientElementDescription),("dynamicType",.dynamicType),
        ("textClipped",.textClipped),("trait",.trait),
    ]
    /// "Audit failed to complete in time": the audit itself gave up, which says nothing about the screen.
    private static func timedOut(_ error:Error)->Bool {
        let error=error as NSError
        return error.domain=="com.apple.xcode.xctest.accessibilityAudit" && error.code == -56
    }
    /// Audits the screen the app shows now; returns the findings that are not known false positives.
    /// When every finding is about an element that no longer exists by the time it is reported (no
    /// element, no frame), the screen is audited once more after it settles and that pass decides: on
    /// iOS 26.5 the minimised pass sometimes catches the system tab bar re-expanding under the audit's
    /// own probing, and the views in flight report "no description" (2026-10-09; the tree at that moment
    /// held only labelled app elements). A finding that is still there the second time fails.
    ///
    /// A full audit that times out (seen on a loaded simulator, never alone) is not retried whole: the
    /// screen is left to settle and audited again one audit type at a time, every type the full audit
    /// covers, each a smaller walk that fits the audit's time limit. A part that times out gets one more
    /// try after the screen settles again; a second timeout fails. Findings are never retried away.
    private func auditOpen(_ app:XCUIApplication,screen:String,state:String,pass:String,retry:Bool=true) throws->[String] {
        var failures:[String]=[]
        var unresolved:Set<String>=[]
        let window=app.frame
        // Field mode's milestones fade into the dark above the eye's clock and footer (a scroll-edge fade, by
        // design): the lowest 30% of the window, where cards scroll out under the clock.
        let fieldFade=screen=="field" ? CGRect(x:0,y:window.height*0.7,width:window.width,height:window.height*0.3) : .null
        let tabBar=app.tabBars.firstMatch.exists ? app.tabBars.firstMatch.frame : .null
        let navigationBar=app.navigationBars.firstMatch.exists ? app.navigationBars.firstMatch.frame : .null
        // What the navigation bar itself shows (its title, search field, buttons), so the bar's own text is never
        // mistaken for page content scrolled under it.
        let barLabels:Set<String>=navigationBar.isNull ? [] : Set(app.navigationBars.firstMatch.descendants(matching:.any).allElementsBoundByIndex.map(\.label).filter { !$0.isEmpty })
        // A field held to the foot of the page (Ask Nyx's question): content scrolling under it and the edge effect
        // above it (about 28 pt) is dimmed by design, as under the tab bar. Found on iPad at AX5 (2026-10-09), where
        // the tab bar sits at the top and a citation passed under the field.
        let footInput=[app.textViews.firstMatch,app.textFields.firstMatch].first { $0.exists && !$0.frame.isEmpty && $0.frame.minY>window.height/2 }
        let footField=footInput.map { CGRect(x:0,y:$0.frame.minY-28,width:window.width,height:window.height-$0.frame.minY+28) } ?? .null
        // The bars each pass measured against, so a finding near an edge can be read in context.
        print("AUDITBARS|\(pass)|\(state)|\(screen)|tabBar \(tabBar)|navigationBar \(navigationBar)|window \(window)")
        let handler:(XCUIAccessibilityAuditIssue) throws->Bool = { issue in
            let frame=issue.element?.frame ?? .null
            let label=issue.element?.label ?? ""
            let line="AUDIT|\(pass)|\(state)|\(screen)|\(issue.auditType.rawValue)|\(issue.compactDescription)|'\(label)'|\(frame)"
            print(line)
            if Self.isKnownFalsePositive(issue,screen:screen,pass:pass,frame:frame,window:window,tabBar:tabBar,navigationBar:navigationBar,barLabels:barLabels,footField:footField) { return true }
            if !fieldFade.isNull, frame.intersects(fieldFade), issue.auditType == .contrast || issue.auditType == .textClipped { return true }
            failures.append(line)
            if issue.element==nil { unresolved.insert(line) }
            return true // collect everything; fail once at the end with the full list
        }
        do { try app.performAccessibilityAudit(for:.all,handler) } catch where Self.timedOut(error) {
            print("AUDITTIMEOUT|\(pass)|\(state)|\(screen)|all")
            // What the timed-out walk reported is found again by the parts below.
            failures=[]; unresolved=[]
            Self.settle(app)
            for part in Self.auditParts {
                do { try app.performAccessibilityAudit(for:part.type,handler) } catch where Self.timedOut(error) {
                    print("AUDITTIMEOUT|\(pass)|\(state)|\(screen)|\(part.name)")
                    Self.settle(app)
                    try app.performAccessibilityAudit(for:part.type,handler)
                }
            }
        }
        // A part tried twice may report the same finding twice: once each.
        var listed:Set<String>=[]
        failures=failures.filter { listed.insert($0).inserted }
        if retry, !failures.isEmpty, failures.allSatisfy(unresolved.contains) {
            print("AUDITRETRY|\(pass)|\(state)|\(screen)|\(failures.count) findings without an element")
            sleep(2)
            return try auditOpen(app,screen:screen,state:state,pass:pass,retry:false)
        }
        // The screen as the audit left it, so a finding can be read against the pixels it was measured on.
        if !failures.isEmpty {
            let shot=XCTAttachment(screenshot:app.screenshot()); shot.name="audit-\(pass)-\(state)-\(screen)"; shot.lifetime = .keepAlways; add(shot)
        }
        return failures
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
        // The same menu under the screen's older route name (`-nyx-screen calendar`).
        ("calendar","Joshua Tree"),
        // My free nights' hero score stops at 150 pt (about three times AX5 body text) so "100" still fits the
        // width; "#" matches a label of digits only. Checked in a system AX5 capture (2026-10-08).
        ("trip","#"),
        // Plan's best nights: the same hero numeral, capped the same way.
        ("best","#"),
        // An unlabelled element of the system search bar (no frame; reported at AX5 only).
        ("parks",""),
    ]
    /// A text's contrast in its own capture: the most common colour (the ground) against the most common colour at
    /// least 1.5:1 brighter than it (the glyphs' solid core), which must cover 24 pixels or more, so a star or a
    /// glyph's anti-aliased edge cannot stand in for the text. Nil for anything but static text or a button, or when
    /// no such colour is found (the audit's finding then stands).
    private static func measuredTextContrast(_ element:XCUIElement)->Double? {
        guard [.staticText,.button].contains(element.elementType), let image=element.screenshot().image.cgImage else { return nil }
        let width=image.width, height=image.height
        guard width>0, height>0, let space=CGColorSpace(name:CGColorSpace.sRGB) else { return nil }
        var pixels=[UInt8](repeating:0,count:width*height*4)
        let drawn=pixels.withUnsafeMutableBytes { buffer->Bool in
            guard let context=CGContext(data:buffer.baseAddress,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:space,bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            context.draw(image,in:CGRect(x:0,y:0,width:width,height:height))
            return true
        }
        guard drawn else { return nil }
        var counts:[UInt32:Int]=[:]
        for i in stride(from:0,to:pixels.count,by:4) { counts[UInt32(pixels[i])<<16 | UInt32(pixels[i+1])<<8 | UInt32(pixels[i+2]),default:0]+=1 }
        func luminance(_ colour:UInt32)->Double {
            func linear(_ v:UInt32)->Double { let c=Double(v)/255; return c<=0.04045 ? c/12.92 : pow((c+0.055)/1.055,2.4) }
            return 0.2126*linear(colour>>16 & 255)+0.7152*linear(colour>>8 & 255)+0.0722*linear(colour & 255)
        }
        guard let ground=counts.max(by:{ $0.value<$1.value })?.key else { return nil }
        let floor=luminance(ground)+0.05
        guard let glyphs=counts.filter({ (luminance($0.key)+0.05)/floor>=1.5 }).max(by:{ $0.value<$1.value }), glyphs.value>=24 else { return nil }
        return (luminance(glyphs.key)+0.05)/floor
    }
    /// Each exclusion was checked by hand.
    private static func isKnownFalsePositive(_ issue:XCUIAccessibilityAuditIssue,screen:String,pass:String,frame:CGRect,window:CGRect,tabBar:CGRect,navigationBar:CGRect,barLabels:Set<String>,footField:CGRect)->Bool {
        // The tab bar plus the scroll-edge fade the system draws just above it (about 56 pt): content
        // scrolling through that band is dimmed by design, whatever the app's colours.
        // On iPad the tab bar floats at the top of the window and the edge effect runs below it (to about 84 pt).
        let topBar = !tabBar.isNull && tabBar.midY<window.height/2
        // Separate bands, never one union: the bounding box of a top band and a bottom band is the whole
        // window, which would excuse every finding on the page (the minimised pass did until 2026-10-09).
        var fadeZones:[CGRect]=tabBar.isNull ? [] : [tabBar.insetBy(dx:0,dy:-56).offsetBy(dx:0,dy:topBar ? 28 : -28)]
        let navigationFade=navigationBar.isNull ? CGRect.null : CGRect(x:0,y:0,width:window.width,height:navigationBar.maxY+56)
        // iPad: the navigation bar's own scroll-edge effect at the top of the window, whatever the tab bar reports.
        if UIDevice.current.userInterfaceIdiom == .pad, !navigationFade.isNull { fadeZones.append(navigationFade) }
        if !footField.isNull { fadeZones.append(footField) }
        // Tonight scrolled with the tab bar minimised: content passing under the navigation bar's own
        // scroll-edge effect at the top is dimmed by design, as under the tab bar.
        if pass=="minimised", !navigationFade.isNull { fadeZones.append(navigationFade) }
        // The minimised bar and the followed night's strip are what that pass is for: their own controls
        // are measured in full, never excused by the band they sit in.
        let barControl=pass=="minimised" && issue.element?.elementType == .button && !tabBar.isNull && tabBar.contains(frame)
        let visible=frame.isNull ? false : window.contains(frame) && (barControl || !fadeZones.contains { frame.intersects($0) })
        switch issue.auditType {
        case .dynamicType:
            // "Fully unsupported" always fails (the share card's route shows the rendered image, as people
            // receive it, with its spoken summary, so its fixed artwork is no longer live text). At the default
            // size the audit calls dozens of scaling texts "partially unsupported", system controls included
            // (Done, Cancel, Form headers): noise. At AX5, where it matters, only the elements below (each
            // checked in a system AX5 capture) may.
            let label=issue.element?.label ?? ""
            guard issue.compactDescription.contains("partially") else { return false }
            if pass != "ax5" { return true }
            // A system toolbar button in the navigation bar (Done, Cancel): the bar caps its own type, and
            // its buttons are reachable with the Large Content Viewer.
            if issue.element?.elementType == .button, !navigationBar.isNull, frame.intersects(navigationBar) { return true }
            // iPad (2026-10-09): the floating tab bar's four tabs (Tonight, Parks, Plan, Journal) keep their size at AX5,
            // as the system bar does everywhere, and come back with no element or frame: four such findings on each tab's
            // root screen, none elsewhere. Checked in a system AX5 capture of Plan; the bar's sidebar button opens the
            // sidebar, whose rows grow with the text.
            if UIDevice.current.userInterfaceIdiom == .pad, issue.element==nil, frame.isNull { return true }
            return partialDynamicType.contains { entry in
                guard entry.screen==screen else { return false }
                switch entry.label {
                case "": return label.isEmpty
                case "#": return !label.isEmpty && label.allSatisfy(\.isNumber)
                default: return label.hasPrefix(entry.label)
                }
            }
        case .contrast:
            // Text measured against the translucent tab bar, or glass with no element, not against its own background.
            // "Nearly passed" is not a failure; it is measured where a star sits beside small text.
            // Night-vision score numerals: the red is 6.2:1 on black (large text needs 3:1); the audit samples the
            // anti-aliased diagonal of thin serif digits such as "77". Checked by eye in a captured frame.
            let numeral = !(issue.element?.label ?? "").isEmpty && (issue.element?.label ?? "").allSatisfy(\.isNumber)
            // Parks band labels under each score ("Pristine", "Estimate"), in the standard passes only: starlight at 72% on
            // black is about 11:1, and the audit can sample a real star inside the glyph box on some nights. Under Increase
            // Contrast (the AX5 passes) the sky is veiled by half and the stars fainter than about magnitude 3 are gone, so
            // those passes carry no exemption (2026-10-08).
            let bandLabel=pass != "ax5" && ["Pristine","Excellent","Good","Fair","Poor","Estimate"].contains(issue.element?.label ?? "")
            // iOS 27 draws system toolbar buttons (Done, Cancel, Save, Edit) on glass the audit cannot sample;
            // they render light-on-dark and legible (checked by screenshot). iOS 26 passes the same buttons.
            // The same glass, unsampled, on a sheet's own top-corner "Close" (permission explainers), checked by screenshot.
            let toolbarButton=issue.element?.elementType == .button && ((!navigationBar.isNull && frame.intersects(navigationBar)) || (screen.hasSuffix("explainer") && frame.maxY<120))
            // Year recap (2026-10-06): its light serif tile numerals ("7") in night vision and the serif heading over the row of
            // Moons sample as low contrast on the same anti-aliased strokes; starlight on solid indigo is about 13:1, red on
            // night-vision black 6.2:1. Checked by eye in zoomed iOS 27 captures in both palettes.
            let recapSerif=screen=="recap" && (numeral || issue.element?.label=="The Moon's phases you met")
            // iPad Learn grid (2026-10-06): the right-hand cards' "2-minute read" captions, starlight at 86% on the indigo
            // panel (about 12:1); the audit samples the glass over the Milky Way behind them. Checked in a zoomed capture.
            let learnCaption=screen=="learn" && (issue.element?.label ?? "").hasSuffix("-minute read")
            // Plan's score under each night (2026-10-08): "77" at 11 pt, starlight at 72% (#B1AEA6) on black is 9.5:1 and
            // night vision's red 5.7:1, measured in the audit's own captures; the audit fails the doubled thin diagonals
            // of "77" only (semibold fails the same way). Checked by eye, zoomed, in both palettes on iOS 27.
            let nightScore=(screen=="calendar" || screen=="plan") && numeral && frame.height<20
            // iOS 26.5 (2026-10-13): the audit's own walk scrolls Parks about 187 pt, leaving rows under the status bar, the
            // navigation bar and its always-shown search field, where the bar's glass dims them by design ("Best Wed · 97"
            // measured 1.50:1 through the search field's glass). Captures before and after the audit: the list at rest
            // starts below the field; afterwards "Darkest tonight first" sits under the status bar. Page content under the
            // bar only; the bar's own title, field and buttons are not excused here. Parks only: its list begins below the
            // field at rest, while other pages (the park's hero) may sit under a clear bar by design and stay measured.
            let underBar=screen=="parks" && !navigationBar.isNull && frame.minY<navigationBar.maxY && !barLabels.contains(issue.element?.label ?? "")
            if !visible || underBar || issue.compactDescription.contains("nearly") || (screen=="parks" && (numeral || bandLabel)) || toolbarButton || recapSerif || learnCaption || nightScore { return true }
            // iPad (2026-10-09): over the real sky the audit misjudges small text it can read in the pixels. Plan's
            // "CA · International Dark Sky Park" captures at 9.6:1 (5.7:1 in night vision) and passes over plain black or
            // with the faint layer off: the Milky Way's glow, one to five levels above black and invisible, outnumbers the
            // glyphs in the audit's own colour count (onboarding's "Skip", 18.6:1 in its capture, the same). So on iPad a
            // text's or a button's finding is measured once more in its own capture, and stands unless its glyphs reach
            // 4.5:1 there (`measuredTextContrast`).
            // iPhone too (2026-10-10): the darkness essay's second paragraph, starlight on black, failed in both palettes
            // while measuring 18.6:1 in its own capture; the still, seeded stars behind the column misled the colour count.
            guard let element=issue.element, let ratio=measuredTextContrast(element) else { return false }
            print("AUDITMEASURED|\(screen)|'\(element.label)'|\(String(format:"%.2f",ratio)):1")
            return ratio>=4.5
        case .textClipped:
            // Scrolled below the fold or behind the tab bar, not truncated; the system search field's placeholder;
            // or PhotosPicker's own "Choose photos" label, which renders in full (checked by screenshot).
            // On iPad the Parks search field sits in the split view's list column; its placeholder is reported as its own element.
            // The DEBUG `light` route (the Sky glow panel pushed alone, no tab bar) opens at the top with its content running
            // on past the home indicator, so whichever line lies across the home-indicator inset (the bottom 34 pt) at rest is
            // reported as clipped by that inset. It renders in full there (capture 2026-10-09) and scrolls clear of it; on the
            // park page the same panel sits mid-page. Clipping only, and only across that inset: contrast there is measured, as
            // is clipping everywhere else on the route. Replaces a 62 pt band that also excused contrast.
            let homeIndicator=CGRect(x:0,y:window.height-34,width:window.width,height:34)
            let pastHomeIndicator=screen=="light" && tabBar.isNull && UIDevice.current.userInterfaceIdiom == .phone && frame.intersects(homeIndicator)
            // iPad Learn grid (2026-10-13): the three-column card's title "Watching a / meteor shower" (the system lifts "meteor"
            // so "shower" is not left alone) gets a frame hugging its wider line, "meteor shower" (New York 20 pt, 136.46 pt),
            // which SwiftUI sets at 136.5 pt on the 2x pixel grid; laid out again in that frame, the audit's own measure pushes
            // "shower" to a third line. Both lines render in full (zoomed iPad Pro 13-inch capture, both palettes). Giving the
            // title the card's width (2026-10-09) and starting it on a whole point did not change the text's own frame.
            // Standard text sizes only: at AX5 the cards stand one to a row, and a clipped title there is measured.
            let learnTitle=screen=="learn" && pass != "ax5" && UIDevice.current.userInterfaceIdiom == .pad && issue.element?.elementType == .staticText && issue.element?.label=="Watching a meteor shower"
            // iPad Your privacy (2026-10-14): the four- and five-line caption under Smoke and haze and under Park alerts, in some
            // runs only (default and night vision), on iOS 27. The audit's own captures show both in full, down to "IP address.";
            // the same quirk as the Learn title. These network captions only, at standard sizes; AX5 still measures them.
            let privacyCaption=screen=="privacy" && pass != "ax5" && UIDevice.current.userInterfaceIdiom == .pad && issue.element?.elementType == .staticText && (issue.element?.label ?? "").hasSuffix("network information such as your IP address.")
            // The `light` route's Protect this sky card (2026-10-21, once it became its own card and moved on screen): the
            // two-line serif "An International Dark Sky Park, certified by DarkSky International." Its second line sets at about
            // 290 of the frame's 299 pt; laid out again by the audit's own measure it takes a third line. Both lines render in
            // full (capture 2026-10-21), and the text grows with its content, so a real third line would show.
            // The same quirk as the Learn title. This line only, at standard sizes; AX5 still measures it.
            let designationLine=screen=="light" && pass != "ax5" && issue.element?.elementType == .staticText && issue.element?.label=="An International Dark Sky Park, certified by DarkSky International."
            return !visible || pastHomeIndicator || learnTitle || privacyCaption || designationLine || issue.element?.elementType == .searchField || issue.element?.label=="Park or state" || (screen=="editor" && issue.element?.label=="Choose photos")
        case .elementDetection:
            // Decorative "NYX" wordmark and the time river's Canvas-drawn dates; the river element speaks the full value.
            // The sky map's Canvas-drawn inset names (Alaska, Hawaiʻi, Am. Samoa, Virgin Is.): decoration; each star is a
            // labelled button and the map has a spoken summary.
            // iPad (2026-10-06): the river is on screen on Tonight (wide) and in the detail's hero column.
            // iPad (2026-10-09): Parks' split view shows the chosen park's page beside the list, river and all; the same
            // element-less finding appears on the detail and river routes, and the list itself passes on iPhone.
            let padParks=screen=="parks" && UIDevice.current.userInterfaceIdiom == .pad
            return issue.element==nil && (padParks || ["onboarding","river","constellation","journal","recap","tonight","detail"].contains(screen))
        default:
            return false
        }
    }
}
