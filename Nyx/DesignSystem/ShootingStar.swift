import SwiftUI
/// Pull to refresh's meteor: it brightens out of nothing, streaks while it is fastest and burns out,
/// as a real one does. Opacity follows sin(π·progress); the trail is longest at the launch spring's
/// top speed (`speed(progress:)`), so a slow end leaves only a short ember.
struct ShootingStar:View,Animatable {
    @Environment(\.nyx) private var palette
    var progress:Double
    var animatableData:Double { get { progress } set { progress=newValue } }
    /// Tonight's launch: critically damped, so the meteor never swings back.
    static let launch=Animation.spring(duration:0.55,bounce:0)
    var body:some View {
        Canvas { context,size in
            guard progress>0,progress<1 else { return }
            let head=CGPoint(x:size.width*(0.08+0.86*progress),y:size.height*(0.12+0.7*progress))
            // Along the direction of travel, 14 pt at rest to 60 pt at full speed.
            let dx=size.width*0.86, dy=size.height*0.7, norm=max(1,(dx*dx+dy*dy).squareRoot())
            let length=14+46*Self.speed(progress:progress)
            let tail=CGPoint(x:head.x-dx/norm*length,y:head.y-dy/norm*length)
            let glow=Self.brightness(progress:progress)
            var trail=Path();trail.move(to:tail);trail.addLine(to:head)
            context.stroke(trail,with:.linearGradient(Gradient(colors:[.clear,palette.ink.opacity(0.8*glow)]),startPoint:tail,endPoint:head),style:StrokeStyle(lineWidth:1.3,lineCap:.round))
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
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
#Preview("Shooting star • fading in") { ShootingStar(progress:0.08).frame(height:160).background(.black) }
#Preview("Shooting star • top speed") { ShootingStar(progress:0.26).frame(height:160).background(.black) }
#Preview("Shooting star • burning out") { ShootingStar(progress:0.85).frame(height:160).background(.black) }
