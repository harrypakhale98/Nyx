import SwiftUI

/// First light: the first time Nyx opens at a park after astronomical dusk, the sky overhead
/// appears once, slowly, the brightest stars first, the way eyes find them after a car's
/// headlights go out. Then the park's name. It stays until Continue (or VoiceOver's escape, or
/// Escape on a keyboard): no timer and no tap-anywhere, so nobody who reads slowly, uses Voice
/// Control, Switch Control or a keyboard, or nudges the screen by accident loses the moment.
/// Under Reduce Motion it is one gentle fade. It never holds the app back.
struct FirstLightView: View {
    @Environment(\.nyx) private var palette
    @MotionReduced private var reduceMotion: Bool
    @Environment(\.dynamicTypeSize) private var typeSize
    let park: Park
    let night: Date
    let moment: Date
    let close: ()->Void
    @State private var started: Date?
    @State private var visible=false
    @State private var leaving=false
    /// The stars have all arrived: the sky is drawn once more, whole, and the timeline rests.
    @State private var done=false
    /// Seconds for the stars to arrive; the name follows as the last of them do.
    private let reveal=7.0
    /// Under Reduce Motion the sky dissolves in slowly; leaving, it goes over a long breath, so the dark does not snap to the screen behind.
    private static let reducedArrival=Animation.easeInOut(duration:1), leave=Animation.easeOut(duration:0.9)
    /// The blooms' shared blur: the middle of the bright stars' diameters (2.6 to 4.7 pt), which
    /// each bloom's own blur once matched.
    private static let bloomBlur=3.6
    /// The words' viewport: they sit low on the screen and scroll when they do not fit it (an
    /// iPhone in landscape at accessibility sizes), so Continue is always reachable.
    @State private var viewport: CGFloat=0
    /// An iPhone in landscape: tighter margins, so the words keep more of the short screen.
    @Environment(\.verticalSizeClass) private var verticalSize
    var body: some View {
        let sky=SkyProjection.shared.sky(for:park,night:night,at:moment)
        let compact=verticalSize == .compact
        ZStack {
            Color.black.ignoresSafeArea()
            TimelineView(.animation(minimumInterval:1/30,paused:reduceMotion || done || started == nil || leaving)) { timeline in
                let elapsed=started.map { timeline.date.timeIntervalSince($0) } ?? 0
                let progress=reduceMotion || done ? 1 : min(1,elapsed/reveal)
                Canvas { context,size in draw(sky,progress:progress,in:&context,size:size) }
            }
            .opacity(reduceMotion ? (visible ? 1 : 0) : 1)
            .ignoresSafeArea()
            // The sky runs edge to edge; the words keep clear of the Dynamic Island and the rounded
            // corners at the sides (top and bottom keep the full-screen margins they always had).
            ScrollView {
                VStack(spacing:14) {
                    Eyebrow(text:"First light")
                    Text(park.shortName).font(.system(typeSize.isAccessibilitySize ? .title : .largeTitle,design:.serif)).multilineTextAlignment(.center).foregroundStyle(palette.ink)
                        .fixedSize(horizontal:false,vertical:true)
                    Text("Your first night under this sky. These are the stars above you now, facing \(park.latitude<0 ? String(localized:"north") : String(localized:"south")).").font(.body).foregroundStyle(palette.muted).multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true)
                    Button("Continue",action:dismiss).buttonStyle(.bordered).padding(.top,10).keyboardShortcut(.cancelAction)
                }
                .padding(.horizontal,32).padding(.top,compact ? 20 : 32).padding(.bottom,compact ? 28 : 86)
                .frame(maxWidth:.infinity,minHeight:viewport,alignment:.bottom)
            }
            .scrollBounceBehavior(.basedOnSize)
            // When the words outgrow the screen, it opens on Continue, the only way on.
            .defaultScrollAnchor(.bottom)
            // The bottom margin is measured from the screen's edge; the top keeps the safe area, so words
            // that outgrow the screen never scroll to rest behind the Dynamic Island.
            .ignoresSafeArea(edges:.bottom)
            .onGeometryChange(for:CGFloat.self) { $0.size.height.rounded() } action:{ viewport=$0 }
            .opacity(visible ? 1 : 0).offset(y:visible || reduceMotion ? 0 : 12)
        }
        .accessibilityIgnoresInvertColors()
        .opacity(leaving ? 0 : 1)
        .accessibilityElement(children:.contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape,dismiss)
        .task {
            started=Date.now
            if reduceMotion { withAnimation(Self.reducedArrival) { visible=true } }
            else {
                try? await Task.sleep(for:.seconds(reveal*0.7))
                withAnimation(NyxMotion.arrival) { visible=true }
            }
            AccessibilityNotification.Announcement(String(localized:"First light at \(park.shortName). The stars above you now.")).post()
            guard !reduceMotion else { return }
            // The last stars land at `reveal`; after that nothing moves, so nothing is redrawn.
            try? await Task.sleep(for:.seconds(reveal*0.3+0.2))
            if !Task.isCancelled { done=true }
        }
    }
    private func dismiss() {
        guard !leaving else { return }
        withAnimation(reduceMotion ? NyxMotion.fade : Self.leave) { leaving=true } completion:{ close() }
    }
    /// Each star arrives at a moment set by its brightness (bright first), with a soft ease; the
    /// Milky Way gathers last, when the eye is ready for it.
    private func draw(_ sky:SkyProjection.Sky,progress:Double,in context:inout GraphicsContext,size:CGSize) {
        func arrival(_ brightness:Double,_ seed:Double)->Double {
            let start=(1-brightness)*0.75+seed*0.08
            let t=min(1,max(0,(progress-start)/0.2))
            return t*t*(3-2*t)
        }
        // Only what can reach the canvas is drawn, as the sky behind every screen does (`RealSky`).
        func shows(_ p:CGPoint,_ margin:Double)->Bool { p.x > -margin && p.x<size.width+margin && p.y > -margin && p.y<size.height+margin }
        if sky.dark {
            let glow=min(1,max(0,(progress-0.7)/0.3))
            if glow>0 { context.drawLayer { layer in
                layer.addFilter(.blur(radius:26))
                for segment in sky.galaxy { for point in segment {
                    let p=SkyProjection.screen(point.position,size:size)
                    guard shows(p,22+52) else { continue }
                    layer.fill(Path(ellipseIn:CGRect(x:p.x-22,y:p.y-22,width:44,height:44)),with:.color(palette.ink.opacity(0.05*point.brightness*glow)))
                } }
            } }
        }
        // Each star that has begun to arrive, with where it lands.
        let arrived=(sky.faint+sky.middle+sky.bright).compactMap { star -> (star:SkyProjection.Star,p:CGPoint,a:Double)? in
            let a=arrival(star.brightness,star.seed), p=SkyProjection.screen(star.position,size:size)
            return a>0 && shows(p,star.diameter*1.6+2*Self.bloomBlur) ? (star,p,a) : nil
        }
        // A soft bloom, not a disc: bright stars swell slightly as the eye finds them. Every bloom
        // shares one blurred layer, one offscreen pass a frame rather than one a star.
        let blooms=arrived.filter { $0.star.diameter>2.6 }
        if !blooms.isEmpty { context.drawLayer { bloom in
            bloom.addFilter(.blur(radius:Self.bloomBlur))
            for (star,p,a) in blooms {
                let d=star.diameter
                bloom.fill(Path(ellipseIn:CGRect(x:p.x-d*1.6,y:p.y-d*1.6,width:d*3.2,height:d*3.2)),with:.color(star.tint(palette.ink).opacity(0.3*a)))
            }
        } }
        for (star,p,a) in arrived where shows(p,star.diameter) {
            let d=star.diameter
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
#Preview("First light • landscape • AX5",traits:.landscapeLeft) { let m=PlanModel(); if let p=m.home { FirstLightView(park:p,night:m.tonight(p),moment:m.tonight(p).addingTimeInterval(11*3600)) {}.dynamicTypeSize(.accessibility5) } }
