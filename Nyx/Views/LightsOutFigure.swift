import SwiftUI

/// "With the lights out" at the foot of "From <start> tonight": a moonless summer sky drawn at the
/// starting point's class, which clears once, slowly, to the darkest place in reach when the figure
/// first comes into view; then the place, how far, and its best night soon, one tap from its page.
/// A native control switches between the two skies at any time. Under Reduce Motion nothing moves
/// by itself and the control switches at once. An illustration, labelled as one, with one spoken summary.
struct LightsOutFigure: View {
    @Environment(\.nyx) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    @MotionReduced private var reduceMotion: Bool
    let target: LightsOut.Target
    let origin: String
    /// Near me: the sky is the person's own, named as theirs rather than "your location".
    var fromDevice=false
    enum Sky: Hashable { case home, dark }
    @State private var selection: Sky = .home
    @State private var drawnClass: Double
    @State private var onScreen=false
    /// The one clearing has played (or Reduce Motion skipped it); it never plays again here.
    @State private var played=false
    init(target: LightsOut.Target, origin: String, fromDevice: Bool=false) {
        self.target=target; self.origin=origin; self.fromDevice=fromDevice
        _drawnClass=State(initialValue:Double(target.homeClass))
    }
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            Eyebrow(text:"With the lights out")
            let shape=RoundedRectangle(cornerRadius:18)
            Group {
                if onScreen { GlowComparisonSky(sky:CityLightFigure.sky(target.place),base:BortleFigure.options(target.place,bortle:drawnClass),bortle:drawnClass) }
                else { Color.black }
            }
            .frame(height:CityLightFigure.height)
            .clipShape(shape)
            .overlay(shape.stroke(palette.line,lineWidth:0.5))
            .frame(maxWidth:CityLightFigure.height*CityLightFigure.aspect)
            .frame(maxWidth:.infinity)
            .onScrollVisibilityChange(threshold:0.6) { visible in
                if visible { onScreen=true; clearOnce() }
            }
            .accessibilityElement()
            .accessibilityLabel(LightsOut.spoken(target,origin:origin))
            .accessibilityValue(selection == .dark ? darkLabel : homeLabel)
            .accessibilityAddTraits(.isImage)
            picker
            Text(selection == .dark ? LightsOut.sentence(target) : homeCaption)
                .font(.system(.body,design:.serif)).foregroundStyle(palette.ink).fixedSize(horizontal:false,vertical:true)
                .contentTransition(.opacity)
            if let best=target.best {
                NavigationLink { ParkDetailView(park:target.place,initialDate:best.id) } label:{
                    HStack(alignment:.firstTextBaseline,spacing:6) {
                        Text(LightsOut.bestLine(best)).fixedSize(horizontal:false,vertical:true)
                        Image(systemName:"chevron.forward").font(.caption.weight(.semibold)).accessibilityHidden(true)
                    }
                    .font(.subheadline).foregroundStyle(palette.accent).frame(minHeight:44,alignment:.leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens that night at the park.")
            }
            Text(target.homeKnown ? "An illustration: a moonless summer sky drawn at your starting point's class, estimated from satellite data, and at the darker place's estimated class."
                                  : "An illustration: a moonless summer sky drawn as a suburban sky, Class 7 (Nyx has no light map here), and at the darker place's estimated class.")
                .font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
                .accessibilityHidden(true)
        }
        .sensoryFeedback(.selection,trigger:selection)
        .onChange(of:selection) { _,new in
            let to=Double(new == .dark ? target.place.bortleEstimate : target.homeClass)
            withAnimation(reduceMotion ? nil : NyxMotion.arrival) { drawnClass=to }
        }
    }
    /// The one slow clearing, a beat after the figure is mostly in view: the glow sinks, the faint
    /// stars and the Milky Way come out. Not under Reduce Motion, where the person switches.
    private func clearOnce() {
        guard !played else { return }
        played=true
        guard !reduceMotion, DebugScenario.screen == nil || DebugScenario.isEnabled("lights-out") else { return }
        Task {
            try? await Task.sleep(for:.seconds(1.2))
            selection = .dark
        }
    }
    /// What the starting point's class is called, said as the figure stands on it.
    private var homeCaption: String {
        let name=BortleScale.name(target.homeClass)
        if target.homeKnown, fromDevice { return String(localized:"Your sky: Class \(target.homeClass), \(name).") }
        return target.homeKnown ? String(localized:"\(origin): Class \(target.homeClass), \(name).")
                                : String(localized:"A suburban sky, as Nyx assumes here: Class \(target.homeClass), \(name).")
    }
    private var homeShort: String { String(localized:"Here · Class \(target.homeClass)") }
    private var darkShort: String { String(localized:"\(target.place.shortName) · Class \(target.place.bortleEstimate)") }
    private var homeLabel: String { String(localized:"Your sky (Class\u{00A0}\(target.homeClass))") }
    private var darkLabel: String { String(localized:"\(target.place.shortName) (Class\u{00A0}\(target.place.bortleEstimate))") }
    @State private var available: CGFloat=0
    @State private var segmentedWidth: CGFloat=0
    /// Segmented when the short labels fit, a menu otherwise (accessibility sizes, a long place name).
    @ViewBuilder private var picker: some View {
        if typeSize.isAccessibilitySize { menu }
        else {
            Group { if available>0 && segmentedWidth>available { menu } else { segmented } }
                .frame(maxWidth:.infinity,alignment:.leading)
                .onGeometryChange(for:CGFloat.self) { $0.size.width } action:{ available=$0 }
                .background {
                    segmented.fixedSize().onGeometryChange(for:CGFloat.self) { $0.size.width } action:{ segmentedWidth=$0 }
                        .hidden().accessibilityHidden(true)
                }
        }
    }
    private var segmented: some View {
        Picker("Sky drawn",selection:$selection) {
            Text(homeShort).tag(Sky.home)
            Text(darkShort).tag(Sky.dark)
        }
        .pickerStyle(.segmented)
    }
    private var menu: some View {
        Menu {
            Picker("Sky drawn",selection:$selection) {
                Text(homeLabel).tag(Sky.home)
                Text(darkLabel).tag(Sky.dark)
            }
        } label:{
            HStack(alignment:.firstTextBaseline,spacing:6) {
                Text(selection == .dark ? darkLabel : homeLabel).multilineTextAlignment(.leading).fixedSize(horizontal:false,vertical:true)
                Image(systemName:"chevron.up.chevron.down").font(.footnote.weight(.semibold)).accessibilityHidden(true)
            }
            .foregroundStyle(palette.accent).frame(maxWidth:.infinity,minHeight:44,alignment:.leading).contentShape(Rectangle())
        }
        .accessibilityLabel(String(localized:"Sky drawn"))
        .accessibilityValue(selection == .dark ? darkLabel : homeLabel)
    }
}

#Preview("Lights out • Chicago to a dark park") {
    let m=PlanModel()
    if let dark=m.parks.min(by:{ $0.bortleEstimate<$1.bortleEstimate }) {
        NavigationStack { ScrollView { Panel { LightsOutFigure(target:LightsOut.Target(place:dark,meters:257_000,homeClass:7,homeKnown:true,best:m.night(dark)),origin:"Chicago") }.padding() } }
            .environment(m).background(.black).preferredColorScheme(.dark)
    }
}
#Preview("Lights out • assumed sky • AX5") {
    let m=PlanModel()
    if let dark=m.parks.first {
        NavigationStack { ScrollView { Panel { LightsOutFigure(target:LightsOut.Target(place:dark,meters:90_000,homeClass:7,homeKnown:false),origin:"your location") }.padding() } }
            .environment(m).dynamicTypeSize(.accessibility5).background(.black).preferredColorScheme(.dark)
    }
}
#Preview("Lights out • night vision") {
    let m=PlanModel()
    if let dark=m.parks.first {
        NavigationStack { ScrollView { Panel { LightsOutFigure(target:LightsOut.Target(place:dark,meters:90_000,homeClass:8,homeKnown:true,best:m.night(dark)),origin:"Denver") }.padding() } }
            .environment(m).environment(\.nyx,NyxPalette(nightVision:true,highContrast:false)).modifier(NightVisionFilter(enabled:true)).background(.black).preferredColorScheme(.dark)
    }
}
