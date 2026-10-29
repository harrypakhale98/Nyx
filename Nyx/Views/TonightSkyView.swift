import SwiftUI

/// "Tonight's sky over <park>": the night's real sky in colour, full screen. Drag sideways to turn
/// toward any direction (a fling coasts on the shared spring, at most 120°; the direction buttons
/// turn the shortest way round); the slider moves through the night from sunset to sunrise in
/// five-minute steps (it opens at the middle of true darkness). Planets, the Moon, the Milky Way,
/// a shower's radiant, NASA's light domes on the horizon, the six brightest named stars in view and
/// the constellation figures as hairlines, drawn for the park's estimated Bortle class. It is
/// geometry, not a forecast: clouds belong to the score. Red under night vision, still under
/// Reduce Motion (it never moves by itself: no coast, and the buttons turn at once), and VoiceOver
/// hears what is up and where.
///
/// The first time it opens for a park and night after Nyx launches, the sky arrives as eyes adapt:
/// from the brightest stars and planets (the 0.3 floor, continuing from the lit card) to the
/// fainter ones, the Milky Way and the figures last, over about four seconds, with "As your eyes
/// adapt" under the title. Landing on its own, the caption turns into "Outdoors, this takes about
/// 30 minutes." for three seconds. Any touch (a drag, the slider, a direction) completes it at once,
/// without that sentence. Reduce Motion and Reduce Highlighting Effects draw the sky whole, with
/// no caption.
struct TonightSkyView: View {
    @Environment(\.nyx) private var palette
    @Environment(\.nyxAccess) private var access
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @MotionReduced private var reduceMotion: Bool
    let night: Night
    var isTonight=true
    @State private var facing: Double
    @State private var minutes: Double
    @State private var dragFrom: Double?
    /// A drag is under way; resets by itself when the system cancels one (a rotation, the home
    /// indicator's gesture), which never reaches `onEnded`, so the next drag starts where the sky is.
    @GestureState private var dragging=false
    @State private var size: CGSize = .zero
    /// The header's lower edge on screen: names stay below it and figures fade out above it.
    @State private var headerBottom: Double=0
    /// The whole screen, so the controls never take more than half of its height at large sizes
    /// and the side column (`beside`) takes its share of the width.
    @State private var screen=CGSize(width:390,height:800)
    private var screenHeight: Double { screen.height }
    /// An iPhone in landscape (compact height), or any window wider than tall and under 500 pt high
    /// (a short iPad window): the title and the controls stand in a column beside the sky, so the
    /// sky keeps the screen's whole height instead of a strip between them.
    @Environment(\.verticalSizeClass) private var verticalSize
    private var beside: Bool { Self.beside(compactHeight:verticalSize == .compact,screen:screen) }
    nonisolated static func beside(compactHeight:Bool,screen:CGSize)->Bool {
        compactHeight || (screen.width>screen.height && screen.height<500)
    }
    /// Accessibility text sizes: the header keeps only its title (the time and facing are in the
    /// controls, and the reveal's caption is decoration). At any size the controls scroll within
    /// half the screen, so the sky always keeps the rest.
    private var large: Bool { typeSize.isAccessibilitySize }
    /// The adaptation reveal is running (from `revealStart`); false once it lands or a touch ends it.
    @State private var revealing: Bool
    @State private var revealStart: Date?
    @State private var captionShown: Bool
    /// The reveal landed by itself (no touch ended it): the caption says how long it takes outdoors.
    @State private var landedNaturally=false
    /// The turn in flight (a coast or a direction button), so a finger can catch it where it is.
    @State private var turning: SkyTurn.Motion?
    private var window: DateInterval { SkyAlmanac.nightWindow(night.sky) }
    /// `previewLanded` opens on the landed sentence, for its preview.
    private let previewLanded: Bool
    init(night:Night,isTonight:Bool=true,previewLanded:Bool=false) {
        self.night=night; self.isTonight=isTonight; self.previewLanded=previewLanded
        _facing=State(initialValue:SkyDome.facing(for:night.park))
        _minutes=State(initialValue:Self.defaultMinutes(night.sky))
        let first = !SkyAdaptation.seen.contains(SkyAdaptation.key(parkID:night.park.id,night:night.id))
        _revealing=State(initialValue:first)
        _captionShown=State(initialValue:first || previewLanded)
    }
    /// The reveal is a highlight and a motion: neither plays under Reduce Motion or Reduce Highlighting Effects.
    private var revealAllowed: Bool { !reduceMotion && !access.reduceHighlighting }
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
    /// Beside the column nothing stands over the sky, so names may use its whole height.
    private var options: PanoramaOptions { PanoramaOptions(facing:facing,bortle:Double(park.bortleEstimate),nightVision:palette.nightVision,labelTop:beside ? 0 : headerBottom) }
    private func adapted(_ adaptation:Double)->PanoramaOptions { var adapted=options; adapted.adaptation=adaptation; return adapted }
    var body: some View {
        let sky=HorizonSkies.shared.sky(park:park,night:night.id,at:moment)
        let adapting=revealing && revealAllowed
        // At most 30 frames a second while the stars arrive; paused (nothing redrawn) once they have.
        TimelineView(.animation(minimumInterval:1/30,paused:!adapting || SkyAdaptation.frozen != nil)) { timeline in
            TurningPanorama(sky:sky,options:adapted(adapting ? SkyAdaptation.progress(since:revealStart,now:timeline.date) : 1))
        }
            // Beside the column the sky also runs under the home indicator and the Dynamic Island's side.
            .ignoresSafeArea(edges:beside ? [.top,.bottom,.leading] : .top)
            .onGeometryChange(for:CGSize.self) { $0.size } action:{ size=$0 }
            .gesture(turn)
            .onChange(of:dragging) { _,now in if !now { dragFrom=nil } }
            .accessibilityElement()
            .accessibilityLabel(title)
            .accessibilityValue(PanoramaCanvas.summary(sky:sky,facing:facing,park:park,bortle:Double(park.bortleEstimate),size:size == .zero ? CGSize(width:390,height:800) : size))
            .accessibilityHint("Swipe up or down to turn 45 degrees.")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: completeReveal(); face(facing+45)
                case .decrement: completeReveal(); face(facing-45)
                @unknown default: break
                }
            }
            .modifier(SkyChrome(beside:beside,header:header,controls:controls(sky:sky),column:column(sky:sky)))
            .background(Color.black)
            .onGeometryChange(for:CGSize.self) { CGSize(width:$0.size.width.rounded(),height:$0.size.height.rounded()) } action:{ screen=$0 }
            .statusBarHidden(palette.nightVision)
            .sensoryFeedback(.selection,trigger:Int(minutes/30))
            .onChange(of:minutes) { completeReveal() }
            .task { await reveal() }
            #if DEBUG
            .task { await debugFling() }
            #endif
    }
    /// The landing caption's slow fade once the sky has settled by itself; a touch fades it at `NyxMotion.fade`.
    private static let captionRelease=Animation.easeOut(duration:0.8)
    /// Starts the reveal on first appearance for this park and night, and lands it after `duration`.
    private func reveal() async {
        SkyAdaptation.seen.insert(SkyAdaptation.key(parkID:park.id,night:night.id))
        if previewLanded { revealing=false; landedNaturally=revealAllowed; return }
        guard revealing, revealAllowed else { revealing=false; captionShown=false; return }
        if let frozen=SkyAdaptation.frozen { landedNaturally=frozen>=1; return }
        revealStart = .now
        try? await Task.sleep(for:.seconds(SkyAdaptation.duration))
        guard !Task.isCancelled, revealing else { return }
        revealing=false
        // Landed by itself: one true sentence in the caption's place, then it goes as before.
        withAnimation(NyxMotion.spring) { landedNaturally=true }
        try? await Task.sleep(for:.seconds(SkyAdaptation.landingHold))
        guard !Task.isCancelled, captionShown else { return }
        withAnimation(Self.captionRelease) { captionShown=false }
    }
    #if DEBUG
    /// DEBUG: `-nyx-sky-fling 90` coasts 90° (as a fling to the left would) two seconds after the
    /// sky opens, for frame checks; `-nyx-sky-turn 180` presses that direction's button instead.
    private func debugFling() async {
        let fling=DebugScenario.number("-nyx-sky-fling"), button=DebugScenario.number("-nyx-sky-turn")
        guard fling != nil || button != nil else { return }
        try? await Task.sleep(for:.seconds(2))
        completeReveal()
        if let button { turn(toward:button); return }
        guard let fling, !reduceMotion else { return }
        let target=facing+max(-SkyTurn.maximumCoast,min(SkyTurn.maximumCoast,fling))
        turning=SkyTurn.Motion(from:facing,to:target,velocity:4,start:.now)
        withAnimation(.interpolatingSpring(NyxMotion.model,initialVelocity:4)) { facing=target }
    }
    #endif
    /// A touch completes the reveal at once: the whole sky, and the caption fades.
    private func completeReveal() {
        guard revealing || captionShown else { return }
        revealing=false
        withAnimation(NyxMotion.fade) { captionShown=false }
    }
    private var title: String {
        isTonight ? String(localized:"Tonight's sky over \(park.shortName)") : String(localized:"The sky over \(park.shortName), \(park.dayLabel(night.id))")
    }
    private var header: some View {
        HStack(alignment:.top,spacing:12) {
            titleBlock
            Spacer(minLength:8)
            closeButton
        }
        .padding(.horizontal,20).padding(.top,8)
        .shadow(color:.black.opacity(0.8),radius:8)
        .onGeometryChange(for:Double.self) { $0.frame(in:.global).maxY } action:{ headerBottom=$0+6 }
    }
    private var closeButton: some View {
        Button { dismiss() } label:{ Image(systemName:"xmark").font(.body.weight(.semibold)).frame(width:44,height:44) }
            .nyxGlass(Circle())
            .accessibilityLabel("Close")
    }
    private var titleBlock: some View {
        VStack(alignment:.leading,spacing:4) {
            Text(title).font(.system(.title3,design:.serif)).foregroundStyle(palette.ink).fixedSize(horizontal:false,vertical:true)
                .accessibilityAddTraits(.isHeader)
            if !large {
                Text("\(park.dayLabel(night.id)) · \(park.time(moment)) · facing \(Compass.name(facing))").font(.caption).foregroundStyle(palette.muted)
                    .fixedSize(horizontal:false,vertical:true).accessibilityHidden(true)
            }
            // Visual only: VoiceOver hears the sky's summary, unchanged.
            if captionShown && revealAllowed && !large {
                // One slot: the landing sentence crossfades over the caption, never under it.
                ZStack(alignment:.topLeading) {
                    if landedNaturally {
                        Text("Outdoors, this takes about 30 minutes.").transition(.opacity)
                    } else {
                        Text("As your eyes adapt").transition(.opacity)
                    }
                }
                .font(.system(.footnote,design:.serif)).italic().foregroundStyle(palette.muted)
                .fixedSize(horizontal:false,vertical:true)
                .padding(.top,6).transition(.opacity).accessibilityHidden(true)
            }
        }
    }
    /// Beside the sky at compact height: the title and close button, then the same controls, in one
    /// glass column that scrolls when the text is large. A third of the width, half at accessibility sizes.
    private func column(sky:HorizonSky)->some View {
        ScrollView {
            VStack(alignment:.leading,spacing:4) {
                HStack(alignment:.top,spacing:8) { titleBlock; Spacer(minLength:4); closeButton }
                    .padding(.horizontal,16).padding(.top,12)
                controlRows(sky:sky).padding(16)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width:large ? (screen.width*0.5).rounded() : min(360,max(320,(screen.width*0.38).rounded())))
        .nyxGlass(RoundedRectangle(cornerRadius:26))
        .padding(.vertical,8).padding(.trailing,8)
    }
    private func controls(sky:HorizonSky)->some View {
        ScrollView { controlRows(sky:sky).padding(16) }.scrollBounceBehavior(.basedOnSize).frame(maxHeight:max(240,screenHeight*0.5)).fixedSize(horizontal:false,vertical:true)
        .nyxGlass(RoundedRectangle(cornerRadius:26))
        .padding(.horizontal,12).padding(.bottom,8)
        .readableColumn(WideLayout.proseWidth)
    }
    private func controlRows(sky:HorizonSky)->some View {
        VStack(alignment:.leading,spacing:12) {
            if large {
                // A part to a line: the time, then the phase, never truncated side by side.
                VStack(alignment:.leading,spacing:4) {
                    Text(park.time(moment)).font(.system(.title2,design:.serif)).monospacedDigit().foregroundStyle(palette.ink)
                    Text(phase(sky)).font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
                }.accessibilityElement(children:.combine)
                Slider(value:$minutes,in:0...max(5,window.duration/60),step:5) { Text("Time of night") }
                    .tint(palette.controlTint)
                    .accessibilityValue(park.time(moment))
                ViewThatFits(in:.horizontal) {
                    HStack { Text(park.time(window.start)); Spacer(minLength:8); Text(park.time(window.end)) }
                    VStack(alignment:.leading,spacing:2) { Text(park.time(window.start)); Text(park.time(window.end)) }
                }
                .font(.caption2).foregroundStyle(palette.muted).accessibilityHidden(true)
                directionGrid
            } else {
                HStack(alignment:.firstTextBaseline) {
                    Text(park.time(moment)).font(.system(.title2,design:.serif)).monospacedDigit().foregroundStyle(palette.ink)
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
                    // The column beside the sky: two by two, as at large sizes, rather than four rows.
                    if beside { directionGrid } else {
                        VStack(alignment:.leading,spacing:8) { directions }
                    }
                }
            }
            Text("Drawn for an estimated Bortle \(park.bortleEstimate) sky. Clouds are not shown; the score covers them.").font(.caption2).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
        }
    }
    @ViewBuilder private var directions: some View {
        ForEach(0..<4,id:\.self) { index in direction(index) }
    }
    private var directionGrid: some View {
        Grid(alignment:.leading,horizontalSpacing:8,verticalSpacing:8) {
            GridRow { direction(0); direction(1) }
            GridRow { direction(2); direction(3) }
        }
    }
    /// North, east, south or west (0…3): turns there the short way round.
    private func direction(_ index:Int)->some View {
        let names=[String(localized:"North"),String(localized:"East"),String(localized:"South"),String(localized:"West")]
        let azimuth=Double(index)*90, name=names[index]
        let facingIt=Compass.name(facing)==Compass.name(azimuth)
        // The way you face in starlight with a starlight rim, the others muted: a control, not the score.
        return Button(name) { completeReveal(); turn(toward:azimuth) }
            .buttonStyle(.bordered).buttonBorderShape(.capsule).font(.footnote.weight(.medium))
            .tint(facingIt ? palette.ink : palette.muted)
            .overlay { if facingIt { Capsule().strokeBorder(palette.ink.opacity(palette.highContrast ? 1 : 0.7),lineWidth:palette.stroke).allowsHitTesting(false) } }
            .accessibilityLabel(String(localized:"Face \(name)"))
            .accessibilityAddTraits(facingIt ? .isSelected : [])
    }
    /// `SkyPhase`'s words; the slider's sunset and sunrise ends read "Twilight", never "The Sun is up".
    private func phase(_ sky:HorizonSky)->String {
        sky.sunAltitude > -6 ? String(localized:"Twilight") : SkyPhase.name(sunAltitude:sky.sunAltitude)
    }
    /// Facing is kept unwrapped (370° is 10°): the projection is trigonometry and `Compass.name`
    /// normalises, so a turn across north animates the short way instead of spinning back.
    private func face(_ azimuth:Double) {
        turning=nil
        var still=Transaction(); still.disablesAnimations=true
        withTransaction(still) { facing=azimuth }
    }
    /// A direction button: the shortest way round on the shared spring, or at once under Reduce Motion.
    /// A turn already in flight starts from where the sky is on screen, not from its old target.
    private func turn(toward azimuth:Double) {
        let from=turning?.position(at:.now) ?? facing
        let target=SkyTurn.shortestTurn(from:from,to:azimuth)
        guard !reduceMotion, abs(target-from)>0.01 else { face(target); return }
        turning=SkyTurn.Motion(from:from,to:target,velocity:0,start:.now)
        withAnimation(NyxMotion.spring) { facing=target }
    }
    private var frame: SkyFrame { SkyFrame(options:options,size:size == .zero ? CGSize(width:390,height:800) : size) }
    /// Drag sideways to turn: the sky follows the finger, so dragging right turns to the left. A
    /// fling coasts on (not under Reduce Motion), and a finger on a turning sky catches it where it is.
    private var turn: some Gesture {
        DragGesture(minimumDistance:4).updating($dragging) { _,state,_ in state=true }.onChanged { drag in
            completeReveal()
            if dragFrom == nil {
                if let turning { face(turning.position(at:.now)) }
                dragFrom=facing
            }
            face((dragFrom ?? facing)-drag.translation.width*frame.degreesPerPoint)
        }.onEnded { drag in
            dragFrom=nil
            guard !reduceMotion else { return }
            let perPoint=frame.degreesPerPoint
            let target=SkyTurn.coastTarget(facing:facing,predicted:drag.predictedEndTranslation.width,translation:drag.translation.width,degreesPerPoint:perPoint)
            let distance=target-facing
            guard abs(distance)>0.5 else { return }
            // The release speed as a share of the distance left, as the spring takes it.
            let velocity=max(0,min(30,-drag.velocity.width*perPoint/distance))
            turning=SkyTurn.Motion(from:facing,to:target,velocity:velocity,start:.now)
            withAnimation(.interpolatingSpring(NyxMotion.model,initialVelocity:velocity)) { facing=target }
        }
    }
}
/// The sky drawn at an animatable facing, so a coast or a turn interpolates the drawing itself
/// frame by frame instead of cutting to the new direction.
private struct TurningPanorama: View, Animatable {
    let sky: HorizonSky
    var options: PanoramaOptions
    var animatableData: Double { get { options.facing } set { options.facing=newValue } }
    var body: some View { PanoramaCanvas(sky:sky,options:options) }
}
/// How the full-screen sky turns: a fling's coast and a direction button's shortest way round.
nonisolated enum SkyTurn {
    /// The furthest a fling coasts on after the finger lifts, in degrees.
    static let maximumCoast=120.0
    /// Where a fling comes to rest: the sky keeps following the finger by the distance it was
    /// predicted to travel (the predicted end less where it lifted), at most 120° either way.
    static func coastTarget(facing:Double,predicted:Double,translation:Double,degreesPerPoint:Double)->Double {
        let extra=(predicted-translation)*degreesPerPoint
        guard extra.isFinite else { return facing }
        return facing-max(-maximumCoast,min(maximumCoast,extra))
    }
    /// The facing that turns from `facing` to the direction `azimuth` the short way round
    /// (350° to 10° is +20°, never −340°). Unwrapped: the result may lie outside 0…360.
    static func shortestTurn(from facing:Double,to azimuth:Double)->Double {
        let delta=((azimuth-facing).truncatingRemainder(dividingBy:360)+540).truncatingRemainder(dividingBy:360)-180
        return facing+delta
    }
    /// A turn in flight on the shared spring, to read where it has got to.
    struct Motion: Sendable {
        let from: Double, to: Double
        /// The initial velocity as a share of the distance per second, as `interpolatingSpring` takes it.
        let velocity: Double
        let start: Date
        func position(at now:Date)->Double {
            let distance=to-from
            return from+NyxMotion.model.value(target:distance,initialVelocity:velocity*distance,time:max(0,now.timeIntervalSince(start)))
        }
    }
}
/// The sky view's adaptation reveal: once per park and night each time Nyx launches, in memory only.
@MainActor enum SkyAdaptation {
    static var seen: Set<String>=[]
    nonisolated static func key(parkID:String,night:Date)->String { "\(parkID)|\(Int(night.timeIntervalSince1970))" }
    /// Seconds for the stars to arrive. Real dark adaptation takes 20 to 30 minutes; this is the
    /// order they arrive in, not the time it takes, and the caption claims nothing more.
    nonisolated static let duration=4.0
    /// Where the reveal starts: the brightest stars and the planets already out (about magnitude
    /// 0.8 at a Bortle 3 site), so the sky continues from the lit card that opened it instead of
    /// going dark first. Honest: those are what an eye straight from a lit screen sees.
    nonisolated static let floor=0.3
    /// Seconds the landing sentence ("Outdoors, this takes about 30 minutes.") stays.
    nonisolated static let landingHold=3.0
    /// DEBUG: `-nyx-sky-adapt 0.5` holds the reveal at that point, for captures (absolute, no
    /// floor); `-nyx-sky-adapt 1.0` holds the landed sentence.
    static var frozen: Double? { DebugScenario.number("-nyx-sky-adapt").map { max(0,min(1,$0)) } }
    /// Adaptation at `now`: from the 0.3 floor to 1, eased in and out; the floor before the reveal starts.
    static func progress(since start:Date?,now:Date)->Double {
        if let frozen { return frozen }
        guard let start else { return floor }
        return floor+(1-floor)*eased(now.timeIntervalSince(start)/duration)
    }
    nonisolated static func eased(_ t:Double)->Double { let t=max(0,min(1,t)); return t*t*(3-2*t) }
}
/// Where the full-screen sky's title and controls stand: over the top and under the bottom of the
/// sky, or, at compact height, together in a column at its side. One structure in both, with only
/// the insets' contents changing, so turning the iPhone keeps the sky itself (its VoiceOver focus,
/// its gesture) rather than building a new one.
private struct SkyChrome<Header: View, Controls: View, Column: View>: ViewModifier {
    let beside: Bool
    let header: Header
    let controls: Controls
    let column: Column
    func body(content:Content)->some View {
        content
            .safeAreaInset(edge:.top,spacing:beside ? 0 : nil) { if !beside { header } }
            .safeAreaInset(edge:.bottom,spacing:beside ? 0 : nil) { if !beside { controls } }
            .safeAreaInset(edge:.trailing,spacing:0) { if beside { column } }
    }
}
/// The sky for a night as a window on the park's page: a still render that opens the full sky.
struct SkyWindowCard: View {
    @Environment(\.nyx) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    let night: Night
    var isTonight=true
    let open: ()->Void
    /// The moment the window shows: where the full sky opens (`TonightSkyView.defaultMinutes`).
    nonisolated static func moment(_ sky:SkyConditions)->Date { SkyAlmanac.nightWindow(sky).start.addingTimeInterval(TonightSkyView.defaultMinutes(sky)*60) }
    var body: some View {
        let sky=HorizonSkies.shared.sky(park:night.park,night:night.id,at:Self.moment(night.sky))
        let shape=RoundedRectangle(cornerRadius:24)
        // Keyed by the sky, so another night cross-fades in on the transaction that chose it (the
        // shared spring) rather than cutting; without an animation it simply changes.
        let picture=ZStack {
            PanoramaCanvas(sky:sky,options:PanoramaOptions(facing:SkyDome.facing(for:night.park),centreAltitude:32,span:1.7,labels:false,bortle:Double(night.park.bortleEstimate)))
                .id(sky.id).transition(.opacity)
        }
        Button(action:open) {
            Group {
                if typeSize.isAccessibilitySize {
                    // Large text would overflow a fixed window, so the words sit under the picture, as tall as they need.
                    VStack(alignment:.leading,spacing:0) {
                        picture.frame(height:160)
                        VStack(alignment:.leading,spacing:12) { caption; expandGlyph }
                            .frame(maxWidth:.infinity,alignment:.leading).padding(16).background(palette.panel)
                    }
                } else {
                    picture.frame(height:200)
                        .overlay(alignment:.bottomLeading) {
                            HStack(alignment:.bottom) { caption; Spacer(minLength:8); expandGlyph }
                                .padding(16)
                                .background(LinearGradient(colors:[.clear,.black.opacity(0.75)],startPoint:.top,endPoint:.bottom))
                        }
                }
            }
            .clipShape(shape)
            .overlay(shape.stroke(palette.line,lineWidth:0.5*palette.stroke))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children:.ignore)
        .accessibilityLabel(isTonight ? String(localized:"Tonight's sky over \(night.park.shortName)") : String(localized:"The sky over \(night.park.shortName), \(night.park.dayLabel(night.id))"))
        .accessibilityHint("Opens the sky for this night, hour by hour.")
        .accessibilityAddTraits(.isButton)
    }
    private var caption: some View {
        VStack(alignment:.leading,spacing:4) {
            Text(isTonight ? String(localized:"Tonight's sky") : String(localized:"This night's sky")).font(.system(.title3,design:.serif)).foregroundStyle(palette.ink).fixedSize(horizontal:false,vertical:true)
            Text("Planets, the Milky Way and town light, hour by hour").font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
        }
    }
    private var expandGlyph: some View {
        Image(systemName:"arrow.up.left.and.arrow.down.right").font(.subheadline.weight(.semibold)).foregroundStyle(palette.ink).accessibilityHidden(true)
    }
}

/// An interactive figure for "Reading the Bortle scale": the same summer sky redrawn from class 1
/// to class 9 as the slider moves, the fainter stars and the Milky Way giving way to a rising
/// glow, with the class's name and one thing you can see for yourself. An illustration, labelled
/// as one: the faint stars' pattern is seeded, not catalogued.
struct BortleFigure: View {
    @Environment(\.nyx) private var palette
    @Environment(\.skyHome) private var home
    @MotionReduced private var reduceMotion: Bool
    @State private var level=Double(DebugScenario.number("-nyx-bortle") ?? 3)
    private static let fallback:Park?=(try? ParkData.load())?.first { $0.id==Park.defaultID }
    private var park: Park? { home ?? Self.fallback }
    /// A summer night near new moon (July 15, 2026), with the Milky Way's core in the south.
    static let summer=Date(timeIntervalSince1970:1_784_116_800)
    /// A winter night near new moon (December 9, 2026), for parks with no true darkness in July.
    static let winter=Date(timeIntervalSince1970:1_796_850_000)
    /// The figure's sky for a park: the middle of true darkness on the summer new-moon night (or the
    /// middle of the night if it has none). The sky is cached by `HorizonSkies`.
    static func sky(_ park:Park,night date:Date=summer)->HorizonSky {
        let night=AstronomyEngine().conditions(for:park,on:park.evening(date))
        let window=SkyAlmanac.nightWindow(night)
        let middle=night.darkStart.flatMap { start in night.darkEnd.map { start.addingTimeInterval($0.timeIntervalSince(start)/2) } } ?? window.start.addingTimeInterval(window.duration/2)
        return HorizonSkies.shared.sky(park:park,night:park.evening(date),at:middle)
    }
    /// The figure's view: toward the park's best direction, 40° up, without the Moon or names.
    static func options(_ park:Park,bortle:Double)->PanoramaOptions {
        PanoramaOptions(facing:SkyDome.facing(for:park),centreAltitude:40,span:1.9,labels:false,bortle:bortle,showsMoon:false)
    }
    private var shownClass: Int { Int(level.rounded()) }
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            Text("An illustration").eyebrow().foregroundStyle(palette.muted)
            if let park {
                // Never more than 45% of the visible height, so the picture stays in view above the
                // slider while it is dragged (a landscape iPhone, accessibility sizes).
                PanoramaCanvas(sky:Self.sky(park),options:Self.options(park,bortle:level))
                    .containerRelativeFrame(.vertical) { length,_ in min(260,(length*0.45).rounded()) }
                    .clipShape(RoundedRectangle(cornerRadius:NyxMetrics.rowRadius,style:.continuous))
                    .nyxCard(radius:NyxMetrics.rowRadius)
                    .accessibilityHidden(true)
            }
            Slider(value:$level,in:1...9) { Text("Bortle class") } minimumValueLabel:{ Text("1").font(.caption).foregroundStyle(palette.muted) } maximumValueLabel:{ Text("9").font(.caption).foregroundStyle(palette.muted) } onEditingChanged:{ editing in
                if !editing { withAnimation(reduceMotion ? nil : NyxMotion.spring) { level=level.rounded() } }
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
            // Under the slider, so the slider sits right below the picture it changes.
            VStack(alignment:.leading,spacing:6) {
                Text("Class \(shownClass): \(BortleScale.name(shownClass))").font(.system(.title3,design:.serif)).foregroundStyle(palette.ink).contentTransition(.numericText(value:level))
                Text(BortleScale.cue(shownClass)).font(.subheadline).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
            }
            .accessibilityHidden(true)
            Text("A summer sky in \(park?.shortName ?? String(localized:"a national park")), redrawn at each class. Real skies vary with the season, the weather and where you stand.").font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
        }
        .sensoryFeedback(.selection,trigger:shownClass)
        // A card like `Panel`, a little tighter so the sky figure keeps its width inside an essay's column.
        .padding(18)
        .nyxCard(radius:NyxMetrics.heroRadius,fill:palette.panel)
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
#Preview("Sky over the park • landed (sentence)") {
    let m=PlanModel()
    if let p=m.home { TonightSkyView(night:m.night(p),previewLanded:true).environment(m).preferredColorScheme(.dark) }
}
#Preview("Sky over the park • Reduce Motion (whole, no caption)") {
    let m=PlanModel()
    if let p=m.home { TonightSkyView(night:m.night(p)).environment(m).environment(\.nyxReduceMotion,true).preferredColorScheme(.dark) }
}
#Preview("Sky over the park • AX5") {
    let m=PlanModel()
    if let p=m.home { TonightSkyView(night:m.night(p)).environment(m).dynamicTypeSize(.accessibility5).preferredColorScheme(.dark) }
}
#Preview("Sky over the park • landscape",traits:.landscapeLeft) {
    let m=PlanModel()
    if let p=m.home { TonightSkyView(night:m.night(p)).environment(m).preferredColorScheme(.dark) }
}
#Preview("Sky over the park • landscape • AX5",traits:.landscapeLeft) {
    let m=PlanModel()
    if let p=m.home { TonightSkyView(night:m.night(p)).environment(m).dynamicTypeSize(.accessibility5).preferredColorScheme(.dark) }
}
#Preview("Sky window") {
    let m=PlanModel()
    if let p=m.home { SkyWindowCard(night:m.night(p)) {}.padding().background(.black).preferredColorScheme(.dark) }
}
#Preview("Bortle figure") { ScrollView { BortleFigure().padding() }.background(.black).preferredColorScheme(.dark) }
#Preview("Bortle figure • AX5") { ScrollView { BortleFigure().padding() }.dynamicTypeSize(.accessibility5).background(.black).preferredColorScheme(.dark) }
