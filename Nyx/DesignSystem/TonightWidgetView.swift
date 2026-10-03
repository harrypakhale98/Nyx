import SwiftUI
import WidgetKit

struct TonightEntry:TimelineEntry {
    let date:Date
    let night:Night?
    let nightVision:Bool
}
struct TonightWidgetView:View {
    @Environment(\.widgetFamily) private var systemFamily
    @Environment(\.dynamicTypeSize) private var typeSize
    var previewFamily:WidgetFamily?=nil
    private var family:WidgetFamily { previewFamily ?? systemFamily }
    let entry:TonightEntry
    private var ink:Color { entry.nightVision ? Color(red:1,green:0.27,blue:0.23) : Color(red:0.961,green:0.945,blue:0.902) }
    private var accent:Color { entry.nightVision ? ink : Color(red:1,green:0.706,blue:0.329) }
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
            .containerBackground(.black,for:.widget)
            .widgetURL(URL(string:entry.night.map{"nyx://park/\($0.park.id)"} ?? "nyx://tonight"))
    }
    private func forecastLabel(_ night:Night)->String { night.score.hasForecast ? night.score.band.label : String(localized:"Clouds unknown") }
    private func homeContent(_ night:Night)->some View {
        VStack(alignment:.leading,spacing:4) {
            if !typeSize.isAccessibilitySize { Text("TONIGHT'S SKY").font(.system(size:9,weight:.medium)).tracking(1.4) }
            Text("\(night.score.value)").font(.system(size:family == .systemMedium ? 54 : 48,weight:.light,design:.serif)).foregroundStyle(accent)
            Text(night.park.shortName).font(.system(.caption,design:.serif)).fixedSize(horizontal:false,vertical:true)
            Text(forecastLabel(night)).font(.caption2).fixedSize(horizontal:false,vertical:true)
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
    private func compactContent(_ night:Night)->some View {
        VStack(alignment:.leading,spacing:4) {
            Text("\(night.score.value)").font(.system(size:40,weight:.light,design:.serif)).foregroundStyle(accent)
            Text(night.park.shortName).font(.system(.caption2,design:.serif)).fixedSize(horizontal:false,vertical:true)
            Text(forecastLabel(night)).font(.caption2).fixedSize(horizontal:false,vertical:true)
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
    private func summary(_ night:Night)->String { String(localized:"\(night.park.shortName), \(night.score.value) out of 100, \(night.score.band.label). \(night.score.hasForecast ? String(localized:"Cached forecast included") : String(localized:"Moon and darkness only, clouds unknown"))") }
}
#if DEBUG
struct WidgetReviewView:View {
    let entry:TonightEntry
    var body:some View {
        ScrollView { VStack(alignment:.leading,spacing:20) {
            Text("Widget content review").font(.system(size:20,design:.serif))
            TonightWidgetView(previewFamily:.systemSmall,entry:entry).frame(width:158,height:158).padding(16).background(.black,in:RoundedRectangle(cornerRadius:24))
            TonightWidgetView(previewFamily:.systemMedium,entry:entry).frame(maxWidth:.infinity).frame(height:158).padding(12).background(.black,in:RoundedRectangle(cornerRadius:24))
            HStack(spacing:24) {
                TonightWidgetView(previewFamily:.accessoryCircular,entry:entry).frame(width:68,height:68)
                TonightWidgetView(previewFamily:.accessoryRectangular,entry:entry).frame(maxWidth:.infinity).frame(height:80)
            }
            Text("Content preview. Check the actual Home and Lock Screen hosts on device.").font(.caption)
        }.padding(24) }.background(Color.black)
    }
}
#endif
