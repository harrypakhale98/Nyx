import AppIntents
import SwiftUI
import WidgetKit

@main struct NyxWidgetsBundle:WidgetBundle {
    var body:some Widget { TonightWidget();NightVisionControl() }
}
struct TonightProvider:TimelineProvider {
    func placeholder(in context:Context)->TonightEntry { TonightEntry(date:.now,night:nil,nightVision:false) }
    func getSnapshot(in context:Context,completion:@escaping(TonightEntry)->Void) {
        var cache:[String:SkyConditions]=[:]
        var snapshot=SharedSettings.read()
        // The widget gallery shows a real sky (Joshua Tree tonight, moon and darkness only), not "save a park".
        if context.isPreview, snapshot?.parks.isEmpty ?? true, let sample=try? ParkData.load().first(where:{ $0.id=="jotr" }) {
            snapshot=SavedSkySnapshot(parks:[sample],forecasts:[:])
        }
        completion(entry(at:.now,snapshot:snapshot,cache:&cache))
    }
    /// Hourly entries, so "tonight" turns over at each park's own sunrise rather than hours later.
    /// Each night's sky is computed once and reused across entries.
    func getTimeline(in context:Context,completion:@escaping(Timeline<TonightEntry>)->Void) {
        let now=Date.now, snapshot=SharedSettings.read()
        let hour=Calendar.current.dateInterval(of:.hour,for:now)?.end ?? now.addingTimeInterval(3600)
        var cache:[String:SkyConditions]=[:]
        let entries=[entry(at:now,snapshot:snapshot,cache:&cache)]+(0..<24).map { entry(at:hour.addingTimeInterval(Double($0)*3600),snapshot:snapshot,cache:&cache) }
        completion(Timeline(entries:entries,policy:.after(hour.addingTimeInterval(23*3600))))
    }
    private func entry(at date:Date,snapshot:SavedSkySnapshot?,cache:inout [String:SkyConditions])->TonightEntry {
        func night(_ park:Park,_ evening:Date)->Night {
            let key="\(park.id)-\(evening.timeIntervalSince1970)"
            let sky=cache[key] ?? AstronomyEngine().conditions(for:park,on:evening)
            cache[key]=sky
            let forecast=snapshot?.forecasts[park.id]
            let clouds=forecast?.mean(from:sky.cloudWindow.start,to:sky.cloudWindow.end,now:date)
            return Night(park:park,sky:sky,score:ScoreEngine().score(sky:sky,bortle:park.bortleEstimate,cloudCover:clouds),cloudCover:clouds,forecastUpdated:clouds==nil ? nil : forecast?.updated)
        }
        let nights=(snapshot?.parks ?? []).map { night($0,$0.currentNight(at:date)) }
        let best=nights.max{$0.score.value<$1.score.value}
        let week=best.map { tonight in (0..<7).map { night(tonight.park,tonight.park.date(tonight.id,addingDays:$0)) } } ?? []
        return TonightEntry(date:date,night:best,nightVision:SharedSettings.defaults.bool(forKey:"nightVision"),week:week)
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
