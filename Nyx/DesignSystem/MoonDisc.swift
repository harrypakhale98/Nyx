import SwiftUI

/// Project a lit sphere. cos(phase angle) gives the terminator ellipse;
/// strips preserve the crescent/gibbous geometry, including both hemispheres.
struct MoonDisc: View, Animatable {
    var animatableData: Double { get { illumination } set { illumination=newValue } }
    @Environment(\.nyx) private var palette
    var illumination: Double
    var waxing: Bool
    var southern: Bool=false
    var iconMode:Bool=false
    var body: some View {
        Canvas { context,size in
            let diameter=min(size.width,size.height), r=diameter/2
            let center=CGPoint(x:size.width/2,y:size.height/2)
            let circle=Path(ellipseIn:CGRect(x:center.x-r,y:center.y-r,width:diameter,height:diameter))
            if !iconMode { context.fill(circle,with:.radialGradient(Gradient(colors:[palette.panel,Color.black]),center:center,startRadius:0,endRadius:r)) }
            let k=1-2*min(1,max(0,illumination)), litRight=(waxing != southern)
            let count=160, height=diameter/Double(count)
            for i in 0..<count {
                let y = -r+(Double(i)+0.5)*height
                let limb=sqrt(max(0,r*r-y*y)), terminator=k*limb
                let left=litRight ? terminator : -limb, right=litRight ? limb : -terminator
                if right>left {
                    let rect=CGRect(x:center.x+left,y:center.y+y-height/2,width:right-left,height:height+0.3)
                    let shade=0.76+0.24*sqrt(max(0,1-pow(y/r,2)))
                    context.fill(Path(rect),with:.color(palette.ink.opacity(shade)))
                }
            }
            // In the tab bar the limb is always outlined, so a new moon is a ring, not nothing.
            let limb=iconMode ? max(1,diameter/16) : 0.6
            context.stroke(Path(ellipseIn:CGRect(x:center.x-r,y:center.y-r,width:diameter,height:diameter).insetBy(dx:limb/2,dy:limb/2)),with:.color(iconMode ? palette.ink : palette.line),lineWidth:limb)
            // Fixed, subtle mare texture, clipped to the disc. Never a photograph.
            var texture=context; texture.clip(to:circle)
            for (x,y,s) in [(0.32,0.31,0.18),(0.57,0.46,0.21),(0.37,0.67,0.12),(0.7,0.26,0.09)] {
                texture.fill(Path(ellipseIn:CGRect(x:center.x-r+x*diameter,y:center.y-r+y*diameter,width:s*diameter,height:s*diameter)),with:.color(.black.opacity(0.055)))
            }
        }
        .aspectRatio(1,contentMode:.fit)
        .accessibilityElement(children:.ignore)
        .accessibilityLabel("Moon, \(Int((illumination*100).rounded())) percent illuminated, \(waxing ? String(localized:"waxing") : String(localized:"waning"))")
        .accessibilityIgnoresInvertColors()
    }
}
#Preview("Phases") {
    VStack { ForEach([false,true],id:\.self) { waxing in HStack { ForEach([0.0,0.25,0.5,0.75,1],id:\.self) { phase in MoonDisc(illumination:phase,waxing:waxing) } } } }.padding().background(.black)
}
