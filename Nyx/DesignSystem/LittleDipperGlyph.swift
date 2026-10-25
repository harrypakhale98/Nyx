import SwiftUI

/// The Little Dipper in its real shape (`LittleDipper.shape`), each star lit in starlight and sized
/// by its brightness when the eye should see it, a hollow hairline ring when it should not; the
/// asterism's lines are faint, so the shape reads even with two stars lit. One hand with
/// `SkyGlyph`: hairlines, filled points, nothing that moves. Decorative: whatever holds it says the
/// count (`LittleDipper.Reading.label`).
struct LittleDipperGlyph: View {
    @Environment(\.nyx) private var palette
    let reading: LittleDipper.Reading
    var body: some View {
        Canvas { context,size in Self.draw(reading,in:&context,size:size,palette:palette) }
            .aspectRatio(LittleDipper.shape.aspect,contentMode:.fit)
            .accessibilityHidden(true)
    }
    static func draw(_ reading:LittleDipper.Reading,in context:inout GraphicsContext,size:CGSize,palette:NyxPalette) {
        let shape=LittleDipper.shape
        // A margin for Polaris's halo, then the figure as large as the frame allows, centred.
        let margin=min(size.width,size.height)*0.16
        let scale=max(0,min((size.width-2*margin)/shape.aspect,size.height-2*margin))
        let origin=CGPoint(x:(size.width-scale*shape.aspect)/2,y:(size.height-scale)/2)
        let points=shape.points.map { CGPoint(x:origin.x+$0.x*scale,y:origin.y+$0.y*scale) }
        let hairline=0.7*palette.stroke
        // Polaris about 2 pt in a 25 pt-high mark, η UMi a point of 0.9: sized by magnitude, never a speck.
        func radius(_ star:LittleDipper.Star)->Double { max(0.9,scale*(0.05+0.06*(5-star.magnitude)/3)) }
        func ring(_ star:LittleDipper.Star)->Double { max(radius(star),1.15) }
        for (a,b) in LittleDipper.lines {
            let start=points[a], end=points[b], dx=end.x-start.x, dy=end.y-start.y, length=hypot(dx,dy)
            // Each line stops short of its stars, so a lit point keeps its own sky around it.
            let trimA=ring(LittleDipper.stars[a])+0.7, trimB=ring(LittleDipper.stars[b])+0.7
            guard length>trimA+trimB+0.5 else { continue }
            var line=Path()
            line.move(to:CGPoint(x:start.x+dx*trimA/length,y:start.y+dy*trimA/length))
            line.addLine(to:CGPoint(x:end.x-dx*trimB/length,y:end.y-dy*trimB/length))
            context.stroke(line,with:.color(palette.line.opacity(0.6)),style:StrokeStyle(lineWidth:0.6*palette.stroke,lineCap:.round))
        }
        for (star,point) in zip(LittleDipper.stars,points) {
            if reading.sees(star) {
                let r=radius(star)
                // The two brightest carry a soft halo, as Polaris and Kochab do to the eye.
                if star.magnitude<2.5 {
                    let h=r*2.2
                    context.fill(Path(ellipseIn:CGRect(x:point.x-h,y:point.y-h,width:2*h,height:2*h)),
                                 with:.radialGradient(Gradient(colors:[palette.ink.opacity(0.35),palette.ink.opacity(0)]),center:point,startRadius:r,endRadius:h))
                }
                context.fill(Path(ellipseIn:CGRect(x:point.x-r,y:point.y-r,width:2*r,height:2*r)),with:.color(palette.ink))
            } else {
                let r=ring(star)
                context.stroke(Path(ellipseIn:CGRect(x:point.x-r,y:point.y-r,width:2*r,height:2*r)),with:.color(palette.muted),lineWidth:hairline)
            }
        }
    }
}

private extension LittleDipper.Reading {
    /// A reading reaching exactly `limit` overhead, for previews.
    static func preview(_ limit:Double,clouds:Bool=false)->Self { Self(limit:limit,dimming:0,cloudsHide:clouds) }
}
/// How a holder speaks for the glyph: the drawing hidden, the count said.
private struct DipperPreviewRow: View {
    let reading: LittleDipper.Reading
    var body: some View {
        HStack(spacing:14) { LittleDipperGlyph(reading:reading).frame(width:88); Text(reading.label).font(.caption).foregroundStyle(NyxPalette.starlight.opacity(0.72)) }
            .accessibilityElement(children:.ignore).accessibilityLabel(reading.label)
    }
}
#Preview("Little Dipper • 7, 5, 2 visible, clouds") {
    VStack(alignment:.leading,spacing:24) { ForEach([6.5,4.3,2.5],id:\.self) { DipperPreviewRow(reading:.preview($0)) }; DipperPreviewRow(reading:.preview(6.5,clouds:true)) }
        .padding(24).background(.black).preferredColorScheme(.dark)
}
#Preview("Little Dipper • row size") {
    HStack(spacing:24) { ForEach([6.5,4.3,2.5],id:\.self) { LittleDipperGlyph(reading:.preview($0)).frame(width:44) } }
        .padding(24).background(.black).preferredColorScheme(.dark)
}
#Preview("Little Dipper • night vision") {
    VStack(alignment:.leading,spacing:24) { ForEach([6.5,4.3,2.5],id:\.self) { DipperPreviewRow(reading:.preview($0)) } }
        .padding(24).background(.black)
        .environment(\.nyx,NyxPalette(nightVision:true,highContrast:false)).modifier(NightVisionFilter(enabled:true)).preferredColorScheme(.dark)
}
#Preview("Little Dipper • AX5, Bold Text") {
    VStack(alignment:.leading,spacing:24) { ForEach([6.5,4.3,2.5],id:\.self) { DipperPreviewRow(reading:.preview($0)) } }
        .padding(24).background(.black).dynamicTypeSize(.accessibility5)
        .environment(\.nyx,NyxPalette(nightVision:false,highContrast:false,boldText:true)).preferredColorScheme(.dark)
}
