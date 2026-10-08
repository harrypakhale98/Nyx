import CoreLocation
import SwiftUI
import WidgetKit

struct TonightEntry:TimelineEntry {
    let date:Date
    let night:Night?
    let nightVision:Bool
    /// Tonight and the six nights after it at the same park, for the medium widget.
    var week:[Night]=[]
    /// The large widget's calendar of nights at the shown park.
    var month:NightPlanner.Month?=nil
    /// Which saved park is shown (1-based, in order of tonight's score) and how many there are.
    var position=0
    var savedCount=0
    /// Rises in the Smart Stack around dusk on a Good or better night.
    var relevance:TimelineEntryRelevance?=nil
    /// The shown park's closure, as the app words it beside the score (from the snapshot).
    var closure:String?=nil
}
/// Builds Tonight entries from the shared snapshot. Each night's sky is computed once and reused
/// across entries; the large widget's month (35 nights with shower and eclipse marks) once per night.
struct TonightTimeline {
    let snapshot:SavedSkySnapshot?
    let large:Bool
    /// A park the widget was set to; nil follows the darkest saved park.
    let pinned:Park?
    private var skies:[String:SkyConditions]=[:]
    private var months:[String:NightPlanner.Month]=[:]
    init(snapshot:SavedSkySnapshot?,large:Bool,pinned:Park?=nil) { self.snapshot=snapshot; self.large=large; self.pinned=pinned }
    private var planner:NightPlanner { snapshot?.planner ?? NightPlanner(forecasts:[:]) }
    /// The sky is fixed; the score is taken at the entry's date (its forecast never expires; it fades by lead time).
    private mutating func night(_ park:Park,_ evening:Date,at date:Date)->Night {
        let key="\(park.id)-\(evening.timeIntervalSince1970)"
        let sky=skies[key] ?? AstronomyEngine().conditions(for:park,on:evening)
        skies[key]=sky
        return planner.night(park,sky:sky,now:date)
    }
    mutating func entry(at date:Date)->TonightEntry {
        let parks=pinned.map { [$0] } ?? snapshot?.parks ?? []
        let tonight=parks.map { night($0,$0.currentNight(at:date),at:date) }
        // A widget set to one park shows that park; otherwise the darkest saved park (or the one "next" moved to).
        let shown=pinned == nil ? WidgetSelection.pick(tonight) : tonight.first
        let week=shown.map { first in (0..<7).map { night(first.park,first.park.date(first.id,addingDays:$0),at:date) } } ?? []
        var month:NightPlanner.Month?
        if large, let shown {
            // Recomputed when the night turns over. A forecast fades by how far ahead it was made,
            // not by the entry's date, so the month is the same all night.
            let key="\(shown.park.id)-\(shown.id.timeIntervalSince1970)"
            month=months[key] ?? planner.month(shown.park,at:date)
            months[key]=month
        }
        let relevance=NightPlanner.relevance(at:date,nights:tonight)
        return TonightEntry(date:date,night:shown,nightVision:SharedSettings.defaults.bool(forKey:"nightVision"),week:week,month:month,
                            position:pinned == nil ? shown.map { WidgetSelection.position(of:$0,in:tonight) } ?? 0 : 0,savedCount:pinned == nil ? parks.count : 0,
                            relevance:TimelineEntryRelevance(score:relevance.score,duration:relevance.duration),
                            closure:shown.flatMap { snapshot?.closures[$0.park.id] })
    }
    /// Dusk windows of Good or better nights across the saved parks (or the set park), `nights` nights from `start`.
    mutating func duskWindows(from start:Date,nights count:Int)->[DateInterval] {
        (pinned.map { [$0] } ?? snapshot?.parks ?? []).flatMap { park in
            (0..<count).compactMap { offset in NightPlanner.duskWindow(night(park,park.date(park.currentNight(at:start),addingDays:offset),at:start)) }
        }.filter { $0.end>start }
    }
    /// Where the park is, for the Smart Stack: 25 km around its first named viewing spot (where
    /// people stand at night), or around the park's own coordinates.
    static func region(_ park:Park)->CLCircularRegion {
        let spot=park.viewingSpots.first
        let center=CLLocationCoordinate2D(latitude:spot?.latitude ?? park.latitude,longitude:spot?.longitude ?? park.longitude)
        return CLCircularRegion(center:center,radius:25_000,identifier:"nyx-\(park.id)")
    }
}
/// What the Tonight control shows ("Tonight 93", the park) and opens.
struct TonightControlValue:Sendable {
    let parkID:String?
    let name:String?
    let score:Int?
    let symbol:String
    init(parkID:String?,name:String?,score:Int?,symbol:String) { self.parkID=parkID; self.name=name; self.score=score; self.symbol=symbol }
    /// The set park's night, else the darkest saved park's (`NightPlanner.best`, as everywhere);
    /// no score before any park is saved. Never the park the widget's "next" button moved to: the
    /// control answers "where is darkest tonight", whatever a widget is showing.
    init(snapshot:SavedSkySnapshot?,pinned:Park?,now:Date) {
        let planner=snapshot?.planner ?? NightPlanner(forecasts:[:])
        let parks=pinned.map { [$0] } ?? snapshot?.parks ?? []
        guard let night=NightPlanner.best(parks.map { planner.night($0,on:$0.currentNight(at:now),now:now) }) else {
            self.init(parkID:nil,name:nil,score:nil,symbol:"moon.stars"); return
        }
        self.init(parkID:night.park.id,name:night.park.shortName,score:night.score.value,symbol:night.sky.moon.symbolName)
    }
}
struct TonightWidgetView:View {
    @Environment(\.widgetFamily) private var systemFamily
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.displayScale) private var displayScale
    var previewFamily:WidgetFamily?=nil
    private var family:WidgetFamily { previewFamily ?? systemFamily }
    let entry:TonightEntry
    /// StandBy at night, tinted Home Screens and the Lock Screen draw the widget in one tint from
    /// its luminance. There, Nyx speaks in white and opacity only (amber and red would read as
    /// mid-grey) and leaves the night-vision red to the system.
    private var tinted:Bool { renderingMode != .fullColor }
    private var nightVision:Bool { entry.nightVision && !tinted }
    private var ink:Color { tinted ? .white : nightVision ? Color(red:1,green:0.27,blue:0.23) : Color(red:0.961,green:0.945,blue:0.902) }
    private var accent:Color { tinted || nightVision ? ink : Color(red:1,green:0.706,blue:0.329) }
    private var muted:Color { ink.opacity(tinted ? 0.62 : nightVision ? 0.9 : 0.7) }
    private var palette:NyxPalette { NyxPalette(nightVision:nightVision,highContrast:false) }
    var body:some View {
        content.foregroundStyle(ink)
            .containerBackground(for:.widget) { WidgetSky(seed:entry.night?.park.id ?? "nyx",ink:ink,night:entry.night) }
            .widgetURL(URL(string:entry.night.map{"nyx://park/\($0.park.id)"} ?? "nyx://tonight"))
    }
    /// iPad's portrait extra-large widget (iOS 27): tonight above the month.
    private var portraitXL:Bool {
        if #available(iOS 27.0,*) { return family == .systemExtraLargePortrait }
        return false
    }
    @ViewBuilder private var content:some View {
        if let night=entry.night {
            if family == .accessoryInline {
                // Above the clock: "☾ 94 Joshua Tree", tonight's phase as the symbol.
                Label { Text(verbatim:"\(night.score.value) \(night.park.shortName)") } icon:{ Image(systemName:night.sky.moon.symbolName) }
                    .summarized(summary(night))
            } else if family == .accessoryCircular {
                // The Lock Screen ring echoes the app's celestial gauge.
                // The Moon in the ring's opening is tonight's actual phase.
                Gauge(value:Double(night.score.value),in:0...100) {
                    MoonSymbol(night:night)
                } currentValueLabel: {
                    // Two digits inside a fixed ring: shrink rather than spill over the arc at large sizes.
                    Text("\(night.score.value)").font(.system(.title3,design:.serif)).minimumScaleFactor(0.6).widgetAccentable()
                }.gaugeStyle(.accessoryCircular).dynamicTypeSize(.small ... .xxxLarge).summarized(summary(night))
            } else if family == .accessoryRectangular {
                // Lock Screen dimensions are fixed: the score is the hero, the band beside it, and a
                // smaller numeral when large text would not fit. The spoken summary stays complete.
                ViewThatFits(in:.vertical) {
                    lockHero(night,numeral:.title)
                    lockHero(night,numeral:.title3)
                }.dynamicTypeSize(.small ... .xxxLarge).summarized(summary(night))
            } else if portraitXL, let month=entry.month, !typeSize.isAccessibilitySize {
                portraitContent(night,month:month).summarized(summary(night)).overlay(alignment:.topTrailing) { cycleButton(night) }
            } else if family == .systemExtraLarge, let month=entry.month, !typeSize.isAccessibilitySize {
                extraLargeContent(night,month:month).summarized(summary(night)).overlay(alignment:.topTrailing) { cycleButton(night) }
            } else if family == .systemLarge || family == .systemExtraLarge || portraitXL, let month=entry.month {
                largeContent(night,month:month).summarized(summary(night)).overlay(alignment:.topTrailing) { cycleButton(night) }
            } else if family == .systemMedium && !entry.week.isEmpty && !typeSize.isAccessibilitySize {
                VStack(alignment:.leading,spacing:6) {
                    HStack(alignment:.top,spacing:14) {
                        homeContent(night).frame(maxWidth:132,alignment:.leading)
                        weekStrip(entry.week)
                    }
                    closureLine(.caption2)
                }.summarized(summary(night)).overlay(alignment:.topTrailing) { cycleButton(night) }
            } else {
                ViewThatFits(in:.vertical) {
                    homeContent(night)
                    // Prefer full Dynamic Type; only a fixed widget footprint needs
                    // the compact fallback. The app's detail remains fully reflowing.
                    compactContent(night).dynamicTypeSize(.small ... .xxxLarge)
                }.summarized(summary(night))
            }
        } else if family == .accessoryInline {
            Label("Save a park in Nyx",systemImage:"moon.stars")
                .summarized(String(localized:"Save a park in Nyx. Your next dark sky will appear here."))
        } else if family == .accessoryCircular {
            ZStack { AccessoryWidgetBackground(); Image(systemName:"moon.stars").font(.title3) }
                .summarized(String(localized:"Save a park in Nyx. Your next dark sky will appear here."))
        } else if family == .accessoryRectangular {
            VStack(alignment:.leading,spacing:2) {
                Label("Nyx",systemImage:"moon.stars").font(.headline)
                Text("Save a park in Nyx").font(.caption).lineLimit(2)
            }.frame(maxWidth:.infinity,alignment:.leading).dynamicTypeSize(.small ... .xxxLarge)
                .summarized(String(localized:"Save a park in Nyx. Your next dark sky will appear here."))
        } else {
            ViewThatFits(in:.vertical) {
                VStack(alignment:.leading,spacing:8) {
                    Image(systemName:"moon.stars")
                    Text("Save a park in Nyx").font(.system(.subheadline,design:.serif)).fixedSize(horizontal:false,vertical:true)
                    if family != .systemSmall { Text("Your next dark sky will appear here.").font(.caption).fixedSize(horizontal:false,vertical:true) }
                }
                Text("Save a park in Nyx").font(.caption).dynamicTypeSize(.small ... .xxxLarge).fixedSize(horizontal:false,vertical:true)
            }.summarized(String(localized:"Save a park in Nyx. Your next dark sky will appear here."))
        }
    }
    /// "2 of 3 ›": moves the widget to the next saved park. Only with two or more saved parks, and
    /// only where it fits (medium and large, outside accessibility sizes); a tap anywhere else opens the park.
    @ViewBuilder private func cycleButton(_ night:Night)->some View {
        if entry.savedCount>1, entry.position>0 {
            Button(intent:CycleWidgetParkIntent()) {
                HStack(spacing:3) {
                    Text("\(entry.position) of \(entry.savedCount)").monospacedDigit()
                    Image(systemName:"chevron.forward").fontWeight(.semibold)
                }
                .font(.caption2.weight(.medium)).foregroundStyle(ink)
                .padding(.horizontal,9).padding(.vertical,5)
                .background(ink.opacity(tinted ? 0.22 : 0.13),in:Capsule())
                // The capsule stays small in the corner; the tap target reaches 44 by 36 around it.
                .frame(minWidth:44,minHeight:36,alignment:.topTrailing)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).dynamicTypeSize(.small ... .large)
            .accessibilityLabel("Next saved park")
            .accessibilityValue("Showing \(night.park.shortName), \(entry.position) of \(entry.savedCount)")
        }
    }
    /// The park's closure, in the accent, as the app shows it beside the score: the one line a
    /// widget must not leave out. Two lines at most, the whole of it in the spoken summary.
    @ViewBuilder private func closureLine(_ font:Font)->some View {
        if let closure=entry.closure {
            Label { Text(closure).lineLimit(2).minimumScaleFactor(0.85) } icon:{ Image(systemName:"exclamationmark.triangle.fill").accessibilityHidden(true) }
                .font(font.weight(.medium)).foregroundStyle(accent).widgetAccentable()
                .frame(maxWidth:.infinity,alignment:.leading)
        }
    }
    /// "Excellent" with a forecast; "Excellent, early look" or "Excellent, usual clouds" without, as on the watch.
    private func forecastLabel(_ night:Night)->String { night.bandWithBasis }
    /// The Lock Screen rectangle: the park, then the score as the hero with its band beside it.
    private func lockHero(_ night:Night,numeral:Font.TextStyle)->some View {
        VStack(alignment:.leading,spacing:0) {
            Text(night.park.shortName).font(.headline).lineLimit(1)
            HStack(alignment:.firstTextBaseline,spacing:6) {
                Text("\(night.score.value)").font(.system(numeral,design:.serif).weight(.light)).monospacedDigit().widgetAccentable()
                Text(forecastLabel(night)).font(.caption).lineLimit(2).fixedSize(horizontal:false,vertical:true)
            }
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
    private func homeContent(_ night:Night)->some View {
        VStack(alignment:.leading,spacing:4) {
            if !typeSize.isAccessibilitySize {
                HStack(alignment:.center) {
                    Text("Tonight's sky").textCase(.uppercase).font(.caption2.weight(.medium)).tracking(0.8).foregroundStyle(muted).lineLimit(1).minimumScaleFactor(0.75)
                    Spacer(minLength:4)
                    moon(night).frame(width:18,height:18)
                }
            }
            Text("\(night.score.value)").font(.system(size:48,weight:.light,design:.serif)).foregroundStyle(accent).widgetAccentable()
            Text(night.park.shortName).font(.system(.caption,design:.serif)).fixedSize(horizontal:false,vertical:true)
            Text(forecastLabel(night)).font(.caption2).foregroundStyle(muted).fixedSize(horizontal:false,vertical:true)
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
    /// The app's pre-rendered lit Moon when it exists; the vector Moon, rendered to an image,
    /// otherwise. An image either way, so a tinted or clear Home Screen can draw it desaturated
    /// with its terminator intact instead of flattening it to a solid disc.
    @ViewBuilder private func moon(_ night:Night)->some View {
        if let image=moonImage(night) {
            Image(uiImage:image).resizable().widgetAccentedRenderingMode(.accentedDesaturated).scaledToFit()
                .accessibilityIgnoresInvertColors().modifier(NightVisionFilter(enabled:nightVision))
        } else {
            MoonDisc(illumination:night.sky.moon.illumination,waxing:night.sky.moon.waxing,southern:night.park.latitude<0)
                .environment(\.nyx,palette).modifier(NightVisionFilter(enabled:nightVision))
        }
    }
    private func moonImage(_ night:Night)->UIImage? {
        // The night's own picture, else the nearest night the app drew (it draws a week ahead).
        if let url=SharedSettings.moonImage(park:night.park.id,night:night.id),let image=UIImage(contentsOfFile:url.path) { return image }
        let renderer=ImageRenderer(content:MoonDisc(illumination:night.sky.moon.illumination,waxing:night.sky.moon.waxing,southern:night.park.latitude<0)
            .environment(\.nyx,palette).frame(width:34,height:34))
        renderer.scale=displayScale
        return renderer.uiImage
    }
    /// Seven nights as small skies: the dot grows with the score, the best night gets a ring,
    /// nights without a cloud forecast are hollow.
    private func weekStrip(_ week:[Night])->some View {
        let best=NightPlanner.best(week)?.id
        return VStack(alignment:.leading,spacing:6) {
            HStack(spacing:0) {
                Text("Next seven nights").textCase(.uppercase).font(.caption2.weight(.medium)).tracking(0.8).foregroundStyle(muted).lineLimit(1).minimumScaleFactor(0.7)
                // Room for the "2 of 3" button laid over the top corner.
                Spacer(minLength:entry.savedCount>1 ? 62 : 0)
            }.frame(minHeight:entry.savedCount>1 ? 24 : nil)
            HStack(spacing:0) {
                ForEach(week) { night in
                    VStack(spacing:5) {
                        Text(night.park.weekdayInitial(night.id)).font(.caption2.weight(night.id==best ? .bold : .regular)).foregroundStyle(night.id==best ? ink : muted)
                        ZStack {
                            if night.id==best { Circle().stroke(accent.opacity(0.8),lineWidth:0.8).frame(width:22,height:22) }
                            let d=4+12*Double(night.score.value)/100
                            NightDot(fill:night.basis.fill,color:accent,fillOpacity:0.45+Double(night.score.value)/200,lineWidth:1).frame(width:d,height:d).widgetAccentable()
                        }.frame(height:24)
                        Text("\(night.score.value)").font(.caption2.monospacedDigit()).foregroundStyle(muted).lineLimit(1).minimumScaleFactor(0.8)
                    }.frame(maxWidth:.infinity)
                }
            }
            // A closure takes this line's room below; the ring already marks the best night.
            if entry.closure == nil, let top=week.first(where:{ $0.id==best }) {
                Text("Best: \(top.park.dayLabel(top.id)) · \(top.score.value)").font(.caption2).foregroundStyle(ink).lineLimit(1).minimumScaleFactor(0.8)
            }
        }.dynamicTypeSize(...DynamicTypeSize.large) // Seven fixed columns: 11 pt text that always fits.
    }
    private func compactContent(_ night:Night)->some View {
        VStack(alignment:.leading,spacing:4) {
            Text("\(night.score.value)").font(.system(size:40,weight:.light,design:.serif)).foregroundStyle(accent)
            Text(night.park.shortName).font(.system(.caption2,design:.serif)).fixedSize(horizontal:false,vertical:true)
            Text(forecastLabel(night)).font(.caption2).fixedSize(horizontal:false,vertical:true)
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
    /// The large widget: tonight at the shown park, then its coming nights as a calendar of small
    /// skies (the same marks as the app's calendar: size for score, hollow without a forecast, a
    /// ring on the best, a glyph on shower peaks and eclipses).
    private func largeContent(_ night:Night,month:NightPlanner.Month)->some View {
        VStack(alignment:.leading,spacing:10) {
            HStack(spacing:0) {
                // A closure takes the eyebrow's place, so the month keeps its room.
                if entry.closure != nil { closureLine(.caption2) }
                else { Text("Tonight's sky").textCase(.uppercase).font(.caption2.weight(.medium)).tracking(1.2).foregroundStyle(muted) }
                Spacer(minLength:entry.savedCount>1 ? 70 : 0)
            }.frame(minHeight:entry.savedCount>1 ? 24 : nil)
            HStack(alignment:.center,spacing:12) {
                VStack(alignment:.leading,spacing:0) {
                    Text(night.park.shortName).font(.system(.headline,design:.serif)).lineLimit(1).minimumScaleFactor(0.8)
                    HStack(alignment:.firstTextBaseline,spacing:8) {
                        Text("\(night.score.value)").font(.system(size:44,weight:.light,design:.serif)).foregroundStyle(accent).widgetAccentable()
                        Text(forecastLabel(night)).font(.caption).foregroundStyle(muted)
                    }
                }
                Spacer(minLength:4)
                VStack(alignment:.trailing,spacing:3) {
                    moon(night).frame(width:34,height:34)
                    Text(night.sky.moon.name).font(.caption2)
                    Text("\(Int((night.sky.moon.illumination*100).rounded()))% lit").font(.caption2).foregroundStyle(muted)
                }
            }
            monthGrid(night.park,month:month)
            HStack(spacing:6) {
                if let best=month.best, let top=month.nights.compactMap({ $0 }).first(where:{ $0.id==best }) {
                    Text("Best: \(top.park.dayLabel(top.id)) · \(top.score.value)").font(.caption2).lineLimit(1).minimumScaleFactor(0.8)
                }
                Spacer(minLength:4)
                if month.nights.contains(where:{ $0.map { $0.basis == .usual } ?? false }) {
                    Circle().stroke(accent,lineWidth:1).frame(width:6,height:6)
                    Text("No cloud forecast yet").font(.caption2).foregroundStyle(muted).lineLimit(1)
                }
            }
        }.dynamicTypeSize(.small ... .xLarge)
    }
    /// iPad's extra-large widget: tonight on the left, large enough to read across a room, and the
    /// coming nights as the same calendar of small skies on the right.
    private func extraLargeContent(_ night:Night,month:NightPlanner.Month)->some View {
        HStack(alignment:.top,spacing:28) {
            VStack(alignment:.leading,spacing:8) {
                Text("Tonight's sky").textCase(.uppercase).font(.caption.weight(.medium)).tracking(1.4).foregroundStyle(muted)
                Text(night.park.shortName).font(.system(.title3,design:.serif)).lineLimit(2).minimumScaleFactor(0.8)
                Text("\(night.score.value)").font(.system(size:72,weight:.light,design:.serif)).foregroundStyle(accent).widgetAccentable()
                Text(forecastLabel(night)).font(.subheadline).foregroundStyle(muted)
                HStack(alignment:.center,spacing:10) {
                    moon(night).frame(width:34,height:34)
                    VStack(alignment:.leading,spacing:2) {
                        Text(night.sky.moon.name).font(.caption)
                        Text("\(Int((night.sky.moon.illumination*100).rounded()))% lit").font(.caption2).foregroundStyle(muted)
                    }
                }.padding(.top,10)
                if let best=month.best, let top=month.nights.compactMap({ $0 }).first(where:{ $0.id==best }) {
                    Text("Best: \(top.park.dayLabel(top.id)) · \(top.score.value)").font(.caption).lineLimit(1).minimumScaleFactor(0.8)
                }
                closureLine(.caption).padding(.top,4)
            }.frame(width:200,alignment:.leading)
            VStack(alignment:.leading,spacing:8) {
                // Room for the "2 of 3" button laid over the top corner.
                Color.clear.frame(height:entry.savedCount>1 ? 18 : 0)
                monthGrid(night.park,month:month)
                if month.nights.contains(where:{ $0.map { $0.basis == .usual } ?? false }) {
                    HStack(spacing:6) { Circle().stroke(accent,lineWidth:1).frame(width:6,height:6); Text("No cloud forecast yet").font(.caption2).foregroundStyle(muted) }
                }
            }
        }.dynamicTypeSize(.small ... .xLarge)
    }
    /// iPad's portrait extra-large widget (iOS 27): tonight above, large enough to read across a
    /// room, then the coming nights as the calendar of small skies, then what the marks mean.
    private func portraitContent(_ night:Night,month:NightPlanner.Month)->some View {
        VStack(alignment:.leading,spacing:14) {
            HStack(spacing:0) {
                Text("Tonight's sky").textCase(.uppercase).font(.caption.weight(.medium)).tracking(1.4).foregroundStyle(muted)
                Spacer(minLength:entry.savedCount>1 ? 70 : 0)
            }.frame(minHeight:entry.savedCount>1 ? 24 : nil)
            HStack(alignment:.center,spacing:16) {
                VStack(alignment:.leading,spacing:2) {
                    Text(night.park.shortName).font(.system(.title2,design:.serif)).lineLimit(2).minimumScaleFactor(0.8)
                    HStack(alignment:.firstTextBaseline,spacing:10) {
                        Text("\(night.score.value)").font(.system(size:80,weight:.light,design:.serif)).foregroundStyle(accent).widgetAccentable()
                        Text(forecastLabel(night)).font(.subheadline).foregroundStyle(muted).fixedSize(horizontal:false,vertical:true)
                    }
                }
                Spacer(minLength:8)
                VStack(alignment:.center,spacing:4) {
                    moon(night).frame(width:56,height:56)
                    Text(night.sky.moon.name).font(.caption)
                    Text("\(Int((night.sky.moon.illumination*100).rounded()))% lit").font(.caption2).foregroundStyle(muted)
                }
            }
            closureLine(.subheadline)
            Spacer(minLength:0)
            monthGrid(night.park,month:month,scale:1.4)
            Spacer(minLength:0)
            HStack(spacing:6) {
                if let best=month.best, let top=month.nights.compactMap({ $0 }).first(where:{ $0.id==best }) {
                    Text("Best: \(top.park.dayLabel(top.id)) · \(top.score.value)").font(.caption).lineLimit(1).minimumScaleFactor(0.8)
                }
                Spacer(minLength:4)
                if month.nights.contains(where:{ $0.map { $0.basis == .usual } ?? false }) {
                    Circle().stroke(accent,lineWidth:1).frame(width:6,height:6)
                    Text("No cloud forecast yet").font(.caption2).foregroundStyle(muted).lineLimit(1)
                }
            }
        }.dynamicTypeSize(.small ... .xLarge)
    }
    /// `scale` enlarges the cells, rings and dots together (the portrait extra-large widget).
    private func monthGrid(_ park:Park,month:NightPlanner.Month,scale:Double=1)->some View {
        let rows=stride(from:0,to:month.nights.count,by:7).map { Array(month.nights[$0..<min($0+7,month.nights.count)]) }
        let first=month.tonight?.id
        return Grid(horizontalSpacing:0,verticalSpacing:4*scale) {
            GridRow {
                ForEach(0..<7,id:\.self) { column in
                    Text(weekdayInitial(park,month:month,column:column)).font((scale>1 ? Font.caption : .caption2).weight(.medium)).foregroundStyle(muted).frame(maxWidth:.infinity)
                }
            }
            ForEach(Array(rows.enumerated()),id:\.offset) { _,row in
                GridRow {
                    ForEach(Array(row.enumerated()),id:\.offset) { _,night in
                        if let night { nightCell(night,best:night.id==month.best,tonight:night.id==first,event:month.events[night.id],scale:scale) }
                        else { Color.clear.frame(height:28*scale) }
                    }
                }
            }
        }.dynamicTypeSize(...DynamicTypeSize.large) // Fixed 28 pt cells: 11 pt numerals, never clipped.
    }
    private func weekdayInitial(_ park:Park,month:NightPlanner.Month,column:Int)->String {
        let lead=month.nights.prefix { $0 == nil }.count
        guard let tonight=month.tonight else { return "" }
        return park.weekdayInitial(park.date(tonight.id,addingDays:column-lead))
    }
    private func nightCell(_ night:Night,best:Bool,tonight:Bool,event:WhatsUp.Events.Glyph?,scale:Double=1)->some View {
        let d=(4+9*Double(night.score.value)/100)*scale
        return VStack(spacing:0) {
            Text(night.park.calendar.component(.day,from:night.id),format:.number).font((scale>1 ? Font.caption : .caption2).weight(tonight ? .bold : .regular)).monospacedDigit()
                .foregroundStyle(tonight ? ink : muted)
            ZStack {
                if best { Circle().stroke(accent.opacity(0.85),lineWidth:0.9).frame(width:17*scale,height:17*scale) }
                NightDot(fill:night.basis.fill,color:accent.opacity(night.basis.fill == .full ? 1 : 0.85),fillOpacity:0.45+Double(night.score.value)/200,lineWidth:0.9).frame(width:d,height:d).widgetAccentable()
                // Beside the dot, never on it: the dot's size is the score and must stay readable.
                if let event { SkyGlyph(event == .eclipse ? .eclipse : .meteors,color:ink).frame(width:12*scale,height:12*scale).offset(x:13*scale,y:-3*scale) }
            }.frame(height:15*scale)
        }.frame(maxWidth:.infinity).frame(height:28*scale)
    }
    private func summary(_ night:Night)->String {
        var tonight=String(localized:"\(night.park.shortName), \(night.score.value) out of 100, \(night.score.band.label). \(night.basisCaption() ?? String(localized:"Cached forecast included"))")
        // The closure is spoken wherever it is shown (medium and larger).
        if let closure=entry.closure, ![.accessoryInline,.accessoryCircular,.accessoryRectangular,.systemSmall].contains(family) { tonight+=" "+String(localized:"Closure alert: \(closure)") }
        if family == .systemLarge || family == .systemExtraLarge || portraitXL, let month=entry.month, let best=month.best, let top=month.nights.compactMap({ $0 }).first(where:{ $0.id==best }) {
            let count=month.nights.compactMap { $0 }.count
            let events=month.nights.compactMap { $0 }.filter { month.events[$0.id] != nil }
                .map { night in String(localized:"\(month.events[night.id] == .eclipse ? String(localized:"Lunar eclipse") : String(localized:"Meteor shower peak")), \(night.park.dayLabel(night.id))") }
            return ([tonight,String(localized:"\(night.sky.moon.name), \(Int((night.sky.moon.illumination*100).rounded())) percent lit."),
                     String(localized:"Best of the next \(count) nights: \(top.park.dayLabel(top.id)), \(top.score.value).")]+events.map { $0+"." }).joined(separator:" ")
        }
        guard family == .systemMedium,let top=NightPlanner.best(entry.week) else { return tonight }
        return tonight+" "+String(localized:"Best of the next seven nights: \(top.park.dayLabel(top.id)), \(top.score.value).")
    }
}
private extension View {
    /// One spoken summary for the widget's information; a button beside it stays its own element.
    func summarized(_ label:String)->some View { accessibilityElement(children:.ignore).accessibilityLabel(label) }
}
/// A still, seeded sky behind the widget. Widgets render once per entry, so nothing animates.
struct WidgetSky:View {
    let seed:String
    let ink:Color
    /// When known, the real stars over that park that night; seeded dots otherwise.
    var night:Night?=nil
    var body:some View {
        Canvas { context,size in
            if let night {
                let sky=SkyProjection.shared.sky(for:night.park,night:night.id)
                for star in sky.bright+sky.middle+sky.faint {
                    let p=SkyProjection.screen(star.position,size:CGSize(width:size.width,height:size.height*1.6))
                    let y=p.y-size.height*0.3
                    guard p.x>=0,p.x<=size.width,y>=0,y<=size.height else { continue }
                    let d=star.diameter*0.7
                    context.fill(Path(ellipseIn:CGRect(x:p.x-d/2,y:y-d/2,width:d,height:d)),with:.color(star.tint(ink).opacity(star.brightness*0.55)))
                }
                return
            }
            var generator=SeededGenerator(seed:seed)
            for _ in 0..<36 {
                let d=Double.random(in:0.6..<1.7,using:&generator)
                let rect=CGRect(x:Double.random(in:0..<size.width,using:&generator),y:Double.random(in:0..<size.height,using:&generator),width:d,height:d)
                context.fill(Path(ellipseIn:rect),with:.color(ink.opacity(Double.random(in:0.12..<0.45,using:&generator))))
            }
        }.background(Color.black)
    }
}
#if DEBUG
struct WidgetReviewView:View {
    let entry:TonightEntry
    /// `widgets-large`: the large family in full colour, night vision and a tinted Home Screen.
    var large=false
    /// `widgets-xl`: iPad's extra-large family.
    var extraLarge=false
    private func card(_ family:WidgetFamily,_ entry:TonightEntry,height:Double,mode:WidgetRenderingMode = .fullColor)->some View {
        TonightWidgetView(previewFamily:family,entry:entry).environment(\.widgetRenderingMode,mode)
            .frame(maxWidth:family == .systemSmall ? 158 : .infinity).frame(height:height).padding(16)
            .background(mode == .fullColor ? AnyView(WidgetSky(seed:entry.night?.park.id ?? "nyx",ink:.white,night:entry.night)) : AnyView(Color.black))
            .clipShape(RoundedRectangle(cornerRadius:24))
    }
    /// StandBy at night draws a widget from its luminance in deep red, with no background.
    private func standBy<Content:View>(_ content:Content)->some View {
        content.saturation(0).colorMultiply(Color(red:1,green:0.16,blue:0.12)).background(Color.black)
    }
    /// `widgets-new`: the inline Lock Screen widget, the Moon widget, a closure line and a widget set to one park.
    var newer=false
    /// `widgets-xl-portrait`: iPad's portrait extra-large family (iOS 27), at an illustrative size.
    var portrait=false
    /// The Moon widget for the shown park.
    var moon:MoonEntry?=nil
    private func with(_ entry:TonightEntry,closure:String?,pinned:Bool=false,nightVision:Bool?=nil)->TonightEntry {
        TonightEntry(date:entry.date,night:entry.night,nightVision:nightVision ?? entry.nightVision,week:entry.week,month:entry.month,
                     position:pinned ? 0 : entry.position,savedCount:pinned ? 0 : entry.savedCount,closure:closure)
    }
    private func moonCard(_ family:WidgetFamily,_ entry:MoonEntry,size:CGSize)->some View {
        MoonWidgetView(previewFamily:family,entry:entry).frame(width:size.width,height:size.height)
            .padding(family == .systemSmall ? 16 : 0)
            .background(family == .systemSmall ? AnyView(WidgetSky(seed:"moon",ink:.white)) : AnyView(Color.clear))
            .clipShape(RoundedRectangle(cornerRadius:family == .systemSmall ? 24 : 0))
    }
    var body:some View {
        ScrollView { VStack(alignment:.leading,spacing:20) {
            Text(portrait ? "Portrait extra-large widget review" : newer ? "New widgets review" : extraLarge ? "Extra-large widget review" : large ? "Large widget review" : "Widget content review").font(.system(size:20,design:.serif))
            if portrait {
                if #available(iOS 27.0,*) {
                    card(.systemExtraLargePortrait,with(entry,closure:"Keys View Road closed at night"),height:740).frame(maxWidth:380+32)
                } else { Text("Portrait extra-large needs iOS 27.").font(.caption) }
            } else if newer {
                let sample="Keys View Road closed at night"
                Text("Lock Screen: inline, Tonight and the Moon").font(.caption)
                HStack(spacing:24) {
                    TonightWidgetView(previewFamily:.accessoryInline,entry:entry).frame(height:22)
                    if let moon { MoonWidgetView(previewFamily:.accessoryInline,entry:moon).frame(height:22) }
                }.foregroundStyle(.white)
                if let moon {
                    Text("The Moon: Home Screen, Lock Screen, night vision").font(.caption)
                    HStack(spacing:16) {
                        moonCard(.systemSmall,moon,size:CGSize(width:126,height:126))
                        moonCard(.systemSmall,MoonEntry(date:moon.date,park:moon.park,nightVision:true),size:CGSize(width:126,height:126))
                        moonCard(.accessoryCircular,moon,size:CGSize(width:68,height:68))
                    }
                }
                Text("A park's closure (illustrative text)").font(.caption)
                card(.systemMedium,with(entry,closure:sample),height:158)
                card(.systemLarge,with(entry,closure:sample),height:338)
                Text("Set to one park: no \"2 of 3\"").font(.caption)
                card(.systemMedium,with(entry,closure:nil,pinned:true),height:158)
            } else if extraLarge {
                card(.systemExtraLarge,entry,height:330).frame(maxWidth:715+32)
                Text("Night vision").font(.caption)
                card(.systemExtraLarge,TonightEntry(date:entry.date,night:entry.night,nightVision:true,week:entry.week,month:entry.month,position:entry.position,savedCount:entry.savedCount),height:330).frame(maxWidth:715+32)
            } else if large {
                card(.systemLarge,entry,height:338)
                Text("Night vision").font(.caption)
                card(.systemLarge,TonightEntry(date:entry.date,night:entry.night,nightVision:true,week:entry.week,month:entry.month,position:entry.position,savedCount:entry.savedCount),height:338)
                Text("Tinted Home Screen (vibrant rendering, simulated)").font(.caption)
                card(.systemLarge,entry,height:338,mode:.vibrant).saturation(0).colorMultiply(Color(red:0.75,green:0.85,blue:1))
            } else {
                card(.systemSmall,entry,height:158)
                card(.systemMedium,entry,height:158)
                HStack(spacing:24) {
                    TonightWidgetView(previewFamily:.accessoryCircular,entry:entry).frame(width:68,height:68)
                    TonightWidgetView(previewFamily:.accessoryRectangular,entry:entry).frame(maxWidth:.infinity).frame(height:80)
                }
                Text("StandBy at night (vibrant rendering, red tint, simulated)").font(.caption)
                standBy(HStack(spacing:12) { card(.systemSmall,entry,height:158,mode:.vibrant); card(.systemSmall,TonightEntry(date:entry.date,night:entry.night,nightVision:true),height:158,mode:.vibrant) })
                standBy(card(.systemMedium,entry,height:158,mode:.vibrant))
            }
            Text("Content preview. Check the actual Home Screen, Lock Screen and StandBy hosts on device.").font(.caption)
        }.padding(24) }.defaultScrollAnchor(ProcessInfo.processInfo.arguments.contains("-nyx-bottom") ? .bottom : .top).background(Color.black)
    }
}
#endif

/// A night's dot in SwiftUI shapes, for the widgets: filled with a forecast, hollow without one,
/// and hollow with its lower half filled for an early look (the same marks as the app's calendar).
struct NightDot: View {
    let fill: NightFill
    let color: Color
    var fillOpacity = 0.6
    var lineWidth = 1.0
    var body: some View {
        switch fill {
        case .full: Circle().fill(color.opacity(fillOpacity))
        case .hollow: Circle().stroke(color, lineWidth: lineWidth)
        case .half:
            ZStack {
                Circle().fill(color.opacity(fillOpacity)).mask { VStack(spacing: 0) { Color.clear; Rectangle() } }
                Circle().stroke(color, lineWidth: lineWidth)
            }
        }
    }
}
#Preview("Night dots") {
    HStack(spacing: 16) { ForEach([NightFill.full, .half, .hollow], id: \.self) { NightDot(fill: $0, color: .orange).frame(width: 14, height: 14) } }.padding().background(.black)
}
