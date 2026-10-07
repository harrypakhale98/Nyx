import SwiftUI

/// "Tonight's sky over <park>": the night's real sky in colour, full screen. Drag sideways to turn
/// toward any direction; the slider moves through the night from sunset to sunrise in five-minute
/// steps (it opens at the middle of true darkness). Planets, the Moon, the Milky Way, a shower's
/// radiant and NASA's light domes on the horizon, drawn for the park's estimated Bortle class.
/// It is geometry, not a forecast: clouds belong to the score. Red under night vision, still under
/// Reduce Motion (it never moves by itself), and VoiceOver hears what is up and where.
struct TonightSkyView: View {
    @Environment(\.nyx) private var palette
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let night: Night
    var isTonight=true
    @State private var facing: Double
    @State private var minutes: Double
    @State private var dragFrom: Double?
    @State private var size: CGSize = .zero
    private var window: DateInterval { SkyAlmanac.nightWindow(night.sky) }
    init(night:Night,isTonight:Bool=true) {
        self.night=night; self.isTonight=isTonight
        _facing=State(initialValue:SkyDome.facing(for:night.park))
        _minutes=State(initialValue:Self.defaultMinutes(night.sky))
    }
    /// Minutes after the night's start that the view opens at: the middle of true darkness, else
    /// the middle of the night.
    nonisolated static func defaultMinutes(_ sky:SkyConditions)->Double {
        let window=SkyAlmanac.nightWindow(sky)
        let middle:Date
        if let start=sky.darkStart, let end=sky.darkEnd, end>start { middle=start.addingTimeInterval(end.timeIntervalSince(start)/2) }
        else { middle=window.start.addingTimeInterval(window.duration/2) }
        return max(0,min(window.duration/60,(middle.timeIntervalSince(window.start)/60/5).rounded()*5))
    }
    private var moment: Date { window.start.addingTimeInterval(minutes*60) }
    private var park: Park { night.park }
    private var options: PanoramaOptions { PanoramaOptions(facing:facing,bortle:Double(park.bortleEstimate),nightVision:palette.nightVision) }
    var body: some View {
        let sky=HorizonSkies.shared.sky(park:park,night:night.id,at:moment)
        PanoramaCanvas(sky:sky,options:options)
            .ignoresSafeArea()
            .onGeometryChange(for:CGSize.self) { $0.size } action:{ size=$0 }
            .gesture(turn)
            .accessibilityElement()
            .accessibilityLabel(title)
            .accessibilityValue(PanoramaCanvas.summary(sky:sky,facing:facing,park:park,bortle:Double(park.bortleEstimate)))
            .accessibilityHint("Swipe up or down to turn 45 degrees.")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: face(facing+45)
                case .decrement: face(facing-45)
                @unknown default: break
                }
            }
            .safeAreaInset(edge:.top) { header }
            .safeAreaInset(edge:.bottom) { controls(sky:sky) }
            .background(Color.black)
            .statusBarHidden(palette.nightVision)
            .sensoryFeedback(.selection,trigger:Int(minutes/30))
    }
    private var title: String {
        isTonight ? String(localized:"Tonight's sky over \(park.shortName)") : String(localized:"The sky over \(park.shortName), \(park.dayLabel(night.id))")
    }
    private var header: some View {
        HStack(alignment:.top,spacing:12) {
            VStack(alignment:.leading,spacing:4) {
                Text(title).font(.system(.title3,design:.serif)).foregroundStyle(palette.ink).fixedSize(horizontal:false,vertical:true)
                    .accessibilityAddTraits(.isHeader)
                Text("\(park.dayLabel(night.id)) · \(park.time(moment)) · facing \(Compass.name(facing))").font(.caption).foregroundStyle(palette.muted)
                    .fixedSize(horizontal:false,vertical:true).accessibilityHidden(true)
            }
            Spacer(minLength:8)
            Button { dismiss() } label:{ Image(systemName:"xmark").font(.body.weight(.semibold)).frame(width:44,height:44) }
                .modifier(FloatingGlass(shape:Circle()))
                .accessibilityLabel("Close")
        }
        .padding(.horizontal,20).padding(.top,8)
        .shadow(color:.black.opacity(0.8),radius:8)
    }
    private func controls(sky:HorizonSky)->some View {
        VStack(alignment:.leading,spacing:12) {
            HStack(alignment:.firstTextBaseline) {
                Text(park.time(moment)).font(.system(.title2,design:.serif)).monospacedDigit().foregroundStyle(palette.accent)
                Spacer(minLength:8)
                Text(phase(sky)).font(.caption).foregroundStyle(palette.muted).multilineTextAlignment(.trailing).fixedSize(horizontal:false,vertical:true)
            }.accessibilityElement(children:.combine)
            Slider(value:$minutes,in:0...max(5,window.duration/60),step:5) { Text("Time of night") } minimumValueLabel:{
                Text(park.time(window.start)).font(.caption2).foregroundStyle(palette.muted)
            } maximumValueLabel:{
                Text(park.time(window.end)).font(.caption2).foregroundStyle(palette.muted)
            }
            .tint(palette.controlTint)
            .accessibilityValue(park.time(moment))
            ViewThatFits(in:.horizontal) {
                HStack(spacing:8) { directions }
                VStack(alignment:.leading,spacing:8) { directions }
            }
            Text("Drawn for an estimated Bortle \(park.bortleEstimate) sky. Clouds are not shown; the score covers them.").font(.caption2).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
        }
        .padding(16)
        .modifier(FloatingGlass(shape:RoundedRectangle(cornerRadius:26)))
        .padding(.horizontal,12).padding(.bottom,8)
        .readableColumn(WideLayout.proseWidth)
    }
    @ViewBuilder private var directions: some View {
        let names=[String(localized:"North"),String(localized:"East"),String(localized:"South"),String(localized:"West")]
        ForEach(0..<4,id:\.self) { index in
            let azimuth=Double(index)*90, name=names[index]
            Button(name) { face(azimuth) }
                .buttonStyle(.bordered).buttonBorderShape(.capsule).font(.footnote.weight(.medium))
                .tint(Compass.name(facing)==Compass.name(azimuth) ? palette.accent : palette.muted)
                .accessibilityLabel(String(localized:"Face \(name.lowercased())"))
                .accessibilityAddTraits(Compass.name(facing)==Compass.name(azimuth) ? .isSelected : [])
        }
    }
    private func phase(_ sky:HorizonSky)->String {
        if sky.sunAltitude > -6 { return String(localized:"Twilight") }
        if !sky.dark { return String(localized:"Late twilight") }
        if sky.sunAltitude > -18 { return String(localized:"Nearly dark") }
        return String(localized:"True darkness")
    }
    private func face(_ azimuth:Double) { facing=(azimuth.truncatingRemainder(dividingBy:360)+360).truncatingRemainder(dividingBy:360) }
    /// Drag sideways to turn: the sky follows the finger, so dragging right turns to the left.
    private var turn: some Gesture {
        DragGesture(minimumDistance:4).onChanged { drag in
            let start=dragFrom ?? facing
            if dragFrom == nil { dragFrom=facing }
            let frame=SkyFrame(options:options,size:size == .zero ? CGSize(width:390,height:800) : size)
            face(start-drag.translation.width*frame.degreesPerPoint)
        }.onEnded { _ in dragFrom=nil }
    }
}
/// Liquid Glass for a floating control; a solid panel under Reduce Transparency, Increase
/// Contrast and night vision.
struct FloatingGlass<S: Shape>: ViewModifier {
    @Environment(\.nyx) private var palette
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let shape: S
    @ViewBuilder func body(content:Content)->some View {
        if reduceTransparency || palette.nightVision || palette.highContrast {
            content.background(shape.fill(palette.panel)).overlay(shape.stroke(palette.line,lineWidth:0.5))
        } else {
            content.glassEffect(.regular.tint(palette.panel.opacity(0.35)),in:shape)
        }
    }
}

/// The sky for a night as a window on the park's page: a still render that opens the full sky.
struct SkyWindowCard: View {
    @Environment(\.nyx) private var palette
    let night: Night
    var isTonight=true
    let open: ()->Void
    var body: some View {
        let sky=HorizonSkies.shared.sky(park:night.park,night:night.id,at:SkyAlmanac.nightWindow(night.sky).start.addingTimeInterval(TonightSkyView.defaultMinutes(night.sky)*60))
        let shape=RoundedRectangle(cornerRadius:24)
        Button(action:open) {
            PanoramaCanvas(sky:sky,options:PanoramaOptions(facing:SkyDome.facing(for:night.park),centreAltitude:32,span:1.7,labels:false,bortle:Double(night.park.bortleEstimate)))
                .frame(height:200)
                .overlay(alignment:.bottomLeading) {
                    HStack(alignment:.bottom) {
                        VStack(alignment:.leading,spacing:4) {
                            Text(isTonight ? String(localized:"Tonight's sky") : String(localized:"This night's sky")).font(.system(.title3,design:.serif)).foregroundStyle(palette.ink)
                            Text("Planets, the Milky Way and town light, hour by hour").font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
                        }
                        Spacer(minLength:8)
                        Image(systemName:"arrow.up.left.and.arrow.down.right").font(.subheadline.weight(.semibold)).foregroundStyle(palette.accent).accessibilityHidden(true)
                    }
                    .padding(16)
                    .background(LinearGradient(colors:[.clear,.black.opacity(0.75)],startPoint:.top,endPoint:.bottom))
                }
                .clipShape(shape)
                .overlay(shape.stroke(palette.line,lineWidth:0.5))
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children:.ignore)
        .accessibilityLabel(isTonight ? String(localized:"Tonight's sky over \(night.park.shortName)") : String(localized:"The sky over \(night.park.shortName), \(night.park.dayLabel(night.id))"))
        .accessibilityHint("Opens the sky for this night, hour by hour.")
        .accessibilityAddTraits(.isButton)
    }
}

/// An interactive figure for "Reading the Bortle scale": the same summer sky redrawn from class 1
/// to class 9 as the slider moves, the fainter stars and the Milky Way giving way to a rising
/// glow, with the class's name and one thing you can see for yourself. An illustration, labelled
/// as one: the faint stars' pattern is seeded, not catalogued.
struct BortleFigure: View {
    @Environment(\.nyx) private var palette
    @Environment(\.skyHome) private var home
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.nyxReduceMotion) private var forcedReduceMotion
    @State private var level=Double(DebugScenario.number("-nyx-bortle") ?? 3)
    private static let fallback:Park?=(try? ParkData.load())?.first { $0.id=="jotr" }
    private var park: Park? { home ?? Self.fallback }
    /// A summer night near new moon (July 15, 2026), with the Milky Way's core in the south.
    private static let summer=Date(timeIntervalSince1970:1_784_116_800)
    private var shownClass: Int { Int(level.rounded()) }
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            Text("An illustration").font(.caption.weight(.medium)).foregroundStyle(palette.muted).textCase(.uppercase).kerning(1.6)
            if let park {
                let night=AstronomyEngine().conditions(for:park,on:park.evening(Self.summer))
                let window=SkyAlmanac.nightWindow(night)
                let middle=night.darkStart.flatMap { start in night.darkEnd.map { start.addingTimeInterval($0.timeIntervalSince(start)/2) } } ?? window.start.addingTimeInterval(window.duration/2)
                let sky=HorizonSkies.shared.sky(park:park,night:park.evening(Self.summer),at:middle)
                PanoramaCanvas(sky:sky,options:PanoramaOptions(facing:SkyDome.facing(for:park),centreAltitude:30,span:1.9,labels:false,bortle:level,showsMoon:false))
                    .frame(height:260)
                    .clipShape(RoundedRectangle(cornerRadius:20))
                    .overlay(RoundedRectangle(cornerRadius:20).stroke(palette.line,lineWidth:0.5))
                    .accessibilityHidden(true)
            }
            VStack(alignment:.leading,spacing:6) {
                Text("Class \(shownClass): \(BortleScale.name(shownClass))").font(.system(.title3,design:.serif)).foregroundStyle(palette.ink).contentTransition(.numericText(value:level))
                Text(BortleScale.cue(shownClass)).font(.subheadline).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
            }
            .accessibilityHidden(true)
            Slider(value:$level,in:1...9) { Text("Bortle class") } minimumValueLabel:{ Text("1").font(.caption).foregroundStyle(palette.muted) } maximumValueLabel:{ Text("9").font(.caption).foregroundStyle(palette.muted) } onEditingChanged:{ editing in
                if !editing { withAnimation(systemReduceMotion || forcedReduceMotion ? nil : NyxMotion.spring) { level=level.rounded() } }
            }
            .tint(palette.controlTint)
            .accessibilityValue(String(localized:"Class \(shownClass), \(BortleScale.name(shownClass)). \(BortleScale.cue(shownClass))"))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: level=min(9,level.rounded()+1)
                case .decrement: level=max(1,level.rounded()-1)
                @unknown default: break
                }
            }
            Text("A summer sky in \(park?.shortName ?? String(localized:"a national park")), redrawn at each class. Real skies vary with the season, the weather and where you stand.").font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
        }
        .sensoryFeedback(.selection,trigger:shownClass)
        .padding(18)
        .background(RoundedRectangle(cornerRadius:24).fill(palette.panel))
        .overlay(RoundedRectangle(cornerRadius:24).stroke(palette.line,lineWidth:0.5))
    }
}
/// A live figure an essay can carry, placed after one of its paragraphs.
enum EssayFigure {
    case bortle
    init?(_ essay:Essay) {
        switch essay {
        case .bortle: self = .bortle
        default: return nil
        }
    }
    /// The figure follows this paragraph (0 is the first after the title).
    var afterParagraph: Int { 0 }
    @ViewBuilder var view: some View {
        switch self {
        case .bortle: BortleFigure()
        }
    }
}
#Preview("Sky over the park") {
    let m=PlanModel()
    if let p=m.home { TonightSkyView(night:m.night(p)).environment(m).preferredColorScheme(.dark) }
}
#Preview("Sky window") {
    let m=PlanModel()
    if let p=m.home { SkyWindowCard(night:m.night(p)) {}.padding().background(.black).preferredColorScheme(.dark) }
}
#Preview("Bortle figure") { ScrollView { BortleFigure().padding() }.background(.black).preferredColorScheme(.dark) }
#Preview("Bortle figure • AX5") { ScrollView { BortleFigure().padding() }.dynamicTypeSize(.accessibility5).background(.black).preferredColorScheme(.dark) }
