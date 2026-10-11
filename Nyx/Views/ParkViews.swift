import SwiftUI


/// How a visitor reaches the night sky, for parks a car cannot simply drive to: one calm line
/// wherever a park is recommended. Nothing for the parks you can drive into.
struct AccessNoteLabel: View {
    @Environment(\.nyx) private var palette
    let park: Park
    var alignment: HorizontalAlignment = .leading
    var body: some View {
        if let note=park.accessNote {
            Label { Text(note).fixedSize(horizontal:false,vertical:true) } icon:{ Image(systemName:park.drivable ? "car.fill" : "ferry") }
                .font(.caption).foregroundStyle(palette.muted)
                .multilineTextAlignment(alignment == .center ? .center : .leading)
                .accessibilityElement(children:.ignore)
                .accessibilityLabel(String(localized:"Getting there: \(note)"))
        }
    }
}
struct ParkRow: View {
    @Environment(\.nyx) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    let night: Night
    var closure: String?=nil
    /// Tonight and the six nights after it, for the week strip.
    var week: [Night]=[]
    /// Said in the row while the Parks list is narrowed to step-free viewing, so the match is visible.
    var stepFree=false
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            // Long names wrap beside the score; only accessibility sizes stack them.
            if typeSize.isAccessibilitySize {
                VStack(alignment:.leading,spacing:14) { names; number }.frame(maxWidth:.infinity,alignment:.leading)
            } else {
                HStack(alignment:.center,spacing:16) { names.layoutPriority(1); Spacer(minLength:8); number }
            }
            if let closure { Label(closure,systemImage:"exclamationmark.triangle").font(.caption).foregroundStyle(palette.accent).fixedSize(horizontal:false,vertical:true) }
        }.padding(.vertical,14)
            .accessibilityElement(children:.ignore)
            // Short, so a list of 63 parks is quick to swipe through: the name, the score, the band and
            // any closure. The rest is a "More content" swipe away (the closure first there too).
            .accessibilityLabel(ParkRow.spokenLabel(night:night,closure:closure))
            .modifier(ParkRowContent(items:ParkRow.moreContent(night:night,closure:closure,week:week,stepFree:stepFree)))
    }
    /// "Zion. Darkness score 88, Excellent. Closure alert: Kolob Canyons Road closed."
    static func spokenLabel(night:Night,closure:String?)->String {
        let main=String(localized:"\(night.park.shortName). Darkness score \(night.score.value), \(night.score.band.label).")
        return closure.map { main+" "+String(localized:"Closure alert: \($0)") } ?? main
    }
    /// The row's custom content, most important first.
    static func moreContent(night:Night,closure:String?,week:[Night],stepFree:Bool)->[ParkRowContent.Item] {
        var items:[ParkRowContent.Item]=[]
        if let closure { items.append(.init(label:String(localized:"Closure alert"),value:closure,high:true)) }
        items.append(.init(label:String(localized:"Clouds"),value:night.basisLabel ?? String(localized:"Cloud forecast included"),high:false))
        if let summary=WeekStrip.summary(week) { items.append(.init(label:String(localized:"This week"),value:summary,high:false)) }
        if stepFree { items.append(.init(label:String(localized:"Step-free viewing"),value:String(localized:"Yes"),high:false)) }
        if !night.park.drivable { items.append(.init(label:String(localized:"Getting there"),value:String(localized:"No road access"),high:false)) }
        items.append(.init(label:String(localized:"State"),value:night.park.state.replacingOccurrences(of:",",with:", "),high:false))
        return items
    }
    private var names: some View {
        VStack(alignment:.leading,spacing:6) {
            Text(night.park.shortName).font(.system(.title3,design:.serif)).foregroundStyle(palette.ink).fixedSize(horizontal:false,vertical:true)
            Text("\(night.park.state.replacingOccurrences(of:",",with:" · "))\(night.park.darkSkyDesignated ? " · "+String(localized:"Dark Sky designated") : "")").font(.caption).foregroundStyle(palette.muted)
            if stepFree { Label("Step-free viewing",systemImage:"figure.roll").font(.caption).foregroundStyle(palette.ink).fixedSize(horizontal:false,vertical:true) }
            if !night.park.drivable { Label("No road access",systemImage:"ferry").font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true) }
            if week.count>1 { WeekStrip(nights:week).padding(.top,4) }
        }
    }
    private var number: some View {
        // The score never wraps, whatever the column width; the name beside it does.
        VStack(alignment:typeSize.isAccessibilitySize ? .leading : .trailing,spacing:2) { Text("\(night.score.value)").font(.system(.largeTitle,design:.serif)).foregroundStyle(palette.accent); Text(night.compactBandLabel).font(.caption2).foregroundStyle(palette.muted) }.fixedSize()
    }
}
/// A row's "More content" for VoiceOver (`accessibilityCustomContent`), in the items' order. One slot per
/// possible item, so the row keeps one view type whatever it holds: a slot past the end has no value,
/// which adds nothing (a nil value only removes an entry with the same id, and each slot's id is its own).
struct ParkRowContent: ViewModifier {
    struct Item: Equatable { let label: String; let value: String; let high: Bool }
    let items: [Item]
    /// The most a row says (`ParkRow.moreContent`): closure, clouds, this week, step-free, getting there, state.
    static let slots=6
    func body(content:Content)->some View {
        content
            .accessibilityCustomContent(key(0),value(0),importance:high(0) ? .high : .default)
            .accessibilityCustomContent(key(1),value(1),importance:high(1) ? .high : .default)
            .accessibilityCustomContent(key(2),value(2),importance:high(2) ? .high : .default)
            .accessibilityCustomContent(key(3),value(3),importance:high(3) ? .high : .default)
            .accessibilityCustomContent(key(4),value(4),importance:high(4) ? .high : .default)
            .accessibilityCustomContent(key(5),value(5),importance:high(5) ? .high : .default)
    }
    private func key(_ slot:Int)->AccessibilityCustomContentKey {
        AccessibilityCustomContentKey(slot<items.count ? Text(items[slot].label) : Text(verbatim:""),id:"parkRow.\(slot)")
    }
    private func value(_ slot:Int)->Text? { slot<items.count ? Text(items[slot].value) : nil }
    private func high(_ slot:Int)->Bool { slot<items.count && items[slot].high }
}
/// The Parks list's narrowing switches, kept apart from the view so they can be tested.
nonisolated struct ParkFilter {
    var darkOnly=false
    var stepFreeOnly=false
    func includes(_ park:Park,access:AccessData = .shared)->Bool {
        (!darkOnly || park.darkSkyDesignated) && (!stepFreeOnly || access.hasStepFreeViewing(park.id))
    }
}
/// Text clamped to a few lines with "More" when it runs longer; "Less" folds it again.
struct ClampedText: View {
    @Environment(\.nyx) private var palette
    let text: String
    var lines=3
    var font: Font = .subheadline
    @State private var expanded=false
    @State private var full: CGFloat=0
    @State private var clamped: CGFloat=0
    private var truncates: Bool { full>clamped+1 }
    var body: some View {
        VStack(alignment:.leading,spacing:4) {
            Text(text).font(font).foregroundStyle(palette.muted).lineLimit(expanded ? nil : lines)
                .fixedSize(horizontal:false,vertical:true)
                .onGeometryChange(for:CGFloat.self) { $0.size.height } action:{ if !expanded { clamped=$0 } }
                .background {
                    Text(text).font(font).fixedSize(horizontal:false,vertical:true).hidden()
                        .onGeometryChange(for:CGFloat.self) { $0.size.height } action:{ full=$0 }
                        .accessibilityHidden(true)
                }
            if truncates || expanded {
                Button(expanded ? "Less" : "More") { expanded.toggle() }
                    .font(font.weight(.medium)).foregroundStyle(palette.accent).frame(minHeight:44).contentShape(Rectangle())
                    .accessibilityHint(expanded ? "Shows less." : "Shows the rest.")
            }
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
}
/// "Listen to this night" and "Feel the Moon" in one row that opens, kept out of the visual path.
/// Both stay reachable as VoiceOver actions on the row, opened or not.
struct SoundAndTouchRow: View {
    @Environment(\.nyx) private var palette
    let night: Night
    var isTonight=true
    var expanded=false
    @State private var open: Bool?
    var body: some View {
        DisclosureGroup(isExpanded:Binding(get:{ open ?? expanded },set:{ open=$0 })) {
            VStack(alignment:.leading,spacing:14) {
                NightListenView(night:night,isTonight:isTonight,expanded:expanded)
                if MoonHaptics.enabled {
                    Button { feel() } label:{ Label("Feel the Moon",systemImage:"hand.tap").font(.subheadline.weight(.medium)).frame(minHeight:44).contentShape(Rectangle()) }
                        .buttonStyle(.nyxAction).foregroundStyle(palette.accent)
                        .accessibilityHint("Plays the Moon's phase as a texture: sharp, sparse taps for a new moon, a broad swell for a full moon.")
                }
            }.padding(.top,8)
        } label:{
            Label("Sound and touch",systemImage:"waveform").font(.subheadline.weight(.medium)).frame(maxWidth:.infinity,minHeight:44,alignment:.leading)
        }
        .tint(palette.accent)
        .accessibilityActions {
            Button(isTonight ? String(localized:"Listen to tonight") : String(localized:"Listen to this night")) { NightListener.shared.play(NightSonification(park:night.park,sky:night.sky)) }
            if MoonHaptics.enabled { Button("Feel the Moon") { feel() } }
        }
    }
    private func feel() { MoonHaptics.shared.play(.moon(illumination:night.sky.moon.illumination,waxing:night.sky.moon.waxing)) }
}
#Preview("Park row") { if let p=PlanModel().home { ParkRow(night:PlanModel().night(p)).padding().background(.black) } }
#Preview("Access note • boat, limited road, none") {
    let parks=(try? ParkData.load()) ?? []
    VStack(alignment:.leading,spacing:20) {
        ForEach(parks.filter { ["chis","dena","jotr"].contains($0.id) }) { park in
            VStack(alignment:.leading,spacing:4) { Text(park.shortName).font(.headline); AccessNoteLabel(park:park) }
        }
    }.padding(24).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading).background(.black).preferredColorScheme(.dark)
}
/// NPS is refusing requests (the shared hourly quota, or a struggling service): say so calmly and
/// offer the park's own current-conditions page, opened in Safari.
struct AlertsBusyNote: View {
    @Environment(\.nyx) private var palette
    let park: Park
    /// True when the summary above already says the alerts are busy.
    var summarySaysBusy=false
    var body: some View {
        VStack(alignment:.leading,spacing:4) {
            if !summarySaysBusy { Text("Park alerts are busy. Check current conditions on nps.gov.").font(.subheadline).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true) }
            if let url=BrowserLink.parkConditions(park) {
                Link(destination:url) { Label("Current conditions on nps.gov",systemImage:"safari").font(.subheadline).frame(maxWidth:.infinity,minHeight:44,alignment:.leading).contentShape(Rectangle()) }
                    .foregroundStyle(palette.accent).accessibilityHint("Opens the park's page in Safari.")
            }
        }
    }
}
#Preview("Alerts busy") { if let park=try? ParkData.load().first { AlertsBusyNote(park:park).padding(24).background(Color.black).preferredColorScheme(.dark) } }
extension SkyConditions {
    /// How much of true darkness the Moon spends below the horizon, in words: "Up through all of
    /// true darkness." rather than a bare 0%; nil on a night without true darkness.
    var moonBelowLine:String? {
        guard darkHours>0 else { return nil }
        let percent=Int((moonBelowFraction*100).rounded())
        return percent==0 ? String(localized:"Up through all of true darkness.") : String(localized:"Below the horizon for \(percent)% of true darkness.")
    }
}
