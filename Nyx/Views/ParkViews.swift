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
/// How a place from the world catalogue (`catalog.json`, from Wikidata) names itself on screen:
/// what it is, in DarkSky International's own designation names, and where it is, in the reader's
/// language. The curated parks and saved spots keep their own words (`regionLine`, `placeEyebrow`).
extension Place {
    /// "National park", or the DarkSky designation exactly as DarkSky International names it
    /// (`designationName`). Nil for a place the person saved, which says "Your spot" instead.
    var kindLabel: String? {
        switch kind {
        case .nationalPark: String(localized:"National park")
        case .custom: nil
        case .darkSkyPark, .reserve, .sanctuary, .community, .urbanNightSky: designationName
        }
    }
    /// "Catalonia, Spain"; "Colorado and Utah, United States"; "Iceland" where Wikidata gives no
    /// region. The country follows the reader's language and is never stored.
    var worldLocality: String {
        let country=StartingPlaces.countryName(countryCode)
        let parts=region.split(separator:",").map { $0.trimmingCharacters(in:.whitespaces) }.filter { !$0.isEmpty }
        let names=countryCode.uppercased()=="US" ? parts.map { StartingPlaces.stateNames[$0] ?? $0 } : parts
        guard !names.isEmpty else { return country }
        let regions=ListFormatter.localizedString(byJoining:names)
        return Park.folded(regions)==Park.folded(country) ? country : PlaceNames.joined(regions,country)
    }
    /// The eyebrow over a catalogue place's name on its page: "International Dark Sky Park · Catalonia, Spain".
    var worldEyebrow: String { kindLabel.map { String(localized:"\($0) · \(worldLocality)") } ?? worldLocality }
    /// The line under a place's name in a list: a park's states, a spot's region, a catalogue place's region and country.
    var rowLocality: String { isCatalogPlace ? worldLocality : regionLine }
    /// The Wikidata item a catalogue place comes from (`sourceURL`), linked only over HTTPS on wikidata.org.
    var wikidataURL: URL? {
        guard isCatalogPlace, let url=URL(string:sourceURL), url.scheme?.lowercased()=="https", let host=url.host()?.lowercased(),
              host=="wikidata.org" || host.hasSuffix(".wikidata.org") else { return nil }
        return url
    }
    /// What Nyx can say about closures at a place the National Park Service does not run, instead of
    /// an empty "no alerts": a catalogue place points to its own site; a saved spot to local checks.
    var unknownClosuresLine: String {
        isCatalogPlace ? String(localized:"Nyx can't check closures here. Check the park's own site before you go.")
            : String(localized:"Nyx has no alerts for this place. Check access, local rules and closures before you go.")
    }
}
/// Under the score at a catalogue place: Nyx cannot see its closures, so it says so and links the
/// park's official site (HTTPS only, `Place.website`). Opens in Safari; Nyx itself contacts nothing.
struct UnknownClosuresNote: View {
    @Environment(\.nyx) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    let park: Park
    var alignment: HorizontalAlignment = .center
    /// Tonight: the line alone, a quiet caption under the dial like the parks' alert line; the park's
    /// page sets it as a sentence with its icon and adds the link.
    var compact=false
    var body: some View {
        VStack(alignment:alignment,spacing:2) {
            if compact {
                Text(park.unknownClosuresLine).font(.caption).foregroundStyle(palette.muted).multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true)
            } else {
                Label { Text(park.unknownClosuresLine).fixedSize(horizontal:false,vertical:true) } icon:{
                    // At accessibility sizes the glyph would take a column of its own: the words alone.
                    if !typeSize.isAccessibilitySize { Image(systemName:"exclamationmark.shield").foregroundStyle(palette.caution).accessibilityHidden(true) }
                }
                .font(.subheadline).foregroundStyle(palette.ink).multilineTextAlignment(alignment == .center ? .center : .leading)
            }
            if !compact, let url=park.website {
                Link(destination:url) {
                    Label("Park website",systemImage:"safari").font(.subheadline.weight(.medium)).frame(minHeight:44).contentShape(Rectangle())
                }
                .foregroundStyle(palette.ink)
                .accessibilityHint("Opens the park's own site in Safari.")
                .accessibilityInputLabels([Text("Park website"),Text("Website")])
            }
        }
    }
}
struct ParkRow: View {
    @Environment(\.nyx) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The Little Dipper grows with the caption beside it, to 1.8× at most.
    @ScaledMetric(relativeTo:.caption2) private var dipperWidth=ParkRow.dipperWidth
    let night: Night
    var closure: String?=nil
    /// Tonight and the six nights after it, for the week strip.
    var week: [Night]=[]
    /// Said in the row while the Parks list is narrowed to step-free viewing, so the match is visible.
    var stepFree=false
    var body: some View {
        VStack(alignment:.leading,spacing:8) {
            // Long names wrap beside the score; only accessibility sizes stack them, and there tonight's
            // score follows the name straight away, before the state and the week's best night.
            if typeSize.isAccessibilitySize {
                VStack(alignment:.leading,spacing:14) { name; number; details }.frame(maxWidth:.infinity,alignment:.leading)
            } else {
                HStack(alignment:.center,spacing:16) { VStack(alignment:.leading,spacing:6) { name; details }.layoutPriority(1); Spacer(minLength:8); number }
            }
            if let closure { Label(closure,systemImage:"exclamationmark.triangle").font(.caption).labelStyle(.caution).fixedSize(horizontal:false,vertical:true) }
        }.padding(.vertical,14)
            .accessibilityElement(children:.ignore)
            // Short, so a list of 63 parks is quick to swipe through: the name, the score, the band and
            // any closure. The rest is a "More content" swipe away (the closure first there too).
            .accessibilityLabel(ParkRow.spokenLabel(night:night,closure:closure))
            .modifier(ParkRowContent(items:ParkRow.moreContent(night:night,closure:closure,week:week,stepFree:stepFree)))
    }
    /// "Zion. Darkness score 88, Excellent. Closure alert: Kolob Canyons Road closed."
    static func spokenLabel(night:Night,closure:String?)->String {
        // Smoke or haze that holds the score down is said with it ("Haze or smoke.").
        let main=Sentences.join([String(localized:"\(night.park.shortName). Darkness score \(night.score.value), \(night.score.band.label)."),night.smokeLabel.map(Sentences.end) ?? ""])
        return closure.map { main+" "+String(localized:"Closure alert: \($0)") } ?? main
    }
    /// The row's custom content, most important first.
    static func moreContent(night:Night,closure:String?,week:[Night],stepFree:Bool)->[ParkRowContent.Item] {
        var items:[ParkRowContent.Item]=[]
        if let closure { items.append(.init(label:String(localized:"Closure alert"),value:closure,high:true)) }
        items.append(.init(label:String(localized:"Clouds"),value:night.basisLabel ?? String(localized:"Cloud forecast included"),high:false))
        if let dipper=LittleDipper.reading(night) { items.append(.init(label:String(localized:"Little Dipper"),value:dipper.label,high:false)) }
        if let summary=WeekStrip.summary(week) { items.append(.init(label:String(localized:"This week"),value:summary,high:false)) }
        if stepFree { items.append(.init(label:String(localized:"Step-free viewing"),value:String(localized:"Yes"),high:false)) }
        if !night.park.drivable { items.append(.init(label:String(localized:"Getting there"),value:String(localized:"No road access"),high:false)) }
        if night.park.isSavedSpot {
            // A spot says where it is in words; far from every town on the list, it says nothing.
            if !night.park.spotLocality.isEmpty { items.append(.init(label:String(localized:"Region"),value:night.park.spotLocality,high:false)) }
        } else if night.park.isCatalogPlace {
            // A place abroad: its region and country, then what DarkSky International certified it as.
            items.append(.init(label:String(localized:"Region"),value:night.park.worldLocality,high:false))
            if night.park.darkSkyDesignated, let kind=night.park.kindLabel { items.append(.init(label:String(localized:"Dark Sky designation"),value:kind,high:false)) }
        } else { items.append(.init(label:String(localized:"State"),value:night.park.region.replacingOccurrences(of:",",with:", "),high:false)) }
        return items
    }
    private var name: some View {
        Text(night.park.shortName).font(.system(.title3,design:.serif)).foregroundStyle(palette.ink).fixedSize(horizontal:false,vertical:true)
    }
    private var details: some View {
        VStack(alignment:.leading,spacing:6) {
            Text("\(night.park.rowLocality)\(night.park.darkSkyDesignated ? " · "+String(localized:"Dark Sky designated") : "")").font(.caption).foregroundStyle(palette.muted)
            if stepFree { Label("Step-free viewing",systemImage:"figure.roll").font(.caption).foregroundStyle(palette.ink).fixedSize(horizontal:false,vertical:true) }
            if !night.park.drivable { Label("No road access",systemImage:"ferry").font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true) }
            if week.count>1 { WeekStrip(nights:week).padding(.top,4) }
        }
    }
    private var number: some View {
        // The score never wraps, whatever the column width; the name beside it does. A step above the
        // name, not three: the list is sixty-three answers, and none of them should shout.
        // Under it, the Little Dipper count in place of the band word, which VoiceOver still says first:
        // a second reading of the night rather than a restatement of the number. Without a reading
        // (no true darkness, or too far south) the band word stays; an early look or an estimate on
        // the usual clouds keeps its word under the stars, since the count does not say it.
        VStack(alignment:typeSize.isAccessibilitySize ? .leading : .trailing,spacing:2) {
            Text("\(night.score.value)").scoreNumeral(.title2,accent:palette.accent)
            if let dipper=LittleDipper.reading(night) {
                LittleDipperGlyph(reading:dipper).frame(width:min(dipperWidth,ParkRow.dipperWidth*1.8)).padding(.top,1)
                if night.basis != .forecast { Text(night.compactBandLabel).font(.caption2).foregroundStyle(palette.muted) }
            } else { Text(night.compactBandLabel).font(.caption2).foregroundStyle(palette.muted) }
        }.fixedSize()
    }
    /// The Little Dipper's width at the default text size: a little wider than a two-figure score, about 25 pt high.
    static let dipperWidth=50.0
}
/// A row's "More content" for VoiceOver (`accessibilityCustomContent`), in the items' order. One slot per
/// possible item, so the row keeps one view type whatever it holds: a slot past the end has no value,
/// which adds nothing (a nil value only removes an entry with the same id, and each slot's id is its own).
struct ParkRowContent: ViewModifier {
    struct Item: Equatable { let label: String; let value: String; let high: Bool }
    let items: [Item]
    /// The most a row says (`ParkRow.moreContent`): closure, clouds, the Little Dipper, this week,
    /// step-free, getting there, state (a place abroad: region and designation, without a week).
    static let slots=7
    func body(content:Content)->some View {
        content
            .accessibilityCustomContent(key(0),value(0),importance:high(0) ? .high : .default)
            .accessibilityCustomContent(key(1),value(1),importance:high(1) ? .high : .default)
            .accessibilityCustomContent(key(2),value(2),importance:high(2) ? .high : .default)
            .accessibilityCustomContent(key(3),value(3),importance:high(3) ? .high : .default)
            .accessibilityCustomContent(key(4),value(4),importance:high(4) ? .high : .default)
            .accessibilityCustomContent(key(5),value(5),importance:high(5) ? .high : .default)
            .accessibilityCustomContent(key(6),value(6),importance:high(6) ? .high : .default)
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
                    .font(font.weight(.medium)).foregroundStyle(palette.ink).frame(minHeight:44).contentShape(Rectangle())
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
                        .buttonStyle(.nyxAction).foregroundStyle(palette.ink)
                        .accessibilityHint("Plays the Moon's phase as a texture: sharp, sparse taps for a new moon, a broad swell for a full moon.")
                }
            }.padding(.top,8)
        } label:{
            Label("Sound and touch",systemImage:"waveform").font(.subheadline.weight(.medium)).frame(maxWidth:.infinity,minHeight:44,alignment:.leading)
        }
        .tint(palette.ink)
        .accessibilityActions {
            Button(isTonight ? String(localized:"Listen to tonight") : String(localized:"Listen to this night")) { NightListener.shared.play(NightSonification(park:night.park,sky:night.sky)) }
            if MoonHaptics.enabled { Button("Feel the Moon") { feel() } }
        }
    }
    private func feel() { MoonHaptics.shared.play(.moon(illumination:night.sky.moon.illumination,waxing:night.sky.moon.waxing)) }
}
#Preview("Park row") { if let p=PlanModel().home { ParkRow(night:PlanModel().night(p)).padding().background(.black) } }
#Preview("Park row • a place abroad") {
    let model=PlanModel()
    VStack(spacing:0) { ForEach(WorldPreview.places) { place in ParkRow(night:model.night(place)); Divider() } }.padding().background(.black).preferredColorScheme(.dark)
}
#Preview("Park row • a place abroad, AX5") {
    let model=PlanModel()
    ScrollView { ParkRow(night:model.night(WorldPreview.places[0])).padding() }.background(.black).dynamicTypeSize(.accessibility5).preferredColorScheme(.dark)
}
#Preview("Unknown closures • with and without a website") {
    VStack(spacing:28) { ForEach(WorldPreview.places) { UnknownClosuresNote(park:$0) }; UnknownClosuresNote(park:WorldPreview.places[0],compact:true) }.padding(24).frame(width:402).background(.black).preferredColorScheme(.dark)
}
#Preview("Unknown closures • night vision, AX5") {
    UnknownClosuresNote(park:WorldPreview.places[0],alignment:.leading).padding(24).background(.black)
        .environment(\.nyx,NyxPalette(nightVision:true,highContrast:false)).modifier(NightVisionFilter(enabled:true)).dynamicTypeSize(.accessibility5).preferredColorScheme(.dark)
}
/// Two catalogue places for previews, read from the bundled `catalog.json`: a Dark Sky community
/// with an HTTPS site (Fulda), and a national park with none (Tai Romyen).
enum WorldPreview {
    static let places:[Park]={
        let catalog=(try? CatalogData.load()) ?? []
        return ["wd:Q3963","wd:Q6652926"].compactMap { id in catalog.first { $0.id==id } }
    }()
}
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
                    .foregroundStyle(palette.ink).accessibilityHint("Opens the park's page in Safari.")
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
        let percent=moonDownPercent
        return percent==0 ? String(localized:"Up through all of true darkness.") : String(localized:"Below the horizon for \(percent)% of true darkness.")
    }
}
