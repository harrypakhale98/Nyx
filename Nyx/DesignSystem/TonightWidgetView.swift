import CoreLocation
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
    /// The shown park's closure, as the app words it beside the score (from the snapshot).
    var closure:String?=nil
    /// Set to a saved spot or world place that is no longer saved: its name ("" when unknown). The
    /// widget says so, rather than showing another place under the setting's name.
    var unsaved:String?=nil
    /// The night the previous and next buttons moved to, as nights after tonight (0 is tonight).
    var offset=0
    /// This widget's setting and size (`WidgetNightStep.scope`), where it offers previous and next
    /// night (medium and large); nil elsewhere, and the face stays on tonight.
    var stepScope:String?=nil
    /// Which "next saved place" choice this widget's button moves (`TonightTimeline.selectionScope`);
    /// nil where there is none to move (the gallery).
    var selectionScope:String?=nil
    /// The night on the face: tonight, or the night of the week the buttons moved to.
    var shown:Night? { offset>0 && offset<week.count ? week[offset] : night }
    /// The night on the face carries a soft plate in the week's column or the month's cell, tonight
    /// included, wherever night buttons can move it.
    func marks(_ candidate:Night)->Bool { stepScope != nil && candidate.id == shown?.id }
    /// What a tap on the face opens: the place on the night the face shows (`nyx://park/<id>?night=`)
    /// when that is a night ahead, so the app opens on the score the widget showed; the place
    /// itself on tonight; Tonight with nothing saved.
    static func link(face:Night?,tonight:Night?)->URL? {
        guard let face else { return URL(string:"nyx://tonight") }
        if let tonight, face.id != tonight.id { return URL(string:"nyx://park/\(face.park.id)?night=\(face.park.isoDay(face.id))") }
        return URL(string:"nyx://park/\(face.park.id)")
    }
}
/// Builds Tonight entries from the shared snapshot. Each night's sky is computed once and reused
/// across entries; the large widget's month (35 nights with shower and eclipse marks) once per night.
struct TonightTimeline {
    let snapshot:SavedSkySnapshot?
    let large:Bool
    /// A park the widget was set to; nil follows the darkest saved park.
    let pinned:Park?
    /// The widget was set to a place no longer saved (its name, or ""): every entry says so.
    var unsaved:String?=nil
    /// The widget's setting and size, where it offers previous and next night (`WidgetNightStep`).
    var stepScope:String?=nil
    /// Where the widgets keep each one's night (the App Group; a test's own suite).
    var stepDefaults:UserDefaults=SharedSettings.defaults
    /// The widget gallery's preview, which keeps no choice of its own.
    var preview=false
    /// Which "next saved place" choice a widget that follows the saved places reads (`WidgetSelection`):
    /// one per size that draws the button. Medium and large are told by their night buttons' scope,
    /// the extra large sizes by `large` without one. Nil for the small and Lock Screen widgets, which
    /// have no button and always show the darkest.
    var selectionScope:String? {
        guard pinned == nil, !preview else { return nil }
        if let stepScope { return stepScope }
        return large ? WidgetNightStep.scope(place:nil,family:"extraLarge") : nil
    }
    private var skies:[String:SkyConditions]=[:]
    private var months:[String:NightPlanner.Month]=[:]
    /// Built once: the snapshot's forecasts and the usual clouds it carries.
    private let planner:NightPlanner
    init(snapshot:SavedSkySnapshot?,large:Bool,pinned:Park?=nil,unsaved:String?=nil) {
        self.snapshot=snapshot; self.large=large; self.pinned=pinned; self.unsaved=unsaved
        planner=snapshot?.planner ?? NightPlanner(forecasts:[:])
    }
    /// The sky is fixed; the score is taken at the entry's date (its forecast never expires; it fades by lead time).
    private mutating func night(_ park:Park,_ evening:Date,at date:Date)->Night {
        let key="\(park.id)-\(evening.timeIntervalSince1970)"
        let sky=skies[key] ?? AstronomyEngine().conditions(for:park,on:evening)
        skies[key]=sky
        return planner.night(park,sky:sky,now:date)
    }
    mutating func entry(at date:Date)->TonightEntry {
        if let unsaved { return TonightEntry(date:date,night:nil,nightVision:SharedSettings.defaults.bool(forKey:NightLook.nightVisionKey),unsaved:unsaved) }
        let parks=pinned.map { [$0] } ?? snapshot?.parks ?? []
        let tonight=parks.map { night($0,$0.currentNight(at:date),at:date) }
        // A widget set to one park shows that park; otherwise the darkest saved park (or the one "next" moved to).
        let shown=pinned == nil ? WidgetSelection.pick(tonight,scope:selectionScope,defaults:stepDefaults) : tonight.first
        let week=shown.map { first in (0..<WidgetNightStep.nights).map { night(first.park,first.park.date(first.id,addingDays:$0),at:date) } } ?? []
        // The night the buttons moved to, read for each entry: one past the shown place's sunrise is tonight again.
        let offset=stepScope.flatMap { scope in shown.map { WidgetNightStep.offset(scope:scope,park:$0.park.id,tonight:$0.id,defaults:stepDefaults) } } ?? 0
        var month:NightPlanner.Month?
        if large, let shown {
            // Recomputed when the night turns over. A forecast fades by how far ahead it was made,
            // not by the entry's date, so the month is the same all night.
            let key="\(shown.park.id)-\(shown.id.timeIntervalSince1970)"
            month=months[key] ?? planner.month(shown.park,at:date)
            months[key]=month
        }
        let relevance=NightPlanner.relevance(at:date,nights:tonight)
        return TonightEntry(date:date,night:shown,nightVision:SharedSettings.defaults.bool(forKey:NightLook.nightVisionKey),week:week,month:month,
                            position:pinned == nil ? shown.map { WidgetSelection.position(of:$0,in:tonight) } ?? 0 : 0,savedCount:pinned == nil ? parks.count : 0,
                            relevance:TimelineEntryRelevance(score:relevance.score,duration:relevance.duration),
                            closure:shown.flatMap { snapshot?.closures[$0.park.id] },offset:offset,stepScope:shown == nil ? nil : stepScope,
                            selectionScope:shown == nil ? nil : selectionScope)
    }
    /// When each park the widget can show moves on to its next night (`Park.nightTurnovers`).
    func turnovers(from start:Date,to end:Date)->[Date] {
        guard unsaved == nil else { return [] }
        return (pinned.map { [$0] } ?? snapshot?.parks ?? []).flatMap { $0.nightTurnovers(from:start,to:end) }
    }
    /// Dusk windows of Good or better nights across the saved parks (or the set park), `nights` nights from `start`.
    mutating func duskWindows(from start:Date,nights count:Int)->[DateInterval] {
        guard unsaved == nil else { return [] }
        return (pinned.map { [$0] } ?? snapshot?.parks ?? []).flatMap { park in
            (0..<count).compactMap { offset in NightPlanner.duskWindow(night(park,park.date(park.currentNight(at:start),addingDays:offset),at:start)) }
        }.filter { $0.end>start }
    }
    /// Where the park is, for the Smart Stack: 25 km around its first named viewing spot (where
    /// people stand at night), or around the park's own coordinates.
    static func region(_ park:Park)->CLCircularRegion {
        let spot=park.viewingSpots.first
        let center=CLLocationCoordinate2D(latitude:spot?.latitude ?? park.latitude,longitude:spot?.longitude ?? park.longitude)
        return CLCircularRegion(center:center,radius:25_000,identifier:"nyx-\(park.id)")
    }
}
/// What the Tonight control shows ("Tonight 93", the park) and opens.
struct TonightControlValue:Sendable {
    let parkID:String?
    let name:String?
    let score:Int?
    let symbol:String
    init(parkID:String?,name:String?,score:Int?,symbol:String) { self.parkID=parkID; self.name=name; self.score=score; self.symbol=symbol }
    /// The set park's night, else the darkest saved park's (`NightPlanner.best`, as everywhere);
    /// no score before any park is saved. Never the park the widget's "next" button moved to: the
    /// control answers "where is darkest tonight", whatever a widget is showing. Darkest is the sky
    /// alone: a closure there never moves the answer, and takes the Moon's place as the symbol, as
    /// on the Lock Screen's inline widget.
    /// Set to a place no longer saved: it says so, and a tap opens Nyx.
    static let unsaved=TonightControlValue(parkID:nil,name:String(localized:"No longer saved"),score:nil,symbol:"mappin.slash")
    init(snapshot:SavedSkySnapshot?,pinned:Park?,now:Date) {
        let planner=snapshot?.planner ?? NightPlanner(forecasts:[:])
        let parks=pinned.map { [$0] } ?? snapshot?.parks ?? []
        guard let night=NightPlanner.best(parks.map { planner.night($0,on:$0.currentNight(at:now),now:now) }) else {
            self.init(parkID:nil,name:nil,score:nil,symbol:"moon.stars"); return
        }
        let closed=snapshot?.closures[night.park.id] != nil
        self.init(parkID:night.park.id,name:night.park.shortName,score:night.score.value,
                  symbol:closed ? "exclamationmark.triangle.fill" : night.sky.moon.symbolName(southern:night.park.latitude<0))
    }
}
/// A widget set to a place no longer saved (a spot deleted, a place abroad unsaved): it names the
/// place and says what to do, in every family, rather than quietly showing another place. Shared
/// by the Tonight and Moon widgets, so both say it in the same words.
struct UnsavedPlaceFace:View {
    let name:String
    let family:WidgetFamily
    let muted:Color
    var body:some View {
        let spoken=Self.summary(name)
        if family == .accessoryInline {
            Label("No longer saved",systemImage:"mappin.slash").summarized(spoken)
        } else if family == .accessoryCircular {
            ZStack { AccessoryWidgetBackground(); Image(systemName:"mappin.slash").font(.title3) }.summarized(spoken)
        } else if family == .accessoryRectangular {
            VStack(alignment:.leading,spacing:2) {
                Label("No longer saved",systemImage:"mappin.slash").font(.headline).lineLimit(1).minimumScaleFactor(0.8)
                if !name.isEmpty { Text(verbatim:name).font(.caption).lineLimit(1) }
            }.frame(maxWidth:.infinity,alignment:.leading).dynamicTypeSize(.small ... .xxxLarge).summarized(spoken)
        } else {
            ViewThatFits(in:.vertical) {
                VStack(alignment:.leading,spacing:8) {
                    Image(systemName:"mappin.slash").foregroundStyle(muted)
                    Text(Self.title(name)).font(.system(.subheadline,design:.serif)).fixedSize(horizontal:false,vertical:true)
                    Text("Save it again in Nyx, or edit the widget to choose another place.").font(.caption).foregroundStyle(muted).fixedSize(horizontal:false,vertical:true)
                }
                Text(Self.title(name)).font(.caption).dynamicTypeSize(.small ... .xxxLarge).fixedSize(horizontal:false,vertical:true)
            }.frame(maxWidth:.infinity,alignment:.leading).summarized(spoken)
        }
    }
    /// "Eifel is no longer saved in Nyx.", or without a name when the setting kept none.
    static func title(_ name:String)->String {
        name.isEmpty ? String(localized:"This place is no longer saved in Nyx.") : String(localized:"\(name) is no longer saved in Nyx.")
    }
    static func summary(_ name:String)->String {
        title(name)+" "+String(localized:"Save it again in Nyx, or edit the widget to choose another place.")
    }
}
struct TonightWidgetView:View {
    @Environment(\.widgetFamily) private var systemFamily
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiate
    /// The eyebrow's smaller step: about four fifths of caption 2, following Dynamic Type.
    @ScaledMetric(relativeTo:.caption2) private var eyebrowSmall=8.8
    var previewFamily:WidgetFamily?=nil
    private var family:WidgetFamily { previewFamily ?? systemFamily }
    let entry:TonightEntry
    /// StandBy at night, tinted Home Screens and the Lock Screen draw the widget in one tint from
    /// its luminance. There, Nyx speaks in white and opacity only (amber and red would read as
    /// mid-grey) and leaves the night-vision red to the system.
    private var tinted:Bool { renderingMode != .fullColor }
    /// The app's night look: its red (brighter by choice or under Increase Contrast) and contrast.
    private var look:NightLook { NightLook(contrast:contrast,nightVision:entry.nightVision && !tinted) }
    private var nightVision:Bool { look.nightVision }
    private var ink:Color { tinted ? .white : look.ink }
    private var accent:Color { tinted ? ink : look.accent }
    private var muted:Color { tinted ? ink.opacity(0.62) : look.muted }
    private var palette:NyxPalette { look.palette }
    /// The warning glyph's warm red in full colour, as in the app (`NyxPalette.cautionColor`); ink in
    /// night vision and on tinted faces, where the system draws the accented group in its own tint.
    private var caution:Color { tinted || nightVision ? ink : NyxPalette.cautionColor }
    var body:some View {
        content.foregroundStyle(ink)
            // The real stars over the place on the night the face shows, and a tap opens that night.
            .containerBackground(for:.widget) { WidgetSky(seed:entry.night?.park.id ?? "nyx",ink:ink,night:faceNight) }
            .widgetURL(TonightEntry.link(face:faceNight,tonight:entry.night))
    }
    /// The night the face shows: the one the night buttons moved to where they are drawn (medium
    /// outside accessibility sizes, large), else tonight.
    private var faceNight:Night? {
        let steps=entry.stepScope != nil && (family == .systemLarge || family == .systemMedium && !entry.week.isEmpty && !typeSize.isAccessibilitySize)
        return steps ? entry.shown : entry.night
    }
    /// iPad's portrait extra-large widget (iOS 27): tonight above the month.
    private var portraitXL:Bool {
        if #available(iOS 27.0,*) { return family == .systemExtraLargePortrait }
        return false
    }
    @ViewBuilder private var content:some View {
        if let night=entry.night {
            if family == .accessoryInline {
                // Above the clock: "☾ 94 Joshua Tree", tonight's phase as the symbol, or the warning sign in
                // its place when the park has a closure: this widget can follow any place, so the name stays,
                // and the spoken summary says the closure in full.
                Label { Text(verbatim:"\(night.score.value) \(night.park.shortName)") } icon:{
                    Image(systemName:entry.closure == nil ? night.sky.moon.symbolName(southern:night.park.latitude<0) : ClosureLine.symbol)
                }.summarized(summary(night))
            } else if family == .accessoryCircular {
                // The Lock Screen ring echoes the app's celestial gauge.
                // The Moon in the ring's opening is tonight's actual phase, or the warning glyph when
                // the park has a closure: the ring keeps the score, the summary says the rest.
                Gauge(value:Double(night.score.value),in:0...100) {
                    if entry.closure != nil { Image(systemName:"exclamationmark.triangle.fill").foregroundStyle(caution).widgetAccentable() } else { MoonSymbol(night:night) }
                } currentValueLabel: {
                    // Two digits inside a fixed ring: shrink rather than spill over the arc at large sizes.
                    Text("\(night.score.value)").scoreNumeral(.title3,accent:accent).minimumScaleFactor(0.6).widgetAccentable().modifier(NightTurn(value:night.score.value,reduceMotion:reduceMotion))
                }.gaugeStyle(.accessoryCircular).dynamicTypeSize(.small ... .xxxLarge).summarized(summary(night))
            } else if family == .accessoryRectangular {
                // Lock Screen dimensions are fixed: the score is the hero, the band beside it, and a
                // smaller numeral when large text would not fit. A long band ("Gut, frühe Vorschau,
                // Dunst oder Rauch") gives way to its one word (`compactBandLabel`) rather than being
                // cut. A closure adds "Closure alert" below; where three lines cannot fit, it takes the
                // band's place beside the score (the band stays in the spoken summary). The score and
                // the closure are never cut.
                ViewThatFits(in:.vertical) {
                    lockHero(night,numeral:.title)
                    lockHero(night,numeral:.title3)
                    lockHero(night,numeral:.title3,shortBand:true)
                    if entry.closure != nil { lockHero(night,numeral:.title3,closureBesideScore:true) }
                }.dynamicTypeSize(.small ... .xxxLarge).summarized(summary(night))
            } else if portraitXL, let month=entry.month, !typeSize.isAccessibilitySize {
                portraitContent(night,month:month).summarized(summary(night)).overlay(alignment:.topTrailing) { cycleButton(night) }
            } else if family == .systemExtraLarge, let month=entry.month, !typeSize.isAccessibilitySize {
                extraLargeContent(night,month:month).summarized(summary(night)).overlay(alignment:.topTrailing) { cycleButton(night) }
            } else if family == .systemLarge || family == .systemExtraLarge || portraitXL, let month=entry.month {
                // The night the buttons moved to, else tonight; the "2 of 3" button still counts tonight's places.
                let shown=entry.shown ?? night
                largeContent(shown,month:month).overlay(alignment:.topTrailing) { cycleButton(night) }
            } else if family == .systemMedium && !entry.week.isEmpty && !typeSize.isAccessibilitySize {
                let shown=entry.shown ?? night
                VStack(alignment:.leading,spacing:6) {
                    HStack(alignment:.top,spacing:14) {
                        // The one spoken summary; the week's marks and the closure line are in it, and the
                        // night buttons beside it stay buttons of their own.
                        homeContent(shown).frame(maxWidth:132,alignment:.leading).summarized(summary(shown))
                        weekStrip(entry.week)
                    }
                    closureLine(.caption2).accessibilityHidden(true)
                }.overlay(alignment:.topTrailing) { cycleButton(night) }
            } else {
                // The small widget (and medium at accessibility sizes) marks a closure in a short
                // line; the whole of it is in the spoken summary and on the park's page.
                ViewThatFits(in:.vertical) {
                    homeContent(night,closureMark:true)
                    // Prefer full Dynamic Type; only a fixed widget footprint needs
                    // the compact fallback. The app's detail remains fully reflowing.
                    compactContent(night).dynamicTypeSize(.small ... .xxxLarge)
                }.summarized(summary(night))
            }
        } else if let name=entry.unsaved {
            UnsavedPlaceFace(name:name,family:family,muted:muted)
        } else if family == .accessoryInline {
            Label("Save a place in Nyx",systemImage:"moon.stars")
                .summarized(String(localized:"Save a place in Nyx. Your next dark sky will appear here."))
        } else if family == .accessoryCircular {
            ZStack { AccessoryWidgetBackground(); Image(systemName:"moon.stars").font(.title3) }
                .summarized(String(localized:"Save a place in Nyx. Your next dark sky will appear here."))
        } else if family == .accessoryRectangular {
            VStack(alignment:.leading,spacing:2) {
                Label("Nyx",systemImage:"moon.stars").font(.headline)
                Text("Save a place in Nyx").font(.caption).lineLimit(2)
            }.frame(maxWidth:.infinity,alignment:.leading).dynamicTypeSize(.small ... .xxxLarge)
                .summarized(String(localized:"Save a place in Nyx. Your next dark sky will appear here."))
        } else {
            ViewThatFits(in:.vertical) {
                VStack(alignment:.leading,spacing:8) {
                    Image(systemName:"moon.stars")
                    Text("Save a place in Nyx").font(.system(.subheadline,design:.serif)).fixedSize(horizontal:false,vertical:true)
                    if family != .systemSmall { Text("Your next dark sky will appear here.").font(.caption).fixedSize(horizontal:false,vertical:true) }
                }
                Text("Save a place in Nyx").font(.caption).dynamicTypeSize(.small ... .xxxLarge).fixedSize(horizontal:false,vertical:true)
            }.summarized(String(localized:"Save a place in Nyx. Your next dark sky will appear here."))
        }
    }
    /// "2 of 3 ›": moves the widget to the next saved park. Only with two or more saved parks, and
    /// only where it fits (medium and large, outside accessibility sizes); a tap anywhere else opens the park.
    @ViewBuilder private func cycleButton(_ night:Night)->some View {
        if entry.savedCount>1, entry.position>0 {
            Button(intent:CycleWidgetParkIntent(scope:entry.selectionScope)) {
                HStack(spacing:3) {
                    Text("\(entry.position) of \(entry.savedCount)").monospacedDigit()
                    Image(systemName:"chevron.forward").fontWeight(.semibold)
                }
                .font(.caption2.weight(.medium)).foregroundStyle(ink)
                .padding(.horizontal,9).padding(.vertical,5)
                .background(ink.opacity(tinted ? 0.22 : 0.13),in:Capsule())
                // The capsule stays small in the corner; the tap target reaches 44 by 36 around it.
                .frame(minWidth:44,minHeight:36,alignment:.topTrailing)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).dynamicTypeSize(.small ... .large)
            .accessibilityLabel("Next saved place")
            .accessibilityValue("Showing \(night.park.shortName), \(entry.position) of \(entry.savedCount)")
        }
    }
    /// The park's closure as the app shows it beside the score: the warning glyph in its warm red, the
    /// words in starlight, so amber stays the score's. The one line a widget must not leave out. Two
    /// lines at most, the whole of it in the spoken summary. Accented as a whole on a tinted face.
    @ViewBuilder private func closureLine(_ font:Font)->some View {
        if let closure=entry.closure {
            Label { Text(closure).foregroundStyle(ink).lineLimit(2).minimumScaleFactor(0.85) } icon:{ Image(systemName:"exclamationmark.triangle.fill").foregroundStyle(caution).accessibilityHidden(true) }
                .font(font.weight(.medium)).widgetAccentable()
                .frame(maxWidth:.infinity,alignment:.leading)
        }
    }
    /// The closure in one line, drawn as the closure line is, where its words do not fit whole (the small
    /// widget and the Lock Screen): the park's own words cut by the line ("⚠ Keys View Road closed…"),
    /// never a bare "Closure alert", which read as the whole park closed when only a road was.
    @ViewBuilder private func closureMark(_ font:Font)->some View {
        if let closure=entry.closure {
            Label { Text(closure).foregroundStyle(ink).lineLimit(1).minimumScaleFactor(0.85) } icon:{ Image(systemName:"exclamationmark.triangle.fill").foregroundStyle(caution).accessibilityHidden(true) }
                .font(font.weight(.medium)).widgetAccentable()
        }
    }
    /// The small and medium widgets' eyebrow, never cut: spaced capitals where they fit, then a
    /// little smaller (English, as before), then set solid on two lines where one is not enough
    /// ("PRÓXIMAS SIETE / NOCHES", "NÄCHSTE SIEBEN / NÄCHTE"). Each step is measured whole, where a
    /// shrinking single line used to end in "…". Japanese is set solid throughout (`Lettering`).
    /// `shorter`, where given, is tried on one line before the two-line form ("Next 7 nights").
    private func eyebrow(_ text:LocalizedStringKey,shorter:LocalizedStringKey?=nil)->some View { eyebrow(Text(text),shorter:shorter.map { Text($0) }) }
    private func eyebrow(_ text:Text,shorter:Text?=nil)->some View {
        let caps=Lettering.spaced, regular=Font.caption2.weight(.medium), small=Font.system(size:eyebrowSmall,weight:.medium), brief=shorter ?? text
        return ViewThatFits(in:.horizontal) {
            text.textCase(caps ? .uppercase : nil).tracking(caps ? 0.8 : 0).font(regular).lineLimit(1)
            text.textCase(caps ? .uppercase : nil).tracking(caps ? 0.8 : 0).font(small).lineLimit(1)
            brief.textCase(caps ? .uppercase : nil).tracking(caps ? 0.8 : 0).font(regular).lineLimit(1)
            brief.textCase(caps ? .uppercase : nil).tracking(caps ? 0.8 : 0).font(small).lineLimit(1)
            text.textCase(caps ? .uppercase : nil).font(small).lineLimit(2).minimumScaleFactor(0.8)
        }.foregroundStyle(muted)
    }
    /// The band word as the iPhone dial sets it (serif, in ink, a step quieter than the numeral).
    private func band(_ night:Night,_ style:Font.TextStyle)->some View {
        Text(night.score.band.label).bandWord(style,ink:ink).fixedSize(horizontal:false,vertical:true).modifier(NightTurn(reduceMotion:reduceMotion))
    }
    /// What the score rests on ("Early look", "Haze or smoke"), muted, on a line of its own; nothing
    /// on a night with a full forecast.
    @ViewBuilder private func basisNote(_ night:Night,_ font:Font)->some View {
        if let note=night.basisNote { Text(note).font(font).foregroundStyle(muted).fixedSize(horizontal:false,vertical:true).modifier(NightTurn(reduceMotion:reduceMotion)) }
    }
    /// The band beside a numeral, with the note under it.
    private func bandBeside(_ night:Night,_ style:Font.TextStyle,note:Font)->some View {
        VStack(alignment:.leading,spacing:0) { band(night,style); basisNote(night,note) }
    }
    /// The month grid's key for its hollow nights, in the words the app gives the first of them
    /// (`Night.basisLabel`): "Cloud forecast unavailable" when a forecast should reach it, else
    /// "No cloud forecast yet". Nil when every night has clouds.
    private func hollowLabel(_ month:NightPlanner.Month)->String? {
        month.nights.compactMap { $0 }.first { $0.basis == .usual }?.basisLabel
    }
    /// The Lock Screen rectangle: the park, then the score as the hero with its band beside it,
    /// then a closure's mark. `closureBesideScore` puts the mark in the band's place, for two lines;
    /// `shortBand` shows the band's one word where its whole line would not fit.
    private func lockHero(_ night:Night,numeral:Font.TextStyle,closureBesideScore:Bool=false,shortBand:Bool=false)->some View {
        VStack(alignment:.leading,spacing:0) {
            // Serif, as the park's name is on every other face.
            Text(night.park.shortName).font(.system(.headline,design:.serif)).lineLimit(1)
            HStack(alignment:.firstTextBaseline,spacing:6) {
                Text("\(night.score.value)").scoreNumeral(numeral,accent:accent).widgetAccentable().modifier(NightTurn(value:night.score.value,reduceMotion:reduceMotion))
                if closureBesideScore { closureMark(.caption) }
                else if shortBand { Text(night.compactBandLabel).font(.caption).lineLimit(1).minimumScaleFactor(0.8) }
                // Unlimited here, so a band that needs a third line does not fit and the short word is chosen.
                else { Text(night.bandWithBasis).font(.caption).fixedSize(horizontal:false,vertical:true) }
            }
            if !closureBesideScore { closureMark(.caption) }
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
    /// `closureMark` puts "Closure alert" in the eyebrow's place (the small widget); the medium
    /// widget shows the closure's own words below instead. The Moon rides the widget's top trailing
    /// corner on the small widget; on the medium one, whose corner belongs to the week, it sits just
    /// after the eyebrow, never floating mid-row at the edge of a narrow column.
    private func homeContent(_ night:Night,closureMark mark:Bool=false)->some View {
        let pinned=family == .systemSmall
        return VStack(alignment:.leading,spacing:4) {
            if !typeSize.isAccessibilitySize {
                HStack(alignment:.center,spacing:6) {
                    if mark && entry.closure != nil { closureMark(.caption2) }
                    else { nightEyebrow(night) }
                    if pinned { Spacer(minLength:4) }
                    moon(night).frame(width:18,height:18).id(night.id)
                    if !pinned { Spacer(minLength:0) }
                }
            } else if mark { closureMark(.caption2) }
            // The band word straight under the numeral, as on the dial.
            VStack(alignment:.leading,spacing:0) {
                Text("\(night.score.value)").scoreNumeral(size:48,accent:accent).widgetAccentable()
                    .modifier(NightTurn(value:night.score.value,reduceMotion:reduceMotion))
                band(night,.subheadline)
            }
            Text(night.park.shortName).font(.system(.caption,design:.serif)).fixedSize(horizontal:false,vertical:true)
            basisNote(night,.caption2)
        }.frame(maxWidth:.infinity,alignment:.leading)
        // While a night button's tap is being answered, the system marks what is about to change.
        .invalidatableContent(entry.stepScope != nil)
    }
    /// "Tonight's sky", or the night the buttons moved to ("Sat, Oct 17"), always in words.
    private func nightEyebrow(_ night:Night)->some View {
        Group {
            if isTonight(night) { eyebrow("Tonight's sky") }
            else { eyebrow(Text(verbatim:night.park.dayLabel(night.id))) }
        }.modifier(NightTurn(reduceMotion:reduceMotion))
    }
    private func isTonight(_ night:Night)->Bool { entry.night.map { $0.id == night.id } ?? true }
    /// Previous and next night (medium and large, `WidgetNightStep`): a pair of chevrons in one
    /// capsule, as the "2 of 3" button is drawn. Tonight has no previous night and the week's last
    /// night no next one: that chevron is dimmed and is not a button, and VoiceOver skips it.
    @ViewBuilder private func nightStepper(_ shown:Night)->some View {
        if let scope=entry.stepScope, let tonight=entry.night, entry.week.count>1 {
            let last=entry.week.count-1
            HStack(spacing:0) {
                stepButton(scope:scope,tonight:tonight,shown:shown,to:entry.offset-1,enabled:entry.offset>0,symbol:"chevron.backward",label:"Previous night")
                stepButton(scope:scope,tonight:tonight,shown:shown,to:entry.offset+1,enabled:entry.offset<last,symbol:"chevron.forward",label:"Next night")
            }
            .background(ink.opacity(tinted ? 0.22 : 0.13),in:Capsule())
            .dynamicTypeSize(.small ... .large)
        }
    }
    /// Each chevron draws 36 by 28 inside the capsule, and its tap target is 44 by 44: 8 pt more on
    /// the capsule's outer side (the two targets meet at its middle, never overlapping), 12 above
    /// (the widget's top margin) and 4 below (short of the week's initials). Transparent padding,
    /// taken back by negative padding, so the capsule and the layout around it keep their size.
    @ViewBuilder private func stepButton(scope:String,tonight:Night,shown:Night,to offset:Int,enabled:Bool,symbol:String,label:LocalizedStringKey)->some View {
        let glyph=Image(systemName:symbol).font(.caption.weight(.semibold)).frame(width:36,height:28)
        let outer:Edge.Set=offset<entry.offset ? .leading : .trailing
        if enabled {
            Button(intent:StepWidgetNightIntent(scope:scope,park:tonight.park.id,tonight:tonight.id,offset:offset)) {
                glyph.foregroundStyle(ink)
                    .padding(outer,StepTarget.side).padding(.top,StepTarget.above).padding(.bottom,StepTarget.below)
                    .contentShape(Rectangle())
            }
                .buttonStyle(.plain)
                .padding(outer,-StepTarget.side).padding(.top,-StepTarget.above).padding(.bottom,-StepTarget.below)
                .accessibilityLabel(label)
                // Where the widget is now, since the face's own summary is a separate element.
                .accessibilityValue(isTonight(shown) ? Text("Tonight") : Text(verbatim:shown.park.dayLabel(shown.id)))
        } else {
            glyph.foregroundStyle(ink.opacity(0.3)).accessibilityHidden(true)
        }
    }
    /// The night buttons' transparent reach past each 36 by 28 chevron, to a 44 by 44 target.
    private enum StepTarget {
        static let side:CGFloat=8, above:CGFloat=12, below:CGFloat=4
    }
    /// The app's pre-rendered lit Moon when it exists; the vector Moon, rendered to an image,
    /// otherwise. An image either way, so a tinted or clear Home Screen can draw it desaturated
    /// with its terminator intact instead of flattening it to a solid disc.
    @ViewBuilder private func moon(_ night:Night)->some View {
        if let image=moonImage(night) {
            Image(uiImage:image).resizable().widgetAccentedRenderingMode(.accentedDesaturated).scaledToFit()
                .accessibilityIgnoresInvertColors().modifier(NightVisionFilter(enabled:nightVision,red:look.red))
        } else {
            MoonDisc(illumination:night.sky.moon.illumination,waxing:night.sky.moon.waxing,southern:night.park.latitude<0)
                .environment(\.nyx,palette).modifier(NightVisionFilter(enabled:nightVision,red:look.red))
        }
    }
    private func moonImage(_ night:Night)->UIImage? {
        // The night's own picture (the app draws a week ahead), else the vector Moon: never another night's phase.
        if let url=SharedSettings.moonImage(park:night.park.id,night:night.id),let image=UIImage(contentsOfFile:url.path) { return image }
        let renderer=ImageRenderer(content:MoonDisc(illumination:night.sky.moon.illumination,waxing:night.sky.moon.waxing,southern:night.park.latitude<0)
            .environment(\.nyx,palette).frame(width:34,height:34))
        renderer.scale=displayScale
        return renderer.uiImage
    }
    /// Seven nights as small skies, as the app's week strip draws them: the dot grows with the score
    /// across the week's own range, the best night gets a ring, early looks are half-filled and
    /// nights without a cloud forecast hollow.
    private func weekStrip(_ week:[Night])->some View {
        let best=NightPlanner.best(week)?.id
        let scores=week.map(\.score.value), low=scores.min() ?? 0, high=scores.max() ?? 0
        return VStack(alignment:.leading,spacing:6) {
            HStack(spacing:0) {
                // With night buttons, they lead the row and the week's columns say the rest.
                if entry.stepScope != nil, let night=entry.shown { nightStepper(night) }
                else { eyebrow("Next seven nights",shorter:"Next 7 nights").accessibilityHidden(true) }
                // Room for the "2 of 3" button laid over the top corner.
                Spacer(minLength:entry.savedCount>1 ? 62 : 0)
            }.frame(minHeight:entry.savedCount>1 ? 24 : nil)
            HStack(spacing:0) {
                ForEach(week) { night in
                    VStack(spacing:5) {
                        Text(night.park.weekdayInitial(night.id)).font(.caption2.weight(night.id==best ? .bold : .regular)).foregroundStyle(night.id==best ? ink : muted)
                        ZStack {
                            if night.id==best { Circle().stroke(accent.opacity(0.8),lineWidth:0.8).frame(width:22,height:22) }
                            // 8 pt at most, so the 11 pt ring stays just outside the largest dot, as in the app.
                            let d=2*NightMark.drawnRadius(NightMark.radius(score:night.score.value,low:low,high:high,largest:8),fill:night.basis.fill,lineWidth:1,stroke:1)
                            NightDot(fill:night.basis.fill,color:accent,fillOpacity:palette.markOpacity(score:night.score.value),lineWidth:palette.stroke,mark:NightMark.mark(night,differentiate:differentiate)).frame(width:d,height:d).widgetAccentable()
                        }.frame(height:24)
                        Text("\(night.score.value)").font(.caption2.monospacedDigit()).foregroundStyle(muted).lineLimit(1).minimumScaleFactor(0.8)
                    }.frame(maxWidth:.infinity)
                    // The night on the face, where the buttons can move it.
                    .background { if entry.marks(night) { RoundedRectangle(cornerRadius:8).fill(ink.opacity(tinted ? 0.2 : 0.12)) } }
                }
            }.accessibilityHidden(true)
            // A closure takes this line's room below; the ring already marks the best night.
            if entry.closure == nil, let line=WeekBest.label(week) {
                Text(line).font(.caption2).foregroundStyle(ink).lineLimit(1).minimumScaleFactor(0.8)
                    .accessibilityHidden(true)
            }
        }.dynamicTypeSize(...DynamicTypeSize.large) // Seven fixed columns: 11 pt text that always fits.
    }
    private func compactContent(_ night:Night)->some View {
        VStack(alignment:.leading,spacing:4) {
            closureMark(.caption2)
            // In the accent group as on every other face, so a tinted Home Screen keeps the score its hero.
            VStack(alignment:.leading,spacing:0) {
                Text("\(night.score.value)").scoreNumeral(size:40,accent:accent).widgetAccentable().modifier(NightTurn(value:night.score.value,reduceMotion:reduceMotion))
                band(night,.footnote)
            }
            Text(night.park.shortName).font(.system(.caption2,design:.serif)).fixedSize(horizontal:false,vertical:true)
            basisNote(night,.caption2)
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
    /// The large widget: tonight at the shown park, then its coming nights as a calendar of small
    /// skies (the same marks as the app's calendar: size for score, hollow without a forecast, a
    /// ring on the best, a glyph on shower peaks and eclipses).
    private func largeContent(_ night:Night,month:NightPlanner.Month)->some View {
        VStack(alignment:.leading,spacing:10) {
            HStack(spacing:0) {
                // A closure takes the eyebrow's place, so the month keeps its room. On another night
                // the night's date leads, and the closure's mark takes the best night's line below
                // (its words are in the spoken summary, and back on tonight's face).
                Group {
                    if !isTonight(night) { largeEyebrow(Text(verbatim:night.park.dayLabel(night.id))) }
                    else if entry.closure != nil { closureLine(.caption2) }
                    else { largeEyebrow(Text("Tonight's sky")) }
                }.accessibilityHidden(true)
                Spacer(minLength:6)
                nightStepper(night)
                // Room for the "2 of 3" button laid over the top corner.
                if entry.savedCount>1 { Color.clear.frame(width:entry.stepScope == nil ? 64 : 78,height:1) }
            }.frame(minHeight:entry.savedCount>1 ? 24 : nil)
            VStack(alignment:.leading,spacing:10) {
                HStack(alignment:.center,spacing:12) {
                    VStack(alignment:.leading,spacing:0) {
                        Text(night.park.shortName).font(.system(.headline,design:.serif)).lineLimit(1).minimumScaleFactor(0.8)
                        HStack(alignment:.firstTextBaseline,spacing:8) {
                            Text("\(night.score.value)").scoreNumeral(size:44,accent:accent).widgetAccentable()
                                .modifier(NightTurn(value:night.score.value,reduceMotion:reduceMotion))
                            bandBeside(night,.subheadline,note:.caption)
                        }
                    }
                    Spacer(minLength:4)
                    VStack(alignment:.trailing,spacing:3) {
                        moon(night).frame(width:34,height:34).id(night.id)
                        Text(night.sky.moon.name).font(.caption2)
                        Text(night.sky.moon.litText).font(.caption2).foregroundStyle(muted)
                    }
                }.invalidatableContent(entry.stepScope != nil)
                monthGrid(night.park,month:month,shown:entry.marks(night) ? night.id : nil)
                HStack(spacing:6) {
                    // The ring already marks the best night; a closure the header cannot hold takes its line.
                    if !isTonight(night), entry.closure != nil { closureMark(.caption2) }
                    else if let best=month.best, let top=month.nights.compactMap({ $0 }).first(where:{ $0.id==best }) {
                        Text("Best: \(top.park.dayLabel(top.id)) · \(top.score.value)").font(.caption2).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    Spacer(minLength:4)
                    if let hollow=hollowLabel(month) {
                        Circle().stroke(accent,lineWidth:1).frame(width:6,height:6)
                        Text(hollow).font(.caption2).foregroundStyle(muted).lineLimit(1)
                    }
                }
            }.summarized(summary(night))
        }.dynamicTypeSize(.small ... .xLarge)
    }
    private func largeEyebrow(_ text:Text)->some View {
        text.textCase(Lettering.spaced ? .uppercase : nil).font(.caption2.weight(.medium)).tracking(Lettering.spaced ? 1.2 : 0).foregroundStyle(muted)
            .lineLimit(1).minimumScaleFactor(0.8).accessibilityHidden(true).modifier(NightTurn(reduceMotion:reduceMotion))
    }
    /// iPad's extra-large widget: tonight on the left, large enough to read across a room, and the
    /// coming nights as the same calendar of small skies on the right.
    private func extraLargeContent(_ night:Night,month:NightPlanner.Month)->some View {
        HStack(alignment:.top,spacing:28) {
            VStack(alignment:.leading,spacing:8) {
                Text("Tonight's sky").textCase(Lettering.spaced ? .uppercase : nil).font(.caption.weight(.medium)).tracking(Lettering.spaced ? 1.4 : 0).foregroundStyle(muted)
                Text(night.park.shortName).font(.system(.title3,design:.serif)).lineLimit(2).minimumScaleFactor(0.8)
                Text("\(night.score.value)").scoreNumeral(size:72,accent:accent).widgetAccentable().modifier(NightTurn(value:night.score.value,reduceMotion:reduceMotion))
                VStack(alignment:.leading,spacing:0) { band(night,.title3); basisNote(night,.subheadline) }
                // Directly under the score, before the Moon and the month's best, as the spoken summary says it.
                closureLine(.caption).padding(.top,4)
                HStack(alignment:.center,spacing:10) {
                    moon(night).frame(width:34,height:34)
                    VStack(alignment:.leading,spacing:2) {
                        Text(night.sky.moon.name).font(.caption)
                        Text(night.sky.moon.litText).font(.caption2).foregroundStyle(muted)
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
                if let hollow=hollowLabel(month) {
                    HStack(spacing:6) { Circle().stroke(accent,lineWidth:1).frame(width:6,height:6); Text(hollow).font(.caption2).foregroundStyle(muted) }
                }
            }
        }.dynamicTypeSize(.small ... .xLarge)
    }
    /// iPad's portrait extra-large widget (iOS 27): tonight above, large enough to read across a
    /// room, then the coming nights as the calendar of small skies, then what the marks mean.
    private func portraitContent(_ night:Night,month:NightPlanner.Month)->some View {
        VStack(alignment:.leading,spacing:14) {
            HStack(spacing:0) {
                Text("Tonight's sky").textCase(Lettering.spaced ? .uppercase : nil).font(.caption.weight(.medium)).tracking(Lettering.spaced ? 1.4 : 0).foregroundStyle(muted)
                Spacer(minLength:entry.savedCount>1 ? 70 : 0)
            }.frame(minHeight:entry.savedCount>1 ? 24 : nil)
            HStack(alignment:.center,spacing:16) {
                VStack(alignment:.leading,spacing:2) {
                    Text(night.park.shortName).font(.system(.title2,design:.serif)).lineLimit(2).minimumScaleFactor(0.8)
                    HStack(alignment:.firstTextBaseline,spacing:10) {
                        Text("\(night.score.value)").scoreNumeral(size:80,accent:accent).widgetAccentable().modifier(NightTurn(value:night.score.value,reduceMotion:reduceMotion))
                        bandBeside(night,.title3,note:.subheadline)
                    }
                }
                Spacer(minLength:8)
                VStack(alignment:.center,spacing:4) {
                    moon(night).frame(width:56,height:56)
                    Text(night.sky.moon.name).font(.caption)
                    Text(night.sky.moon.litText).font(.caption2).foregroundStyle(muted)
                }
            }
            closureLine(.subheadline)
            Spacer(minLength:0)
            monthGrid(night.park,month:month,scale:1.4)
            Spacer(minLength:0)
            HStack(spacing:6) {
                if let best=month.best, let top=month.nights.compactMap({ $0 }).first(where:{ $0.id==best }) {
                    Text("Best: \(top.park.dayLabel(top.id)) · \(top.score.value)").font(.caption).lineLimit(1).minimumScaleFactor(0.8)
                }
                Spacer(minLength:4)
                if let hollow=hollowLabel(month) {
                    Circle().stroke(accent,lineWidth:1).frame(width:6,height:6)
                    Text(hollow).font(.caption2).foregroundStyle(muted).lineLimit(1)
                }
            }
        }.dynamicTypeSize(.small ... .xLarge)
    }
    /// `scale` enlarges the cells, rings and dots together (the portrait extra-large widget).
    /// `shown` marks the night on the face, where night buttons can move it.
    private func monthGrid(_ park:Park,month:NightPlanner.Month,scale:Double=1,shown:Date?=nil)->some View {
        let rows=stride(from:0,to:month.nights.count,by:7).map { Array(month.nights[$0..<min($0+7,month.nights.count)]) }
        let first=month.tonight?.id
        return Grid(horizontalSpacing:0,verticalSpacing:4*scale) {
            GridRow {
                ForEach(0..<7,id:\.self) { column in
                    Text(weekdayInitial(park,month:month,column:column)).font((scale>1 ? Font.caption : .caption2).weight(.medium)).foregroundStyle(muted).frame(maxWidth:.infinity)
                }
            }
            ForEach(Array(rows.enumerated()),id:\.offset) { _,row in
                GridRow {
                    ForEach(Array(row.enumerated()),id:\.offset) { _,night in
                        if let night { nightCell(night,best:night.id==month.best,tonight:night.id==first,event:month.events[night.id],scale:scale,shown:night.id==shown) }
                        else { Color.clear.frame(height:28*scale) }
                    }
                }
            }
        }.dynamicTypeSize(...DynamicTypeSize.large) // Fixed 28 pt cells: 11 pt numerals, never clipped.
    }
    private func weekdayInitial(_ park:Park,month:NightPlanner.Month,column:Int)->String {
        let lead=month.nights.prefix { $0 == nil }.count
        guard let tonight=month.tonight else { return "" }
        return park.weekdayInitial(park.date(tonight.id,addingDays:column-lead))
    }
    private func nightCell(_ night:Night,best:Bool,tonight:Bool,event:WhatsUp.Events.Glyph?,scale:Double=1,shown:Bool=false)->some View {
        let d=(4+9*Double(night.score.value)/100)*scale
        return VStack(spacing:0) {
            Text(night.park.calendar.component(.day,from:night.id),format:.number).font((scale>1 ? Font.caption : .caption2).weight(tonight ? .bold : .regular)).monospacedDigit()
                .foregroundStyle(tonight ? ink : muted)
            ZStack {
                if best { Circle().stroke(accent.opacity(0.85),lineWidth:0.9).frame(width:17*scale,height:17*scale) }
                NightDot(fill:night.basis.fill,color:accent.opacity(night.basis.fill == .full ? 1 : 0.85),fillOpacity:palette.markOpacity(score:night.score.value),lineWidth:0.9*palette.stroke,mark:NightMark.mark(night,differentiate:differentiate)).frame(width:d,height:d).widgetAccentable()
                // Beside the dot, never on it: the dot's size is the score and must stay readable.
                if let event { SkyGlyph(event == .eclipse ? .eclipse : .meteors,color:ink).frame(width:12*scale,height:12*scale).offset(x:13*scale,y:-3*scale) }
                // The best night's ring fits here; the cell stays 28 pt and spills into the row gap, so the month keeps its height.
            }.frame(height:17*scale)
        }.frame(maxWidth:.infinity).frame(height:28*scale)
            .background { if shown { RoundedRectangle(cornerRadius:6).fill(ink.opacity(tinted ? 0.2 : 0.12)).padding(.horizontal,2) } }
    }
    private func summary(_ night:Night)->String { Self.summary(night,entry:entry,family:family) }
    /// What VoiceOver says for the widget: the park, its score and band, then any closure in full
    /// in every family (the Lock Screen and the small widget show only its mark), right after the
    /// score it stands beside, as the watch says it; then what the score rests on, and what the
    /// larger families add.
    static func summary(_ night:Night,entry:TonightEntry,family:WidgetFamily)->String {
        // Another night of the week, moved to with the night buttons: its date, then its Moon.
        let ahead=entry.night.map { $0.id != night.id } ?? false
        // The watch's complications say the same words (`Night.widgetSummary`).
        var tonight=night.widgetSummary(closure:entry.closure,ahead:ahead)
        var portraitXL=false
        if #available(iOS 27.0,*) { portraitXL = family == .systemExtraLargePortrait }
        if family == .systemLarge || family == .systemExtraLarge || portraitXL, let month=entry.month, let best=month.best, let top=month.nights.compactMap({ $0 }).first(where:{ $0.id==best }) {
            let count=month.nights.compactMap { $0 }.count
            let events=month.nights.compactMap { $0 }.filter { month.events[$0.id] != nil }
                .map { night in String(localized:"\(month.events[night.id] == .eclipse ? String(localized:"Lunar eclipse") : String(localized:"Meteor shower peak")), \(night.park.dayLabel(night.id))") }
            return ([tonight,Sentences.end(night.sky.moon.spoken),
                     String(localized:"Best of the next \(count) nights: \(top.park.dayLabel(top.id)), \(top.score.value).")]+events.map { $0+"." }).joined(separator:" ")
        }
        if ahead { tonight+=" "+Sentences.end(night.sky.moon.spoken) }
        // The week's best as the strip shows it (`WeekBest`), "every night" included.
        guard family == .systemMedium,let week=WeekBest.label(entry.week) else { return tonight }
        return tonight+" "+Sentences.end(week)
    }
}
private extension View {
    /// One spoken summary for the widget's information; a button beside it stays its own element.
    func summarized(_ label:String)->some View { accessibilityElement(children:.ignore).accessibilityLabel(label) }
}
/// How a night's words and score change when the night buttons move the face: the numeral rolls
/// to the new score, the words cross-fade; under Reduce Motion everything cross-fades in place.
struct NightTurn:ViewModifier {
    var value:Int?=nil
    let reduceMotion:Bool
    func body(content:Content)->some View {
        if let value, !reduceMotion { content.contentTransition(.numericText(value:Double(value))) }
        else { content.contentTransition(.opacity) }
    }
}
/// A still, seeded sky behind the widget. Widgets render once per entry, so nothing animates.
/// The real sky shows what the app's sky shows for that night (`RealSky.Visibility`): by the Sun's
/// height at the moment drawn, only the brightest stars in a white night and none under the midnight
/// sun (Denali in June), and without the faint stars under Increase Contrast. Plain black behind:
/// no twilight lift, so the widget's text keeps its contrast in every rendering mode.
struct WidgetSky:View {
    @Environment(\.colorSchemeContrast) private var contrast
    let seed:String
    let ink:Color
    /// When known, the real stars over that park that night; seeded dots otherwise.
    var night:Night?=nil
    var body:some View {
        let highContrast=contrast == .increased
        Canvas { context,size in
            if let night {
                let sky=SkyProjection.shared.sky(for:night.park,night:night.id)
                let seen=RealSky.Visibility(sunAltitude:sky.sunAltitude,highContrast:highContrast,liftAllowed:false)
                for (stars,level) in [(sky.bright,seen.bright),(sky.middle,seen.middle),(sky.faint,seen.faint)] where level>0 {
                    for star in stars {
                        let p=SkyProjection.screen(star.position,size:CGSize(width:size.width,height:size.height*1.6))
                        let y=p.y-size.height*0.3
                        guard p.x>=0,p.x<=size.width,y>=0,y<=size.height else { continue }
                        let d=star.diameter*0.7
                        context.fill(Path(ellipseIn:CGRect(x:p.x-d/2,y:y-d/2,width:d,height:d)),with:.color(star.tint(ink).opacity(star.brightness*0.55*level)))
                    }
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
    /// `widgets-step`: the medium widget with its night buttons, on tonight, a night ahead and the
    /// last night, with a closure and in night vision; `widgets-step-large`: the large widget, a
    /// night ahead with a closure, tonight, and the last night on a tinted Home Screen.
    var stepped=false
    var steppedLarge=false
    private func steppedEntry(_ entry:TonightEntry,offset:Int,family:String,closure:String?=nil,nightVision:Bool=false)->TonightEntry {
        var moved=TonightEntry(date:entry.date,night:entry.night,nightVision:nightVision,week:entry.week,month:entry.month,
                               position:entry.position,savedCount:entry.savedCount,closure:closure)
        moved.stepScope=WidgetNightStep.scope(place:nil,family:family)
        moved.offset=offset
        return moved
    }
    /// `widgets-new`: the inline Lock Screen widget, the Moon widget, a closure line and a widget set to one park.
    var newer=false
    /// `widgets-xl-portrait`: iPad's portrait extra-large family (iOS 27), at an illustrative size.
    var portrait=false
    /// The Moon widget for the shown park.
    var moon:MoonEntry?=nil
    private func with(_ entry:TonightEntry,closure:String?,pinned:Bool=false,nightVision:Bool?=nil)->TonightEntry {
        TonightEntry(date:entry.date,night:entry.night,nightVision:nightVision ?? entry.nightVision,week:entry.week,month:entry.month,
                     position:pinned ? 0 : entry.position,savedCount:pinned ? 0 : entry.savedCount,closure:closure)
    }
    private func moonCard(_ family:WidgetFamily,_ entry:MoonEntry,size:CGSize)->some View {
        MoonWidgetView(previewFamily:family,entry:entry).frame(width:size.width,height:size.height)
            .padding(family == .systemSmall ? 16 : 0)
            .background(family == .systemSmall ? AnyView(WidgetSky(seed:"moon",ink:.white)) : AnyView(Color.clear))
            .clipShape(RoundedRectangle(cornerRadius:family == .systemSmall ? 24 : 0))
    }
    var body:some View {
        ScrollView { VStack(alignment:.leading,spacing:20) {
            Text(stepped || steppedLarge ? "Night buttons review" : portrait ? "Portrait extra-large widget review" : newer ? "New widgets review" : extraLarge ? "Extra-large widget review" : large ? "Large widget review" : "Widget content review").font(.system(size:20,design:.serif))
            if stepped {
                let sample="Keys View Road closed at night"
                Text(verbatim:"Medium: tonight, three nights ahead, the last night").font(.caption)
                card(.systemMedium,steppedEntry(entry,offset:0,family:"medium"),height:158)
                card(.systemMedium,steppedEntry(entry,offset:3,family:"medium"),height:158)
                card(.systemMedium,steppedEntry(entry,offset:6,family:"medium"),height:158)
                Text(verbatim:"Medium with a closure; night vision").font(.caption)
                card(.systemMedium,steppedEntry(entry,offset:2,family:"medium",closure:sample),height:158)
                card(.systemMedium,steppedEntry(entry,offset:2,family:"medium",nightVision:true),height:158)
            } else if steppedLarge {
                let sample="Keys View Road closed at night"
                Text(verbatim:"Large: a night ahead with a closure, tonight, tinted").font(.caption)
                card(.systemLarge,steppedEntry(entry,offset:4,family:"large",closure:sample),height:338)
                card(.systemLarge,steppedEntry(entry,offset:0,family:"large"),height:338)
                card(.systemLarge,steppedEntry(entry,offset:6,family:"large"),height:338,mode:.vibrant).saturation(0).colorMultiply(Color(white:0.85))
            } else if portrait {
                if #available(iOS 27.0,*) {
                    card(.systemExtraLargePortrait,with(entry,closure:"Keys View Road closed at night"),height:740).frame(maxWidth:380+32)
                } else { Text("Portrait extra-large needs iOS 27.").font(.caption) }
            } else if newer {
                let sample="Keys View Road closed at night"
                Text("Lock Screen: inline, Tonight and the Moon").font(.caption)
                HStack(spacing:24) {
                    TonightWidgetView(previewFamily:.accessoryInline,entry:entry).frame(height:22)
                    if let moon { MoonWidgetView(previewFamily:.accessoryInline,entry:moon).frame(height:22) }
                }.foregroundStyle(.white)
                if let moon {
                    Text("The Moon: Home Screen, Lock Screen, night vision").font(.caption)
                    HStack(spacing:16) {
                        moonCard(.systemSmall,moon,size:CGSize(width:126,height:126))
                        moonCard(.systemSmall,MoonEntry(date:moon.date,park:moon.park,nightVision:true),size:CGSize(width:126,height:126))
                        moonCard(.accessoryCircular,moon,size:CGSize(width:68,height:68))
                    }
                    moonCard(.accessoryRectangular,moon,size:CGSize(width:160,height:72)).foregroundStyle(.white)
                }
                Text("A park's closure (illustrative text)").font(.caption)
                HStack(spacing:24) {
                    TonightWidgetView(previewFamily:.accessoryCircular,entry:with(entry,closure:sample)).frame(width:68,height:68)
                    TonightWidgetView(previewFamily:.accessoryRectangular,entry:with(entry,closure:sample)).frame(width:160,height:72)
                }.foregroundStyle(.white)
                TonightWidgetView(previewFamily:.accessoryInline,entry:with(entry,closure:sample)).frame(height:22).foregroundStyle(.white)
                card(.systemSmall,with(entry,closure:sample),height:158)
                card(.systemMedium,with(entry,closure:sample),height:158)
                card(.systemLarge,with(entry,closure:sample),height:338)
                Text("Set to one park: no \"2 of 3\"").font(.caption)
                card(.systemMedium,with(entry,closure:nil,pinned:true),height:158)
            } else if extraLarge {
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
        }.padding(24) }.defaultScrollAnchor(ProcessInfo.processInfo.arguments.contains("-nyx-bottom") ? .bottom : .top).background(Color.black)
    }
}
#endif
