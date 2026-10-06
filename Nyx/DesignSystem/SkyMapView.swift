import SwiftUI

/// What a sky map shows: the 63 parks as the faint stars of the sky, a few bright stars on top, and
/// figures joining them. Figures draw themselves one after another.
nonisolated struct SkyMapContent: Sendable {
    struct Star: Identifiable, Sendable {
        let id: String
        /// Canvas units, as `SkyMap`.
        let point: CGPoint
        /// 0.3…1.
        let brightness: Double
        /// Ringed in amber: the trip's best night.
        var ringed = false
        /// What VoiceOver says for the star.
        let label: String
    }
    var stars: [Star]
    var figures: [[(CGPoint, CGPoint)]]
    /// The part of the canvas shown, in canvas units.
    var viewport = CGRect(x:0,y:0,width:1,height:SkyMap.aspect)
    var showsInsets = true
    /// The regions whose faint coastline is drawn: all of them on the whole map, only the trip's own
    /// when zoomed, so an inset's outline never wanders into a close-up of the lower 48.
    var outlineRegions = Set(SkyMap.Region.allCases)
    /// The smallest box around `points`, padded and widened to the map's shape, so a trip's few
    /// hundred miles fill the panel instead of a corner of the country.
    static func viewport(around points: [CGPoint], padding: Double = 0.05, minimumWidth: Double = 0.16) -> CGRect {
        guard let first=points.first else { return CGRect(x:0,y:0,width:1,height:SkyMap.aspect) }
        var box=points.dropFirst().reduce(CGRect(origin:first,size:.zero)) { $0.union(CGRect(origin:$1,size:.zero)) }.insetBy(dx:-padding,dy:-padding)
        let width=max(minimumWidth,box.width,box.height/SkyMap.aspect)
        box=CGRect(x:box.midX-width/2,y:box.midY-width*SkyMap.aspect/2,width:width,height:width*SkyMap.aspect)
        return box
    }
}
/// The sky map, drawn in Canvas. `progress` runs 0…1 across all figures, in order.
struct SkyMapCanvas: View {
    @Environment(\.nyx) private var palette
    let content: SkyMapContent
    var progress: Double = 1
    /// Every park, as faint background stars.
    var parks: [Park]
    var body: some View {
        Canvas { context,size in
            let view=content.viewport
            let scale=min(size.width/view.width,size.height/view.height)
            let dx=(size.width-view.width*scale)/2, dy=(size.height-view.height*scale)/2
            func screen(_ p:CGPoint)->CGPoint { CGPoint(x:dx+(p.x-view.minX)*scale,y:dy+(p.y-view.minY)*scale) }
            let zoom=min(3,max(1,1/view.width))
            // The insets' quiet frames and names, only on the whole map.
            if content.showsInsets && view.width>0.9 {
                for inset in SkyMap.insets.dropFirst() {
                    let rect=CGRect(origin:screen(inset.frame.origin),size:CGSize(width:inset.frame.width*scale,height:inset.frame.height*scale)).insetBy(dx:-3,dy:-3)
                    context.stroke(Path(roundedRect:rect,cornerRadius:4),with:.color(palette.line.opacity(0.7)),style:StrokeStyle(lineWidth:0.5,dash:[2,3]))
                    // Kept inside the canvas: a longer name ("I. Vírgenes") ends at the right edge instead of past it.
                    let name=context.resolve(Text(inset.name).font(.system(size:8,weight:.medium)).foregroundStyle(palette.muted.opacity(0.85)))
                    let width=name.measure(in:size).width
                    context.draw(name,at:CGPoint(x:max(1,min(rect.minX+1,size.width-width-1)),y:rect.maxY+2),anchor:.topLeading)
                }
            }
            // The country, barely there: coasts and borders so the stars read as places.
            for outline in SkyMap.outlines where content.outlineRegions.contains(outline.region) {
                var path=Path()
                for ring in outline.rings { path.addLines(ring.map(screen)); path.closeSubpath() }
                let clip=outline.clip
                context.drawLayer { layer in
                    layer.clip(to:Path(CGRect(origin:screen(clip.origin),size:CGSize(width:clip.width*scale,height:clip.height*scale))))
                    layer.stroke(path,with:.color(palette.ink.opacity(palette.nightVision ? 0.17 : 0.14)),style:StrokeStyle(lineWidth:0.6,lineJoin:.round))
                }
            }
            // The 63 parks: the sky's faint background.
            for park in parks {
                let p=screen(SkyMap.position(park))
                guard p.x > -4, p.y > -4, p.x<size.width+4, p.y<size.height+4 else { continue }
                let r=0.9*zoom
                context.fill(Path(ellipseIn:CGRect(x:p.x-r,y:p.y-r,width:2*r,height:2*r)),with:.color(palette.ink.opacity(0.28)))
            }
            // Figures, one after another, each edge growing from its first star.
            let count=max(1,content.figures.count)
            for (index,figure) in content.figures.enumerated() where !figure.isEmpty {
                let local=min(1,max(0,progress*Double(count)-Double(index)))
                guard local>0 else { continue }
                var path=Path()
                for (e,edge) in figure.enumerated() {
                    let t=min(1,max(0,local*Double(figure.count)-Double(e)))
                    guard t>0 else { break }
                    let a=screen(edge.0), b=screen(edge.1)
                    path.move(to:a); path.addLine(to:CGPoint(x:a.x+(b.x-a.x)*t,y:a.y+(b.y-a.y)*t))
                }
                context.stroke(path,with:.color(palette.ink.opacity(0.5)),style:StrokeStyle(lineWidth:0.8,lineCap:.round))
            }
            // Your stars: a soft halo and a bright core, brighter for darker nights.
            for star in content.stars {
                let p=screen(star.point), b=star.brightness
                let core=1.2+2.6*b, halo=core*3.2
                context.drawLayer { glow in
                    glow.addFilter(.blur(radius:halo/2.4))
                    glow.fill(Path(ellipseIn:CGRect(x:p.x-halo/2,y:p.y-halo/2,width:halo,height:halo)),with:.color(palette.accent.opacity(0.35+0.4*b)))
                }
                context.fill(Path(ellipseIn:CGRect(x:p.x-core/2,y:p.y-core/2,width:core,height:core)),with:.color(palette.ink.opacity(0.55+0.45*b)))
                if star.ringed {
                    context.stroke(Path(ellipseIn:CGRect(x:p.x-9,y:p.y-9,width:18,height:18)),with:.color(palette.accent.opacity(0.8)),lineWidth:0.9)
                }
            }
        }
        .accessibilityIgnoresInvertColors()
    }
}
/// The sky map with motion and touch: figures draw themselves once on appear (static under
/// Reduce Motion), and each star is a 44-point button for touch and for VoiceOver.
struct SkyMapView: View {
    @Environment(PlanModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.nyxReduceMotion) private var forcedReduceMotion
    let content: SkyMapContent
    var summary: String
    var onSelect: ((String)->Void)? = nil
    @State private var started: Date?
    @State private var done=false
    private var reduceMotion: Bool { systemReduceMotion || forcedReduceMotion }
    /// About a second per figure, at most four seconds in all.
    private var duration: Double { min(4,0.4+1.1*Double(content.figures.count)) }
    var body: some View {
        TimelineView(.animation(minimumInterval:1/60,paused:reduceMotion || done || started == nil)) { timeline in
            let elapsed=started.map { timeline.date.timeIntervalSince($0) } ?? 0
            // Ease out, like a pen slowing as it reaches the last star.
            let t=reduceMotion || content.figures.isEmpty ? 1 : 1-pow(1-min(1,elapsed/duration),3)
            // Drawn text (the insets' names) is decoration; the stars below and the summary speak.
            SkyMapCanvas(content:content,progress:t,parks:model.parks).accessibilityHidden(true)
        }
        .aspectRatio(1/SkyMap.aspect,contentMode:.fit)
        .overlay { if let onSelect { GeometryReader { proxy in hitTargets(size:proxy.size,onSelect:onSelect) } } }
        .accessibilityElement(children:onSelect == nil ? .ignore : .contain)
        .accessibilityLabel(summary)
        .task(id:content.figures.count) {
            started=Date.now; done=false
            try? await Task.sleep(for:.seconds(duration+0.1))
            if !Task.isCancelled { done=true }
        }
    }
    private func hitTargets(size:CGSize,onSelect:@escaping (String)->Void)->some View {
        let view=content.viewport, scale=min(size.width/view.width,size.height/view.height)
        let dx=(size.width-view.width*scale)/2, dy=(size.height-view.height*scale)/2
        return ForEach(content.stars) { star in
            Button { onSelect(star.id) } label:{ Color.clear.frame(width:44,height:44).contentShape(Circle()) }
                .buttonStyle(.plain)
                .position(x:dx+(star.point.x-view.minX)*scale,y:dy+(star.point.y-view.minY)*scale)
                .accessibilityLabel(star.label)
        }
    }
}
#Preview("Sky map • parks only") { SkyMapView(content:SkyMapContent(stars:[],figures:[]),summary:"").padding().background(.black).environment(PlanModel()) }
