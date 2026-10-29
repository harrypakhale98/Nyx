import AlarmKit
import SwiftUI
import SwiftData

/// Field mode: the night itself, at the park. Black everywhere, red through the night-vision
/// filter whatever the app's setting, large serif type, one fact at a time. The milestones scroll
/// like a crown, snapping one by one with a light tick; "Where to look" turns the real sky to the
/// phone. The dark-adaptation clock runs along the bottom, over Field's own controls: glove-grade,
/// 60 points or more, all within a thumb's reach at the foot of the screen.
struct FieldView: View {
    enum Page: Hashable { case night, look }
    let session: FieldSession
    var initialPage: Page = .night
    /// DEBUG: a fixed pose for the compass, so the simulator can show it.
    var fixedPose: SkyCompass.Pose?=nil
    /// DEBUG: open with the "Wake me" sheet showing.
    var showsAlarms=false
    let close: ()->Void
    @State private var page: Page?
    @State private var focused: String?
    @State private var alarmsShown: Bool?
    @State private var aboutEyes=false
    @Environment(\.colorSchemeContrast) private var contrast
    @AppStorage(NightTint.key,store:SharedSettings.defaults) private var brighterRed=false
    @Environment(\.dynamicTypeSize) private var typeSize
    @MotionReduced private var reduceMotion: Bool
    private var current: Page { page ?? initialPage }
    private var alarms: Binding<Bool> { Binding(get:{ alarmsShown ?? showsAlarms },set:{ alarmsShown=$0 }) }
    /// At accessibility sizes the eye's clock scrolls with the page instead of standing in the
    /// footer, so the countdown keeps the room it needs.
    private var inline: Bool { typeSize.isAccessibilitySize }
    /// "Your eyes started over" scrolls with the page at accessibility sizes and at compact height
    /// (an iPhone in landscape), where standing above the page it would push the page, its own
    /// buttons and the footer off the screen.
    private var resetInPage: Bool { inline || verticalSize == .compact }
    /// The window's size, for the side-by-side layout.
    @State private var size=CGSize.zero
    /// A wide landscape window: "The night" and "Where to look" side by side, with no switch between them.
    private var sideBySide: Bool { WideLayout.sideBySide(width:size.width,height:size.height,largeText:typeSize.isAccessibilitySize,compactHeight:verticalSize == .compact) }
    @Environment(\.verticalSizeClass) private var verticalSize
    /// iPhone Duo's inner display, half open like a book or open flat (`readingFold`): the night on one side of the fold, the sky on the other.
    @State private var fold: Fold?
    private var foldSplit: (leading: CGFloat, gap: CGFloat)? {
        guard sideBySide, let fold, let leading=fold.leadingWidth(in:size.width,minimum:320) else { return nil }
        return (CGFloat(leading), CGFloat(fold.width))
    }
    /// The night's pages, beside the sky or on their own.
    private var nightPager: some View { FieldNightPager(session:session,focused:$focused,eyeClock:inline ? $aboutEyes : nil,note:inline ? basisNote : nil,showsReset:resetInPage) }
    /// What the score's clouds rest on, without a full cloud forecast (offline with nothing cached, or a stale one).
    /// Field mode is tonight, always within a forecast's reach: without one, it is unavailable, never "not yet".
    private var basisNote: String? {
        // With no usual clouds for the night's month, an early look counts the forecast as it stands.
        return Self.basisNote(session.score,usualClouds:session.usualClouds)
    }
    /// What the score's clouds rest on, said as the park page says it (`CloudBasis.earlyLookCaption`); nil with a full forecast.
    nonisolated static func basisNote(_ score:DarknessScore,usualClouds:Bool)->String? {
        guard !score.hasForecast else { return nil }
        if let early=score.basis.earlyLookCaption(usualClouds:usualClouds) { return early }
        return Sentences.join([String(localized:"Cloud forecast unavailable."),score.cloudPoints == nil ? String(localized:"This score counts the Moon and darkness only.") : String(localized:"This score uses the park's usual clouds.")])
    }
    /// Red whatever the app's setting. Built here, not read from the environment: this view sets it for everything inside.
    private var palette: NyxPalette { NyxPalette(nightVision:true,highContrast:contrast == .increased,brighterRed:brighterRed || DebugScenario.isEnabled("brighter-red")) }
    var body: some View {
        VStack(spacing:0) {
            header
            // Without a full cloud forecast (offline with nothing cached, or a stale one) the score says
            // what its clouds rest on, under it, aligned with the park's name.
            // At accessibility sizes it scrolls with the page instead, so the page keeps its room.
            if let basisNote, !inline {
                Text(basisNote).font(.caption)
                    .fixedSize(horizontal:false,vertical:true).frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,24)
            }
            // In the flow, not over it: the countdown under it stays readable.
            if let reset=session.reset, !resetInPage { FieldResetNotice(session:session,reset:reset).padding(.horizontal,16).padding(.top,8).transition(.opacity.combined(with:.move(edge:.top))) }
            Group {
                if sideBySide {
                    // The night on the left, the sky on the right; the eye's clock stays with the night.
                    // On iPhone Duo's inner display, the hairline is the fold itself and each page keeps to its side.
                    let split=foldSplit
                    HStack(spacing:0) {
                        nightPager.frame(width:split?.leading).frame(maxWidth:split == nil ? .infinity : nil)
                        Rectangle().fill(palette.line).frame(width:split == nil ? 0.5 : 0).padding(.vertical,24).frame(width:split?.gap).accessibilityHidden(true)
                        FieldCompassView(session:session,fixedPose:fixedPose).frame(maxWidth:.infinity)
                    }
                } else {
                    switch current {
                    case .night: nightPager
                    case .look: FieldCompassView(session:session,fixedPose:fixedPose,eyeClock:inline ? $aboutEyes : nil,note:inline ? basisNote : nil,showsReset:resetInPage)
                    }
                }
            }.frame(maxHeight:.infinity)
            // The pages' own buttons (the compass's, "Keep this night") at their largest, for gloved thumbs.
            .controlSize(.extraLarge)
            .readingFold($fold)
            .animation(reduceMotion ? nil : NyxMotion.spring,value:fold)
            footer
        }
        .background(Color.black.ignoresSafeArea())
        .onGeometryChange(for:CGSize.self) { CGSize(width:$0.size.width.rounded(),height:$0.size.height.rounded()) } action:{ size=$0 }
        // VoiceOver's two-finger scrub leaves field mode, as it would leave any modal screen. On a
        // container, so the action is not copied onto every caption inside (which would make them
        // read as small buttons).
        .accessibilityElement(children:.contain)
        .accessibilityAction(.escape) { NightListener.shared.stop(); close() }
        .animation(reduceMotion ? nil : NyxMotion.spring,value:session.reset)
        // Back from time away with the clock started over: where the notice opens the page, the page
        // returns to it (it may have been scrolled to a later milestone), and VoiceOver hears it either way.
        // Every new start-over (a second return while the notice still shows makes a new one) brings it back.
        .onChange(of:session.reset) { _,reset in
            guard let reset else { return }
            if resetInPage { withAnimation(reduceMotion ? nil : NyxMotion.spring) { focused="now" } }
            AccessibilityNotification.Announcement(String(localized:"Your eyes started over at \(session.park.time(reset.at)).")).post()
        }
        #if DEBUG
        // `-nyx-state reset-later`: scrolled to the night's last milestone, then the eyes start over, as after a return.
        .task {
            guard DebugScenario.state == "reset-later" else { return }
            try? await Task.sleep(for:.seconds(1))
            focused=session.night.cards(after:session.now,status:session.night.status(at:session.now)).last?.id
            try? await Task.sleep(for:.seconds(3))
            session.reset=DarkAdaptation.Reset(at:session.now.addingTimeInterval(-60),previousStart:session.now.addingTimeInterval(-26*60))
        }
        #endif
        .environment(\.nyx,palette)
        .foregroundStyle(palette.ink,palette.muted,palette.muted).tint(palette.ink)
        .modifier(NightVisionFilter(enabled:true,red:palette.red))
        .preferredColorScheme(.dark)
        .statusBarHidden(true).persistentSystemOverlays(.hidden)
        // Remembered so the park's page can offer "Keep this night" the morning after.
        .onAppear { if session.changesPhone { KeepThisNight.record(park:session.park,night:session.night.sky.evening) } }
        .modifier(FieldJournalStore())
        .sensoryFeedback(.selection,trigger:focused)
        .sensoryFeedback(.impact(weight:.light),trigger:session.milestonesPassed)
        // True darkness is the night's milestone: the vocabulary's medium pulse (the success thump is the journal's).
        .sensoryFeedback(.impact(weight:.medium),trigger:session.darknessBegan)
        .sheet(isPresented:alarms) {
            NavigationStack {
                ScrollView { FieldAlarmRows(park:session.park,options:session.night.alarmOptions(at:session.now),rowHeight:60).padding(24) }
                    .background(Color.black).navigationTitle("Wake me").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement:.cancellationAction) { Button(role:.close) { alarms.wrappedValue=false } } }.singleControlBar()
            }
            // The palette goes outside, so the red presentation style reads it (a sheet does not inherit it from here).
            .nyxPresentation().environment(\.nyx,palette).presentationDetents([.medium,.large])
        }
    }
    // MARK: Header: the park and its score

    /// Facts only: what Field does sits at the foot of the screen, where a thumb reaches it one-handed.
    private var header: some View {
        VStack(alignment:.leading,spacing:2) {
            // Wraps to its full height, never shrunk or cut: the pages below give way instead.
            Text(session.park.shortName).font(.system(.headline,design:.serif)).fixedSize(horizontal:false,vertical:true)
            // Wraps at accessibility sizes rather than cutting the band short.
            Text("\(session.score.value) · \(session.score.band.label)").font(.caption).monospacedDigit().fixedSize(horizontal:false,vertical:true)
        }
        // One spoken line; the visible caption keeps its own short text.
        .accessibilityElement(children:.ignore)
        .accessibilityLabel("\(session.park.shortName). Darkness score \(session.score.value), \(session.score.band.label)")
        .frame(maxWidth:.infinity,alignment:.leading)
        .padding(.horizontal,24).padding(.top,12)
    }
    // MARK: Footer: the eye's clock, then leave, the two pages and the night's options

    private var footer: some View {
        VStack(spacing:14) {
            if !inline { EyeClock(session:session,expanded:$aboutEyes) }
            // In one row while it fits; otherwise (accessibility sizes, longer translations) the page
            // switch takes the full width over leave and options, which keep the corners.
            ViewThatFits(in:.horizontal) {
                HStack(spacing:10) { closeButton; if sideBySide { Spacer(minLength:10) } else { pageSwitch }; optionsMenu }
                VStack(spacing:10) {
                    if !sideBySide { pageSwitch }
                    HStack(spacing:10) { closeButton; Spacer(minLength:10); optionsMenu }
                }
            }
        }
        .padding(.horizontal,16).padding(.bottom,8).padding(.top,8)
        .readableColumn(WideLayout.proseWidth)
    }
    private var closeButton: some View {
        Button { NightListener.shared.stop(); close() } label:{ FieldGlyph(symbol:"xmark") }
            .buttonStyle(.plain)
            // A keyboard's Escape leaves too, beside VoiceOver's scrub (the cover itself has no swipe to dismiss).
            .keyboardShortcut(.cancelAction)
            .accessibilityLabel("Leave field mode").accessibilityInputLabels([Text("Leave"),Text("Close"),Text("Leave field mode")])
            .accessibilityShowsLargeContentViewer { Label("Leave field mode",systemImage:"xmark") }
    }
    private var optionsMenu: some View {
        Menu {
            if FieldAlarms.supported && !session.night.alarmOptions(at:session.now).isEmpty { Button("Wake me…",systemImage:"alarm") { alarms.wrappedValue=true } }
            if FieldActivities.enabled || !session.changesPhone {
                Toggle(isOn:Binding(get:{ session.following },set:{ session.follow($0) })) { Label("Follow on the Lock Screen",systemImage:"lock.rectangle") }
            }
            // Tonight as twelve seconds of sound; best with headphones, out of respect for the dark around you.
            if NightListener.shared.isPlaying { Button("Stop listening",systemImage:"stop.fill") { NightListener.shared.stop() } }
            else { Button("Listen to tonight",systemImage:"waveform") { NightListener.shared.play(NightSonification(park:session.park,sky:session.night.sky)) } }
            // For the eyes reading it: a red that holds its contrast for colour-blind eyes, and the person's own brightness.
            Section {
                Toggle(isOn:$brighterRed) { Label("Brighter red",systemImage:"circle.lefthalf.filled") }
                Toggle(isOn:Binding(get:{ session.keepsBrightness },set:{ session.keepBrightness($0) })) { Label("Keep my brightness",systemImage:"sun.max") }
            }
        } label:{ FieldGlyph(symbol:"ellipsis") }
            .accessibilityLabel("Field mode options").accessibilityInputLabels([Text("Options"),Text("Field mode options")])
            .accessibilityShowsLargeContentViewer { Label("Field mode options",systemImage:"ellipsis") }
    }
    private func pageTitle(_ page:Page)->Text {
        switch page {
        case .night: Text("The night")
        case .look: Text("Where to look")
        }
    }
    /// The night or where to look, one at a time (both show side by side on a wide landscape window).
    /// Two 60-point halves of one capsule rather than a segmented control, whose segments do not grow;
    /// at accessibility sizes a menu, which never clips its labels. Switching is a cut, never a slide.
    @ViewBuilder private var pageSwitch: some View {
        if inline {
            Menu {
                Picker("View",selection:Binding(get:{ current },set:{ page=$0 })) {
                    pageTitle(.night).tag(Page.night)
                    pageTitle(.look).tag(Page.look)
                }
            } label:{
                HStack(spacing:10) {
                    pageTitle(current).fixedSize(horizontal:false,vertical:true)
                    Spacer(minLength:0)
                    Image(systemName:"chevron.up.chevron.down").accessibilityHidden(true)
                }
                .font(.subheadline.weight(.semibold)).padding(.horizontal,20).padding(.vertical,8)
                .frame(maxWidth:.infinity).modifier(FieldKey())
            }
            .accessibilityLabel("View").accessibilityValue(pageTitle(current))
        } else {
            FieldSegments { segment(.night); segment(.look) }
                .modifier(FieldKey())
                .accessibilityElement(children:.contain)
        }
    }
    private func segment(_ target:Page)->some View {
        let selected=current == target
        return Button { page=target } label:{
            pageTitle(target).font(.subheadline.weight(selected ? .semibold : .regular)).lineLimit(1)
                .padding(.horizontal,16).frame(maxWidth:.infinity,minHeight:60)
                // The chosen half carries a lit inner capsule as well as heavier type, so it never rests on colour alone.
                .background { if selected { Capsule().fill(palette.ink.opacity(0.16)).overlay(Capsule().strokeBorder(palette.line,lineWidth:palette.stroke)).padding(5) } }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The page switch's halves: each its own label's width plus an equal share of what is left, so the
/// longer label is never cut to make the halves equal. Its ideal width is the labels' own, so the
/// footer's `ViewThatFits` moves the switch to its own row before anything is cut.
private struct FieldSegments: Layout {
    func sizeThatFits(proposal:ProposedViewSize,subviews:Subviews,cache:inout ())->CGSize {
        let sizes=subviews.map { $0.sizeThatFits(.unspecified) }
        let natural=sizes.reduce(0) { $0+$1.width }
        return CGSize(width:max(natural,proposal.width ?? natural),height:sizes.map(\.height).max() ?? 0)
    }
    func placeSubviews(in bounds:CGRect,proposal:ProposedViewSize,subviews:Subviews,cache:inout ()) {
        let sizes=subviews.map { $0.sizeThatFits(.unspecified) }
        let share=subviews.isEmpty ? 0 : max(0,bounds.width-sizes.reduce(0) { $0+$1.width })/Double(subviews.count)
        var x=bounds.minX
        for (subview,size) in zip(subviews,sizes) {
            subview.place(at:CGPoint(x:x,y:bounds.minY),proposal:ProposedViewSize(width:size.width+share,height:bounds.height))
            x+=size.width+share
        }
    }
}
/// A glove-grade key: at least 60 points each way, the palette's panel inside its line, so it reads
/// in the dark without lighting it. Equal sides make it a circle.
private struct FieldKey: ViewModifier {
    @Environment(\.nyx) private var palette
    func body(content:Content)->some View {
        content.frame(minWidth:60,minHeight:60)
            .background(Capsule().fill(palette.panel))
            .overlay(Capsule().strokeBorder(palette.line,lineWidth:palette.stroke*0.75))
            .contentShape(Capsule())
    }
}
/// A symbol on a glove-grade key. The glyph stops growing at the first accessibility size, so the
/// row keeps both corners; a long press shows it large (`accessibilityShowsLargeContentViewer`).
private struct FieldGlyph: View {
    let symbol: String
    var body: some View {
        Image(systemName:symbol).font(.title3.weight(.semibold)).dynamicTypeSize(...DynamicTypeSize.accessibility1).modifier(FieldKey())
    }
}

/// "Your eyes started over": after time away from field mode, the eye's clock starts again unless
/// the person says the screen stayed dark. Above the page at standard sizes in portrait; in the
/// page itself at accessibility sizes and at compact height (`FieldView.resetInPage`).
struct FieldResetNotice: View {
    let session: FieldSession
    let reset: DarkAdaptation.Reset
    @Environment(\.nyx) private var palette
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            Text("Your eyes started over at \(session.park.time(reset.at)).").font(.system(.headline,design:.serif))
                .fixedSize(horizontal:false,vertical:true)
            Text("Nyx can't see what you looked at while you were away. Bright light resets dark adaptation.").font(.subheadline)
                .fixedSize(horizontal:false,vertical:true)
            ViewThatFits(in:.horizontal) {
                HStack(spacing:12) { buttons }
                VStack(alignment:.leading,spacing:8) { buttons }
            }
        }
        .padding(18).frame(maxWidth:.infinity,alignment:.leading)
        .background(RoundedRectangle(cornerRadius:20).fill(palette.panel))
        .overlay(RoundedRectangle(cornerRadius:20).strokeBorder(palette.line,lineWidth:palette.stroke*0.5))
        .accessibilityElement(children:.contain)
    }
    @ViewBuilder private var buttons: some View {
        Button { session.reset=nil } label:{ key("Start over") }.buttonStyle(.plain)
        Button { session.keepAdaptation() } label:{ key("My screen stayed dark") }.buttonStyle(.plain)
    }
    private func key(_ title:LocalizedStringKey)->some View {
        Text(title).font(.subheadline.weight(.semibold)).fixedSize(horizontal:false,vertical:true)
            .padding(.horizontal,20).padding(.vertical,8).modifier(FieldKey())
    }
}

// MARK: The night, one milestone at a time

/// "Now" first, then each milestone still ahead, snapping into place one at a time. Passed
/// milestones collect quietly at the end.
struct FieldNightPager: View {
    let session: FieldSession
    @Binding var focused: String?
    /// At accessibility sizes, the eye's clock scrolls here, under "Now" and with it.
    var eyeClock: Binding<Bool>?=nil
    /// At accessibility sizes, what the score's clouds rest on scrolls here, above "Now", instead of under the header.
    var note: String?=nil
    /// At accessibility sizes and at compact height, "Your eyes started over" opens the page.
    var showsReset=false
    @Environment(\.nyx) private var palette
    @MotionReduced private var reduceMotion: Bool
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @ScaledMetric(relativeTo:.largeTitle) private var numeral=68.0
    /// The page's visible height, which the two tap zones split.
    @State private var height=0.0
    /// The fades at the page's edges, in points: fixed, so the bottom margin can always clear the lower one.
    private static let topFade=16.0, bottomFade=44.0
    private static let space="fieldPage"
    var body: some View {
        TimelineView(.periodic(from:.now,by:30)) { _ in
            let now=session.now
            // Each fact once: no card for the moment "Now" is already counting toward.
            let ahead=session.night.cards(after:now,status:session.night.status(at:now)), passed=session.night.milestones.filter { $0.date<=now }
            // The page's stops in order, for the tap zones: "Now", each milestone ahead, then the night so far.
            let stops=["now"]+ahead.map(\.id)+(passed.isEmpty ? [] : ["earlier"])
            ScrollView(.vertical) {
                LazyVStack(alignment:.leading,spacing:44) {
                    VStack(alignment:.leading,spacing:20) {
                        if showsReset, let reset=session.reset { FieldResetNotice(session:session,reset:reset).transition(.opacity) }
                        if let note { Text(note).font(.caption).fixedSize(horizontal:false,vertical:true).frame(maxWidth:.infinity,alignment:.leading) }
                        nowCard(now)
                        // Part of "Now", not a stop of its own: the page snaps from "Now" straight to the next
                        // milestone. On its own the clock was a separate snap stop, and on iPad at AX5 the
                        // accessibility audit could not size its text there (reported as not scaling).
                        if let eyeClock { EyeClock(session:session,expanded:eyeClock).padding(.top,24) }
                    }.id("now")
                    ForEach(ahead) { milestone in card(milestone,now:now).id(milestone.id) }
                    if !passed.isEmpty { earlier(passed).id("earlier") }
                }
                .scrollTargetLayout()
                // Two big tap zones for a gloved thumb: the upper half of the visible page goes back a stop,
                // the lower half on. On the content, measured in the page's own frame: a gesture on the
                // ScrollView itself never sees taps its scroll view takes. Buttons inside keep their taps
                // (a child's gesture wins), and a drag still scrolls. Off under VoiceOver, which steps
                // through the cards (and the Milestones rotor) on its own, so a double-tap on a card never
                // moves the page under it; the zones are never exposed as elements.
                .contentShape(Rectangle())
                .gesture(SpatialTapGesture(coordinateSpace:.named(Self.space)).onEnded { tap in step(tap.location.y<height/2 ? -1 : 1,through:stops) },isEnabled:!voiceOver)
                // VoiceOver: step through what is still to come tonight, one milestone at a time.
                .accessibilityRotor(Text("Milestones"),entries:ahead.map { MilestoneStop(id:$0.id,label:String(localized:"\($0.title), \(session.night.park.time($0.date))")) },entryID:\.id,entryLabel:\.label)
                .padding(.horizontal,24)
                // An iPad in landscape: one milestone at a time, at a reading width.
                .readableColumn(WideLayout.proseWidth)
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id:$focused,anchor:.top)
            // The last stop scrolls clear of the lower fade, never resting in it above the controls.
            .contentMargins(.top,28,for:.scrollContent).contentMargins(.bottom,28+Self.bottomFade,for:.scrollContent)
            // Text fades into the dark before it reaches the eye's clock below.
            .mask {
                VStack(spacing:0) {
                    LinearGradient(colors:[.clear,.black],startPoint:.top,endPoint:.bottom).frame(height:Self.topFade)
                    Rectangle()
                    LinearGradient(colors:[.black,.clear],startPoint:.top,endPoint:.bottom).frame(height:Self.bottomFade)
                }
            }
            .onGeometryChange(for:Double.self) { $0.size.height } action:{ height=$0 }
            .coordinateSpace(.named(Self.space))
        }
    }
    /// One stop back or on, with the page's light tick (`FieldView`'s selection feedback on `focused`).
    /// A cut under Reduce Motion; the shared spring otherwise. Past either end, nothing moves.
    private func step(_ delta:Int,through stops:[String]) {
        let index=stops.firstIndex(of:focused ?? "now") ?? 0
        guard stops.indices.contains(index+delta) else { return }
        withAnimation(reduceMotion ? nil : NyxMotion.spring) { focused=stops[index+delta] }
    }
    private func dims(_ content:some View)->some View {
        content.scrollTransition(.interactive) { [still = reduceMotion] view,phase in
            view.scaleEffect(still || phase.isIdentity ? 1 : 0.96,anchor:.leading)
        }
    }
    private func nowCard(_ now:Date)->some View {
        let status=session.night.status(at:now)
        return dims(VStack(alignment:.leading,spacing:10) {
            Eyebrow(text:"Now")
            Text(status.lead).font(.system(.title2,design:.serif)).fixedSize(horizontal:false,vertical:true)
            if let target=status.target { FieldCountdown(target:session.real(target),numeral:numeral) }
            if !status.trailing.isEmpty { Text(status.trailing).font(.system(.title3,design:.serif)).fixedSize(horizontal:false,vertical:true) }
            // Dawn: the night can go straight into the journal, with the park, the date and the score
            // (not when the journal could not open, since the entry would not last).
            if status.phase == .over, !JournalAccess.unavailable, KeepThisNight.container != nil || DebugScenario.screen != nil {
                KeepThisNightButton(prefill:JournalPrefill(parkID:session.park.id,date:session.night.sky.evening,observedBortle:session.park.bortleEstimate,
                    notes:JournalPrefill.note(score:session.score,moon:session.night.sky.moon)),prominent:false)
                    .padding(.top,10)
            }
            Text(moonLine(now)).font(.subheadline).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true).padding(.top,6)
        }
        .frame(maxWidth:.infinity,alignment:.leading)
        .accessibilityElement(children:status.phase == .over ? .contain : .ignore)
        .accessibilityLabel([status.spoken,darknessExplained(status),moonLine(now)].compactMap { $0 }.joined(separator:" ")))
    }
    private func card(_ milestone:FieldNight.Milestone,now:Date)->some View {
        let park=session.night.park
        let until=String(localized:"in \(FieldNight.span(milestone.date.timeIntervalSince(now)))")
        return dims(VStack(alignment:.leading,spacing:8) {
            HStack(alignment:.firstTextBaseline,spacing:12) {
                Image(systemName:milestone.symbol).font(.title2).accessibilityHidden(true)
                Text(park.time(milestone.date)).font(.system(.largeTitle,design:.serif)).monospacedDigit()
            }
            Text(milestone.title).font(.system(.title2,design:.serif)).fixedSize(horizontal:false,vertical:true)
            Text(until).font(.subheadline.weight(.medium))
            Text(milestone.detail).font(.body).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
        }
        .frame(maxWidth:.infinity,alignment:.leading)
        .accessibilityElement(children:.ignore)
        .accessibilityLabel("\(milestone.title), \(park.time(milestone.date)), \(String(localized:"in \(FieldNight.spokenSpan(milestone.date.timeIntervalSince(now)))")). \(milestone.detail)"))
    }
    /// While waiting, the darkness card is not shown, so its explanation joins the spoken Now card.
    private func darknessExplained(_ status:FieldNight.Status)->String? {
        guard status.phase == .waiting else { return nil }
        return session.night.milestones.first { $0.kind == .darkness && $0.date == status.target }?.detail
    }
    private func earlier(_ passed:[FieldNight.Milestone])->some View {
        VStack(alignment:.leading,spacing:10) {
            Eyebrow(text:"Earlier tonight")
            ForEach(passed) { milestone in
                VStack(alignment:.leading,spacing:4) {
                    HStack(alignment:.firstTextBaseline) {
                        Text(milestone.title).fixedSize(horizontal:false,vertical:true)
                        Spacer(minLength:8)
                        Text(session.night.park.time(milestone.date)).monospacedDigit()
                    }
                    // True darkness never had a card of its own while "Now" counted toward it: what it means stays here.
                    if milestone.kind == .darkness { Text(milestone.detail).font(.footnote).fixedSize(horizontal:false,vertical:true) }
                }.font(.subheadline).foregroundStyle(palette.muted)
                .accessibilityElement(children:.combine)
            }
        }.padding(.bottom,24)
    }
    /// Where the Moon is now, in one line.
    private func moonLine(_ now:Date)->String {
        let night=session.night, sky=night.sky
        // Too thin to matter (`MoonPhase.negligible`), as the verdict and reminders say it; "new moon" is the
        // phase name, under 3% (`MoonPhase.name`).
        if sky.moon.negligible { return String(localized:"Almost no moonlight tonight.") }
        let lit=sky.moon.litText
        let up=AstronomyEngine().lunarAltitude(at:now,park:night.park) > -0.833
        if up { return sky.moonset.flatMap { $0>now ? String(localized:"Moon up, \(lit). It sets at \(night.park.time($0)).") : nil } ?? String(localized:"Moon up, \(lit).") }
        return sky.moonrise.flatMap { $0>now ? String(localized:"Moon below the horizon until \(night.park.time($0)).") : nil } ?? String(localized:"Moon below the horizon.")
    }
}

/// A milestone's rotor stop: "Moonrise, 1:12 AM", in park time like its card.
struct MilestoneStop: Identifiable { let id: String; let label: String }

// MARK: The eye's clock

/// How far into dark adaptation the eye should be, from the time spent in red light. An estimate,
/// said plainly; tapping it explains the physiology.
struct EyeClock: View {
    let session: FieldSession
    @Binding var expanded: Bool
    @Environment(\.nyx) private var palette
    var body: some View {
        TimelineView(.periodic(from:.now,by:15)) { _ in
            let now=session.now, adaptation=session.adaptation
            let minutes=Int(adaptation.elapsed(at:now)/60)
            VStack(alignment:.leading,spacing:10) {
                Button { expanded.toggle() } label:{
                    HStack(spacing:14) {
                        ZStack {
                            Circle().stroke(palette.line,lineWidth:3)
                            Circle().trim(from:0,to:adaptation.progress(at:now)).stroke(palette.ink,style:StrokeStyle(lineWidth:3,lineCap:.round)).rotationEffect(.degrees(-90))
                            Image(systemName:"eye").font(.caption2).accessibilityHidden(true)
                        }.frame(width:34,height:34)
                        VStack(alignment:.leading,spacing:2) {
                            Text(title(adaptation.stage(at:now))).font(.subheadline.weight(.medium)).fixedSize(horizontal:false,vertical:true)
                            if adaptation.stage(at:now) == .rods { Text("Your faint-light vision is waking up.").font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true) }
                            Text(adaptation.stage(at:now) == .adapted ? String(localized:"About 30 minutes in red light. An estimate.") : String(localized:"\(minutes) of about 30 minutes. An estimate."))
                                .font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
                        }
                        Spacer(minLength:0)
                        Image(systemName:expanded ? "chevron.down" : "info.circle").font(.caption).accessibilityHidden(true)
                    }.frame(minHeight:60).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children:.ignore)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(adaptation.stage(at:now) == .rods ? String(localized:"Dark adaptation: rods taking over. Your faint-light vision is waking up.") : String(localized:"Dark adaptation: \(title(adaptation.stage(at:now)))"))
                .accessibilityValue(String(localized:"\(minutes) of about 30 minutes. An estimate."))
                .accessibilityHint(expanded ? "Hides how this works" : "Explains how this works")
                if expanded {
                    Text("Eyes adapt to the dark in two steps. Cones settle in about 10 minutes; rods, which see faint stars and the Milky Way, need 20 to 30. Dim red light barely touches rods, and a moment of white light starts them over. This clock counts your time in field mode, so it is only an estimate.")
                        .font(.footnote).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
                }
            }
        }
    }
    private func title(_ stage:DarkAdaptation.Stage)->String {
        switch stage {
        case .cones: String(localized:"Eyes adjusting")
        case .rods: String(localized:"Rods taking over")
        case .adapted: String(localized:"Dark-adapted")
        }
    }
}

// MARK: Wake me

/// The night's alarms as switches: core up, true darkness, half an hour before the Moon sets.
/// Permission is asked in context, after an explainer, the first time one is set.
struct FieldAlarmRows: View {
    let park: Park
    let options: [FieldNight.AlarmOption]
    var showsHeading=false
    /// 44 on the park's page; 60 in field mode, for gloves.
    var rowHeight: CGFloat=44
    @Environment(\.nyx) private var palette
    @Environment(\.openURL) private var openURL
    @State private var set: Set<String>=[]
    @State private var pending: FieldNight.AlarmOption?
    @State private var message: String?
    @State private var working=false
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            if showsHeading { Eyebrow(text:"Wake me") }
            ForEach(options) { option in
                let on=set.contains(FieldAlarms.key(park:park,option:option))
                Button { Task { await toggle(option) } } label:{
                    Label {
                        VStack(alignment:.leading,spacing:2) {
                            Text(option.label).fixedSize(horizontal:false,vertical:true)
                            Text(on ? String(localized:"Set for \(park.time(option.fire))") : park.time(option.fire)).font(.caption).foregroundStyle(palette.muted)
                        }
                    } icon:{ Image(systemName:on ? "alarm.fill" : "alarm").foregroundStyle(palette.ink) }
                    .frame(maxWidth:.infinity,minHeight:rowHeight,alignment:.leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain).disabled(working)
                .accessibilityAddTraits(.isToggle).accessibilityValue(on ? "Set" : "Off").accessibilityHint(on ? "Removes the alarm" : "Sets an alarm on this iPhone")
            }
            Text("Alarms ring through Silent and Focus. They are set on this iPhone and nowhere else.").font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
            if let message {
                Text(message).font(.caption).foregroundStyle(palette.ink).fixedSize(horizontal:false,vertical:true)
                if FieldAlarms.access == .denied, let url=URL(string:UIApplication.openSettingsURLString) { Button("Open Settings") { openURL(url) }.font(.caption).frame(minHeight:rowHeight).contentShape(Rectangle()) }
            }
        }
        .task {
            refresh()
            // An alarm that rings, is stopped or is removed in Clock changes its row while it is open.
            for await _ in AlarmManager.shared.alarmUpdates { refresh() }
        }
        .sheet(item:$pending) { option in
            PermissionExplainer(symbol:"alarm",title:"An alarm for the sky",message:"Nyx can set an alarm on this iPhone for a moment in the night, like the Milky Way's core rising, so you can rest until the sky is ready. Alarms ring through Silent and Focus. Nothing leaves this phone.",action:"Allow alarms") {
                pending=nil
                Task {
                    if await FieldAlarms.requestAccess() { await toggle(option) }
                    else { message=String(localized:"Alarms for Nyx are off. You can allow them in iPhone Settings.") }
                }
            }.nyxPresentation()
        }
    }
    private func refresh() { set=Set(options.filter { FieldAlarms.isSet(park:park,option:$0) }.map { FieldAlarms.key(park:park,option:$0) }) }
    private func toggle(_ option:FieldNight.AlarmOption) async {
        guard DebugScenario.screen == nil else { return }
        switch FieldAlarms.access {
        case .notAsked: pending=option
        case .denied: message=String(localized:"Alarms for Nyx are off. You can allow them in iPhone Settings.")
        case .allowed:
            working=true; defer { working=false }
            do { try await FieldAlarms.toggle(park:park,option:option); message=nil }
            catch { message=String(localized:"The alarm could not be set. Try again, or use the Clock app.") }
            refresh()
        }
    }
}

// MARK: Entry from park detail

/// "I'm here tonight": opens field mode for tonight at this park. Under it, a quieter way to have
/// the night's countdown on the Lock Screen without opening the field screen.
struct FieldEntry: View {
    @Environment(PlanModel.self) private var model
    @Environment(SceneCommands.self) private var commands: SceneCommands?
    @Environment(\.nyx) private var palette
    @AppStorage(NightLook.nightVisionKey,store:SharedSettings.defaults) private var nightVision=false
    @Environment(\.modelContext) private var context
    let park: Park
    let night: Night
    var body: some View {
        VStack(spacing:6) {
            if FieldPresenter.supported {
                Button { FieldPresenter.present(park:park,model:model,from:commands?.topController ?? SceneCommands.top(in:nil)) } label:{
                    Label("I'm here tonight",systemImage:"scope").font(.headline).padding(.horizontal,10).frame(minHeight:44)
                }
                .secondaryAction()
                .accessibilityHint("Opens field mode: a dark red screen with tonight's milestones and where to look.")
            }
            // Tonight, followed: scheduled for half an hour before sunset, or at once after that (`FollowNight`).
            if FollowNight.offered(night,now:model.present) {
                let following=NightFollowing.shared.isFollowing(park:park,night:night.id)
                Button { Task { await FollowNight.toggle(night,closure:model.closure(park),nightVision:nightVision) } } label:{
                    // The whole 44-point row is the target, not just the line of text.
                    Text(following ? "On your Lock Screen tonight. Stop" : "Follow tonight on the Lock Screen")
                        .font(.footnote).multilineTextAlignment(.center).padding(.horizontal,12).frame(minHeight:44).contentShape(Rectangle())
                }
                .accessibilityValue(FollowNight.caption(night,following:following,now:model.present))
            }
        }
        .task { NightFollowing.shared.reload() }
        // Field mode is presented over the app; its dawn "Keep this night" needs the journal's store.
        .onAppear { KeepThisNight.container=context.container }
    }
}

/// The journal's store for field mode, which is presented over the app without its environment.
private struct FieldJournalStore: ViewModifier {
    @ViewBuilder func body(content:Content)->some View {
        if let container=KeepThisNight.container { content.modelContainer(container) } else { content }
    }
}
/// The time to a moment, in words a dark-adapted eye cannot mistake for a clock: "23 min",
/// "1 h 31 min", serif numerals with smaller units, ticking each minute. Only the last two
/// minutes count down as m:ss. The surrounding card speaks it as a sentence.
struct FieldCountdown: View {
    let target: Date
    var numeral: Double=68
    var body: some View {
        TimelineView(FieldCountdownSchedule(target:target)) { context in
            let remaining=target.timeIntervalSince(context.date)
            Group {
                if remaining<=120 {
                    Text(timerInterval:context.date...max(context.date,target),countsDown:true,showsHours:false)
                        .font(.system(size:numeral,weight:.light,design:.serif)).monospacedDigit().tracking(-1)
                } else {
                    let parts=Self.parts(remaining)
                    ViewThatFits(in:.horizontal) {
                        HStack(alignment:.firstTextBaseline,spacing:6) { units(parts) }
                        VStack(alignment:.leading,spacing:0) { units(parts) }
                    }
                }
            }
            .lineLimit(1)
            .accessibilityHidden(true)
        }
    }
    @ViewBuilder private func units(_ parts:(hours:Int,minutes:Int))->some View {
        if parts.hours>0 {
            HStack(alignment:.firstTextBaseline,spacing:4) { figure(parts.hours); unit(String(localized:"h")) }
        }
        if parts.minutes>0 || parts.hours==0 {
            HStack(alignment:.firstTextBaseline,spacing:4) { figure(parts.minutes); unit(String(localized:"min")) }
        }
    }
    private func figure(_ value:Int)->some View { Text(value,format:.number).font(.system(size:numeral,weight:.light,design:.serif)).monospacedDigit().tracking(-1) }
    private func unit(_ text:String)->some View { Text(text).font(.system(size:numeral*0.36,weight:.regular,design:.serif)) }
    /// Whole hours and minutes, rounded up to the next minute, as a countdown should be.
    nonisolated static func parts(_ seconds:TimeInterval)->(hours:Int,minutes:Int) {
        let minutes=Int((max(0,seconds)/60).rounded(.up))
        return (minutes/60,minutes%60)
    }
}
/// Ticks on each minute boundary counted back from the target, then every second for the last two minutes.
struct FieldCountdownSchedule: TimelineSchedule {
    let target: Date
    func entries(from startDate:Date,mode:TimelineScheduleMode)->AnyIterator<Date> {
        var next=startDate
        return AnyIterator {
            let current=next
            let remaining=target.timeIntervalSince(current)
            if remaining<=120 { next=current.addingTimeInterval(1) }
            else {
                // The next moment the rounded-up minute changes.
                let step=remaining.truncatingRemainder(dividingBy:60)
                next=current.addingTimeInterval(step>0.001 ? step : 60)
            }
            return current
        }
    }
}
#Preview("Countdown • 23 min • 1 h 31 min • 1:40") {
    VStack(alignment:.leading,spacing:24) {
        FieldCountdown(target:.now.addingTimeInterval(22*60+39))
        FieldCountdown(target:.now.addingTimeInterval(90*60+10))
        FieldCountdown(target:.now.addingTimeInterval(100))
    }.padding().foregroundStyle(.white).background(.black)
}
/// Field mode with its eyes started over: the notice above the page in portrait; in the page itself
/// at compact height (an iPhone in landscape) and at accessibility sizes, so every control stays reachable.
@MainActor private func resetPreviewSession()->FieldSession? {
    let model=PlanModel()
    guard let park=model.home else { return nil }
    let session=FieldSession(park:park,model:model,changesPhone:false,adaptedFor:120)
    session.reset=DarkAdaptation.Reset(at:session.now.addingTimeInterval(-120),previousStart:session.now.addingTimeInterval(-26*60))
    return session
}
#Preview("Eyes started over • portrait") { if let session=resetPreviewSession() { FieldView(session:session) {} } }
#Preview("Eyes started over • landscape",traits:.landscapeLeft) { if let session=resetPreviewSession() { FieldView(session:session) {} } }
#Preview("Eyes started over • landscape • AX5",traits:.landscapeLeft) { if let session=resetPreviewSession() { FieldView(session:session) {}.dynamicTypeSize(.accessibility5) } }
#Preview("Eyes started over • notice") {
    if let session=resetPreviewSession(), let reset=session.reset { FieldResetNotice(session:session,reset:reset).padding().foregroundStyle(.red).background(.black) }
}
#Preview("Where to look • the compass alone") { if let session=resetPreviewSession() { FieldCompassView(session:session).background(.black) } }
#Preview("Where to look • the compass alone • AX5") { if let session=resetPreviewSession() { FieldCompassView(session:session).dynamicTypeSize(.accessibility5).background(.black) } }
