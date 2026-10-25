import SwiftUI

/// What every tab's first screen carries in its leading toolbar: night vision, one tap away in the
/// dark, and Settings. Screen actions (add, share, sort) stay on the trailing side. The keyboard's
/// ⌘, and ⌘N (`NyxCommands`) open Settings and the journal editor from here, for the tab on screen.
struct TabRootToolbar: ViewModifier {
    @State private var settings=false
    @State private var recording=false
    @Environment(SceneCommands.self) private var commands:SceneCommands?
    @Environment(PlanModel.self) private var model:PlanModel?
    @Environment(\.nyxTab) private var tab
    func body(content:Content)->some View {
        content
            .toolbar {
                // Night vision is the control reached for in the dark: on iPhone Duo's side bar, where
                // items overflow as space runs short, it stays out longest. Settings keeps its title for
                // the overflow menu; the bar shows its symbol.
                if #available(iOS 27.0,*) {
                    ToolbarItem(placement:.topBarLeading) { NightVisionToggle() }.visibilityPriority(.high)
                } else {
                    ToolbarItem(placement:.topBarLeading) { NightVisionToggle() }
                }
                ToolbarItem(placement:.topBarLeading) {
                    Button("Settings",systemImage:"gearshape") { settings=true }
                        .accessibilityInputLabels([Text("Settings"),Text("Preferences")])
                }
            }
            .sheet(isPresented:$settings) { SettingsSheet() }
            // ⌘N from any tab: the editor the Journal's "Record a night" opens.
            .sheet(isPresented:$recording) { NavigationStack { JournalEditorView() }.nyxPresentation() }
            .onChange(of:commands?.closeSettings) { settings=false }
            .onChange(of:commands?.sheetRequest) { _,request in
                // Only over this window's own screen: never a second sheet above one already open
                // (Settings, a draft, a park from a reminder), where it would land on top of work.
                guard let request, request.tab==tab, commands?.topController?.presentingViewController == nil else { return }
                // A key command leaves a focused field (Find a Park's search) first responder under the sheet,
                // which then could not be dismissed (seen on iPad after ⌘F): let it go first, as a tap does.
                // Find a Park's search also ends itself (`SearchEnder`); the sheet waits for that to finish.
                let hadFocus=UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),to:nil,from:nil,for:nil)
                Task { @MainActor in
                    if hadFocus { try? await Task.sleep(for:.milliseconds(350)) } else { await Task.yield() }
                    switch request.kind {
                    case .settings: settings=true
                    case .record: if model?.journalUnavailable == false { recording=true }
                    }
                }
            }
            // Tonight is the one tab root with pull-to-refresh; it shows and says its own result.
            .modifier(RefreshKey(speaks:true))
    }
}
extension View {
    /// Night vision and Settings in a tab's root toolbar (`TabRootToolbar`).
    func tabRootToolbar()->some View { modifier(TabRootToolbar()) }
}
/// Settings in its own sheet, so it opens the same way from every tab, on iPhone and iPad.
struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            // Settings apply as they change, so the sheet closes rather than confirms (iOS 26's close glyph).
            SettingsView().toolbar { ToolbarItem(placement:.cancellationAction) { Button(role:.close) { dismiss() } } }.singleControlBar()
        }.nyxPresentation()
    }
}
/// The night-vision switch as a toolbar toggle: a lamp, not a theme. The window dips to black, the
/// red comes up under the cover and is revealed (`NightVisionLamp`, run by `RootView`), with one
/// soft tap at the turn. Under Reduce Motion or Prefer Cross-Fade Transitions it writes the setting
/// at once and the palette crossfades. VoiceOver hears a toggle with its state, said once: the
/// switch's own value when VoiceOver is on it, "Night vision on" or "off" only when it was turned
/// from elsewhere (Voice Control with VoiceOver running). Voice Control answers to "Night vision",
/// "Red light" or "Flashlight".
struct NightVisionToggle: View {
    @AppStorage("nightVision",store:SharedSettings.defaults) private var nightVision=false
    @Environment(SceneCommands.self) private var commands:SceneCommands?
    @MotionReduced private var reduceMotion: Bool
    @Environment(\.nyxAccess) private var access
    private var shown:Bool { commands?.lampTarget ?? nightVision }
    /// The switch's centre in its window, for the lamp's dark to grow from.
    @State private var center:CGPoint?
    var body: some View {
        Toggle(isOn:Binding(get:{ shown },set:{ turn($0) })) {
            Label("Night vision",systemImage:shown ? "flashlight.on.circle.fill" : "flashlight.off.circle")
        }
        .toggleStyle(.button).labelStyle(.iconOnly)
        .onGeometryChange(for:CGPoint.self) { proxy in let frame=proxy.frame(in:.global); return CGPoint(x:frame.midX,y:frame.midY) } action:{ center=$0 }
        .accessibilityLabel("Night vision")
        // "Flashlight" too: it is the glyph on screen.
        .accessibilityInputLabels([Text("Night vision"),Text("Red light"),Text("Red screen"),Text("Flashlight")])
        .help("Night vision")
        // The soft tap at the turn comes once, from `RootView`: every tab's toolbar has its own switch.
    }
    private func turn(_ on:Bool) {
        // Read at the tap, before the lamp's cover could move VoiceOver anywhere.
        let announce = !NightVisionLamp.voiceOverOnSwitch()
        // Under At dusk a turn by hand holds until the next dusk or dawn (`NightVisionMode`).
        NightVisionMode.turnedByHand()
        if let commands, !(reduceMotion || access.crossFade) { commands.requestNightVision(on,announce:announce,origin:center); return }
        nightVision=on
        if announce { NightVisionLamp.announce(on) }
    }
}
/// The lamp's timing, shared by the toolbar switch and `RootView`: ~0.2 s down to black, the turn,
/// then the reveal on the shared spring (~0.45 s to the eye). A second tap mid-way reverses from
/// wherever the cover is, so no frame is ever brighter than the one before on the way into the red.
enum NightVisionLamp {
    /// One tap on the switch: the state asked for, and whether to say it (`voiceOverOnSwitch`).
    struct Request: Equatable { let id:Int; let on:Bool; var announce=true; var origin:CGPoint?=nil }
    static let dim=0.2
    static let reveal=0.45
    /// The soft rim of the dark as it grows from the switch, in points.
    static let feather=60.0
    /// The dark's radius as it grows from `center` (0 clear, 1 covering): at 1 its solid part, inside
    /// the feathered rim, reaches the farthest corner of `size`, so the whole window is black at the
    /// moment the palette turns, exactly as the even fade is.
    static func radius(cover:Double,center:CGPoint,size:CGSize)->Double {
        let corners=[CGPoint.zero,CGPoint(x:size.width,y:0),CGPoint(x:0,y:size.height),CGPoint(x:size.width,y:size.height)]
        let farthest=corners.map { hypot($0.x-center.x,$0.y-center.y) }.max() ?? 0
        return max(0,min(1,cover))*(farthest+feather)
    }
    /// Where the cover is between frames, as far as the lamp needs to know: a straight line from one
    /// value to another over a duration. The drawn curve is eased; this only sets how long is left.
    struct Cover: Equatable {
        var from=0.0, to=0.0
        var start=Date.distantPast
        var duration=0.0
        func value(at now:Date)->Double {
            guard duration>0 else { return to }
            let done=min(1,max(0,now.timeIntervalSince(start)/duration))
            return from+(to-from)*done
        }
    }
    /// Seconds left to reach full cover from a cover already partly down (0 to 1).
    static func dimTime(from cover:Double)->Double { dim*(1-min(max(cover,0),1)) }
    /// Whether VoiceOver is on the switch itself, which then speaks its own new value: an
    /// announcement as well would say the state twice. The toolbar's switch is hosted by UIKit,
    /// so the element VoiceOver is on is read there, by the switch's label.
    @MainActor static func voiceOverOnSwitch()->Bool {
        guard UIAccessibility.isVoiceOverRunning,
              let element=UIAccessibility.focusedElement(using:UIAccessibility.AssistiveTechnologyIdentifier.notificationVoiceOver) as? NSObject else { return false }
        return element.accessibilityLabel == String(localized:"Night vision")
    }
    /// Said after the setting is written, politely, after anything VoiceOver is already saying.
    @MainActor static func announce(_ on:Bool) {
        NightListener.announce(on ? String(localized:"Night vision on") : String(localized:"Night vision off"),priority:.default)
    }
}
/// The lamp's cover over the window: black growing as a circle from the switch (`origin`, in the
/// window's coordinates) while it dims, or an even black at `cover`'s opacity (the reveal, and every
/// dim that does not start from a clear window or from the switch). Animatable, so the circle grows
/// on the same eased timing as the even fade it replaces.
struct LampCover: View, Animatable {
    var cover: Double
    let origin: CGPoint?
    var animatableData: Double { get { cover } set { cover=newValue } }
    var body: some View {
        if let origin {
            GeometryReader { proxy in
                let frame=proxy.frame(in:.global), center=CGPoint(x:origin.x-frame.minX,y:origin.y-frame.minY)
                let r=NightVisionLamp.radius(cover:cover,center:center,size:proxy.size)
                let solid=r>0 ? max(0,1-NightVisionLamp.feather/r) : 0
                Circle().fill(RadialGradient(stops:[.init(color:.black,location:0),.init(color:.black,location:solid),.init(color:.black.opacity(0),location:1)],center:.center,startRadius:0,endRadius:max(r,0.001)))
                    .frame(width:2*r,height:2*r).position(center)
            }
        } else {
            Color.black.opacity(cover)
        }
    }
}
#Preview("Tab root toolbar") {
    NavigationStack { Color.black.navigationTitle("Tonight").navigationBarTitleDisplayMode(.inline).tabRootToolbar() }
        .environment(PlanModel()).preferredColorScheme(.dark)
}
