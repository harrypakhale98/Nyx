import AppIntents
import SwiftUI
import WidgetKit

@main struct NyxWidgetsBundle:WidgetBundle {
    var body:some Widget { TonightWidget();NightVisionControl();FieldModeControl();FieldLiveActivity();FieldAlarmLiveActivity() }
}
struct TonightProvider:TimelineProvider {
    /// The same sample sky as the gallery, so the system's redacted placeholder has the real shape
    /// of the widget rather than the empty state's copy.
    func placeholder(in context:Context)->TonightEntry {
        var builder=TonightTimeline(snapshot:Self.sample,large:context.family == .systemLarge || context.family == .systemExtraLarge)
        return builder.entry(at:.now)
    }
    func getSnapshot(in context:Context,completion:@escaping(TonightEntry)->Void) {
        var snapshot=SharedSettings.read()
        // The widget gallery shows a real sky (Joshua Tree tonight, moon and darkness only), not "save a park".
        if context.isPreview, snapshot?.parks.isEmpty ?? true { snapshot=Self.sample }
        var builder=TonightTimeline(snapshot:snapshot,large:context.family == .systemLarge || context.family == .systemExtraLarge)
        completion(builder.entry(at:.now))
    }
    /// Joshua Tree tonight, moon and darkness only. Nil only if the bundled parks cannot be read.
    static var sample:SavedSkySnapshot? {
        (try? ParkData.load().first(where:{ $0.id=="jotr" })).map { SavedSkySnapshot(parks:[$0],forecasts:[:]) }
    }
    /// Hourly entries, so "tonight" turns over at each park's own sunrise rather than hours later,
    /// plus one at each edge of a promising dusk, where the Smart Stack relevance changes.
    func getTimeline(in context:Context,completion:@escaping(Timeline<TonightEntry>)->Void) {
        let now=Date.now
        var builder=TonightTimeline(snapshot:SharedSettings.read(),large:context.family == .systemLarge || context.family == .systemExtraLarge)
        let hour=Calendar.current.dateInterval(of:.hour,for:now)?.end ?? now.addingTimeInterval(3600)
        let end=hour.addingTimeInterval(23*3600)
        let edges=builder.duskWindows(from:now,nights:2).flatMap { [$0.start,$0.end] }.filter { $0>now && $0<end }
        let dates=Set([now]+(0..<24).map { hour.addingTimeInterval(Double($0)*3600) }+edges).sorted()
        completion(Timeline(entries:dates.map { builder.entry(at:$0) },policy:.after(end)))
    }
    /// The Smart Stack's own hint (iOS 18+): the dusk of each Good or better night in the next
    /// two weeks at a saved park. Entries carry the same windows as `TimelineEntryRelevance`.
    func relevance() async -> WidgetRelevance<Void> {
        var builder=TonightTimeline(snapshot:SharedSettings.read(),large:false)
        return WidgetRelevance(builder.duskWindows(from:.now,nights:14).map { WidgetRelevanceAttribute(context:.date(interval:$0,kind:.default)) })
    }
}
/// Builds Tonight entries from the shared snapshot. Each night's sky is computed once and reused
/// across entries; the large widget's month (35 nights with shower and eclipse marks) once per night.
struct TonightTimeline {
    let snapshot:SavedSkySnapshot?
    let large:Bool
    private var skies:[String:SkyConditions]=[:]
    private var months:[String:NightPlanner.Month]=[:]
    init(snapshot:SavedSkySnapshot?,large:Bool) { self.snapshot=snapshot; self.large=large }
    private var planner:NightPlanner { NightPlanner(forecasts:snapshot?.forecasts ?? [:]) }
    /// The sky is fixed; the score is taken at the entry's date, because a forecast expires after 36 hours.
    private mutating func night(_ park:Park,_ evening:Date,at date:Date)->Night {
        let key="\(park.id)-\(evening.timeIntervalSince1970)"
        let sky=skies[key] ?? AstronomyEngine().conditions(for:park,on:evening)
        skies[key]=sky
        return planner.night(park,sky:sky,now:date)
    }
    mutating func entry(at date:Date)->TonightEntry {
        let parks=snapshot?.parks ?? []
        let tonight=parks.map { night($0,$0.currentNight(at:date),at:date) }
        let shown=WidgetSelection.pick(tonight)
        let week=shown.map { first in (0..<7).map { night(first.park,first.park.date(first.id,addingDays:$0),at:date) } } ?? []
        var month:NightPlanner.Month?
        if large, let shown {
            // Recomputed when the night turns over or the cached forecast expires (36 hours), never showing stale clouds.
            let fresh=snapshot?.forecasts[shown.park.id].map { date.timeIntervalSince($0.updated)<36*3600 } ?? false
            let key="\(shown.park.id)-\(shown.id.timeIntervalSince1970)-\(fresh)"
            month=months[key] ?? planner.month(shown.park,at:date)
            months[key]=month
        }
        let relevance=NightPlanner.relevance(at:date,nights:tonight)
        return TonightEntry(date:date,night:shown,nightVision:SharedSettings.defaults.bool(forKey:"nightVision"),week:week,month:month,
                            position:shown.map { WidgetSelection.position(of:$0,in:tonight) } ?? 0,savedCount:parks.count,
                            relevance:TimelineEntryRelevance(score:relevance.score,duration:relevance.duration))
    }
    /// Dusk windows of Good or better nights across the saved parks, `nights` nights from `start`.
    mutating func duskWindows(from start:Date,nights count:Int)->[DateInterval] {
        (snapshot?.parks ?? []).flatMap { park in
            (0..<count).compactMap { offset in NightPlanner.duskWindow(night(park,park.date(park.currentNight(at:start),addingDays:offset),at:start)) }
        }.filter { $0.end>start }
    }
}
struct TonightWidget:Widget {
    var body:some WidgetConfiguration {
        StaticConfiguration(kind:WidgetSelection.kind,provider:TonightProvider()) { entry in TonightWidgetView(entry:entry) }
            .configurationDisplayName("Tonight's sky").description("The darkest sky among your saved parks, with forecast limits shown.")
            // Extra large appears only on iPad: tonight and the month side by side.
            .supportedFamilies([.systemSmall,.systemMedium,.systemLarge,.systemExtraLarge,.accessoryCircular,.accessoryRectangular])
    }
}
struct NightVisionControl:ControlWidget {
    var body:some ControlWidgetConfiguration {
        StaticControlConfiguration(kind:"NightVisionControl",provider:NightVisionProvider()) { value in
            // The state reads in both word and symbol: "On" with a filled moon, "Off" with an outline.
            ControlWidgetToggle(isOn:value,action:NightVisionIntent()) { Text("Night vision") } valueLabel:{ isOn in
                if isOn { Label("On",systemImage:"moon.fill") } else { Label("Off",systemImage:"moon") }
            }
        }.displayName("Night vision").description("Use Nyx's red palette to reduce glare at night.")
    }
}
/// Opens field mode for the last park used in the field, or the starting park.
struct FieldModeControl:ControlWidget {
    var body:some ControlWidgetConfiguration {
        StaticControlConfiguration(kind:"FieldModeControl") {
            ControlWidgetButton(action:OpenFieldModeIntent()) { Label("Field mode",systemImage:"scope") }
        }.displayName("Field mode").description("Open Nyx's dark, red field screen for tonight.")
    }
}
struct NightVisionProvider:ControlValueProvider {
    var previewValue:Bool { false }
    func currentValue() async throws -> Bool { SharedSettings.defaults.bool(forKey:"nightVision") }
}
#Preview(as:.systemSmall) { TonightWidget() } timeline:{ TonightEntry(date:.now,night:nil,nightVision:false) }
#Preview(as:.systemMedium) { TonightWidget() } timeline:{ TonightEntry(date:.now,night:nil,nightVision:true) }
#Preview(as:.systemLarge) { TonightWidget() } timeline:{ TonightEntry(date:.now,night:nil,nightVision:false) }
#Preview(as:.accessoryCircular) { TonightWidget() } timeline:{ TonightEntry(date:.now,night:nil,nightVision:false) }
#Preview(as:.accessoryRectangular) { TonightWidget() } timeline:{ TonightEntry(date:.now,night:nil,nightVision:false) }
