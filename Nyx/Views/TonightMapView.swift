import SwiftUI

/// Tonight's places on one map: the "where" answer in one picture. Drawn in Canvas over the
/// world's land (`WorldLand`; no MapKit, so no request leaves the device). Each place is its night
/// cell's mark: larger and brighter for a higher score; filled, half-filled or hollow for what its
/// clouds rest on; a small triangle beside a park with a closure. A dashed ring is the search
/// radius around the starting point. The names (the darkest few, and any place a pointer or
/// VoiceOver rests on) are text laid over the drawing by `TonightMapView`.
struct TonightMapCanvas: View {
    @Environment(\.nyx) private var palette
    @Environment(\.nyxAccess) private var access
    let map: TonightMap
    /// The search radius around the starting point, in canvas units (`SkyMap.ring`), and the point itself.
    var ring: [CGPoint]? = nil
    var origin: CGPoint? = nil
    /// 0…1: marks light up from west to east once on appear (1 at once under Reduce Motion).
    var progress: Double = 1
    /// The place named because a pointer rests on it or VoiceOver is on it.
    var highlighted: String?
    var body: some View {
        // Read here, so the map redraws when the land arrives (it loads once, off the main thread).
        let landLoaded=WorldLandStore.shared.land != nil
        Canvas { context,size in
            let place=WorldLand.Placement(map.frame,in:size)
            func screen(_ p:CGPoint)->CGPoint { place.screen(p) }
            // Room for bigger marks on a wide iPad, never smaller than a phone's.
            let size1=max(1,min(1.8,size.width/360))
            // The land, faint: coasts so the marks read as places.
            if landLoaded {
                MapLand.draw(context,frame:map.frame,in:size,palette:palette,fill:palette.nightVision ? 0.05 : 0.035,
                             coast:palette.highContrast ? 0.4 : palette.nightVision ? 0.22 : 0.18)
            }
            // The search radius, dashed, and the starting point inside it.
            if let ring, ring.count>2 {
                var path=Path(); path.addLines(ring.map(screen)); path.closeSubpath()
                context.stroke(path,with:.color(palette.line),style:StrokeStyle(lineWidth:0.8*palette.stroke,dash:[3,4]))
            }
            if let origin {
                let o=screen(origin), arm=4.5
                var cross=Path()
                cross.move(to:CGPoint(x:o.x-arm,y:o.y)); cross.addLine(to:CGPoint(x:o.x+arm,y:o.y))
                cross.move(to:CGPoint(x:o.x,y:o.y-arm)); cross.addLine(to:CGPoint(x:o.x,y:o.y+arm))
                context.stroke(cross,with:.color(palette.ink.opacity(0.75)),lineWidth:1.1*palette.stroke)
            }
            // Dimmer nights first, so the darkest skies sit on top where places crowd together.
            for mark in map.marks.sorted(by:{ $0.score<$1.score }) {
                // West to east, each mark fading in over a fifth of the reveal.
                let start=(map.reveal[mark.id] ?? 0)*0.8
                let shown=min(1,max(0,(progress-start)/0.2))
                guard shown>0 else { continue }
                let p=screen(mark.point), radius=mark.radius*size1
                guard p.x > -radius-8, p.y > -radius-8, p.x<size.width+radius+8, p.y<size.height+radius+8 else { continue }
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
                shape.draw(in:&layer,center:p,radius:radius,fill:mark.fill,color:palette.accent,fillOpacity:palette.markOpacity(score:mark.score),lineWidth:1,stroke:palette.stroke,hollowBackground:palette.panel)
                if mark.closure != nil { layer.stroke(Self.triangle(at:CGPoint(x:p.x+radius*0.8+4,y:p.y-radius*0.8-2),size:6),with:.color(palette.ink),lineWidth:1.1*palette.stroke) }
                if mark.id==highlighted {
                    let ring=radius+5
                    layer.stroke(Path(ellipseIn:CGRect(x:p.x-ring,y:p.y-ring,width:2*ring,height:2*ring)),with:.color(palette.ink.opacity(0.9)),lineWidth:palette.stroke)
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

/// The map with touch, pointer and VoiceOver. A tap opens the nearest place within reach of the
/// finger (parks in Utah sit a few points apart, so overlapping buttons would guess); VoiceOver
/// reads the places as a container, darkest first, with a "West to east" rotor across the map.
struct TonightMapView: View {
    @Environment(\.nyx) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.nyxReduceMotion) private var forcedReduceMotion
    let map: TonightMap
    /// The search radius (`SkyMap.ring`) and the starting point, in canvas units.
    var ring: [CGPoint]? = nil
    var origin: CGPoint? = nil
    /// What the map shows ("Lower 48", "Around Chicago"), said before the map's summary.
    var title: String? = nil
    let open: (String)->Void
    @State private var hovered: String?
    @AccessibilityFocusState private var focused: String?
    @State private var started: Date?
    @State private var done=false
    @Namespace private var rotor
    private var reduceMotion: Bool { systemReduceMotion || forcedReduceMotion }
    private static let reveal=1.2
    var body: some View {
        drawing
            .aspectRatio(1/map.frame.aspect,contentMode:.fit)
            .overlay { GeometryReader { proxy in interaction(size:proxy.size) } }
            .accessibilityElement(children:.contain)
            .accessibilityLabel(title.map { "\($0). \(map.summary)" } ?? map.summary)
            .accessibilityRotor("West to east") { ForEach(map.marks.sorted { $0.point.x<$1.point.x }) { mark in AccessibilityRotorEntry(Text(mark.label),id:mark.id,in:rotor) } }
            // A new area lights up again from the west.
            .task(id:map.frame) { await reveal() }
            .task { await WorldLandStore.shared.load() }
    }
    private var drawing: some View {
        TimelineView(.animation(minimumInterval:1/60,paused:reduceMotion || done || started == nil)) { timeline in
            TonightMapCanvas(map:map,ring:ring,origin:origin,progress:progress(at:timeline.date),highlighted:focused ?? hovered).accessibilityHidden(true)
        }
    }
    /// Ease out over the reveal, like lights coming on across the land.
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
                if !typeSize.isAccessibilitySize { tags(size:size) }
                elements(size:size)
            }.accessibilityIgnoresInvertColors()
        }
    }
    /// The names on the map are a glance: the darkest three (and a place a pointer or VoiceOver rests
    /// on), each on a dark plate so it reads over coastlines and other marks. Each lies inside its
    /// place's element, which speaks it.
    private func tags(size:CGSize)->some View {
        let fixed=map.labelled()
        let extra=(focused ?? hovered).flatMap { id in fixed.contains { $0.id==id } ? nil : map.marks.first { $0.id==id } }
        let size1=max(1,min(1.8,size.width/360))
        // The darkest three first, so a name shown for a pointer or VoiceOver never moves them.
        return ForEach(fixed+(extra.map { [$0] } ?? [])) { mark in
            Text("\(mark.name) \(mark.score)").font(.caption2.weight(.semibold)).foregroundStyle(palette.ink)
                // The plate reaches past the words, fills its corners and starts clear of the mark (the gap below),
                // so nothing bright shows beside the words.
                .background(RoundedRectangle(cornerRadius:4,style:.continuous).fill(Color.black).padding(.horizontal,-TonightMapLabels.plate.width).padding(.vertical,-TonightMapLabels.plate.height))
                .opacity(namesShown ? 1 : 0)
                .accessibilityHidden(true)
                .layoutValue(key:TonightMapLabels.Key.self,value:.tag(id:mark.id,point:point(mark,size:size),gap:mark.radius*size1+4+TonightMapLabels.plate.width,holds:fixed.contains { $0.id==mark.id }))
        }
    }
    /// Names appear once every mark has lit (at once under Reduce Motion).
    private var namesShown: Bool { reduceMotion || done }
    private func hover(_ phase:HoverPhase,size:CGSize) {
        switch phase {
        case .active(let location): hovered=nearest(location,size:size)
        case .ended: hovered=nil
        }
    }
    private func point(_ mark:TonightMap.Mark,size:CGSize)->CGPoint { WorldLand.Placement(map.frame,in:size).screen(mark.point) }
    /// The place nearest a touch, within 26 points (a 44-point target's reach, with a little slack).
    private func nearest(_ location:CGPoint,size:CGSize)->String? {
        var best:(id:String,distance:Double)?
        for mark in map.marks {
            let p=point(mark,size:size)
            let distance=hypot(p.x-location.x,p.y-location.y)
            if distance<=26, distance<(best?.distance ?? .infinity) { best=(mark.id,distance) }
        }
        return best?.id
    }
    /// One VoiceOver element per place at its place (44 points, and its name tag when it has one),
    /// darkest first (the sort priority keeps SwiftUI from reordering them by position). Clear and
    /// without a content shape, so touches fall through to the tap above.
    private func elements(size:CGSize)->some View {
        let count=map.darkest.count
        return ForEach(Array(map.darkest.enumerated()),id:\.element.id) { index,mark in
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
/// no earlier tag; each place's element over its mark and the tag that names it, so the words on
/// screen belong to the element that speaks them.
struct TonightMapLabels: Layout {
    enum Spot: Sendable {
        /// `holds`: the place's element grows to cover the tag (the darkest few, never a passing name).
        case tag(id:String,point:CGPoint,gap:Double,holds:Bool)
        case element(id:String,point:CGPoint)
    }
    struct Key: LayoutValueKey { static let defaultValue: Spot? = nil }
    /// The dark plate's margin around a name.
    static let plate=CGSize(width:4,height:1.5)
    func sizeThatFits(proposal:ProposedViewSize,subviews:Subviews,cache:inout ())->CGSize { proposal.replacingUnspecifiedDimensions() }
    func placeSubviews(in bounds:CGRect,proposal:ProposedViewSize,subviews:Subviews,cache:inout ()) {
        let area=CGRect(origin:.zero,size:bounds.size).insetBy(dx:2,dy:2)
        var taken:[CGRect]=[], held:[String:CGRect]=[:]
        func put(_ subview:LayoutSubview,_ rect:CGRect) { subview.place(at:CGPoint(x:bounds.minX+rect.minX,y:bounds.minY+rect.minY),proposal:ProposedViewSize(rect.size)) }
        for subview in subviews {
            guard case .tag(let id,let point,let gap,let holds)=subview[Key.self] else { continue }
            let text=subview.sizeThatFits(.unspecified)
            let rect=CGRect(origin:Self.origin(text:text,beside:point,gap:gap,in:area,avoiding:taken),size:text)
            let plated=rect.insetBy(dx:-Self.plate.width,dy:-Self.plate.height)
            taken.append(plated)
            if holds { held[id]=plated }
            put(subview,rect)
        }
        for subview in subviews {
            guard case .element(let id,let point)=subview[Key.self] else { continue }
            let mark=CGRect(x:point.x-22,y:point.y-22,width:44,height:44)
            put(subview,held[id].map { mark.union($0) } ?? mark)
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

/// Places as a map: the picture, what its marks mean, and the darkest few as rows that work at
/// every text size. The map opens on the starting point's own area (the lower 48 for most US
/// starting points, so the curated parks show as they always have; the circle around it anywhere
/// else) and a stock menu moves it: around the starting point, each US area, or the world.
/// Curated parks and saved spots always show; the rest of the catalogue is thinned where it
/// crowds, darkest first (`SkyMap.shown`). `open` pushes the place, exactly as a row of the list does.
struct ParksMapView: View {
    @Environment(PlanModel.self) private var model
    @Environment(\.nyx) private var palette
    @Environment(\.nyxAccess) private var access
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The map's area for this window, by `SkyMap.Region` name; empty until chosen, which means the
    /// starting point's own (`SkyMap.defaultRegion`), so a new starting point moves the map with it.
    @SceneStorage("parksMapArea") private var areaChoice=""
    /// Which catalogue places this map has asked forecasts for (held outside observation).
    @State private var forecasts=OnScreenForecasts()
    let open: (Park)->Void
    private var area: SkyMap.Region {
        let chosen=SkyMap.Region(rawValue:areaChoice)
        return chosen ?? SkyMap.defaultRegion(origin:model.mapOrigin,countryCode:model.mapOriginCountry)
    }
    private var aroundTitle: String { model.originName.isEmpty ? SkyMap.Region.around.name : String(localized:"Around \(model.originName)") }
    var body: some View {
        let origin=model.mapOrigin, area=area
        let frame=SkyMap.frame(area,origin:origin,radiusMeters:model.radiusMeters)
        let picked=SkyMap.shown(model.mapPlaces,in:frame) { places in places.map { model.night($0) }.sorted(by:NightPlanner.better).map(\.park) }
        let byID=Dictionary(picked.places.map { ($0.id,$0) },uniquingKeysWith:{ a,_ in a })
        let closures=Dictionary(picked.places.compactMap { place in model.closure(place).map { (place.id,$0) } },uniquingKeysWith:{ a,_ in a })
        let map=TonightMap(nights:picked.places.map { model.night($0) },closures:closures,frame:frame,inView:picked.inView)
        let ring=SkyMap.ring(around:origin,meters:model.radiusMeters,on:frame)
        let start=origin.flatMap(frame.point).flatMap { frame.shows($0) ? $0 : nil }
        // Catalogue places drawn on a regional map ask for their forecasts once the map settles. The
        // world map asks for none: a few hundred places scattered over every continent would cost
        // dozens of regions' requests for a glance; their usual clouds stand until one is opened.
        let wanted:[Park]={ if case .azimuthal=frame.projection { return picked.places.filter(\.isCatalogPlace) } else { return [] } }()
        ScrollView {
            VStack(alignment:.leading,spacing:18) {
                ViewThatFits(in:.horizontal) {
                    HStack(alignment:.firstTextBaseline,spacing:8) { eyebrow(map); Spacer(minLength:8); areaMenu(origin:origin) }
                    VStack(alignment:.leading,spacing:8) { eyebrow(map); areaMenu(origin:origin) }
                }
                TonightMapView(map:map,ring:ring,origin:start,title:area == .around ? aroundTitle : area.name) { id in if let park=byID[id] { open(park) } }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius:24).fill(palette.panel))
                    .overlay(RoundedRectangle(cornerRadius:24).stroke(palette.line,lineWidth:0.5))
                // What the marks mean, under the picture it explains (and clear of the tab bar's fade at rest). At
                // accessibility sizes it runs long, so the answer comes first and the legend follows the list.
                if !typeSize.isAccessibilitySize { legend(ring:ring != nil) }
                Eyebrow(text:"Darkest tonight")
                if map.darkest.isEmpty {
                    Text("No places in this part of the map. Choose another area above.").font(.subheadline).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
                }
                VStack(spacing:0) {
                    ForEach(Array(map.darkest.prefix(5))) { mark in
                        if let park=byID[mark.id] {
                            // A real button around real text, so its words wrap and are measured as they read; it speaks the map's label.
                            Button { open(park) } label:{ row(mark,park:park) }.buttonStyle(.plain).hoverEffect(.highlight).draggable(park)
                                .accessibilityLabel(mark.label)
                            Divider().overlay(palette.line)
                        }
                    }
                }
                if typeSize.isAccessibilitySize { legend(ring:ring != nil) }
                // As on the Parks list and Tonight: said only when a row here reads "Estimate". The local date is
                // explained in each night's score breakdown.
                if map.darkest.prefix(5).contains(where:{ mark in byID[mark.id].map { model.night($0).basis == .usual } ?? false }) {
                    Text("Scores marked Estimate have no cloud forecast yet and use each park's usual clouds.").font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
                }
            }.padding(24).readableColumn(1100)
        }
        .background(NightBackground()).navigationTitle("Parks").navigationBarTitleDisplayMode(.inline)
        // Clouds for the curated parks in one request, and the one bulk alerts request for the closure marks.
        .task { await model.refresh(model.parks) }
        .task(id:wanted.map(\.id)) {
            guard !wanted.isEmpty else { return }
            try? await Task.sleep(for:OnScreenForecasts.settle)
            guard !Task.isCancelled else { return }
            await forecasts.shown(wanted,model:model)
        }
        .refreshable { await model.refresh(model.parks,force:true) }
    }
    @ViewBuilder private func eyebrow(_ map:TonightMap)->some View {
        if let home=model.home { Eyebrow(text:"\(home.dayLabel(model.tonight(home))) · \(map.marks.count) places tonight") }
    }
    /// Which part of the world the map shows: a stock menu, said as "Map area".
    private func areaMenu(origin:GeoPoint?)->some View {
        Picker("Map area",selection:Binding(get:{ area },set:{ areaChoice=$0.rawValue })) {
            if origin != nil { Text(aroundTitle).tag(SkyMap.Region.around) }
            ForEach(SkyMap.Region.unitedStates,id:\.self) { region in Text(region.name).tag(region) }
            Text(SkyMap.Region.world.name).tag(SkyMap.Region.world)
        }
        .pickerStyle(.menu).labelsHidden().fixedSize()
        .accessibilityLabel("Map area")
    }
    /// What the marks mean, in words beside small drawn examples.
    private func legend(ring:Bool)->some View {
        var items:[(LegendGlyph.Kind,LocalizedStringKey)]=[(.sizes,"Larger and brighter: a darker night"),(.fills,"Filled: forecast. Half: early look. Hollow: usual clouds"),(.closure,"Closure in the last park update")]
        if ring { items.append((.ring,"Dashed ring: your search radius, as the crow flies")) }
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
            Text(park.shortName).font(.system(.title3,design:.serif)).foregroundStyle(palette.ink)
            Text("\(park.region.replacingOccurrences(of:",",with:", ")) · \(model.night(park).bandWithBasis)").font(.subheadline).foregroundStyle(palette.muted)
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
    enum Kind { case sizes, fills, closure, ring }
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
                    NightMark.mark(score:score,hasForecast:true,differentiate:access.differentiate).draw(in:&context,center:CGPoint(x:6+Double(i)*16,y:y),radius:r,fill:.full,color:palette.accent,fillOpacity:palette.markOpacity(score:score))
                }
            case .fills:
                for (i,fill) in [NightFill.full,.half,.hollow].enumerated() {
                    NightMark.dot(filled:fill == .full).draw(in:&context,center:CGPoint(x:6+Double(i)*16,y:y),radius:5,fill:fill,color:palette.accent,fillOpacity:0.85,stroke:palette.stroke,hollowBackground:palette.panel)
                }
            case .closure:
                context.fill(Path(ellipseIn:CGRect(x:2,y:y-4,width:8,height:8)),with:.color(palette.accent.opacity(0.8)))
                context.stroke(TonightMapCanvas.triangle(at:CGPoint(x:17,y:y-3),size:7),with:.color(palette.ink),lineWidth:1.1*palette.stroke)
            case .ring:
                // A stretch of the dashed ring around the starting point's cross.
                var arc=Path()
                arc.addArc(center:CGPoint(x:8,y:y+14),radius:20,startAngle:.degrees(-80),endAngle:.degrees(-5),clockwise:false)
                context.stroke(arc,with:.color(palette.line),style:StrokeStyle(lineWidth:0.8*palette.stroke,dash:[3,4]))
                var cross=Path()
                cross.move(to:CGPoint(x:4,y:y+4)); cross.addLine(to:CGPoint(x:12,y:y+4))
                cross.move(to:CGPoint(x:8,y:y)); cross.addLine(to:CGPoint(x:8,y:y+8))
                context.stroke(cross,with:.color(palette.ink.opacity(0.75)),lineWidth:1.1*palette.stroke)
            }
        }.accessibilityHidden(true)
    }
}

#Preview("Map of tonight") { NavigationStack { ParksMapView { _ in } }.environment(PlanModel()).preferredColorScheme(.dark) }
#Preview("Map • night vision") { NavigationStack { ParksMapView { _ in } }.environment(PlanModel()).environment(\.nyx,NyxPalette(nightVision:true,highContrast:false)).modifier(NightVisionFilter(enabled:true)).preferredColorScheme(.dark) }
#Preview("Map • AX5") { NavigationStack { ParksMapView { _ in } }.environment(PlanModel()).dynamicTypeSize(.accessibility5).preferredColorScheme(.dark) }
#Preview("Map • Differentiate") { NavigationStack { ParksMapView { _ in } }.environment(PlanModel()).environment(\.nyxAccess,NyxAccess(differentiate:true)).preferredColorScheme(.dark) }
