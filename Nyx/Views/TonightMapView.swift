import SwiftUI

/// The 63 parks on one map, tonight: the "where" answer in one picture. Drawn in Canvas over the
/// bundled US outline (no MapKit, so no request leaves the device). Each park is its night cell's
/// mark: larger and brighter for a higher score; filled, half-filled or hollow for what its clouds
/// rest on; a small triangle beside a park with a closure. The names (the darkest few, and any park
/// a pointer or VoiceOver rests on) are text laid over the drawing by `TonightMapView`.
struct TonightMapCanvas: View {
    @Environment(\.nyx) private var palette
    @Environment(\.nyxAccess) private var access
    let map: TonightMap
    /// 0…1: marks light up from west to east once on appear (1 at once under Reduce Motion).
    var progress: Double = 1
    /// The park named because a pointer rests on it or VoiceOver is on it.
    var highlighted: String?
    var body: some View {
        Canvas { context,size in
            let view=CGRect(x:0,y:0,width:1,height:SkyMap.aspect)
            let scale=min(size.width/view.width,size.height/view.height)
            let dx=(size.width-view.width*scale)/2, dy=(size.height-view.height*scale)/2
            func screen(_ p:CGPoint)->CGPoint { CGPoint(x:dx+p.x*scale,y:dy+p.y*scale) }
            // Room for bigger marks on a wide iPad, never smaller than a phone's.
            let size1=max(1,min(1.8,size.width/360))
            // The insets' quiet frames (their names are text over the map: `TonightMapLabels`).
            for inset in SkyMap.insets.dropFirst() {
                let rect=CGRect(origin:screen(inset.frame.origin),size:CGSize(width:inset.frame.width*scale,height:inset.frame.height*scale)).insetBy(dx:-3,dy:-3)
                context.stroke(Path(roundedRect:rect,cornerRadius:4),with:.color(palette.line.opacity(0.8)),style:StrokeStyle(lineWidth:0.5,dash:[2,3]))
            }
            // The country, faint: coasts and borders so the marks read as places.
            for outline in SkyMap.outlines {
                var path=Path()
                for ring in outline.rings { path.addLines(ring.map(screen)); path.closeSubpath() }
                let clip=outline.clip
                context.drawLayer { layer in
                    layer.clip(to:Path(CGRect(origin:screen(clip.origin),size:CGSize(width:clip.width*scale,height:clip.height*scale))))
                    layer.fill(path,with:.color(palette.ink.opacity(palette.nightVision ? 0.05 : 0.035)))
                    layer.stroke(path,with:.color(palette.ink.opacity(palette.highContrast ? 0.4 : palette.nightVision ? 0.22 : 0.18)),style:StrokeStyle(lineWidth:0.6,lineJoin:.round))
                }
            }
            // Dimmer nights first, so the darkest skies sit on top where parks crowd together.
            let count=Double(max(1,map.marks.count))
            let order=Dictionary(map.marks.enumerated().map { ($1.id,Double($0)) },uniquingKeysWith:{ a,_ in a })
            for mark in map.marks.sorted(by:{ $0.score<$1.score }) {
                // West to east, each mark fading in over a fifth of the reveal.
                let start=(order[mark.id] ?? 0)/count*0.8
                let shown=min(1,max(0,(progress-start)/0.2))
                guard shown>0 else { continue }
                let p=screen(mark.point), radius=mark.radius*size1
                var layer=context
                layer.opacity=shown
                // A soft glow for Excellent and Pristine nights: a dark sky glows a little.
                if mark.score>=75 && !palette.nightVision {
                    let halo=radius*3
                    layer.drawLayer { glow in
                        glow.addFilter(.blur(radius:halo/2.6))
                        glow.fill(Path(ellipseIn:CGRect(x:p.x-halo/2,y:p.y-halo/2,width:halo,height:halo)),with:.color(palette.accent.opacity(0.35*access.glow)))
                    }
                }
                let shape=NightMark.mark(score:mark.score,hasForecast:mark.fill == .full,differentiate:access.differentiate)
                shape.draw(in:&layer,center:p,radius:radius,fill:mark.fill,color:palette.accent,fillOpacity:mark.fillOpacity,lineWidth:1,hollowBackground:palette.panel)
                if mark.closure != nil { layer.stroke(Self.triangle(at:CGPoint(x:p.x+radius*0.8+4,y:p.y-radius*0.8-2),size:6),with:.color(palette.ink),lineWidth:1.1) }
                if mark.id==highlighted {
                    let ring=radius+5
                    layer.stroke(Path(ellipseIn:CGRect(x:p.x-ring,y:p.y-ring,width:2*ring,height:2*ring)),with:.color(palette.ink.opacity(0.9)),lineWidth:1)
                }
            }
        }
        .accessibilityIgnoresInvertColors()
    }
    /// The closure mark: a small hollow warning triangle, the shape of the alert symbol beside every score.
    static func triangle(at center:CGPoint,size:Double)->Path {
        var path=Path()
        path.move(to:CGPoint(x:center.x,y:center.y-size/2))
        path.addLine(to:CGPoint(x:center.x+size/2,y:center.y+size/2))
        path.addLine(to:CGPoint(x:center.x-size/2,y:center.y+size/2))
        path.closeSubpath()
        return path
    }
}

/// The map with touch, pointer and VoiceOver. A tap opens the nearest park within reach of the
/// finger (parks in Utah sit a few points apart, so overlapping buttons would guess); VoiceOver
/// reads the parks as a container in geographic order, with a "Darkest tonight" rotor.
struct TonightMapView: View {
    @Environment(\.nyx) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.nyxReduceMotion) private var forcedReduceMotion
    let map: TonightMap
    let open: (String)->Void
    @State private var hovered: String?
    @AccessibilityFocusState private var focused: String?
    @State private var started: Date?
    @State private var done=false
    /// The insets' names, a step below caption2 (9 points at the default size).
    @ScaledMetric(relativeTo:.caption2) private var insetType=9.0
    @Namespace private var rotor
    private var reduceMotion: Bool { systemReduceMotion || forcedReduceMotion }
    private static let reveal=1.2
    var body: some View {
        drawing
            .aspectRatio(1/SkyMap.aspect,contentMode:.fit)
            .overlay { GeometryReader { proxy in interaction(size:proxy.size) } }
            .accessibilityElement(children:.contain)
            .accessibilityLabel(map.summary)
            .accessibilityRotor("Darkest tonight") { ForEach(map.darkest) { mark in AccessibilityRotorEntry(Text(mark.label),id:mark.id,in:rotor) } }
            .task { await reveal() }
    }
    private var drawing: some View {
        TimelineView(.animation(minimumInterval:1/60,paused:reduceMotion || done || started == nil)) { timeline in
            TonightMapCanvas(map:map,progress:progress(at:timeline.date),highlighted:focused ?? hovered).accessibilityHidden(true)
        }
    }
    /// Ease out over the reveal, like lights coming on across the country.
    private func progress(at date:Date)->Double {
        guard !reduceMotion, let started else { return reduceMotion ? 1 : 0 }
        let t=min(1,date.timeIntervalSince(started)/Self.reveal)
        return 1-pow(1-t,3)
    }
    private func reveal() async {
        started=Date.now; done=false
        try? await Task.sleep(for:.milliseconds(1300))
        if !Task.isCancelled { done=true }
    }
    private func interaction(size:CGSize)->some View {
        ZStack {
            Color.clear.contentShape(Rectangle())
                .gesture(SpatialTapGesture().onEnded { value in if let id=nearest(value.location,size:size) { open(id) } })
                .onContinuousHover { phase in hover(phase,size:size) }
            TonightMapLabels {
                // At accessibility sizes the map keeps its marks and the words move to the list below it,
                // where they can be as large as they need to be.
                if !typeSize.isAccessibilitySize {
                    insetNames(size:size)
                    tags(size:size)
                }
                regions(size:size)
                elements(size:size)
            }.accessibilityIgnoresInvertColors()
        }
    }
    /// The names on the map are a glance: the darkest three (and a park a pointer or VoiceOver rests
    /// on), each on a dark plate so it reads over coastlines and other marks. Each lies inside its
    /// park's element, which speaks it.
    private func tags(size:CGSize)->some View {
        let fixed=map.labelled()
        let extra=(focused ?? hovered).flatMap { id in fixed.contains { $0.id==id } ? nil : map.marks.first { $0.id==id } }
        let size1=max(1,min(1.8,size.width/360))
        // The darkest three first, so a name shown for a pointer or VoiceOver never moves them.
        return ForEach(fixed+(extra.map { [$0] } ?? [])) { mark in
            Text("\(mark.name) \(mark.score)").font(.caption2.weight(.semibold)).foregroundStyle(palette.ink)
                // The plate reaches past the words, fills its corners and starts clear of the mark (the gap below),
                // so nothing bright shows beside the words.
                .background(RoundedRectangle(cornerRadius:4,style:.continuous).fill(Color.black.opacity(0.9)).padding(.horizontal,-TonightMapLabels.plate.width).padding(.vertical,-TonightMapLabels.plate.height))
                .opacity(namesShown ? 1 : 0)
                .accessibilityHidden(true)
                .layoutValue(key:TonightMapLabels.Key.self,value:.tag(id:mark.id,point:point(mark,size:size),gap:mark.radius*size1+4+TonightMapLabels.plate.width,holds:fixed.contains { $0.id==mark.id }))
        }
    }
    /// Each inset's name under its dashed frame. Its region's element speaks it in full.
    private func insetNames(size:CGSize)->some View {
        ForEach(SkyMap.insets.dropFirst(),id:\.region) { inset in
            Text(inset.name).font(.system(size:insetType,weight:.medium)).foregroundStyle(palette.muted)
                .accessibilityHidden(true)
                .layoutValue(key:TonightMapLabels.Key.self,value:.inset(region:inset.region,frame:frame(inset,size:size)))
        }
    }
    /// One static element for each inset (its frame and its name), read just before its parks.
    private func regions(size:CGSize)->some View {
        let count=map.marks.count
        return ForEach(SkyMap.insets.dropFirst(),id:\.region) { inset in
            let first=map.marks.firstIndex { $0.region==inset.region } ?? count
            Color.clear
                .layoutValue(key:TonightMapLabels.Key.self,value:.region(inset.region,frame:frame(inset,size:size)))
                .accessibilityElement()
                .accessibilityLabel(inset.spokenName)
                .accessibilityAddTraits(.isStaticText)
                .accessibilitySortPriority(Double(count-first)+0.5)
        }
    }
    /// An inset's dashed frame, as the drawing strokes it.
    private func frame(_ inset:SkyMap.Inset,size:CGSize)->CGRect {
        let l=layout(size)
        return CGRect(x:l.dx+inset.frame.minX*l.scale,y:l.dy+inset.frame.minY*l.scale,width:inset.frame.width*l.scale,height:inset.frame.height*l.scale).insetBy(dx:-3,dy:-3)
    }
    /// Names appear once every mark has lit (at once under Reduce Motion).
    private var namesShown: Bool { reduceMotion || done }
    private func hover(_ phase:HoverPhase,size:CGSize) {
        switch phase {
        case .active(let location): hovered=nearest(location,size:size)
        case .ended: hovered=nil
        }
    }
    private func layout(_ size:CGSize)->(scale:Double,dx:Double,dy:Double) {
        let scale=min(size.width,size.height/SkyMap.aspect)
        return (scale,(size.width-scale)/2,(size.height-SkyMap.aspect*scale)/2)
    }
    private func point(_ mark:TonightMap.Mark,size:CGSize)->CGPoint {
        let l=layout(size)
        return CGPoint(x:l.dx+mark.point.x*l.scale,y:l.dy+mark.point.y*l.scale)
    }
    /// The park nearest a touch, within 26 points (a 44-point target's reach, with a little slack).
    private func nearest(_ location:CGPoint,size:CGSize)->String? {
        var best:(id:String,distance:Double)?
        for mark in map.marks {
            let p=point(mark,size:size)
            let distance=hypot(p.x-location.x,p.y-location.y)
            if distance<=26, distance<(best?.distance ?? .infinity) { best=(mark.id,distance) }
        }
        return best?.id
    }
    /// One VoiceOver element per park at its place (44 points, and its name tag when it has one), in
    /// geographic order (the sort priority keeps SwiftUI from reordering them by position). Clear and
    /// without a content shape, so touches fall through to the tap above.
    private func elements(size:CGSize)->some View {
        let count=map.marks.count
        return ForEach(Array(map.marks.enumerated()),id:\.element.id) { index,mark in
            Color.clear
                .layoutValue(key:TonightMapLabels.Key.self,value:.element(id:mark.id,point:point(mark,size:size)))
                .accessibilityElement()
                .accessibilityLabel(mark.label)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Opens the park.")
                .accessibilityAction { open(mark.id) }
                .accessibilitySortPriority(Double(count-index))
                .accessibilityFocused($focused,equals:mark.id)
                .accessibilityRotorEntry(id:mark.id,in:rotor)
        }
    }
}

/// Lays the map's words and VoiceOver elements over the drawing (in its coordinates): each name tag
/// on the first side of its mark (right, left, above, below) where it stays on the map and overlaps
/// no earlier tag; each inset's name under its frame, kept on the map; each park's element over its
/// mark and the tag that names it, so the words on screen belong to the element that speaks them.
struct TonightMapLabels: Layout {
    enum Spot: Sendable {
        /// `holds`: the park's element grows to cover the tag (the darkest few, never a passing name).
        case tag(id:String,point:CGPoint,gap:Double,holds:Bool)
        /// An inset's name, under its frame.
        case inset(region:SkyMap.Region,frame:CGRect)
        /// An inset's element: its frame and its name.
        case region(SkyMap.Region,frame:CGRect)
        case element(id:String,point:CGPoint)
    }
    struct Key: LayoutValueKey { static let defaultValue: Spot? = nil }
    /// The dark plate's margin around a name.
    static let plate=CGSize(width:4,height:1.5)
    func sizeThatFits(proposal:ProposedViewSize,subviews:Subviews,cache:inout ())->CGSize { proposal.replacingUnspecifiedDimensions() }
    func placeSubviews(in bounds:CGRect,proposal:ProposedViewSize,subviews:Subviews,cache:inout ()) {
        let area=CGRect(origin:.zero,size:bounds.size).insetBy(dx:2,dy:2)
        var taken:[CGRect]=[], held:[String:CGRect]=[:], names:[SkyMap.Region:CGRect]=[:]
        func put(_ subview:LayoutSubview,_ rect:CGRect) { subview.place(at:CGPoint(x:bounds.minX+rect.minX,y:bounds.minY+rect.minY),proposal:ProposedViewSize(rect.size)) }
        for subview in subviews {
            switch subview[Key.self] {
            case .tag(let id,let point,let gap,let holds):
                let text=subview.sizeThatFits(.unspecified)
                let rect=CGRect(origin:Self.origin(text:text,beside:point,gap:gap,in:area,avoiding:taken),size:text)
                let plated=rect.insetBy(dx:-Self.plate.width,dy:-Self.plate.height)
                taken.append(plated)
                if holds { held[id]=plated }
                put(subview,rect)
            case .inset(let region,let frame):
                let size=subview.sizeThatFits(.unspecified)
                let rect=CGRect(origin:CGPoint(x:max(1,min(frame.minX+1,bounds.width-size.width-1)),y:frame.maxY+2),size:size)
                names[region]=rect
                put(subview,rect)
            default: break
            }
        }
        for subview in subviews {
            switch subview[Key.self] {
            case .region(let region,let frame): put(subview,names[region].map { frame.union($0) } ?? frame)
            case .element(let id,let point):
                let mark=CGRect(x:point.x-22,y:point.y-22,width:44,height:44)
                put(subview,held[id].map { mark.union($0) } ?? mark)
            default: break
            }
        }
    }
    /// Where a name of this size goes beside a mark: the first side that stays inside `area` and
    /// clear of every name already placed, or the right-hand side when none does.
    static func origin(text:CGSize,beside p:CGPoint,gap:Double,in area:CGRect,avoiding taken:[CGRect])->CGPoint {
        let options=[CGPoint(x:p.x+gap,y:p.y-text.height/2),CGPoint(x:p.x-gap-text.width,y:p.y-text.height/2),
                     CGPoint(x:p.x-text.width/2,y:p.y-gap-text.height),CGPoint(x:p.x-text.width/2,y:p.y+gap)]
        return options.first { o in
            let r=CGRect(origin:o,size:text).insetBy(dx:-3,dy:-1)
            return area.contains(r) && !taken.contains { $0.intersects(r) }
        } ?? options[0]
    }
}

/// Parks as a map: the picture, what its marks mean, and the darkest few as rows that work at
/// every text size. `open` pushes the park, exactly as a row of the list does.
struct ParksMapView: View {
    @Environment(PlanModel.self) private var model
    @Environment(\.nyx) private var palette
    @Environment(\.nyxAccess) private var access
    @Environment(\.dynamicTypeSize) private var typeSize
    let open: (Park)->Void
    var body: some View {
        let map=TonightMap(nights:model.parks.map { model.night($0) },closures:closures)
        ScrollView {
            VStack(alignment:.leading,spacing:18) {
                if let home=model.home { Eyebrow(text:"\(home.dayLabel(model.tonight(home))) · \(map.marks.count) parks tonight") }
                TonightMapView(map:map) { id in if let park=model.park(id) { open(park) } }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius:24).fill(palette.panel))
                    .overlay(RoundedRectangle(cornerRadius:24).stroke(palette.line,lineWidth:0.5))
                // What the marks mean, under the picture it explains (and clear of the tab bar's fade at rest). At
                // accessibility sizes it runs long, so the answer comes first and the legend follows the list.
                if !typeSize.isAccessibilitySize { legend }
                Eyebrow(text:"Darkest tonight")
                VStack(spacing:0) {
                    ForEach(Array(map.darkest.prefix(5))) { mark in
                        if let park=model.park(mark.id) {
                            // A real button around real text, so its words wrap and are measured as they read; it speaks the map's label.
                            Button { open(park) } label:{ row(mark,park:park) }.buttonStyle(.plain).hoverEffect(.highlight).draggable(park)
                                .accessibilityLabel(mark.label)
                            Divider().overlay(palette.line)
                        }
                    }
                }
                if typeSize.isAccessibilitySize { legend }
                Text("Each park uses its own local date. Scores without a full forecast can change when one arrives.").font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
            }.padding(24).readableColumn(1100)
        }
        .background(NightBackground()).navigationTitle("Parks").navigationBarTitleDisplayMode(.inline)
        // Clouds for all 63 parks in one request, and the one bulk alerts request for the closure marks.
        .task { await model.refresh(model.parks) }
        .refreshable { await model.refresh(model.parks,force:true) }
    }
    private var closures:[String:String] {
        Dictionary(model.parks.compactMap { park in model.closure(park).map { (park.id,$0) } },uniquingKeysWith:{ a,_ in a })
    }
    /// What the marks mean, in words beside small drawn examples.
    private var legend: some View {
        let items:[(LegendGlyph.Kind,LocalizedStringKey)]=[(.sizes,"Larger and brighter: a darker night"),(.fills,"Filled: forecast. Half: early look. Hollow: usual clouds"),(.closure,"Closure in the last park update")]
        return VStack(alignment:.leading,spacing:10) {
            ForEach(Array(items.enumerated()),id:\.offset) { _,item in
                HStack(alignment:.top,spacing:12) {
                    if !typeSize.isAccessibilitySize { LegendGlyph(kind:item.0).frame(width:46,height:18) }
                    Text(item.1).font(.footnote).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
                }
            }
        }.accessibilityElement(children:.combine)
    }
    /// Score, name and line beside each other; at accessibility sizes the score sits above the words,
    /// so a long name keeps the row's full width.
    private func row(_ mark:TonightMap.Mark,park:Park)->some View {
        let score=Text("\(mark.score)").font(.system(.title2,design:.serif).monospacedDigit()).foregroundStyle(palette.accent)
        let chevron=Image(systemName:"chevron.forward").font(.caption.weight(.semibold)).foregroundStyle(palette.muted).accessibilityHidden(true)
        let words=VStack(alignment:.leading,spacing:3) {
            Text(park.shortName).font(.system(.headline,design:.serif)).foregroundStyle(palette.ink)
            Text("\(park.state.replacingOccurrences(of:",",with:", ")) · \(model.night(park).bandWithBasis)").font(.subheadline).foregroundStyle(palette.muted)
            if let closure=mark.closure { Label(closure,systemImage:"exclamationmark.triangle").font(.subheadline).foregroundStyle(palette.accent) }
        }.multilineTextAlignment(.leading).frame(maxWidth:.infinity,alignment:.leading)
        return Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment:.leading,spacing:6) { HStack(alignment:.firstTextBaseline) { score; Spacer(minLength:8); chevron }; words }
            } else {
                // The words take the row's width, so a long name wraps in place rather than meeting the chevron.
                HStack(alignment:.firstTextBaseline,spacing:14) { score.frame(minWidth:44,alignment:.leading); words; chevron }
            }
        }
        .padding(.vertical,12).frame(minHeight:44).contentShape(Rectangle())
    }
}

/// The legend's small drawn examples, from the same marks the map draws.
private struct LegendGlyph: View {
    enum Kind { case sizes, fills, closure }
    @Environment(\.nyx) private var palette
    @Environment(\.nyxAccess) private var access
    let kind: Kind
    var body: some View {
        Canvas { context,size in
            let y=size.height/2
            switch kind {
            case .sizes:
                for (i,score) in [40,70,95].enumerated() {
                    let r=TonightMap.radius(score:score)*0.75
                    NightMark.mark(score:score,hasForecast:true,differentiate:access.differentiate).draw(in:&context,center:CGPoint(x:6+Double(i)*16,y:y),radius:r,fill:.full,color:palette.accent,fillOpacity:TonightMap.fillOpacity(score:score))
                }
            case .fills:
                for (i,fill) in [NightFill.full,.half,.hollow].enumerated() {
                    NightMark.dot(filled:fill == .full).draw(in:&context,center:CGPoint(x:6+Double(i)*16,y:y),radius:5,fill:fill,color:palette.accent,fillOpacity:0.85,hollowBackground:palette.panel)
                }
            case .closure:
                context.fill(Path(ellipseIn:CGRect(x:2,y:y-4,width:8,height:8)),with:.color(palette.accent.opacity(0.8)))
                context.stroke(TonightMapCanvas.triangle(at:CGPoint(x:17,y:y-3),size:7),with:.color(palette.ink),lineWidth:1.1)
            }
        }.accessibilityHidden(true)
    }
}

#Preview("Map of tonight") { NavigationStack { ParksMapView { _ in } }.environment(PlanModel()).preferredColorScheme(.dark) }
#Preview("Map • night vision") { NavigationStack { ParksMapView { _ in } }.environment(PlanModel()).environment(\.nyx,NyxPalette(nightVision:true,highContrast:false)).modifier(NightVisionFilter(enabled:true)).preferredColorScheme(.dark) }
#Preview("Map • AX5") { NavigationStack { ParksMapView { _ in } }.environment(PlanModel()).dynamicTypeSize(.accessibility5).preferredColorScheme(.dark) }
#Preview("Map • Differentiate") { NavigationStack { ParksMapView { _ in } }.environment(PlanModel()).environment(\.nyxAccess,NyxAccess(differentiate:true)).preferredColorScheme(.dark) }
