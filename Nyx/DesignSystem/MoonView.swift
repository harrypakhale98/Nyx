import SwiftUI

/// The Moon as it will look from a park on a night: NASA's lunar map on a lit sphere, with the
/// real phase, the tilt seen from that place at the Moon's highest point that night, libration,
/// and earthshine on the night side. Falls back to the vector `MoonDisc` where Metal shaders
/// don't run (widgets) and in the tab bar.
///
/// Two sizes of map. From 120 pt (the Moon hero, onboarding, the share card, Assistive Access) it
/// draws on `MoonAtlas`: the 4096×2048 colour map, and LOLA's relief, which casts crater shadows
/// along the terminator unless `moonRelief` is off (while the Moon is being scrubbed). Smaller
/// Moons keep the 1024×512 `MoonMap` and gain a faint limb ring under 90 pt, so a Moon near new
/// reads as a Moon rather than a hole (the Tonight tab icon's convention).
struct MoonView: View {
    @Environment(\.nyx) private var palette
    @Environment(\.moonRelief) private var relief
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
                .overlay { limb(side:side) }
                .position(x:proxy.size.width/2,y:proxy.size.height/2)
        }
        .aspectRatio(1,contentMode:.fit)
        .accessibilityElement(children:.ignore)
        .accessibilityLabel(label)
        .accessibilityIgnoresInvertColors()
    }
    /// From this size the Moon draws on the atlas (and its relief); below it, never. Shared with
    /// the Vision Pro window (`MoonShading`).
    nonisolated static let atlasSide=MoonShading.atlasSide
    /// Below this size the Moon gains its limb ring and a brighter earthshine.
    nonisolated static let smallSide=90.0
    /// The terrain's slopes, exaggerated 2.5 times (`MoonShading.reliefStrength`).
    nonisolated static let reliefStrength=MoonShading.reliefStrength
    private func shader(side:Double)->Shader {
        let sun=light
        let size=Shader.Argument.float2(CGSize(width:side,height:side))
        let lighting=Shader.Argument.float4(sun.x,sun.y,sun.z,Self.earthshine(geometry,side:side))
        let frame=Shader.Argument.float4(cos(geometry.north),sin(geometry.north),geometry.librationLongitude,geometry.librationLatitude)
        if MoonShading.usesAtlas(side:side) {
            return ShaderLibrary.nyxMoonRelief(size,lighting,frame,.float(relief ? Self.reliefStrength : 0),.image(Image("MoonAtlas")))
        }
        return ShaderLibrary.nyxMoon(size,lighting,frame,.image(Image("MoonMap")))
    }
    /// The Sun's direction in screen space (x right, y up, z toward the viewer).
    private var light:SIMD3<Double> { MoonShading.sunDirection(geometry) }
    /// Earth as seen from the Moon is full when the Moon is new: the night side glows most then.
    /// The hero is physically scaled (0.09 of the albedo at most); under 90 pt the floor is lifted
    /// to 0.14, so a 20–60 pt Moon near new keeps a visible night side.
    nonisolated static func earthshine(_ geometry:MoonGeometry,side:Double)->Double {
        (side<smallSide ? 0.14 : 0.09)*(1-cos(geometry.phaseAngle))/2
    }
    /// The limb ring's strength: starlight at 30%, or at the palette's hairline strength (3:1 or
    /// more against black) under Increase Contrast and in night vision, which mirrors `NyxPalette.line`.
    nonisolated static func limbOpacity(nightVision:Bool,highContrast:Bool)->Double {
        nightVision ? 0.7 : highContrast ? 0.6 : 0.3
    }
    @ViewBuilder private func limb(side:Double)->some View {
        if side<Self.smallSide {
            let strong=palette.nightVision || palette.highContrast
            Circle().strokeBorder(palette.ink.opacity(Self.limbOpacity(nightVision:palette.nightVision,highContrast:palette.highContrast)),lineWidth:strong ? 1 : 0.75)
                .frame(width:side,height:side)
                .allowsHitTesting(false)
        }
    }
    private func halo(side:Double)->some View {
        // Fades out well inside its frame, so no container can clip it into a visible square.
        Circle().fill(RadialGradient(colors:[palette.ink.opacity(0.08+0.12*geometry.illumination),.clear],center:.center,startRadius:side*0.46,endRadius:side*0.68))
            .frame(width:side*1.4,height:side*1.4)
            .opacity(geometry.illumination>0.02 ? 1 : 0)
            .allowsHitTesting(false)
    }
    private var label:String { MoonView.label(geometry,moment:moment) }
    /// "Waxing crescent, 34 percent lit, lit from the right": the phase first, as people name it.
    static func label(_ geometry:MoonGeometry,moment:String?=nil)->String {
        let percent=Int((geometry.illumination*100).rounded())
        let degrees=Int((geometry.brightLimb*180/Double.pi).rounded())
        let side=MoonView.side(ofDegrees:degrees)
        let name=geometry.phase?.name ?? String(localized:"Moon")
        if let moment { return String(localized:"\(name), \(percent) percent lit, lit from the \(side), as seen \(moment)") }
        return String(localized:"\(name), \(percent) percent lit, lit from the \(side)")
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
extension EnvironmentValues {
    /// Whether a large Moon may draw its relief. Off while the Moon or the time river is being
    /// scrubbed, so the drag holds the display's full frame rate; the relief returns on release.
    @Entry var moonRelief=true
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
#Preview("Small Moons near new • contrast and night vision") {
    let engine=AstronomyEngine()
    if let park=try? ParkData.load().first(where:{ $0.id=="jotr" }) {
        let near=Date(timeIntervalSince1970:1791100000+28*86400)
        VStack(spacing:16) {
            HStack { ForEach([20.0,26,56,64],id:\.self) { side in MoonView(geometry:engine.moonGeometry(for:park,at:near)).frame(width:side) } }
            HStack { ForEach([20.0,26,56,64],id:\.self) { side in MoonView(geometry:engine.moonGeometry(for:park,at:near)).frame(width:side) } }
                .environment(\.nyx,NyxPalette(nightVision:false,highContrast:true))
            HStack { ForEach([20.0,26,56,64],id:\.self) { side in MoonView(geometry:engine.moonGeometry(for:park,at:near)).frame(width:side) } }
                .environment(\.nyx,NyxPalette(nightVision:true,highContrast:false)).modifier(NightVisionFilter(enabled:true))
        }.padding().background(.black)
    }
}
#Preview("Relief along the terminator") {
    let engine=AstronomyEngine()
    if let park=try? ParkData.load().first(where:{ $0.id=="jotr" }) {
        let crescent=Date(timeIntervalSince1970:1791100000+4*86400), quarter=Date(timeIntervalSince1970:1791100000+8*86400)
        VStack(spacing:20) {
            MoonView(geometry:engine.moonGeometry(for:park,at:quarter)).frame(width:280)
            HStack(spacing:20) {
                MoonView(geometry:engine.moonGeometry(for:park,at:crescent)).frame(width:150)
                MoonView(geometry:engine.moonGeometry(for:park,at:crescent)).frame(width:150).environment(\.moonRelief,false)
            }
        }.padding().background(.black)
    }
}
/// Near full the relief fades out (toward opposition and toward the limb): the edge stays clean.
#Preview("Relief near full Moon • limb stays clean") {
    let engine=AstronomyEngine()
    if let park=try? ParkData.load().first(where:{ $0.id=="jotr" }) {
        let full=Date(timeIntervalSince1970:1791100000+22*86400), gibbous=Date(timeIntervalSince1970:1791100000+20*86400)
        VStack(spacing:20) {
            MoonView(geometry:engine.moonGeometry(for:park,at:full)).frame(width:280)
            HStack(spacing:20) {
                MoonView(geometry:engine.moonGeometry(for:park,at:gibbous)).frame(width:120)
                MoonView(geometry:engine.moonGeometry(for:park,at:full)).frame(width:120)
            }
        }.padding().background(.black)
    }
}
