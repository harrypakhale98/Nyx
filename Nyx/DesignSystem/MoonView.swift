import SwiftUI

/// The Moon as it will look from a park on a night: NASA's lunar map on a lit sphere, with the
/// real phase, the tilt seen from that place at the Moon's highest point that night, libration,
/// and earthshine on the night side. Falls back to the vector `MoonDisc` where Metal shaders
/// don't run (widgets) and in the tab bar.
struct MoonView: View {
    @Environment(\.nyx) private var palette
    let geometry: MoonGeometry
    /// Spoken with the label, e.g. "as seen at 11:40 PM".
    var moment: String?=nil
    var body: some View {
        GeometryReader { proxy in
            let side=min(proxy.size.width,proxy.size.height)
            Rectangle().fill(.black)
                .frame(width:side,height:side)
                .colorEffect(shader(side:side))
                .background { halo(side:side) }
                .position(x:proxy.size.width/2,y:proxy.size.height/2)
        }
        .aspectRatio(1,contentMode:.fit)
        .accessibilityElement(children:.ignore)
        .accessibilityLabel(label)
        .accessibilityIgnoresInvertColors()
    }
    private func shader(side:Double)->Shader {
        let sun=light
        return ShaderLibrary.nyxMoon(.float2(CGSize(width:side,height:side)),.float4(sun.x,sun.y,sun.z,earthshine),
            .float4(cos(geometry.north),sin(geometry.north),geometry.librationLongitude,geometry.librationLatitude),.image(Image("MoonMap")))
    }
    /// The Sun's direction in screen space (x right, y up, z toward the viewer).
    private var light:SIMD3<Double> {
        let i=geometry.phaseAngle, a=geometry.brightLimb
        return SIMD3(sin(i) * -sin(a), sin(i)*cos(a), cos(i))
    }
    /// Earth as seen from the Moon is full when the Moon is new: the night side glows most then.
    private var earthshine:Double { 0.05*(1-cos(geometry.phaseAngle))/2 }
    private func halo(side:Double)->some View {
        // Fades out well inside its frame, so no container can clip it into a visible square.
        Circle().fill(RadialGradient(colors:[palette.ink.opacity(0.08+0.12*geometry.illumination),.clear],center:.center,startRadius:side*0.46,endRadius:side*0.68))
            .frame(width:side*1.4,height:side*1.4)
            .opacity(geometry.illumination>0.02 ? 1 : 0)
            .allowsHitTesting(false)
    }
    private var label:String {
        let percent=Int((geometry.illumination*100).rounded())
        let degrees=Int((geometry.brightLimb*180/Double.pi).rounded())
        let side=MoonView.side(ofDegrees:degrees)
        if let moment { return String(localized:"Moon, \(percent) percent illuminated, lit from the \(side), as seen \(moment)") }
        return String(localized:"Moon, \(percent) percent illuminated, lit from the \(side)")
    }
    /// Plain words for the direction of the lit side.
    static func side(ofDegrees value:Int)->String {
        let a=((value%360)+360)%360
        switch a {
        case 338...,..<23: return String(localized:"top")
        case 23..<68: return String(localized:"upper left")
        case 68..<113: return String(localized:"left")
        case 113..<158: return String(localized:"lower left")
        case 158..<203: return String(localized:"bottom")
        case 203..<248: return String(localized:"lower right")
        case 248..<293: return String(localized:"right")
        default: return String(localized:"upper right")
        }
    }
}
extension AstronomyEngine {
    /// The Moon for a night at a park, oriented as it looks at its highest point that night.
    func moon(for night:Night)->(geometry:MoonGeometry,moment:Date) {
        let at=moonViewTime(for:night.sky,park:night.park)
        return (moonGeometry(for:night.park,at:at),at)
    }
}
#Preview("Phases at Joshua Tree") {
    let engine=AstronomyEngine()
    if let park=try? ParkData.load().first(where:{ $0.id=="jotr" }) {
        HStack { ForEach([0,4,8,12,16,22],id:\.self) { day in
            MoonView(geometry:engine.moonGeometry(for:park,at:Date(timeIntervalSince1970:1791100000+Double(day)*86400))).frame(width:56)
        } }.padding().background(.black)
    }
}
