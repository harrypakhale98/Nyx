import SwiftUI

/// The Moon at size for the selected night: NASA's map on the lit sphere, about 280 pt and never
/// wider than the column, tilted as it stands over the park at its highest that night, with its
/// phase, how much is lit and when it rises and sets in park time. It follows the night chosen on
/// the river, and a horizontal drag across the Moon itself turns the nights one by one; the
/// terminator sweeps on the shared spring (at once under Reduce Motion).
struct MoonHero: View {
    @Environment(\.nyx) private var palette
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.nyxReduceMotion) private var forcedReduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    private var reduceMotion: Bool { systemReduceMotion || forcedReduceMotion }
    let night: Night
    /// Moves the selected night by a number of nights and says whether it moved (false at the
    /// river's ends); nil where the Moon only shows one night.
    var step: ((Int)->Bool)?=nil
    /// The drawn angles, kept unwrapped so a new night turns the short way round.
    @State private var phase: Double?
    @State private var limb: Double?
    @State private var north: Double?
    @State private var dragged=0
    @State private var detents=0
    /// Whether the current drag is a sideways scrub, decided once per drag; reset by the system even when a drag is cancelled.
    @GestureState private var scrubbing: Bool?=nil
    private var target: (geometry:MoonGeometry,moment:Date) { AstronomyEngine().moon(for:night) }
    var body: some View {
        let target=target
        let shown=MoonGeometry(phaseAngle:phase ?? target.geometry.phaseAngle,brightLimb:limb ?? target.geometry.brightLimb,north:north ?? target.geometry.north,
                               librationLongitude:target.geometry.librationLongitude,librationLatitude:target.geometry.librationLatitude)
        VStack(spacing:18) {
            MorphingMoon(geometry:shown)
                .frame(maxWidth:280).aspectRatio(1,contentMode:.fit)
                .padding(.horizontal,8)
                .contentShape(Circle())
                // Simultaneous, and only for drags that start sideways, so the page still scrolls through the Moon.
                .simultaneousGesture(scrub)
                .accessibilityHidden(true)
            VStack(spacing:6) {
                Text(night.sky.moon.name).font(.system(.title2,design:.serif)).foregroundStyle(palette.ink).contentTransition(.opacity)
                Text("\(Self.percent(night))% lit").font(.subheadline).foregroundStyle(palette.muted).contentTransition(.numericText())
            }.multilineTextAlignment(.center)
            ViewThatFits(in:.horizontal) {
                HStack(spacing:28) { times }
                VStack(spacing:10) { times }
            }
            Text(Self.tiltLine(night:night,moment:target.moment)).font(.caption).foregroundStyle(palette.muted).multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true)
        }
        .frame(maxWidth:.infinity)
        .accessibilityElement(children:.ignore)
        // A fixed name and the night as its value, so adjusting it says which night it now shows.
        .accessibilityLabel("Moon")
        .accessibilityValue(night.park.dayLabel(night.id)+". "+Self.spoken(night:night,geometry:target.geometry))
        .accessibilityAdjustableAction { direction in
            guard let step else { return }
            switch direction {
            case .increment: _=step(1)
            case .decrement: _=step(-1)
            @unknown default: break
            }
        }
        .accessibilityHint(step == nil ? "" : String(localized:"Swipe up or down to move one night at a time."))
        .sensoryFeedback(.selection,trigger:detents)
        // The page holds still during a sideways scrub, as it does for the river's.
        .preference(key:RiverScrubbingKey.self,value:scrubbing==true)
        .onChange(of:target.geometry,initial:true) { _,geometry in follow(geometry) }
    }
    @ViewBuilder private var times: some View {
        ForEach(Self.events(night),id:\.label) { event in
            VStack(spacing:2) {
                Text(event.label).font(.caption.weight(.medium)).foregroundStyle(palette.muted).textCase(typeSize.isAccessibilitySize ? nil : .uppercase).kerning(typeSize.isAccessibilitySize ? 0 : 1.2)
                Text(event.time).font(.system(.title3,design:.serif)).monospacedDigit().foregroundStyle(palette.accent)
            }
        }
    }
    /// Drag sideways across the Moon: one night per 36 pt, later to the right as on the river.
    /// The axis is chosen once per drag, as on the river; the detent is felt only when the night
    /// actually moves, never at the ends of the thirty nights.
    private var scrub: some Gesture {
        DragGesture(minimumDistance:8).updating($scrubbing) { drag,state,_ in
            if state==nil { state=abs(drag.translation.width)>abs(drag.translation.height) }
        }.onChanged { drag in
            guard let step, scrubbing ?? (abs(drag.translation.width)>abs(drag.translation.height)) else { return }
            let nights=Int((drag.translation.width/36).rounded(.towardZero))
            if nights != dragged {
                if step(nights-dragged) { detents+=1 }
                dragged=nights
            }
        }.onEnded { _ in dragged=0 }
    }
    private func follow(_ geometry:MoonGeometry) {
        let to=(phase:geometry.phaseAngle,
                limb:Self.nearest(geometry.brightLimb,to:limb ?? geometry.brightLimb),
                north:Self.nearest(geometry.north,to:north ?? geometry.north))
        withAnimation(reduceMotion || phase == nil ? nil : NyxMotion.spring) { phase=to.phase; limb=to.limb; north=to.north }
    }
    /// `angle` moved by whole turns to sit closest to `reference`, so the Moon never spins the long way.
    nonisolated static func nearest(_ angle:Double,to reference:Double)->Double {
        angle+2*Double.pi*((reference-angle)/(2*Double.pi)).rounded()
    }
    nonisolated static func percent(_ night:Night)->Int { Int((night.sky.moon.illumination*100).rounded()) }
    /// Moonrise and moonset within the night, in the order they happen.
    nonisolated static func events(_ night:Night)->[(label:String,time:String,date:Date)] {
        let park=night.park
        let list:[(String,Date?)]=[(String(localized:"Rises"),night.sky.moonrise),(String(localized:"Sets"),night.sky.moonset)]
        return list.compactMap { label,date in date.map { (label,park.time($0),$0) } }.sorted { $0.date<$1.date }
    }
    /// "Tilted as it looks from Joshua Tree at 11:40 PM."
    nonisolated static func tiltLine(night:Night,moment:Date)->String {
        String(localized:"Tilted as it looks from \(night.park.shortName) at \(night.park.time(moment)), at its highest that night.")
    }
    /// "Waxing crescent, 23 percent lit, lit from the lower right. Sets 9:40 PM."
    static func spoken(night:Night,geometry:MoonGeometry)->String {
        let side=MoonView.side(ofDegrees:Int((geometry.brightLimb*180/Double.pi).rounded()))
        var line=String(localized:"\(night.sky.moon.name), \(percent(night)) percent lit, lit from the \(side).")
        for event in events(night) { line+=" "+String(localized:"\(event.label) \(event.time).") }
        return line
    }
}
/// MoonView whose phase and tilt interpolate, so the terminator sweeps between two nights.
private struct MorphingMoon: View, Animatable {
    var geometry: MoonGeometry
    var animatableData: AnimatablePair<Double,AnimatablePair<Double,Double>> {
        get { AnimatablePair(geometry.phaseAngle,AnimatablePair(geometry.brightLimb,geometry.north)) }
        set { geometry=MoonGeometry(phaseAngle:newValue.first,brightLimb:newValue.second.first,north:newValue.second.second,librationLongitude:geometry.librationLongitude,librationLatitude:geometry.librationLatitude) }
    }
    var body: some View { MoonView(geometry:geometry) }
}
#Preview("Moon hero") {
    let m=PlanModel()
    if let p=m.home { ScrollView { MoonHero(night:m.night(p)).padding(24) }.background(.black).preferredColorScheme(.dark) }
}
#Preview("Moon hero • AX5") {
    let m=PlanModel()
    if let p=m.home { ScrollView { MoonHero(night:m.night(p,on:p.date(m.tonight(p),addingDays:8))).padding(24) }.dynamicTypeSize(.accessibility5).background(.black).preferredColorScheme(.dark) }
}
#Preview("Moon hero • night vision") {
    let m=PlanModel()
    if let p=m.home { MoonHero(night:m.night(p,on:p.date(m.tonight(p),addingDays:12))).padding(24).environment(\.nyx,NyxPalette(nightVision:true,highContrast:false)).modifier(NightVisionFilter(enabled:true)).background(.black) }
}
