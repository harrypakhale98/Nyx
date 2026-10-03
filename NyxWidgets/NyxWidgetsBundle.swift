import AppIntents
import SwiftUI
import WidgetKit

@main struct NyxWidgetsBundle:WidgetBundle {
    var body:some Widget { TonightWidget();NightVisionControl() }
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
            let sky=AstronomyEngine().conditions(for:park,on:park.currentNight(at:date))
            let forecast=snapshot?.forecasts[park.id]
            let clouds=forecast?.mean(from:sky.cloudWindow.start,to:sky.cloudWindow.end,now:date)
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
