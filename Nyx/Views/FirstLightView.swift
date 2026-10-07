import SwiftUI

/// First light: the first time Nyx opens at a park after astronomical dusk, the sky overhead
/// appears once, slowly, the brightest stars first, the way eyes find them after a car's
/// headlights go out. Then the park's name. Any tap ends it; it fades on its own after a while.
/// Under Reduce Motion it is one gentle fade. It never holds the app back.
struct FirstLightView: View {
    @Environment(\.nyx) private var palette
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.nyxReduceMotion) private var forcedReduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.accessibilitySwitchControlEnabled) private var switchControl
    let park: Park
    let night: Date
    let moment: Date
    /// Fades away on its own after a while; off in screenshot scenarios.
    var leavesOnItsOwn = true
    let close: ()->Void
    @State private var started: Date?
    @State private var visible=false
    @State private var leaving=false
    private var reduceMotion: Bool { systemReduceMotion || forcedReduceMotion }
    /// Seconds for the stars to arrive; the name follows as the last of them do.
    private let reveal=7.0
    var body: some View {
        let sky=SkyProjection.shared.sky(for:park,night:night,at:moment)
        ZStack {
            Color.black
            TimelineView(.animation(minimumInterval:1/30,paused:reduceMotion || started == nil || leaving)) { timeline in
                let elapsed=started.map { timeline.date.timeIntervalSince($0) } ?? 0
                let progress=reduceMotion ? 1 : min(1,elapsed/reveal)
                Canvas { context,size in draw(sky,progress:progress,in:&context,size:size) }
            }
            .opacity(reduceMotion ? (visible ? 1 : 0) : 1)
            VStack(spacing:14) {
                Spacer()
                Eyebrow(text:"First light")
                Text(park.shortName).font(.system(typeSize.isAccessibilitySize ? .title : .largeTitle,design:.serif)).multilineTextAlignment(.center).foregroundStyle(palette.ink)
                Text("Your first night under this sky. These are the stars above you now, facing \(park.latitude<0 ? String(localized:"north") : String(localized:"south")).").font(.body).foregroundStyle(palette.muted).multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true)
                Button("Continue",action:dismiss).buttonStyle(.bordered).padding(.top,10)
                Spacer().frame(height:40)
            }.padding(32)
            .opacity(visible ? 1 : 0).offset(y:visible || reduceMotion ? 0 : 12)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture(perform:dismiss)
        .opacity(leaving ? 0 : 1)
        .accessibilityElement(children:.contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape,dismiss)
        .task {
            started=Date.now
            if reduceMotion { withAnimation(.easeInOut(duration:1)) { visible=true } }
            else {
                try? await Task.sleep(for:.seconds(reveal*0.7))
                withAnimation(.spring(response:1.6,dampingFraction:1)) { visible=true }
            }
            AccessibilityNotification.Announcement(String(localized:"First light at \(park.shortName). The stars above you now.")).post()
            // Leave quietly if nobody touches it.
            try? await Task.sleep(for:.seconds(14))
            // Never on a timer for someone reading it with VoiceOver or Switch Control.
            if !Task.isCancelled && leavesOnItsOwn && !voiceOver && !switchControl { dismiss() }
        }
    }
    private func dismiss() {
        guard !leaving else { return }
        withAnimation(reduceMotion ? .easeOut(duration:0.3) : .easeOut(duration:0.9)) { leaving=true } completion:{ close() }
    }
    /// Each star arrives at a moment set by its brightness (bright first), with a soft ease; the
    /// Milky Way gathers last, when the eye is ready for it.
    private func draw(_ sky:SkyProjection.Sky,progress:Double,in context:inout GraphicsContext,size:CGSize) {
        func arrival(_ brightness:Double,_ seed:Double)->Double {
            let start=(1-brightness)*0.75+seed*0.08
            let t=min(1,max(0,(progress-start)/0.2))
            return t*t*(3-2*t)
        }
        if sky.dark {
            let glow=min(1,max(0,(progress-0.7)/0.3))
            if glow>0 { context.drawLayer { layer in
                layer.addFilter(.blur(radius:26))
                for segment in sky.galaxy { for point in segment {
                    let p=SkyProjection.screen(point.position,size:size)
                    layer.fill(Path(ellipseIn:CGRect(x:p.x-22,y:p.y-22,width:44,height:44)),with:.color(palette.ink.opacity(0.05*point.brightness*glow)))
                } }
            } }
        }
        for star in sky.faint+sky.middle+sky.bright {
            let a=arrival(star.brightness,star.seed)
            guard a>0 else { continue }
            let p=SkyProjection.screen(star.position,size:size), d=star.diameter
            if star.diameter>2.6 {
                // A soft bloom, not a disc: bright stars swell slightly as the eye finds them.
                context.drawLayer { bloom in
                    bloom.addFilter(.blur(radius:d))
                    bloom.fill(Path(ellipseIn:CGRect(x:p.x-d*1.6,y:p.y-d*1.6,width:d*3.2,height:d*3.2)),with:.color(star.tint(palette.ink).opacity(0.3*a)))
                }
            }
            context.fill(Path(ellipseIn:CGRect(x:p.x-d/2,y:p.y-d/2,width:d,height:d)),with:.color(star.tint(palette.ink).opacity(star.brightness*a)))
        }
        for planet in sky.planets {
            let a=arrival(1,0)
            let p=SkyProjection.screen(planet.position,size:size)
            context.fill(Path(ellipseIn:CGRect(x:p.x-2.6,y:p.y-2.6,width:5.2,height:5.2)),with:.color(palette.accent.opacity(a)))
        }
    }
}
/// Watches for first light: when Nyx becomes active, if location was already allowed and this
/// iPhone is at a park in true darkness, and that park has never had its moment.
@MainActor enum FirstLightWatcher {
    static func check(model:PlanModel,now:Date = .now) async -> Park? {
        // Only in the evening and night hours here, so a daytime open never asks where the iPhone is.
        let hour=Calendar.current.component(.hour,from:now)
        guard DebugScenario.screen == nil, hour>=17 || hour<7, let fix=await OneShotLocation.current(),
              let park=model.fieldPark(latitude:fix.latitude,longitude:fix.longitude) else { return nil }
        let seen=UserDefaults.standard.bool(forKey:FirstLight.key(park.id))
        guard FirstLight.shouldShow(sky:model.night(park).sky,now:now,alreadySeen:seen) else { return nil }
        UserDefaults.standard.set(true,forKey:FirstLight.key(park.id))
        return park
    }
}
#Preview("First light") { let m=PlanModel(); if let p=m.home { FirstLightView(park:p,night:m.tonight(p),moment:m.tonight(p).addingTimeInterval(11*3600)) {} } }
