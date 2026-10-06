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
}
struct TonightWidgetView:View {
    @Environment(\.widgetFamily) private var systemFamily
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.widgetRenderingMode) private var renderingMode
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
    @ViewBuilder private var content:some View {
        if let night=entry.night {
            if family == .accessoryCircular {
                // The Lock Screen ring echoes the app's celestial gauge.
                Gauge(value:Double(night.score.value),in:0...100) {
                    Image(systemName:"moon.stars")
                } currentValueLabel: {
                    Text("\(night.score.value)").font(.system(.title3,design:.serif))
                }.gaugeStyle(.accessoryCircular).summarized(summary(night))
            } else if family == .accessoryRectangular {
                // Lock Screen dimensions are fixed. Keep the complete spoken summary
                // while bounding this compact visual annotation to the host's height.
                VStack(alignment:.leading,spacing:2) {
                    Text(night.park.shortName).font(.system(.caption,design:.serif)).fixedSize(horizontal:false,vertical:true)
                    Text("\(night.score.value)/100 · \(forecastLabel(night))").font(.caption2).fixedSize(horizontal:false,vertical:true)
                }.dynamicTypeSize(.small ... .xxxLarge).summarized(summary(night))
            } else if family == .systemExtraLarge, let month=entry.month, !typeSize.isAccessibilitySize {
                extraLargeContent(night,month:month).summarized(summary(night)).overlay(alignment:.topTrailing) { cycleButton(night) }
            } else if family == .systemLarge || family == .systemExtraLarge, let month=entry.month {
                largeContent(night,month:month).summarized(summary(night)).overlay(alignment:.topTrailing) { cycleButton(night) }
            } else if family == .systemMedium && !entry.week.isEmpty && !typeSize.isAccessibilitySize {
                HStack(alignment:.top,spacing:14) {
                    homeContent(night).frame(maxWidth:132,alignment:.leading)
                    weekStrip(entry.week)
                }.summarized(summary(night)).overlay(alignment:.topTrailing) { cycleButton(night) }
            } else {
                ViewThatFits(in:.vertical) {
                    homeContent(night)
                    // Prefer full Dynamic Type; only a fixed widget footprint needs
                    // the compact fallback. The app's detail remains fully reflowing.
                    compactContent(night).dynamicTypeSize(.small ... .xxxLarge)
                }.summarized(summary(night))
            }
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
                .font(.system(size:10,weight:.medium)).foregroundStyle(ink)
                .padding(.horizontal,9).padding(.vertical,5)
                .background(ink.opacity(tinted ? 0.22 : 0.13),in:Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain).dynamicTypeSize(.small ... .large)
            .accessibilityLabel("Next saved park")
            .accessibilityValue("Showing \(night.park.shortName), \(entry.position) of \(entry.savedCount)")
        }
    }
    private func forecastLabel(_ night:Night)->String { night.score.hasForecast ? night.score.band.label : String(localized:"Clouds unknown") }
    private func homeContent(_ night:Night)->some View {
        VStack(alignment:.leading,spacing:4) {
            if !typeSize.isAccessibilitySize {
                HStack(alignment:.center) {
                    Text("TONIGHT'S SKY").font(.system(size:9,weight:.medium)).tracking(1.4).foregroundStyle(muted)
                    Spacer(minLength:4)
                    moon(night).frame(width:18,height:18)
                }
            }
            Text("\(night.score.value)").font(.system(size:48,weight:.light,design:.serif)).foregroundStyle(accent).widgetAccentable()
            Text(night.park.shortName).font(.system(.caption,design:.serif)).fixedSize(horizontal:false,vertical:true)
            Text(forecastLabel(night)).font(.caption2).foregroundStyle(muted).fixedSize(horizontal:false,vertical:true)
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
    /// The app's pre-rendered lit Moon when it exists; the vector Moon otherwise.
    @ViewBuilder private func moon(_ night:Night)->some View {
        if let url=SharedSettings.moonImageURL(park:night.park.id,night:night.id),let image=UIImage(contentsOfFile:url.path) {
            Image(uiImage:image).resizable().scaledToFit().modifier(NightVisionFilter(enabled:nightVision))
        } else {
            MoonDisc(illumination:night.sky.moon.illumination,waxing:night.sky.moon.waxing,southern:night.park.latitude<0)
                .environment(\.nyx,palette).modifier(NightVisionFilter(enabled:nightVision))
        }
    }
    /// Seven nights as small skies: the dot grows with the score, the best night gets a ring,
    /// nights without a cloud forecast are hollow.
    private func weekStrip(_ week:[Night])->some View {
        let best=week.max { $0.score.value<$1.score.value }?.id
        return VStack(alignment:.leading,spacing:6) {
            HStack(spacing:0) {
                Text("NEXT SEVEN NIGHTS").font(.system(size:9,weight:.medium)).tracking(1.4).foregroundStyle(muted).lineLimit(1).minimumScaleFactor(0.7)
                // Room for the "2 of 3" button laid over the top corner.
                Spacer(minLength:entry.savedCount>1 ? 62 : 0)
            }.frame(minHeight:entry.savedCount>1 ? 24 : nil)
            HStack(spacing:0) {
                ForEach(week) { night in
                    VStack(spacing:5) {
                        Text(night.park.weekdayInitial(night.id)).font(.system(size:10,weight:night.id==best ? .bold : .regular)).foregroundStyle(night.id==best ? ink : muted)
                        ZStack {
                            if night.id==best { Circle().stroke(accent.opacity(0.8),lineWidth:0.8).frame(width:22,height:22) }
                            let d=4+12*Double(night.score.value)/100
                            if night.score.hasForecast { Circle().fill(accent.opacity(0.45+Double(night.score.value)/200)).frame(width:d,height:d).widgetAccentable() }
                            else { Circle().stroke(accent,lineWidth:1).frame(width:d,height:d).widgetAccentable() }
                        }.frame(height:24)
                        Text("\(night.score.value)").font(.system(size:10).monospacedDigit()).foregroundStyle(muted)
                    }.frame(maxWidth:.infinity)
                }
            }
            if let top=week.first(where:{ $0.id==best }) {
                Text("Best: \(top.park.dayLabel(top.id)) · \(top.score.value)").font(.caption2).foregroundStyle(ink).lineLimit(1).minimumScaleFactor(0.8)
            }
        }
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
                Text("TONIGHT'S SKY").font(.system(size:9,weight:.medium)).tracking(1.4).foregroundStyle(muted)
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
                if month.nights.contains(where:{ $0.map { !$0.score.hasForecast } ?? false }) {
                    Circle().stroke(accent,lineWidth:1).frame(width:6,height:6)
                    Text("No forecast yet").font(.caption2).foregroundStyle(muted).lineLimit(1)
                }
            }
        }.dynamicTypeSize(.small ... .xLarge)
    }
    /// iPad's extra-large widget: tonight on the left, large enough to read across a room, and the
    /// coming nights as the same calendar of small skies on the right.
    private func extraLargeContent(_ night:Night,month:NightPlanner.Month)->some View {
        HStack(alignment:.top,spacing:28) {
            VStack(alignment:.leading,spacing:8) {
                Text("TONIGHT'S SKY").font(.system(size:10,weight:.medium)).tracking(1.4).foregroundStyle(muted)
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
            }.frame(width:200,alignment:.leading)
            VStack(alignment:.leading,spacing:8) {
                // Room for the "2 of 3" button laid over the top corner.
                Color.clear.frame(height:entry.savedCount>1 ? 18 : 0)
                monthGrid(night.park,month:month)
                if month.nights.contains(where:{ $0.map { !$0.score.hasForecast } ?? false }) {
                    HStack(spacing:6) { Circle().stroke(accent,lineWidth:1).frame(width:6,height:6); Text("No forecast yet").font(.caption2).foregroundStyle(muted) }
                }
            }
        }.dynamicTypeSize(.small ... .xLarge)
    }
    private func monthGrid(_ park:Park,month:NightPlanner.Month)->some View {
        let rows=stride(from:0,to:month.nights.count,by:7).map { Array(month.nights[$0..<min($0+7,month.nights.count)]) }
        let first=month.tonight?.id
        return Grid(horizontalSpacing:0,verticalSpacing:4) {
            GridRow {
                ForEach(0..<7,id:\.self) { column in
                    Text(weekdayInitial(park,month:month,column:column)).font(.system(size:9,weight:.medium)).foregroundStyle(muted).frame(maxWidth:.infinity)
                }
            }
            ForEach(Array(rows.enumerated()),id:\.offset) { _,row in
                GridRow {
                    ForEach(Array(row.enumerated()),id:\.offset) { _,night in
                        if let night { nightCell(night,best:night.id==month.best,tonight:night.id==first,event:month.events[night.id]) }
                        else { Color.clear.frame(height:28) }
                    }
                }
            }
        }
    }
    private func weekdayInitial(_ park:Park,month:NightPlanner.Month,column:Int)->String {
        let lead=month.nights.prefix { $0 == nil }.count
        guard let tonight=month.tonight else { return "" }
        return park.weekdayInitial(park.date(tonight.id,addingDays:column-lead))
    }
    private func nightCell(_ night:Night,best:Bool,tonight:Bool,event:WhatsUp.Events.Glyph?)->some View {
        let d=4+11*Double(night.score.value)/100
        return VStack(spacing:2) {
            Text(night.park.calendar.component(.day,from:night.id),format:.number).font(.system(size:8,weight:tonight ? .bold : .regular)).monospacedDigit()
                .foregroundStyle(tonight ? ink : muted)
            ZStack {
                if best { Circle().stroke(accent.opacity(0.85),lineWidth:0.9).frame(width:19,height:19) }
                if night.score.hasForecast { Circle().fill(accent.opacity(0.45+Double(night.score.value)/200)).frame(width:d,height:d).widgetAccentable() }
                else { Circle().stroke(accent.opacity(0.85),lineWidth:0.9).frame(width:d,height:d).widgetAccentable() }
                // Beside the dot, never on it: the dot's size is the score and must stay readable.
                if let event { SkyGlyph(event == .eclipse ? .eclipse : .meteors,color:ink).frame(width:12,height:12).offset(x:12,y:-6) }
            }.frame(height:19)
        }.frame(maxWidth:.infinity).frame(height:28)
    }
    private func summary(_ night:Night)->String {
        let tonight=String(localized:"\(night.park.shortName), \(night.score.value) out of 100, \(night.score.band.label). \(night.score.hasForecast ? String(localized:"Cached forecast included") : String(localized:"Moon and darkness only, clouds unknown"))")
        if family == .systemLarge || family == .systemExtraLarge, let month=entry.month, let best=month.best, let top=month.nights.compactMap({ $0 }).first(where:{ $0.id==best }) {
            let count=month.nights.compactMap { $0 }.count
            let events=month.nights.compactMap { $0 }.filter { month.events[$0.id] != nil }
                .map { night in String(localized:"\(month.events[night.id] == .eclipse ? String(localized:"Lunar eclipse") : String(localized:"Meteor shower peak")), \(night.park.dayLabel(night.id))") }
            return ([tonight,String(localized:"\(night.sky.moon.name), \(Int((night.sky.moon.illumination*100).rounded())) percent lit."),
                     String(localized:"Best of the next \(count) nights: \(top.park.dayLabel(top.id)), \(top.score.value).")]+events.map { $0+"." }).joined(separator:" ")
        }
        guard family == .systemMedium,let top=entry.week.max(by:{ $0.score.value<$1.score.value }) else { return tonight }
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
    var body:some View {
        ScrollView { VStack(alignment:.leading,spacing:20) {
            Text(extraLarge ? "Extra-large widget review" : large ? "Large widget review" : "Widget content review").font(.system(size:20,design:.serif))
            if extraLarge {
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
        }.padding(24) }.background(Color.black)
    }
}
#endif
