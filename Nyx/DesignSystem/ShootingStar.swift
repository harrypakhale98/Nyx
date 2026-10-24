import SwiftUI
/// Pull to refresh's meteor: it brightens out of nothing, streaks while it is fastest and burns out,
/// as a real one does. Opacity follows sin(π·progress); the trail is longest at the launch spring's
/// top speed (`speed(progress:)`), so a slow end leaves only a short ember.
/// Before it launches, the pull gathers it: a point of light at its start, kindled as the page is
/// pulled down (`gather`, 0 to 1), which the launch hands to the meteor's head.
struct ShootingStar:View,Animatable {
    @Environment(\.nyx) private var palette
    var progress:Double
    var gather=0.0
    var animatableData:AnimatablePair<Double,Double> { get { AnimatablePair(progress,gather) } set { progress=newValue.first; gather=newValue.second } }
    /// Tonight's launch: critically damped, so the meteor never swings back.
    static let launch=Animation.spring(duration:0.55,bounce:0)
    var body:some View {
        Canvas { context,size in
            // A star kindling where the meteor will start: a soft halo and a core, growing with the pull.
            // It is gone within the launch's first steps, so the light leaves with the head, not beside it.
            let kindled=gather*max(0,1-progress/0.08)
            if kindled>0 {
                let at=CGPoint(x:size.width*0.08,y:size.height*0.12), core=0.8+0.9*kindled, halo=4+6*kindled
                context.fill(Path(ellipseIn:CGRect(x:at.x-halo,y:at.y-halo,width:halo*2,height:halo*2)),with:.radialGradient(Gradient(colors:[palette.ink.opacity(0.35*kindled),.clear]),center:at,startRadius:0,endRadius:halo))
                context.fill(Path(ellipseIn:CGRect(x:at.x-core,y:at.y-core,width:core*2,height:core*2)),with:.color(palette.ink.opacity(0.9*kindled)))
            }
            guard progress>0,progress<1 else { return }
            let head=CGPoint(x:size.width*(0.08+0.86*progress),y:size.height*(0.12+0.7*progress))
            // Along the direction of travel, 14 pt at rest to 60 pt at full speed.
            let dx=size.width*0.86, dy=size.height*0.7, norm=max(1,(dx*dx+dy*dy).squareRoot())
            let length=14+46*Self.speed(progress:progress)
            let tail=CGPoint(x:head.x-dx/norm*length,y:head.y-dy/norm*length)
            // A gathered star launches already lit: its light (released on the same spring) carries the head
            // until the meteor's own brightness takes over.
            let glow=max(Self.brightness(progress:progress),gather)
            var trail=Path();trail.move(to:tail);trail.addLine(to:head)
            context.stroke(trail,with:.linearGradient(Gradient(colors:[.clear,palette.ink.opacity(0.8*glow)]),startPoint:tail,endPoint:head),style:StrokeStyle(lineWidth:1.3,lineCap:.round))
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
    /// How far a pull has gathered the star, in twelve steps (so a pull rebuilds the page a dozen
    /// times, not every frame): nothing at rest, full at `gatherDistance` of overscroll.
    nonisolated static func gather(overscroll:Double)->Double { (min(1,max(0,overscroll/gatherDistance))*12).rounded(.down)/12 }
    /// About where the system's refresh control commits.
    nonisolated static let gatherDistance=90.0
    /// 0 at both ends, 1 halfway: the meteor fades in and burns out.
    static func brightness(progress:Double)->Double { max(0,sin(Double.pi*min(max(progress,0),1))) }
    /// The launch spring's speed at a given progress, from 0 to 1 (its top speed). A critically damped
    /// spring from rest covers p(s) = 1 − (1 + s)·e^(−s) at s = ω·t, moving at s·e^(1 − s) of its peak;
    /// s is found by bisection, since p rises monotonically.
    static func speed(progress:Double)->Double {
        let p=min(max(progress,0),1)
        var low=0.0, high=14.0
        for _ in 0..<32 {
            let mid=(low+high)/2
            if 1-(1+mid)*exp(-mid)<p { low=mid } else { high=mid }
        }
        let s=(low+high)/2
        return min(1,max(0,s*exp(1-s)))
    }
}
/// A pull's state, read only by the meteor's overlay (`PullMeteor`), so a pull redraws the star, never the page.
@Observable final class PullGather {
    /// The overscroll as `ShootingStar.gather`, in its twelve steps.
    var pull=0.0
    /// A finger is on the page: a fling's bounce at the top, or the refresh control's inset, gathers nothing.
    var interacting=false
    /// This pull has launched its meteor; cleared once the page comes to rest.
    var spent=false
}
/// Tonight's meteor, reading the pull itself.
struct PullMeteor: View {
    let progress:Double
    let pull:PullGather
    /// Reduce Motion and Reduce Highlighting: no meteor, so nothing gathers either.
    var off=false
    var body:some View { ShootingStar(progress:progress,gather:off || pull.spent || !pull.interacting ? 0 : pull.pull) }
}
#Preview("Shooting star • gathering") { ShootingStar(progress:0,gather:0.75).frame(height:160).background(.black) }
#Preview("Shooting star • fading in") { ShootingStar(progress:0.08).frame(height:160).background(.black) }
#Preview("Shooting star • top speed") { ShootingStar(progress:0.26).frame(height:160).background(.black) }
#Preview("Shooting star • burning out") { ShootingStar(progress:0.85).frame(height:160).background(.black) }
