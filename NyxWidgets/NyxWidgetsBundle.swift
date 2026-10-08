import AppIntents
import CoreLocation
import SwiftUI
import WidgetKit

@main struct NyxWidgetsBundle:WidgetBundle {
    var body:some Widget { TonightWidget();MoonWidget();NightVisionControl();FieldModeControl();TonightControl();FieldLiveActivity();FieldAlarmLiveActivity() }
}
struct TonightProvider:AppIntentTimelineProvider {
    /// The same sample sky as the gallery, so the system's redacted placeholder has the real shape
    /// of the widget rather than the empty state's copy.
    func placeholder(in context:Context)->TonightEntry {
        var builder=TonightTimeline(snapshot:Self.sample,large:Self.large(context.family))
        return builder.entry(at:.now)
    }
    func snapshot(for configuration:TonightWidgetIntent,in context:Context) async -> TonightEntry {
        var snapshot=SharedSettings.read()
        // The widget gallery shows a real sky (Joshua Tree tonight, with its usual clouds), not "save a park".
        if context.isPreview, snapshot?.parks.isEmpty ?? true, configuration.park == nil { snapshot=Self.sample }
        var builder=TonightTimeline(snapshot:snapshot,large:Self.large(context.family),pinned:Self.park(configuration.park))
        return builder.entry(at:.now)
    }
    /// Joshua Tree tonight, with its usual clouds. Nil only if the bundled parks cannot be read.
    static var sample:SavedSkySnapshot? {
        (try? ParkData.load().first(where:{ $0.id=="jotr" })).map { SavedSkySnapshot(parks:[$0],forecasts:[:]) }
    }
    /// The month's calendar is drawn in the large, extra-large and (iOS 27, iPad) portrait extra-large widgets.
    static func large(_ family:WidgetFamily)->Bool {
        if #available(iOS 27.0,*), family == .systemExtraLargePortrait { return true }
        return family == .systemLarge || family == .systemExtraLarge
    }
    /// The park a widget was set to follow, from the bundled library.
    static func park(_ entity:ParkEntity?)->Park? {
        guard let entity else { return nil }
        return (try? ParkData.load())?.first { $0.id==entity.id }
    }
    /// Hourly entries, so "tonight" turns over at each park's own sunrise rather than hours later,
    /// plus one at each edge of a promising dusk, where the Smart Stack relevance changes.
    func timeline(for configuration:TonightWidgetIntent,in context:Context) async -> Timeline<TonightEntry> {
        let now=Date.now
        var builder=TonightTimeline(snapshot:SharedSettings.read(),large:Self.large(context.family),pinned:Self.park(configuration.park))
        let hour=Calendar.current.dateInterval(of:.hour,for:now)?.end ?? now.addingTimeInterval(3600)
        let end=hour.addingTimeInterval(23*3600)
        let edges=builder.duskWindows(from:now,nights:2).flatMap { [$0.start,$0.end] }.filter { $0>now && $0<end }
        let dates=Set([now]+(0..<24).map { hour.addingTimeInterval(Double($0)*3600) }+edges).sorted()
        return Timeline(entries:dates.map { builder.entry(at:$0) },policy:.after(end))
    }
    /// The Smart Stack's own hints (iOS 18+): the dusk of each Good or better night in the next
    /// two weeks at a saved park, and the park itself (its first viewing spot, 25 km around), for
    /// the default widget and for one set to that park. The system matches the place; Nyx is told
    /// nothing and needs no location permission for it.
    func relevance() async -> WidgetRelevance<TonightWidgetIntent> {
        let snapshot=SharedSettings.read()
        var builder=TonightTimeline(snapshot:snapshot,large:false)
        var attributes=builder.duskWindows(from:.now,nights:14).map { WidgetRelevanceAttribute(configuration:TonightWidgetIntent(),context:.date(interval:$0,kind:.default)) }
        for park in snapshot?.parks ?? [] {
            let pinned=TonightWidgetIntent(park:ParkEntity(park))
            var one=TonightTimeline(snapshot:snapshot,large:false,pinned:park)
            attributes+=one.duskWindows(from:.now,nights:14).map { WidgetRelevanceAttribute(configuration:pinned,context:.date(interval:$0,kind:.default)) }
            let region=TonightTimeline.region(park)
            attributes+=[WidgetRelevanceAttribute(configuration:TonightWidgetIntent(),context:.location(region)),
                         WidgetRelevanceAttribute(configuration:pinned,context:.location(region))]
        }
        return WidgetRelevance(attributes)
    }
}
struct TonightWidget:Widget {
    /// iPad's portrait extra-large size where the system has it (iOS 27).
    private var families:[WidgetFamily] {
        var families:[WidgetFamily]=[.systemSmall,.systemMedium,.systemLarge,.systemExtraLarge,.accessoryCircular,.accessoryRectangular,.accessoryInline]
        if #available(iOS 27.0,*) { families.append(.systemExtraLargePortrait) }
        return families
    }
    var body:some WidgetConfiguration {
        // The same kind as before the park setting, so widgets already placed keep working (as "darkest saved park").
        AppIntentConfiguration(kind:WidgetSelection.kind,intent:TonightWidgetIntent.self,provider:TonightProvider()) { entry in TonightWidgetView(entry:entry) }
            .configurationDisplayName("Tonight's sky").description("The darkest sky among your saved parks, or one park you choose, with forecast limits and closures shown.")
            // Extra large appears only on iPad: tonight and the month side by side (portrait: tonight above the month).
            .supportedFamilies(families)
    }
}

// MARK: The Moon

struct MoonProvider:AppIntentTimelineProvider {
    func placeholder(in context:Context)->MoonEntry { MoonEntry(date:.now,park:Self.park(nil),nightVision:false) }
    func snapshot(for configuration:MoonWidgetIntent,in context:Context) async -> MoonEntry {
        MoonEntry(date:.now,park:Self.park(configuration.park),nightVision:SharedSettings.defaults.bool(forKey:"nightVision"))
    }
    /// Every hour for a day, plus each rise and set, so "up now" and the next event turn over on time.
    func timeline(for configuration:MoonWidgetIntent,in context:Context) async -> Timeline<MoonEntry> {
        let now=Date.now, park=Self.park(configuration.park), vision=SharedSettings.defaults.bool(forKey:"nightVision")
        let hour=Calendar.current.dateInterval(of:.hour,for:now)?.end ?? now.addingTimeInterval(3600)
        let end=hour.addingTimeInterval(23*3600)
        let events=park.map { MoonNow.events(at:$0,around:now).map(\.date).filter { $0>now && $0<end } } ?? []
        let dates=Set([now]+(0..<24).map { hour.addingTimeInterval(Double($0)*3600) }+events.map { $0.addingTimeInterval(1) }).sorted()
        return Timeline(entries:dates.map { MoonEntry(date:$0,park:park,nightVision:vision) },policy:.after(end))
    }
    /// The chosen park, else the first saved park, else Joshua Tree in the gallery's preview.
    static func park(_ entity:ParkEntity?)->Park? {
        let library=(try? ParkData.load()) ?? []
        if let entity { return library.first { $0.id==entity.id } }
        return SharedSettings.read()?.parks.first
    }
}
/// The Moon on the Home Screen and the Lock Screen: never stale, because it needs no forecast.
struct MoonWidget:Widget {
    var body:some WidgetConfiguration {
        AppIntentConfiguration(kind:"MoonWidget",intent:MoonWidgetIntent.self,provider:MoonProvider()) { entry in MoonWidgetView(entry:entry) }
            .configurationDisplayName("The Moon").description("Tonight's Moon: its phase, how much is lit, and when it rises or sets at your park.")
            .supportedFamilies([.systemSmall,.accessoryCircular,.accessoryInline])
    }
}

// MARK: Controls

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
/// "Tonight 93": tonight's score at a park (the darkest saved park unless one is chosen), read
/// from the widgets' snapshot. A tap opens that park. Read only: it changes nothing.
struct TonightControl:ControlWidget {
    var body:some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind:WidgetSelection.controlKind,provider:TonightControlProvider()) { value in
            ControlWidgetButton(action:OpenTonightParkIntent(parkID:value.parkID)) {
                Label {
                    Text(value.score.map { String(localized:"Tonight \($0)") } ?? String(localized:"Tonight"))
                    Text(value.name ?? String(localized:"Save a park in Nyx"))
                } icon:{ Image(systemName:value.symbol) }
            }
        }.displayName("Tonight's score").description("Tonight's darkness score at your darkest saved park, or a park you choose.")
    }
}
struct TonightControlProvider:AppIntentControlValueProvider {
    func previewValue(configuration:TonightControlIntent)->TonightControlValue { TonightControlValue(parkID:nil,name:"Joshua Tree",score:93,symbol:"moon.stars") }
    func currentValue(configuration:TonightControlIntent) async throws -> TonightControlValue {
        TonightControlValue(snapshot:SharedSettings.read(),pinned:TonightProvider.park(configuration.park),now:.now)
    }
}
#Preview(as:.systemSmall) { TonightWidget() } timeline:{ TonightEntry(date:.now,night:nil,nightVision:false) }
#Preview(as:.systemMedium) { TonightWidget() } timeline:{ TonightEntry(date:.now,night:nil,nightVision:true) }
#Preview(as:.systemLarge) { TonightWidget() } timeline:{ TonightEntry(date:.now,night:nil,nightVision:false) }
#Preview(as:.accessoryCircular) { TonightWidget() } timeline:{ TonightEntry(date:.now,night:nil,nightVision:false) }
#Preview(as:.accessoryRectangular) { TonightWidget() } timeline:{ TonightEntry(date:.now,night:nil,nightVision:false) }
#Preview(as:.accessoryInline) { TonightWidget() } timeline:{ TonightEntry(date:.now,night:nil,nightVision:false) }
#Preview(as:.systemSmall) { MoonWidget() } timeline:{ MoonEntry(date:.now,park:nil,nightVision:false) }
