import SwiftUI
struct ShootingStar:View,Animatable {
    @Environment(\.nyx) private var palette
    var progress:Double
    var animatableData:Double { get { progress } set { progress=newValue } }
    var body:some View {
        Canvas { context,size in
            guard progress>0,progress<1 else { return }
            let head=CGPoint(x:size.width*(0.08+0.86*progress),y:size.height*(0.12+0.7*progress))
            var trail=Path();trail.move(to:CGPoint(x:head.x-40,y:head.y-25));trail.addLine(to:head)
            context.stroke(trail,with:.linearGradient(Gradient(colors:[.clear,palette.ink.opacity(0.8)]),startPoint:CGPoint(x:head.x-40,y:head.y-25),endPoint:head),style:StrokeStyle(lineWidth:1.3,lineCap:.round))
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}
#Preview("Shooting star") { ShootingStar(progress:0.4).frame(height:160).background(.black) }
