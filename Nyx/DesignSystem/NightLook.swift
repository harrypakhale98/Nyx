import SwiftUI

// Night vision as it reaches surfaces outside the app's own windows, the contrast arithmetic
// that keeps it legible, and a night's mark (`NightMark`), so a week reads alike on every device.
// Apart from NyxTheme.swift (the app's views and its sky), so the widgets and complications
// compile this alone.

struct NightVisionFilter: ViewModifier {
    let enabled:Bool
    var red:NightTint = .standard
    @ViewBuilder func body(content:Content)->some View {
        content.saturation(enabled ? 0 : 1).colorMultiply(enabled ? red.color : .white)
    }
}
/// One night look for what Nyx draws outside its own windows: the widgets, the Live Activity, the
/// alarm and Siri's cards. Night vision and the brighter-red choice come from the shared suite,
/// where the app, Control Center and field mode write them; Increase Contrast comes from the view
/// that draws, since an extension has no app root to read it once. Where nothing filters the
/// surface red (a widget, the Live Activity), `ink` and `accent` are the red itself; where Nyx
/// draws a whole card (Siri), `palette` with `NightVisionFilter` reddens it as the app does.
nonisolated struct NightLook: Equatable, Sendable {
    let nightVision: Bool
    let brighterRed: Bool
    let highContrast: Bool
    /// The night-vision switch's key in the shared defaults.
    static let nightVisionKey="nightVision"
    /// Starlight and moon-amber, gamma-encoded sRGB, from `NyxPalette`.
    static let starlight=NyxPalette.starlightRGB, amber=NyxPalette.amberRGB
    init(nightVision: Bool, brighterRed: Bool=false, highContrast: Bool=false) {
        self.nightVision=nightVision; self.brighterRed=brighterRed; self.highContrast=highContrast
    }
    /// From the shared settings. `nightVision` stands in for the stored switch on a surface that
    /// carries its own (a widget's entry, a Live Activity's state).
    init(defaults: UserDefaults=SharedSettings.defaults, contrast: ColorSchemeContrast = .standard, nightVision: Bool?=nil) {
        self.init(nightVision:nightVision ?? defaults.bool(forKey:Self.nightVisionKey),brighterRed:defaults.bool(forKey:NightTint.key),highContrast:contrast == .increased)
    }
    var palette: NyxPalette { NyxPalette(nightVision:nightVision,highContrast:highContrast,brighterRed:brighterRed) }
    /// The brighter red by choice or under Increase Contrast, as in the app.
    var red: NightTint { palette.red }
    var inkRGB: SIMD3<Double> { nightVision ? red.rgb : Self.starlight }
    var accentRGB: SIMD3<Double> { nightVision ? red.rgb : Self.amber }
    var ink: Color { Color(red:inkRGB.x,green:inkRGB.y,blue:inkRGB.z) }
    var accent: Color { Color(red:accentRGB.x,green:accentRGB.y,blue:accentRGB.z) }
    /// Secondary text. Night vision's red is already dim, so it stays near full, and full under
    /// Increase Contrast; starlight is held at 90% there, as in the app.
    var mutedOpacity: Double { nightVision ? (highContrast ? 1 : 0.9) : highContrast ? 0.9 : 0.7 }
    var muted: Color { ink.opacity(mutedOpacity) }
}
/// How text contrast holds up for the commonest colour-vision deficiencies: Machado, Oliveira and
/// Fernandes (2009) full-severity matrices, applied in linear RGB, then WCAG 2 contrast.
nonisolated enum ColorVision: String, Sendable, CaseIterable {
    case typical, protan, deutan
    private var matrix: [[Double]] {
        switch self {
        case .typical: [[1,0,0],[0,1,0],[0,0,1]]
        case .protan: [[0.152286,1.052583,-0.204868],[0.114503,0.786281,0.099216],[-0.003882,-0.048116,1.051998]]
        case .deutan: [[0.367322,0.860646,-0.227968],[0.280085,0.672501,0.047413],[-0.011820,0.042940,0.968881]]
        }
    }
    /// Relative luminance of a gamma-encoded sRGB colour as these eyes see it.
    func luminance(_ rgb: SIMD3<Double>) -> Double {
        let l=[SRGB.linear(rgb.x),SRGB.linear(rgb.y),SRGB.linear(rgb.z)]
        let seen=matrix.map { row in min(1,max(0,zip(row,l).map(*).reduce(0,+))) }
        return 0.2126*seen[0]+0.7152*seen[1]+0.0722*seen[2]
    }
    /// WCAG contrast ratio between two colours, as these eyes see them.
    func contrast(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double {
        let x=luminance(a), y=luminance(b)
        return (max(x,y)+0.05)/(min(x,y)+0.05)
    }
}

// MARK: Colour independence

/// The shape vocabulary that carries meaning colour also carries, so nothing depends on amber alone.
/// Used everywhere a night is a mark: the calendar, the river, the week strip, the widgets and the watch.
nonisolated enum NightMark: Equatable, Sendable {
    /// Excellent or Pristine nights become four-pointed stars when Differentiate Without Color
    /// is on; every other night stays a dot. Hollow means no cloud forecast yet and half-filled an
    /// early look (a forecast eased toward the usual clouds), in both shapes.
    case dot(filled:Bool)
    case star(filled:Bool)
    static func mark(score:Int,hasForecast:Bool,differentiate:Bool)->NightMark {
        differentiate && score>=75 ? .star(filled:hasForecast) : .dot(filled:hasForecast)
    }
    /// A night's mark; an early look is drawn hollow with its lower half filled (`draw`).
    static func mark(_ night:Night,differentiate:Bool)->NightMark { mark(score:night.score.value,hasForecast:night.basis.fill == .full,differentiate:differentiate) }
    /// Draws a mark: filled, hollow, or hollow with its lower half filled for an early look.
    /// `stroke` is the palette's outline weight (`NyxPalette.stroke`: 1.6 under Increase Contrast or
    /// Bold Text). A mark that is not filled is never smaller than 2.6 pt in radius, grown by the
    /// half of the heavier outline that falls inward, so its hole stays the size it is at default
    /// settings and a half fill always reads as half, without a low score looking like a high one.
    /// `minimumRadius` replaces that floor where marks stand close together (the time river).
    func draw(in context:inout GraphicsContext,center:CGPoint,radius:Double,fill:NightFill,color:Color,fillOpacity:Double,lineWidth:Double=1.1,stroke:Double=1,minimumRadius:Double?=nil,hollowBackground:Color?=nil) {
        let radius=NightMark.drawnRadius(radius,fill:fill,lineWidth:lineWidth,stroke:stroke,minimum:minimumRadius)
        let lineWidth=lineWidth*stroke
        let shape=path(center:center,radius:radius)
        switch fill {
        case .full: context.fill(shape,with:.color(color.opacity(fillOpacity)))
        case .half, .hollow:
            if let hollowBackground { context.fill(shape,with:.color(hollowBackground)) }
            if fill == .half {
                var lower=context
                let reach=radius*1.5+2
                lower.clip(to:Path(CGRect(x:center.x-reach,y:center.y,width:2*reach,height:reach)))
                lower.fill(shape,with:.color(color.opacity(fillOpacity)))
            }
            context.stroke(shape,with:.color(color),lineWidth:lineWidth)
        }
    }
    /// The radius a mark is drawn at: as asked when filled, at least `floor` (or `minimum`) otherwise.
    static func drawnRadius(_ radius:Double,fill:NightFill,lineWidth:Double=1.1,stroke:Double,minimum:Double?=nil)->Double {
        fill == .full ? radius : max(radius,minimum ?? unfilledFloor(lineWidth:lineWidth,stroke:stroke))
    }
    /// The smallest radius for a mark that is not filled: 2.6 pt, plus the inward half of the extra
    /// outline `stroke` adds, so the hole inside the ring is the same at 1 and at 1.6. A score-40
    /// early look stays smaller than a score-85 dot under Bold Text, as it is by default.
    static func unfilledFloor(lineWidth:Double=1.1,stroke:Double)->Double { 2.6+lineWidth*max(0,stroke-1)/2 }
    var filled: Bool { switch self { case .dot(let filled),.star(let filled): filled } }
    /// The mark's outline, `radius` being the dot's own radius; a star reaches a little farther so
    /// it reads as the same size.
    func path(center:CGPoint,radius:Double)->Path {
        switch self {
        case .dot: return Path(ellipseIn:CGRect(x:center.x-radius,y:center.y-radius,width:2*radius,height:2*radius))
        case .star:
            let outer=max(3,radius*1.35), inner=outer*0.42
            var path=Path()
            for i in 0..<8 {
                let angle=Double(i)*Double.pi/4-Double.pi/2, r=i%2==0 ? outer : inner
                let point=CGPoint(x:center.x+r*cos(angle),y:center.y+r*sin(angle))
                if i==0 { path.move(to:point) } else { path.addLine(to:point) }
            }
            path.closeSubpath()
            return path
        }
    }
    /// One sentence for a legend, said only when the stars are drawn.
    static var legend: String { String(localized:"Star-shaped marks are Excellent or Pristine nights.") }
    /// A week's dot radius, `largest` being the surface's biggest: the week's lowest score at 0.32 of
    /// it, its highest at all of it, the rest between by score; a week of one score draws every dot
    /// at 0.66. Across the week's own range, so a week of 40s to 60s still shows its peak where sizes
    /// on the whole 0…100 scale were near identical. The app's 1.6 to 5 pt, scaled to each surface.
    static func radius(score:Int,low:Int,high:Int,largest:Double=5)->Double {
        let unit=high>low ? 1.6+3.4*Double(min(high,max(low,score))-low)/Double(high-low) : 3.3
        return unit*(largest/5)
    }
}
/// A mark's outline as a shape filling its frame (the dot's radius is half the frame), or only the
/// part below its centre: an early look's fill, reaching past a star's points as `draw` clips it.
nonisolated struct NightMarkShape: Shape {
    let mark: NightMark
    var lowerHalf = false
    func path(in rect: CGRect) -> Path {
        let center=CGPoint(x:rect.midX,y:rect.midY), radius=min(rect.width,rect.height)/2
        let shape=mark.path(center:center,radius:radius)
        guard lowerHalf else { return shape }
        let reach=radius*1.5+2
        return shape.intersection(Path(CGRect(x:center.x-reach,y:center.y,width:2*reach,height:reach)))
    }
}
/// A night's mark in SwiftUI shapes, for the widgets and the watch: filled with a forecast, hollow
/// without one, and hollow with its lower half filled for an early look, as `NightMark.draw` draws it
/// in the app; a star where `mark` is one (Differentiate Without Color).
struct NightDot: View {
    let fill: NightFill
    let color: Color
    var fillOpacity = 0.6
    var lineWidth = 1.0
    var mark: NightMark = .dot(filled: true)
    var body: some View {
        let shape=NightMarkShape(mark:mark)
        switch fill {
        case .full: shape.fill(color.opacity(fillOpacity))
        case .hollow: shape.stroke(color, lineWidth: lineWidth)
        case .half:
            ZStack {
                NightMarkShape(mark:mark,lowerHalf:true).fill(color.opacity(fillOpacity))
                shape.stroke(color, lineWidth: lineWidth)
            }
        }
    }
}
#Preview("Night dots") {
    VStack(spacing: 16) {
        ForEach([false, true], id: \.self) { star in
            HStack(spacing: 16) { ForEach([NightFill.full, .half, .hollow], id: \.self) { NightDot(fill: $0, color: .orange, mark: star ? .star(filled: true) : .dot(filled: true)).frame(width: 14, height: 14) } }
        }
    }.padding().background(.black)
}
