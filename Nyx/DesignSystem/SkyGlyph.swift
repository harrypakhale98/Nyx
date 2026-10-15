import SwiftUI

/// Small drawn marks for what is in the sky: the galaxy's bright center, a ringed planet, a meteor
/// streak, an eclipsed Moon, a crescent beside a planet, a near Full Moon, the Sun on the horizon at
/// a solstice, the gegenschein's soft glow and aurora's curtains. SF Symbols has no meteor or eclipse, and these share one hand:
/// hairline strokes, one filled accent, drawn at any size. Decorative; the text beside them speaks.
struct SkyGlyph: View {
    enum Kind: Sendable, CaseIterable { case core, planet, meteors, eclipse, aurora, pairing, moon, season, glow, binoculars }
    let kind: Kind
    var color: Color
    var body: some View {
        Canvas { context,size in Self.draw(kind,in:&context,rect:CGRect(origin:.zero,size:size),color:color) }
            .aspectRatio(1,contentMode:.fit)
            .accessibilityHidden(true)
    }
    init(_ kind:Kind,color:Color) { self.kind=kind; self.color=color }
    init(item kind:WhatsUp.Kind,color:Color) { self.kind=Kind(kind); self.color=color }
    /// Also used inside other canvases (calendar nights, the time river), at any rect.
    static func draw(_ kind:Kind,in context:inout GraphicsContext,rect:CGRect,color:Color) {
        let s=min(rect.width,rect.height), c=CGPoint(x:rect.midX,y:rect.midY), line=max(0.8,s/18)
        func p(_ x:Double,_ y:Double)->CGPoint { CGPoint(x:c.x+(x-0.5)*s,y:c.y+(y-0.5)*s) }
        switch kind {
        case .core:
            // A tilted lens of light with a bright heart: the galaxy seen edge-on.
            var lens=context
            lens.translateBy(x:c.x,y:c.y); lens.rotate(by:.degrees(-28))
            let ellipse=Path(ellipseIn:CGRect(x:-0.46*s,y:-0.15*s,width:0.92*s,height:0.3*s))
            lens.fill(ellipse,with:.radialGradient(Gradient(colors:[color.opacity(0.7),color.opacity(0.12)]),center:.zero,startRadius:0,endRadius:0.46*s))
            lens.stroke(ellipse,with:.color(color.opacity(0.8)),lineWidth:line)
            lens.fill(Path(ellipseIn:CGRect(x:-0.09*s,y:-0.09*s,width:0.18*s,height:0.18*s)),with:.color(color))
        case .planet:
            // A disc and a tilted ring, the ring passing in front of the disc's lower half.
            let disc=Path(ellipseIn:CGRect(x:c.x-0.22*s,y:c.y-0.22*s,width:0.44*s,height:0.44*s))
            context.fill(disc,with:.color(color))
            var ring=context
            ring.translateBy(x:c.x,y:c.y); ring.rotate(by:.degrees(-20))
            ring.stroke(Path(ellipseIn:CGRect(x:-0.47*s,y:-0.12*s,width:0.94*s,height:0.24*s)),with:.color(color.opacity(0.85)),lineWidth:line)
        case .meteors:
            // Two streaks leaving the same radiant, bright at the head, fading to the tail.
            for (start,end,width) in [(p(0.9,0.1),p(0.24,0.76),1.0),(p(0.92,0.42),p(0.56,0.78),0.7)] {
                var streak=Path(); streak.move(to:start); streak.addLine(to:end)
                context.stroke(streak,with:.linearGradient(Gradient(colors:[color.opacity(0),color]),startPoint:start,endPoint:end),style:StrokeStyle(lineWidth:line*1.6*width,lineCap:.round))
                context.fill(Path(ellipseIn:CGRect(x:end.x-line*1.5*width,y:end.y-line*1.5*width,width:line*3*width,height:line*3*width)),with:.color(color))
            }
        case .eclipse:
            // The Moon with Earth's round shadow across it.
            let r=0.38*s, moon=Path(ellipseIn:CGRect(x:c.x-r,y:c.y-r,width:2*r,height:2*r))
            context.drawLayer { layer in
                layer.fill(moon,with:.color(color))
                layer.blendMode = .destinationOut
                layer.fill(Path(ellipseIn:CGRect(x:c.x-r*0.55-r*1.25,y:c.y+r*0.3-r*1.25,width:2.5*r,height:2.5*r)),with:.color(.black))
            }
            context.stroke(moon,with:.color(color),lineWidth:line)
        case .aurora:
            // Three hanging curtains of light, brightest at the foot, fading upward.
            for (x,top,height) in [(0.24,0.22,0.56),(0.5,0.12,0.7),(0.76,0.28,0.48)] {
                var curtain=Path()
                curtain.move(to:p(x-0.06,top+height)); curtain.addQuadCurve(to:p(x+0.06,top+height),control:p(x,top+height+0.08))
                curtain.addLine(to:p(x+0.04,top)); curtain.addQuadCurve(to:p(x-0.04,top),control:p(x,top-0.04)); curtain.closeSubpath()
                context.fill(curtain,with:.linearGradient(Gradient(colors:[color.opacity(0.08),color]),startPoint:p(x,top),endPoint:p(x,top+height)))
            }
        case .pairing:
            // A thin crescent with a planet's point of light beside it.
            let r=0.3*s, centre=p(0.4,0.52)
            let disc=Path(ellipseIn:CGRect(x:centre.x-r,y:centre.y-r,width:2*r,height:2*r))
            context.drawLayer { layer in
                layer.fill(disc,with:.color(color))
                layer.blendMode = .destinationOut
                layer.fill(Path(ellipseIn:CGRect(x:centre.x-r+0.13*s,y:centre.y-r-0.04*s,width:2*r,height:2*r)),with:.color(.black))
            }
            let dot=p(0.82,0.3), d=0.07*s
            context.fill(Path(ellipseIn:CGRect(x:dot.x-d,y:dot.y-d,width:2*d,height:2*d)),with:.color(color))
        case .moon:
            // A full disc with a faint halo: the Moon at its nearest and brightest.
            let r=0.3*s
            context.fill(Path(ellipseIn:CGRect(x:c.x-0.47*s,y:c.y-0.47*s,width:0.94*s,height:0.94*s)),
                         with:.radialGradient(Gradient(colors:[color.opacity(0.35),color.opacity(0)]),center:c,startRadius:r,endRadius:0.47*s))
            context.fill(Path(ellipseIn:CGRect(x:c.x-r,y:c.y-r,width:2*r,height:2*r)),with:.color(color))
        case .season:
            // The Sun half under the horizon line.
            let r=0.26*s, y=c.y+0.1*s
            var half=Path(); half.addArc(center:CGPoint(x:c.x,y:y),radius:r,startAngle:.degrees(180),endAngle:.degrees(360),clockwise:false); half.closeSubpath()
            context.fill(half,with:.color(color))
            var horizon=Path(); horizon.move(to:CGPoint(x:c.x-0.46*s,y:y)); horizon.addLine(to:CGPoint(x:c.x+0.46*s,y:y))
            context.stroke(horizon,with:.color(color.opacity(0.85)),style:StrokeStyle(lineWidth:line,lineCap:.round))
        case .binoculars:
            // Two round eyepieces joined by a bridge, a small cluster of points in the left one.
            for x in [0.3,0.7] {
                let centre=p(x,0.56), r=0.2*s
                context.stroke(Path(ellipseIn:CGRect(x:centre.x-r,y:centre.y-r,width:2*r,height:2*r)),with:.color(color),lineWidth:line)
            }
            var bridge=Path(); bridge.move(to:p(0.42,0.44)); bridge.addLine(to:p(0.58,0.44))
            context.stroke(bridge,with:.color(color),style:StrokeStyle(lineWidth:line,lineCap:.round))
            for (x,y,d) in [(0.26,0.52,0.035),(0.33,0.6,0.03),(0.3,0.5,0.025)] {
                let point=p(x,y); context.fill(Path(ellipseIn:CGRect(x:point.x-d*s,y:point.y-d*s,width:2*d*s,height:2*d*s)),with:.color(color))
            }
        case .glow:
            // A soft, wide oval of light with no edge: the gegenschein.
            var oval=context
            oval.translateBy(x:c.x,y:c.y); oval.scaleBy(x:1,y:0.7)
            oval.fill(Path(ellipseIn:CGRect(x:-0.46*s,y:-0.46*s,width:0.92*s,height:0.92*s)),
                      with:.radialGradient(Gradient(colors:[color.opacity(0.75),color.opacity(0.25),color.opacity(0)]),center:.zero,startRadius:0,endRadius:0.46*s))
        }
    }
}
extension SkyGlyph.Kind {
    init(_ glyph:WhatsUp.Events.Glyph) { self = switch glyph { case .eclipse: .eclipse; case .meteors: .meteors } }
    init(_ kind:WhatsUp.Kind) {
        self = switch kind {
        case .core: .core
        case .planet, .planetBest: .planet
        case .meteors: .meteors
        case .eclipse: .eclipse
        case .aurora: .aurora
        case .pairing: .pairing
        case .moon: .moon
        case .season: .season
        case .gegenschein: .glow
        case .deepSky: .binoculars
        }
    }
}
#Preview("Glyphs") {
    HStack(spacing:24) { ForEach(SkyGlyph.Kind.allCases,id:\.self) { SkyGlyph($0,color:NyxPalette.amber).frame(width:28) } }
        .padding().background(.black)
}
#Preview("Glyphs • small") {
    HStack(spacing:12) { ForEach(SkyGlyph.Kind.allCases,id:\.self) { SkyGlyph($0,color:.white).frame(width:9) } }
        .padding().background(.black)
}
