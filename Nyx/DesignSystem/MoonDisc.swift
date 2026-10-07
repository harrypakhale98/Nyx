import SwiftUI

/// Project a lit sphere. The lit region is bounded by the bright limb (a semicircle)
/// and the terminator, a half-ellipse whose horizontal semi-axis is cos(phase angle)·r.
/// Both edges are true vector curves, so the disc stays smooth at any size.
/// The southern hemisphere sees the Moon rotated 180°: the lit side and the maria flip.
struct MoonDisc: View, Animatable {
    var animatableData: Double { get { illumination } set { illumination=newValue } }
    @Environment(\.nyx) private var palette
    var illumination: Double
    var waxing: Bool
    var southern: Bool=false
    var iconMode:Bool=false
    /// Approximate near-side maria in unit coordinates (x right, y down) as seen from the north.
    private static let maria:[(x:Double,y:Double,w:Double,h:Double)]=[
        (-0.52,-0.02,0.42,0.86), // Oceanus Procellarum
        (-0.26,-0.42,0.46,0.40), // Imbrium
        (0.16,-0.38,0.30,0.28),  // Serenitatis
        (0.32,-0.06,0.36,0.30),  // Tranquillitatis
        (0.66,-0.30,0.20,0.18),  // Crisium
        (0.55,0.16,0.20,0.26),   // Fecunditatis
        (0.30,0.30,0.20,0.18),   // Nectaris
        (-0.18,0.38,0.32,0.24),  // Nubium
        (0.02,-0.74,0.70,0.12),  // Frigoris
    ]
    /// The lit part of the disc, in the disc's own coordinates.
    static func litPath(center:CGPoint,radius r:Double,illumination:Double,litRight:Bool,samples:Int=96)->Path {
        let k=1-2*min(1,max(0,illumination))
        let side:Double=litRight ? 1 : -1
        var path=Path()
        // Bright limb from the north pole to the south pole, then back up the terminator.
        for i in 0...samples {
            let t = -Double.pi/2+Double.pi*Double(i)/Double(samples)
            let point=CGPoint(x:center.x+side*r*cos(t),y:center.y+r*sin(t))
            if i==0 { path.move(to:point) } else { path.addLine(to:point) }
        }
        for i in stride(from:samples,through:0,by:-1) {
            let t = -Double.pi/2+Double.pi*Double(i)/Double(samples)
            path.addLine(to:CGPoint(x:center.x+side*k*r*cos(t),y:center.y+r*sin(t)))
        }
        path.closeSubpath()
        return path
    }
    /// A faint glow that grows with the light the Moon actually throws. Drawn in a larger
    /// layer behind the disc so the blur is never cut off at the disc's frame.
    private var halo: some View {
        GeometryReader { proxy in
            let side=min(proxy.size.width,proxy.size.height)
            Canvas { context,size in
                let lit=min(1,max(0,illumination))
                guard lit>0.02 else { return }
                let center=CGPoint(x:size.width/2,y:size.height/2)
                context.addFilter(.blur(radius:side*0.11))
                context.fill(Self.litPath(center:center,radius:side/2,illumination:lit,litRight:waxing != southern,samples:48),with:.color(palette.ink.opacity(0.10+0.16*lit)))
            }
            .frame(width:side*1.8,height:side*1.8)
            .position(x:proxy.size.width/2,y:proxy.size.height/2)
        }
        .allowsHitTesting(false)
    }
    var body: some View {
        Canvas { context,size in
            let diameter=min(size.width,size.height), r=diameter/2
            let center=CGPoint(x:size.width/2,y:size.height/2)
            let disc=CGRect(x:center.x-r,y:center.y-r,width:diameter,height:diameter)
            let circle=Path(ellipseIn:disc)
            let lit=min(1,max(0,illumination))
            let litPath=Self.litPath(center:center,radius:r,illumination:lit,litRight:waxing != southern,samples:iconMode ? 48 : 96)
            if iconMode {
                // The unlit disc is a faint ghost (template icons keep alpha), so a new moon is still
                // a moon, and a crescent reads as a crescent rather than as the letter O.
                context.fill(circle,with:.color(palette.ink.opacity(0.22)))
                context.fill(litPath,with:.color(palette.ink))
                return
            }
            // The unlit side: earthshine, never quite black.
            context.fill(circle,with:.radialGradient(Gradient(colors:[palette.panel,Color.black]),center:center,startRadius:0,endRadius:r))
            context.drawLayer { surface in
                surface.clip(to:litPath)
                surface.fill(circle,with:.color(palette.ink))
                // Maria: soft, low-contrast patches, flipped for the southern sky. Never a photograph.
                surface.drawLayer { seas in
                    seas.addFilter(.blur(radius:r*0.045))
                    let flip:Double=southern ? -1 : 1
                    for mare in Self.maria {
                        let x=center.x+flip*mare.x*r, y=center.y+flip*mare.y*r
                        seas.fill(Path(ellipseIn:CGRect(x:x-mare.w*r/2,y:y-mare.h*r/2,width:mare.w*r,height:mare.h*r)),with:.color(Color(red:0.36,green:0.34,blue:0.40).opacity(0.13)))
                    }
                }
                // Limb darkening: the edge of a sphere returns less light toward us.
                surface.fill(circle,with:.radialGradient(Gradient(stops:[.init(color:.clear,location:0.55),.init(color:.black.opacity(0.22),location:1)]),center:center,startRadius:0,endRadius:r))
                // A soft terminator: sunlight grazes the surface there.
                surface.drawLayer { edge in
                    edge.addFilter(.blur(radius:max(0.6,r*0.035)))
                    let shadow=Self.litPath(center:center,radius:r,illumination:1-lit,litRight:waxing == southern,samples:96)
                    edge.fill(shadow,with:.color(.black.opacity(0.55)))
                }
            }
            context.stroke(Path(ellipseIn:disc.insetBy(dx:0.3,dy:0.3)),with:.color(palette.line),lineWidth:0.6)
        }
        .aspectRatio(1,contentMode:.fit)
        .background { if !iconMode { halo } }
        .accessibilityElement(children:.ignore)
        .accessibilityLabel("Moon, \(Int((illumination*100).rounded())) percent illuminated, \(waxing ? String(localized:"waxing") : String(localized:"waning"))")
        .accessibilityIgnoresInvertColors()
    }
}
#Preview("Phases") {
    VStack { ForEach([false,true],id:\.self) { waxing in HStack { ForEach([0.0,0.25,0.5,0.75,1],id:\.self) { phase in MoonDisc(illumination:phase,waxing:waxing) } } } }.padding().background(.black)
}
#Preview("Southern • large") { MoonDisc(illumination:0.3,waxing:true,southern:true).frame(width:260).padding().background(.black) }
#Preview("Tab icon") { HStack { ForEach([0.0,0.3,0.5,0.9],id:\.self) { MoonDisc(illumination:$0,waxing:true,iconMode:true).frame(width:24,height:24) } }.padding().background(.black) }
