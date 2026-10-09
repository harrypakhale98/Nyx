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
    let park: Park
    @State private var selection: Sky
    /// The class drawn: animates between the park's estimate and `cityClass`.
    @State private var drawnClass: Double
    /// Drawn only once it first scrolls on screen; the sky is worked out then and cached.
    @State private var onScreen=false
    static let cityClass=8.0
    private static var nights:[String:Date]=[:]
    /// The figure's night: the summer new moon, or the winter one where July has no true darkness
    /// (Alaska's parks). Worked out once per park.
    static func night(_ park:Park)->Date {
        if let night=nights[park.id] { return night }
        let night=AstronomyEngine().conditions(for:park,on:park.evening(BortleFigure.summer)).darkStart == nil ? BortleFigure.winter : BortleFigure.summer
        nights[park.id]=night
        return night
    }
    /// Only where the park's estimate is clearly darker than a city's (class 6 or lower).
    static func compares(_ park:Park)->Bool { Double(park.bortleEstimate)<=cityClass-2 }
    static let height=200.0
    init(park:Park,selection:Sky = .here) {
        self.park=park
        _selection=State(initialValue:selection)
        _drawnClass=State(initialValue:selection == .city ? Self.cityClass : Double(park.bortleEstimate))
    }
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            let shape=RoundedRectangle(cornerRadius:18)
            Group {
                if onScreen { GlowComparisonSky(sky:BortleFigure.sky(park,night:Self.night(park)),base:BortleFigure.options(park,bortle:drawnClass),bortle:drawnClass) }
                else { Color.black }
            }
            .frame(height:Self.height)
            .clipShape(shape)
            .overlay(shape.stroke(palette.line,lineWidth:0.5))
            .onScrollVisibilityChange(threshold:0.01) { visible in if visible { onScreen=true } }
            .accessibilityElement()
            .accessibilityLabel(String(localized:"Illustration. From a city, the Milky Way and most faint stars disappear; only the brightest stars remain."))
            .accessibilityAddTraits(.isImage)
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
    /// The park's label in full, and short for a phone's width ("Here (Class 3)"): the caption and
    /// the estimate row just below say "estimated", and VoiceOver always hears the full label.
    private var hereFull: String { String(localized:"Here (Class \(park.bortleEstimate), estimated)") }
    private var hereShort: String { String(localized:"Here (Class \(park.bortleEstimate))") }
    private var cityLabel: String { String(localized:"From a city (Class 8)") }
    @State private var available: CGFloat=0
    @State private var fullWidth: CGFloat=0
    @State private var shortWidth: CGFloat=0
    /// Segmented, full width, with the full labels where they fit and the short "Here" where only
    /// that fits; a menu with a wrapping label at accessibility sizes or when neither fits.
    @ViewBuilder private var picker: some View {
        if typeSize.isAccessibilitySize { menu }
        else {
            Group {
                if available>0 && shortWidth>available { menu }
                else { segmented(here:available>0 && fullWidth>available ? hereShort : hereFull) }
            }
            .frame(maxWidth:.infinity,alignment:.leading)
            .onGeometryChange(for:CGFloat.self) { $0.size.width } action:{ available=$0 }
            .background {
                // Each segmented form at its natural width, measured and never shown.
                VStack {
                    segmented(here:hereFull).fixedSize().onGeometryChange(for:CGFloat.self) { $0.size.width } action:{ fullWidth=$0 }
                    segmented(here:hereShort).fixedSize().onGeometryChange(for:CGFloat.self) { $0.size.width } action:{ shortWidth=$0 }
                }.hidden().accessibilityHidden(true)
            }
        }
    }
    private func segmented(here:String)->some View {
        Picker("Sky drawn",selection:$selection) {
            Text(here).accessibilityLabel(hereFull).tag(Sky.here)
            Text(cityLabel).tag(Sky.city)
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
                if CityLightFigure.compares(park) { CityLightFigure(park:park,selection:comparison) }
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
#Preview("Sky glow · AX5") {
    if let p=try? ParkData.load().first(where:{$0.id=="deva"}) { NavigationStack { ScrollView { SkyGlowPanel(park:p).padding() }.background(.black) }.dynamicTypeSize(.accessibility5).preferredColorScheme(.dark) }
}
#Preview("Sky glow · night vision") {
    if let p=try? ParkData.load().first(where:{$0.id=="grte"}) { NavigationStack { ScrollView { SkyGlowPanel(park:p).padding() }.background(.black) }.environment(\.nyx,NyxPalette(nightVision:true,highContrast:false)).modifier(NightVisionFilter(enabled:true)).preferredColorScheme(.dark) }
}
#Preview("Sky glow · Reduce Motion") {
    if let p=try? ParkData.load().first(where:{$0.id=="jotr"}) { NavigationStack { ScrollView { SkyGlowPanel(park:p).padding() }.background(.black) }.environment(\.nyxReduceMotion,true).preferredColorScheme(.dark) }
}
