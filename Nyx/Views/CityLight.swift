import SwiftUI

/// What city light takes: the park's own sky on a new-moon night, drawn at its estimated Bortle
/// class, and the same sky drawn at class 8, a city's. A native control switches between them; the
/// class itself animates on the shared spring, so the faint stars drain out, the Milky Way fades
/// and the glow climbs from the horizon (instant under Reduce Motion). An illustration, labelled as
/// one, with one spoken summary. No real city is named as class 8.
struct CityLightFigure: View {
    enum Sky: Hashable { case here, city }
    @Environment(\.nyx) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.nyxReduceMotion) private var forcedReduceMotion
    @Environment(\.horizontalSizeClass) private var sizeClass
    let park: Park
    @State private var selection: Sky
    /// The class drawn: animates between the park's estimate and `cityClass`.
    @State private var drawnClass: Double
    /// Drawn only once it first scrolls on screen; the sky is worked out then and cached.
    @State private var onScreen=false
    static let cityClass=8.0
    private static var nights:[String:Date]=[:]
    private static var skies:[String:HorizonSky]=[:]
    /// The figure's night: the summer new moon, or the winter one where July has no true darkness
    /// (Alaska's parks). Worked out once per park.
    static func night(_ park:Park)->Date {
        if let night=nights[park.id] { return night }
        let night=AstronomyEngine().conditions(for:park,on:park.evening(BortleFigure.summer)).darkStart == nil ? BortleFigure.winter : BortleFigure.summer
        nights[park.id]=night
        return night
    }
    /// The figure's sky, worked out once per park: the body runs several times as the control's
    /// width settles and on every switch, and the conditions behind it are a full night's astronomy.
    static func sky(_ park:Park)->HorizonSky {
        if let sky=skies[park.id] { return sky }
        let sky=BortleFigure.sky(park,night:night(park))
        skies[park.id]=sky
        return sky
    }
    /// Only where the park's estimate is clearly darker than a city's (class 6 or lower).
    static func compares(_ park:Park)->Bool { Double(park.bortleEstimate)<=cityClass-2 }
    static let height=200.0
    /// The figure is never wider than this many times its height. Its view (40° up, `BortleFigure.options`)
    /// reaches the horizon only about 1.3 heights either side of the middle; a full-width iPad panel
    /// showed the ground's ends as a black slab with the sky in a bowl between them.
    static let aspect=2.2
    /// Taller in a regular-width layout (iPad), so the capped figure keeps its presence in a wide panel.
    private var figureHeight: Double { sizeClass == .regular ? 260 : Self.height }
    init(park:Park,selection:Sky = .here) {
        self.park=park
        _selection=State(initialValue:selection)
        _drawnClass=State(initialValue:selection == .city ? Self.cityClass : Double(park.bortleEstimate))
    }
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            let shape=RoundedRectangle(cornerRadius:18)
            Group {
                if onScreen { GlowComparisonSky(sky:Self.sky(park),base:BortleFigure.options(park,bortle:drawnClass),bortle:drawnClass) }
                else { Color.black }
            }
            .frame(height:figureHeight)
            .clipShape(shape)
            .overlay(shape.stroke(palette.line,lineWidth:0.5))
            .frame(maxWidth:figureHeight*Self.aspect)
            .frame(maxWidth:.infinity)
            .onScrollVisibilityChange(threshold:0.01) { visible in if visible { onScreen=true } }
            .accessibilityElement()
            .accessibilityLabel(String(localized:"Illustration: this park's sky at its estimated Class \(park.bortleEstimate), and the same sky from a city, Class 8. From a city, the Milky Way and most faint stars disappear; only the brightest stars remain."))
            .accessibilityAddTraits(.isImage)
            // Which sky is drawn now, so a swipe back to the picture after switching hears the change.
            .accessibilityValue(selection == .city ? cityLabel : hereFull)
            picker
            Text("An illustration: the same sky drawn at this park's estimated class and at a city's.")
                .font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
                .accessibilityHidden(true)
        }
        .sensoryFeedback(.selection,trigger:selection)
        .onChange(of:selection) { _,new in
            let target=new == .city ? Self.cityClass : Double(park.bortleEstimate)
            withAnimation(systemReduceMotion || forcedReduceMotion ? nil : NyxMotion.spring) { drawnClass=target }
        }
    }
    /// The labels in full for the menu, and short for the segments ("Here · Class 3", "City · Class 8"),
    /// short enough for a phone's width at standard sizes (the menu takes over where they are not). The segmented control's
    /// bridge ignores a per-segment accessibility label (checked by a UI test), so VoiceOver hears the
    /// short ones; the figure's own label, the caption and the estimate row below say "estimated".
    /// The class number is held to its word (a no-break space), so an accessibility-size menu label
    /// never leaves "3," alone on a line.
    private var hereFull: String { String(localized:"Here (Class\u{00A0}\(park.bortleEstimate), estimated)") }
    private var hereShort: String { String(localized:"Here · Class \(park.bortleEstimate)") }
    private var cityLabel: String { String(localized:"From a city (Class 8)") }
    private var cityShort: String { String(localized:"City · Class 8") }
    @State private var available: CGFloat=0
    @State private var segmentedWidth: CGFloat=0
    /// Segmented and full width; a menu with a wrapping label at accessibility sizes, or where even
    /// the short segments would not fit (a narrow column), measured rather than guessed.
    @ViewBuilder private var picker: some View {
        if typeSize.isAccessibilitySize { menu }
        else {
            Group {
                if available>0 && segmentedWidth>available { menu } else { segmented }
            }
            .frame(maxWidth:.infinity,alignment:.leading)
            .onGeometryChange(for:CGFloat.self) { $0.size.width } action:{ available=$0 }
            .background {
                // The segmented form at its natural width, measured and never shown.
                segmented.fixedSize().onGeometryChange(for:CGFloat.self) { $0.size.width } action:{ segmentedWidth=$0 }
                    .hidden().accessibilityHidden(true)
            }
        }
    }
    private var segmented: some View {
        Picker("Sky drawn",selection:$selection) {
            Text(hereShort).tag(Sky.here)
            Text(cityShort).tag(Sky.city)
        }
        .pickerStyle(.segmented)
    }
    /// A native menu whose label wraps, so a long label is never cut at large text sizes.
    private var menu: some View {
        Menu {
            Picker("Sky drawn",selection:$selection) {
                Text(hereFull).tag(Sky.here)
                Text(cityLabel).tag(Sky.city)
            }
        } label: {
            HStack(alignment:.firstTextBaseline,spacing:6) {
                Text(selection == .city ? cityLabel : hereFull).multilineTextAlignment(.leading).fixedSize(horizontal:false,vertical:true)
                Image(systemName:"chevron.up.chevron.down").font(.footnote.weight(.semibold)).accessibilityHidden(true)
            }
            .foregroundStyle(palette.accent)
            .frame(maxWidth:.infinity,minHeight:44,alignment:.leading)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(String(localized:"Sky drawn"))
        .accessibilityValue(selection == .city ? cityLabel : hereFull)
    }
}
/// The figure's canvas, with the Bortle class as its animatable value: redrawn only while the
/// class moves, then still.
private struct GlowComparisonSky: View, Animatable {
    let sky: HorizonSky
    let base: PanoramaOptions
    var bortle: Double
    var animatableData: Double { get { bortle } set { bortle=newValue } }
    var body: some View { PanoramaCanvas(sky:sky,options:options) }
    private var options: PanoramaOptions { var options=base; options.bortle=bortle; return options }
}

/// The park page's "Sky glow" panel: what city light takes (the illustration), the estimate and
/// NASA's night lights with the towns whose glow reaches the horizon (cause), then what anyone can
/// do about it (Protect this sky). One panel tells cause, effect and action.
struct SkyGlowPanel: View {
    @Environment(\.nyx) private var palette
    let park: Park
    var comparison: CityLightFigure.Sky = .here
    var body: some View {
        Panel {
            VStack(alignment:.leading,spacing:16) {
                Eyebrow(text:"Sky glow")
                // A park already under a city's glow has nothing to compare: the two skies would match.
                // Identity per park: the selection and the drawn class are seeded from the park once.
                if CityLightFigure.compares(park) { CityLightFigure(park:park,selection:comparison).id(park.id) }
                LightPollution(park:park)
                Divider().overlay(palette.line).padding(.vertical,4)
                ProtectThisSky(park:park)
            }
        }
    }
}

#Preview("Sky glow · Death Valley") {
    if let p=try? ParkData.load().first(where:{$0.id=="deva"}) { NavigationStack { ScrollView { SkyGlowPanel(park:p).padding() }.background(.black) }.preferredColorScheme(.dark) }
}
#Preview("Sky glow · from a city") {
    if let p=try? ParkData.load().first(where:{$0.id=="grca"}) { NavigationStack { ScrollView { SkyGlowPanel(park:p,comparison:.city).padding() }.background(.black) }.preferredColorScheme(.dark) }
}
#Preview("Sky glow · Denali (winter sky)") {
    if let p=try? ParkData.load().first(where:{$0.id=="dena"}) { NavigationStack { ScrollView { SkyGlowPanel(park:p).padding() }.background(.black) }.preferredColorScheme(.dark) }
}
#Preview("Sky glow · iPad width") {
    if let p=try? ParkData.load().first(where:{$0.id=="deva"}) { NavigationStack { ScrollView { SkyGlowPanel(park:p,comparison:.city).padding() }.background(.black) }.environment(\.horizontalSizeClass,.regular).frame(width:1000,height:900).preferredColorScheme(.dark) }
}
#Preview("Sky glow · AX5") {
    if let p=try? ParkData.load().first(where:{$0.id=="deva"}) { NavigationStack { ScrollView { SkyGlowPanel(park:p).padding() }.background(.black) }.dynamicTypeSize(.accessibility5).preferredColorScheme(.dark) }
}
#Preview("Sky glow · night vision") {
    if let p=try? ParkData.load().first(where:{$0.id=="grte"}) { NavigationStack { ScrollView { SkyGlowPanel(park:p).padding() }.background(.black) }.environment(\.nyx,NyxPalette(nightVision:true,highContrast:false)).modifier(NightVisionFilter(enabled:true)).preferredColorScheme(.dark) }
}
#Preview("Sky glow · Reduce Motion") {
    if let p=try? ParkData.load().first(where:{$0.id=="jotr"}) { NavigationStack { ScrollView { SkyGlowPanel(park:p).padding() }.background(.black) }.environment(\.nyxReduceMotion,true).preferredColorScheme(.dark) }
}
