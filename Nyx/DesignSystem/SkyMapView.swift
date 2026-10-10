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
/// A star arriving: a night just recorded. Its season's new edge grows toward it, then its core
/// grows from nothing on the shared spring while its halo blooms to about 1.8× and settles. Pure
/// functions of the arrival's progress (0…1 over `duration`), so a held frame draws exactly what
/// the motion passes through, and progress 1 is the star as every other star is drawn.
nonisolated enum StarArrival {
    /// After the save, so the editor's sheet has dropped before the star appears.
    static let delay=0.35
    static let duration=1.6
    /// The new edge reaches the star at 0.5 s, as its core begins.
    static let edgeTime=0.5, coreStart=0.45
    static func seconds(_ progress: Double) -> Double { min(1,max(0,progress))*duration }
    /// How far the new edge has grown, 0…1, easing out as a pen does reaching a star.
    static func edge(_ progress: Double) -> Double {
        guard progress<1 else { return 1 }
        return 1-pow(1-min(1,seconds(progress)/edgeTime),3)
    }
    private static func spring(_ time: Double) -> Double { time<=0 ? 0 : NyxMotion.model.value(target:1.0,time:time) }
    /// The core's size, as a share of its settled size.
    static func core(_ progress: Double) -> Double {
        guard progress<1 else { return 1 }
        return max(0,spring(seconds(progress)-coreStart))
    }
    /// The halo's size, as a share of its settled size: it grows with the core, blooms to about
    /// 1.8× and settles as a second spring, a beat behind, lets it go.
    static func halo(_ progress: Double) -> Double {
        guard progress<1 else { return 1 }
        let t=seconds(progress)-coreStart
        return max(0,spring(t)*(2-spring(t-0.3)))
    }
}
/// The sky map, drawn in Canvas. `progress` runs 0…1 across all figures, in order.
struct SkyMapCanvas: View {
    @Environment(\.nyx) private var palette
    /// The insets' names grow with the reader's text size, to the size their frames can hold.
    @ScaledMetric(relativeTo:.caption2) private var insetNameSize=9.0
    let content: SkyMapContent
    var progress: Double = 1
    /// Every park, as faint background stars.
    var parks: [Park]
    /// The star arriving (a night just recorded) and how far its arrival has got (`StarArrival`).
    var arriving: String? = nil
    var arrival: Double = 1
    var body: some View {
        Canvas { context,size in
            let view=content.viewport
            let scale=min(size.width/view.width,size.height/view.height)
            let dx=(size.width-view.width*scale)/2, dy=(size.height-view.height*scale)/2
            func screen(_ p:CGPoint)->CGPoint { CGPoint(x:dx+(p.x-view.minX)*scale,y:dy+(p.y-view.minY)*scale) }
            let zoom=min(3,max(1,1/view.width))
            // The arriving star's place: only the edges that reach it grow in, and it grows itself.
            let newcomer=arriving.flatMap { id in content.stars.first { $0.id==id } }.map(\.point)
            // The insets' quiet frames, only on the whole map (their names are drawn last, above everything).
            var boxes:[SkyMap.Region:CGRect]=[:]
            if content.showsInsets && view.width>0.9 {
                for inset in SkyMap.insets.dropFirst() {
                    let rect=CGRect(origin:screen(inset.frame.origin),size:CGSize(width:inset.frame.width*scale,height:inset.frame.height*scale)).insetBy(dx:-3,dy:-3)
                    boxes[inset.region]=rect
                    context.stroke(Path(roundedRect:rect,cornerRadius:4),with:.color(palette.line.opacity(0.7)),style:StrokeStyle(lineWidth:0.5,dash:[2,3]))
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
                    var a=screen(edge.0), b=screen(edge.1), grown=t
                    // An edge to the arriving star grows from its other end toward it.
                    if let newcomer, edge.0==newcomer || edge.1==newcomer {
                        if edge.0==newcomer { swap(&a,&b) }
                        grown=StarArrival.edge(arrival)
                        guard grown>0 else { continue }
                    }
                    path.move(to:a); path.addLine(to:CGPoint(x:a.x+(b.x-a.x)*grown,y:a.y+(b.y-a.y)*grown))
                }
                context.stroke(path,with:.color(palette.ink.opacity(0.5)),style:StrokeStyle(lineWidth:0.8,lineCap:.round))
            }
            // Your stars: a soft halo and a bright core, brighter for darker nights.
            for star in content.stars {
                let p=screen(star.point), b=star.brightness
                let born=star.id==arriving ? StarArrival.core(arrival) : 1
                guard born>0.001 else { continue }
                let core=(1.2+2.6*b)*born, halo=(1.2+2.6*b)*3.2*(star.id==arriving ? StarArrival.halo(arrival) : 1)
                context.drawLayer { kept in
                    // A star in an inset keeps its halo inside the inset's frame, clear of the names beneath.
                    if let box=boxes[SkyMap.region(at:star.point)] { kept.clipToLayer { mask in TonightMapCanvas.softBox(&mask,box) } }
                    kept.drawLayer { glow in
                        glow.addFilter(.blur(radius:halo/2.4))
                        glow.fill(Path(ellipseIn:CGRect(x:p.x-halo/2,y:p.y-halo/2,width:halo,height:halo)),with:.color(palette.accent.opacity(0.35+0.4*b)))
                    }
                }
                context.fill(Path(ellipseIn:CGRect(x:p.x-core/2,y:p.y-core/2,width:core,height:core)),with:.color(palette.ink.opacity(0.55+0.45*b)))
                if star.ringed {
                    context.stroke(Path(ellipseIn:CGRect(x:p.x-9,y:p.y-9,width:18,height:18)),with:.color(palette.accent.opacity(0.8)),lineWidth:0.9)
                }
            }
            // The insets' names under their frames, on one baseline, above the stars and figures. Each
            // steps down a point at a time (to 9 pt) until it fits its room before the next frame and
            // a line fits the band under the insets, so names never collide and descenders never clip.
            let band=(SkyMap.aspect-SkyMap.insetBottom)*scale-4, nameTint=palette.muted.opacity(0.85)
            for room in SkyMap.nameRooms(width:scale) {
                guard let rect=boxes[room.region] else { continue }
                let label=SkyMap.inset(room.region).name
                func resolved(_ points:Double)->GraphicsContext.ResolvedText {
                    context.resolve(Text(label).font(.system(size:points,weight:.medium)).foregroundStyle(nameTint))
                }
                var points=min(15,insetNameSize), name=resolved(points), measured=name.measure(in:size)
                while points>9, measured.width>room.room || measured.height>band {
                    points=max(9,points-1); name=resolved(points); measured=name.measure(in:size)
                }
                // Inside its room: the last name ("I. Vírgenes") ends at the right edge instead of past it.
                let end=room.atEdge ? size.width-1 : dx+room.minX+room.room
                let x=max(dx+room.minX,min(dx+room.x,end-measured.width))
                context.draw(name,at:CGPoint(x:max(1,x),y:rect.maxY+2),anchor:.topLeading)
            }
        }
        .accessibilityIgnoresInvertColors()
    }
}
/// The sky map with motion and touch: figures draw themselves on appear (static under Reduce
/// Motion), a night just recorded arrives as a star, and each star is a 44-point button for touch
/// and for VoiceOver.
struct SkyMapView: View {
    @Environment(PlanModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.nyxReduceMotion) private var forcedReduceMotion
    @Environment(\.nyxAccess) private var access
    let content: SkyMapContent
    var summary: String
    /// The star arriving: a night just recorded (`ConstellationArrivals`). Held unborn until the
    /// arrival plays; nil draws every star as it is.
    var arriving: String? = nil
    /// DEBUG captures and previews: the arrival held at this progress, 0…1.
    var arrivalHold: Double? = nil
    /// True while the map is out of sight (another tab, field mode over it): the arrival waits.
    var arrivalPaused = false
    /// With a key, the figures draw themselves once per launch and again only when a figure or an
    /// edge is added, not on every appear. Without one, on every appear, as the trip and the recap do.
    var drawInMemory: String? = nil
    var onSelect: ((String)->Void)? = nil
    /// The arrival has landed (or, under Reduce Motion, the star is drawn whole).
    var onArrived: ((String)->Void)? = nil
    @State private var started: Date?
    @State private var done=false
    @State private var arrivalStart: Date?
    @State private var arrivedID: String?
    private var reduceMotion: Bool { systemReduceMotion || forcedReduceMotion }
    /// Reduce Motion and Reduce Highlighting draw an arriving star whole.
    private var stillArrival: Bool { reduceMotion || access.reduceHighlighting }
    /// About a second per figure, at most four seconds in all.
    private var duration: Double { min(4,0.4+1.1*Double(content.figures.count)) }
    private var signature: SkyMapDrawIns.Signature { SkyMapDrawIns.Signature(figures:content.figures.count,edges:content.figures.reduce(0) { $0+$1.count }) }
    private var drawKey: String { drawInMemory == nil ? "\(content.figures.count)" : "\(signature.figures)-\(signature.edges)" }
    private var arrivalRunning: Bool { arriving != nil && arrivalHold == nil && arrivalStart != nil && arrivedID != arriving }
    var body: some View {
        TimelineView(.animation(minimumInterval:1/60,paused:reduceMotion ? !arrivalRunning : ((done || started == nil) && !arrivalRunning))) { timeline in
            let elapsed=started.map { timeline.date.timeIntervalSince($0) } ?? 0
            // Already drawn this launch (or a star arriving into figures already drawn): no pen at all.
            let drawn=started == nil && (arriving != nil || drawInMemory.map { !signature.grows(from:SkyMapDrawIns.drawn[$0]) } == true)
            // Ease out, like a pen slowing as it reaches the last star.
            let t=reduceMotion || content.figures.isEmpty || drawn ? 1 : 1-pow(1-min(1,elapsed/duration),3)
            // Drawn text (the insets' names) is decoration; the stars below and the summary speak.
            SkyMapCanvas(content:content,progress:t,parks:model.parks,arriving:arriving,arrival:arrivalProgress(at:timeline.date)).accessibilityHidden(true)
        }
        .aspectRatio(1/SkyMap.aspect,contentMode:.fit)
        .overlay { if let onSelect { GeometryReader { proxy in hitTargets(size:proxy.size,onSelect:onSelect) } } }
        .accessibilityElement(children:onSelect == nil ? .ignore : .contain)
        .accessibilityLabel(summary)
        .task(id:drawKey) {
            let signature=signature
            if let drawInMemory {
                let before=SkyMapDrawIns.drawn[drawInMemory]
                SkyMapDrawIns.drawn[drawInMemory]=signature
                // A star arriving brings only its own edge; figures already drawn stay drawn.
                guard arriving == nil, signature.grows(from:before) else { started=nil; done=true; return }
            }
            started=Date.now; done=false
            try? await Task.sleep(for:.seconds(duration+0.1))
            if !Task.isCancelled { done=true }
        }
        .task(id:ArrivalKey(id:arriving,paused:arrivalPaused)) {
            guard let id=arriving, arrivalHold == nil, arrivedID != id else { return }
            arrivalStart=nil
            guard !arrivalPaused else { return }
            try? await Task.sleep(for:.seconds(StarArrival.delay))
            guard !Task.isCancelled else { return }
            if !stillArrival {
                arrivalStart=Date.now
                try? await Task.sleep(for:.seconds(StarArrival.duration))
                guard !Task.isCancelled else { arrivalStart=nil; return }
            }
            arrivedID=id
            onArrived?(id)
        }
    }
    /// How far the arriving star has got, 0…1 (1 when there is none).
    private func arrivalProgress(at date: Date) -> Double {
        guard let arriving else { return 1 }
        if let arrivalHold { return min(1,max(0,arrivalHold)) }
        if arrivedID == arriving || stillArrival { return 1 }
        guard let arrivalStart else { return 0 }
        return min(1,max(0,date.timeIntervalSince(arrivalStart)/StarArrival.duration))
    }
    private struct ArrivalKey: Equatable { let id: String?; let paused: Bool }
    private func hitTargets(size:CGSize,onSelect:@escaping (String)->Void)->some View {
        let view=content.viewport, scale=min(size.width/view.width,size.height/view.height)
        let dx=(size.width-view.width*scale)/2, dy=(size.height-view.height*scale)/2
        // West to east, so VoiceOver crosses the country as a reader would cross the map.
        return ForEach(SkyMapView.geographic(content.stars)) { star in
            Button { onSelect(star.id) } label:{ Color.clear.frame(width:44,height:44).contentShape(Circle()) }
                .buttonStyle(.plain)
                .position(x:dx+(star.point.x-view.minX)*scale,y:dy+(star.point.y-view.minY)*scale)
                .accessibilityLabel(star.label)
        }
    }
}
extension SkyMapView {
    /// Stars in map order, west to east (north to south where they share a meridian).
    nonisolated static func geographic(_ stars:[SkyMapContent.Star])->[SkyMapContent.Star] {
        stars.sorted { abs($0.point.x-$1.point.x)>0.002 ? $0.point.x<$1.point.x : $0.point.y<$1.point.y }
    }
}
/// The figure draw-ins seen this launch, by `SkyMapView.drawInMemory`: in memory only, empty at
/// every launch, so the journal's figures draw themselves once and not on every visit.
@MainActor enum SkyMapDrawIns {
    static var drawn: [String: Signature]=[:]
    nonisolated struct Signature: Equatable, Sendable {
        let figures: Int
        let edges: Int
        /// A figure or an edge more than last time (or never drawn): the pen draws again.
        func grows(from old: Signature?) -> Bool { old.map { figures>$0.figures || edges>$0.edges } ?? true }
    }
}
#Preview("Sky map • parks only") { SkyMapView(content:SkyMapContent(stars:[],figures:[]),summary:"").padding().background(.black).environment(PlanModel()) }
#if DEBUG
/// A lived-in constellation with its newest night arriving, held at `arrival`.
private struct ArrivalPreview: View {
    let arrival: Double
    var nightVision=false
    @State private var model=PlanModel()
    var body: some View {
        let nights=DebugJournal.nights()
        let layout=ConstellationLayout(nights:nights,parks:model.parks)
        let newest=nights.max { $0.date<$1.date }?.id.uuidString
        let palette=NyxPalette(nightVision:nightVision,highContrast:false)
        SkyMapCanvas(content:layout.content(parks:model.parks),parks:model.parks,arriving:newest,arrival:arrival)
            .aspectRatio(1/SkyMap.aspect,contentMode:.fit).padding().background(.black)
            .environment(\.nyx,palette).modifier(NightVisionFilter(enabled:nightVision,red:palette.red))
    }
}
#Preview("Star arriving • 0") { ArrivalPreview(arrival:0) }
#Preview("Star arriving • 0.5") { ArrivalPreview(arrival:0.5) }
#Preview("Star arriving • 1") { ArrivalPreview(arrival:1) }
#Preview("Star arriving • night vision") { ArrivalPreview(arrival:0.4,nightVision:true) }
#endif
