import AppIntents
import SwiftUI
import WidgetKit

@main struct NyxWidgetsBundle:WidgetBundle {
    var body:some Widget { TonightWidget();NightVisionControl() }
}
struct TonightEntry:TimelineEntry {
    let date:Date
    let night:Night?
    let nightVision:Bool
}
struct TonightProvider:TimelineProvider {
    func placeholder(in context:Context)->TonightEntry { TonightEntry(date:.now,night:nil,nightVision:false) }
    func getSnapshot(in context:Context,completion:@escaping(TonightEntry)->Void) { completion(entry(at:.now)) }
    func getTimeline(in context:Context,completion:@escaping(Timeline<TonightEntry>)->Void) {
        let now=Date.now
        let entries=(0..<8).map { entry(at:now.addingTimeInterval(Double($0)*3*3600)) }
        completion(Timeline(entries:entries,policy:.after(now.addingTimeInterval(24*3600))))
    }
    private func entry(at date:Date)->TonightEntry {
        let snapshot=SharedSettings.read()
        let nights=(snapshot?.parks ?? []).map { park in
            let sky=AstronomyEngine().conditions(for:park,on:date)
            let forecast=snapshot?.forecasts[park.id]
            let clouds=forecast?.mean(from:sky.darkStart,to:sky.darkEnd,now:date)
            return Night(park:park,sky:sky,score:ScoreEngine().score(sky:sky,bortle:park.bortleEstimate,cloudCover:clouds),cloudCover:clouds,forecastUpdated:forecast?.updated)
        }
        return TonightEntry(date:date,night:nights.max{$0.score.value<$1.score.value},nightVision:SharedSettings.defaults.bool(forKey:"nightVision"))
    }
}
struct TonightWidget:Widget {
    var body:some WidgetConfiguration {
        StaticConfiguration(kind:"TonightWidget",provider:TonightProvider()) { entry in TonightWidgetView(entry:entry) }
            .configurationDisplayName("Tonight's sky").description("The darkest sky among your saved parks, with forecast limits shown.")
            .supportedFamilies([.systemSmall,.systemMedium,.accessoryCircular,.accessoryRectangular])
    }
}
struct TonightWidgetView:View {
    @Environment(\.widgetFamily) private var family
    let entry:TonightEntry
    private var ink:Color { entry.nightVision ? Color(red:1,green:0.56,blue:0.51) : Color(red:0.961,green:0.945,blue:0.902) }
    private var accent:Color { entry.nightVision ? ink : Color(red:1,green:0.706,blue:0.329) }
    var body:some View {
        Group {
            if let night=entry.night {
                if family == .accessoryCircular {
                    VStack(spacing:0) { Text("\(night.score.value)").font(.system(.title,design:.serif));Image(systemName:night.score.hasForecast ? "moon.stars" : "moon") }.accessibilityLabel(summary(night))
                } else if family == .accessoryRectangular {
                    VStack(alignment:.leading) { Text(night.park.shortName).font(.headline);Text("\(night.score.value)/100 · \(night.score.hasForecast ? night.score.band.label : String(localized:"Clouds unknown"))").font(.caption) }.accessibilityLabel(summary(night))
                } else {
                    HStack(alignment:.center,spacing:16) {
                        VStack(alignment:.leading,spacing:6) {
                            Text("TONIGHT'S SKY").font(.system(size:9,weight:.medium)).tracking(1.4)
                            Text("\(night.score.value)").font(.system(size:family == .systemMedium ? 58 : 52,weight:.light,design:.serif)).foregroundStyle(accent)
                            Text(night.park.shortName).font(.system(.subheadline,design:.serif)).lineLimit(2)
                            Text(night.score.hasForecast ? night.score.band.label : String(localized:"Clouds unknown")).font(.caption2)
                        }
                        if family == .systemMedium { Spacer(minLength:0);VStack(alignment:.trailing,spacing:10) { Image(systemName:"moonphase.waning.crescent").font(.largeTitle).foregroundStyle(accent);Text(night.park.dayLabel(night.id)).font(.caption);Text("Check access in Nyx").font(.caption2) } }
                    }.foregroundStyle(ink).accessibilityElement(children:.ignore).accessibilityLabel(summary(night))
                }
            } else {
                VStack(alignment:.leading,spacing:8) { Image(systemName:"moon.stars");Text("Save a park in Nyx").font(.system(.subheadline,design:.serif));if family == .systemMedium { Text("Your next dark sky will appear here.").font(.caption) } }.foregroundStyle(ink)
            }
        }.containerBackground(.black,for:.widget)
            .widgetURL(URL(string:entry.night.map{"nyx://park/\($0.park.id)"} ?? "nyx://tonight"))
    }
    private func summary(_ night:Night)->String { String(localized:"\(night.park.shortName), \(night.score.value) out of 100, \(night.score.band.label). \(night.score.hasForecast ? String(localized:"Cached forecast included") : String(localized:"Moon and darkness only, clouds unknown"))") }
}
struct NightVisionControl:ControlWidget {
    var body:some ControlWidgetConfiguration {
        StaticControlConfiguration(kind:"NightVisionControl",provider:NightVisionProvider()) { value in
            ControlWidgetToggle(isOn:value,action:NightVisionIntent()) { Label("Nyx night vision",systemImage:"moon") }
        }.displayName("Night vision").description("Use Nyx's red palette to reduce glare at night.")
    }
}
struct NightVisionProvider:ControlValueProvider {
    var previewValue:Bool { false }
    func currentValue() async throws -> Bool { SharedSettings.defaults.bool(forKey:"nightVision") }
}
#Preview(as:.systemSmall) { TonightWidget() } timeline:{ TonightEntry(date:.now,night:nil,nightVision:false) }
#Preview(as:.systemMedium) { TonightWidget() } timeline:{ TonightEntry(date:.now,night:nil,nightVision:true) }
#Preview(as:.accessoryCircular) { TonightWidget() } timeline:{ TonightEntry(date:.now,night:nil,nightVision:false) }
#Preview(as:.accessoryRectangular) { TonightWidget() } timeline:{ TonightEntry(date:.now,night:nil,nightVision:false) }
