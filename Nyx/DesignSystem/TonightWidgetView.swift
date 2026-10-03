import SwiftUI
import WidgetKit

struct TonightEntry:TimelineEntry {
    let date:Date
    let night:Night?
    let nightVision:Bool
    /// Tonight and the six nights after it at the same park, for the medium widget.
    var week:[Night]=[]
}
struct TonightWidgetView:View {
    @Environment(\.widgetFamily) private var systemFamily
    @Environment(\.dynamicTypeSize) private var typeSize
    var previewFamily:WidgetFamily?=nil
    private var family:WidgetFamily { previewFamily ?? systemFamily }
    let entry:TonightEntry
    private var ink:Color { entry.nightVision ? Color(red:1,green:0.27,blue:0.23) : Color(red:0.961,green:0.945,blue:0.902) }
    private var accent:Color { entry.nightVision ? ink : Color(red:1,green:0.706,blue:0.329) }
    private var muted:Color { ink.opacity(entry.nightVision ? 0.9 : 0.7) }
    private var palette:NyxPalette { NyxPalette(nightVision:entry.nightVision,highContrast:false) }
    var body:some View {
        Group {
            if let night=entry.night {
                if family == .accessoryCircular {
                    // The Lock Screen ring echoes the app's celestial gauge.
                    Gauge(value:Double(night.score.value),in:0...100) {
                        Image(systemName:"moon.stars")
                    } currentValueLabel: {
                        Text("\(night.score.value)").font(.system(.title3,design:.serif))
                    }.gaugeStyle(.accessoryCircular)
                } else if family == .accessoryRectangular {
                    // Lock Screen dimensions are fixed. Keep the complete spoken summary
                    // while bounding this compact visual annotation to the host's height.
                    VStack(alignment:.leading,spacing:2) {
                        Text(night.park.shortName).font(.system(.caption,design:.serif)).fixedSize(horizontal:false,vertical:true)
                        Text("\(night.score.value)/100 · \(forecastLabel(night))").font(.caption2).fixedSize(horizontal:false,vertical:true)
                    }.dynamicTypeSize(.small ... .xxxLarge)
                } else if family == .systemMedium && !entry.week.isEmpty && !typeSize.isAccessibilitySize {
                    HStack(alignment:.top,spacing:14) {
                        homeContent(night).frame(maxWidth:132,alignment:.leading)
                        weekStrip(entry.week)
                    }
                } else {
                    ViewThatFits(in:.vertical) {
                        homeContent(night)
                        // Prefer full Dynamic Type; only a fixed widget footprint needs
                        // the compact fallback. The app's detail remains fully reflowing.
                        compactContent(night).dynamicTypeSize(.small ... .xxxLarge)
                    }
                }
            } else {
                ViewThatFits(in:.vertical) {
                    VStack(alignment:.leading,spacing:8) {
                        Image(systemName:"moon.stars")
                        Text("Save a park in Nyx").font(.system(.subheadline,design:.serif)).fixedSize(horizontal:false,vertical:true)
                        if family == .systemMedium { Text("Your next dark sky will appear here.").font(.caption).fixedSize(horizontal:false,vertical:true) }
                    }
                    Text("Save a park in Nyx").font(.caption).dynamicTypeSize(.small ... .xxxLarge).fixedSize(horizontal:false,vertical:true)
                }
            }
        }.foregroundStyle(ink)
            .accessibilityElement(children:.ignore)
            .accessibilityLabel(entry.night.map(summary) ?? String(localized:"Save a park in Nyx. Your next dark sky will appear here."))
            .containerBackground(for:.widget) { WidgetSky(seed:entry.night?.park.id ?? "nyx",ink:ink) }
            .widgetURL(URL(string:entry.night.map{"nyx://park/\($0.park.id)"} ?? "nyx://tonight"))
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
    private func moon(_ night:Night)->some View {
        MoonDisc(illumination:night.sky.moon.illumination,waxing:night.sky.moon.waxing,southern:night.park.latitude<0)
            .environment(\.nyx,palette).modifier(NightVisionFilter(enabled:entry.nightVision))
    }
    /// Seven nights as small skies: the dot grows with the score, the best night gets a ring,
    /// nights without a cloud forecast are hollow.
    private func weekStrip(_ week:[Night])->some View {
        let best=week.max { $0.score.value<$1.score.value }?.id
        return VStack(alignment:.leading,spacing:6) {
            Text("NEXT SEVEN NIGHTS").font(.system(size:9,weight:.medium)).tracking(1.4).foregroundStyle(muted)
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
    private func summary(_ night:Night)->String {
        let tonight=String(localized:"\(night.park.shortName), \(night.score.value) out of 100, \(night.score.band.label). \(night.score.hasForecast ? String(localized:"Cached forecast included") : String(localized:"Moon and darkness only, clouds unknown"))")
        guard family == .systemMedium,let top=entry.week.max(by:{ $0.score.value<$1.score.value }) else { return tonight }
        return tonight+" "+String(localized:"Best of the next seven nights: \(top.park.dayLabel(top.id)), \(top.score.value).")
    }
}
/// A still, seeded sky behind the widget. Widgets render once per entry, so nothing animates.
struct WidgetSky:View {
    let seed:String
    let ink:Color
    var body:some View {
        Canvas { context,size in
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
    var body:some View {
        ScrollView { VStack(alignment:.leading,spacing:20) {
            Text("Widget content review").font(.system(size:20,design:.serif))
            TonightWidgetView(previewFamily:.systemSmall,entry:entry).frame(width:158,height:158).padding(16).background(.black,in:RoundedRectangle(cornerRadius:24))
            TonightWidgetView(previewFamily:.systemMedium,entry:entry).frame(maxWidth:.infinity).frame(height:158).padding(16).background(.black,in:RoundedRectangle(cornerRadius:24))
            HStack(spacing:24) {
                TonightWidgetView(previewFamily:.accessoryCircular,entry:entry).frame(width:68,height:68)
                TonightWidgetView(previewFamily:.accessoryRectangular,entry:entry).frame(maxWidth:.infinity).frame(height:80)
            }
            Text("Content preview. Check the actual Home and Lock Screen hosts on device.").font(.caption)
        }.padding(24) }.background(Color.black)
    }
}
#endif
