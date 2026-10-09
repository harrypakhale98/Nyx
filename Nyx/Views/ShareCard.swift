import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

/// The night as artwork to share, led by the night itself: the park's real sky, the Moon as it
/// will look (or "New moon" in words, never a dark disc), the score as a light serif numeral with its
/// band, the forecast models' range when they disagree, then the park, the date, one line on why
/// the night is good and what the clouds rest on. A small wordmark at the foot. Two shapes in one
/// layout: a card (4:5-ish, for messages) and a 9:16 story. The words travel with the image as its
/// message, so a VoiceOver recipient hears the night, not "image".
struct ShareCard:View {
    enum Format: String, CaseIterable, Identifiable {
        case card, story
        var id: String { rawValue }
        var size: CGSize { self == .card ? CGSize(width:420,height:580) : CGSize(width:405,height:720) }
    }
    @Environment(\.nyx) private var palette
    let night:Night
    var shape:Format = .card
    /// One reason to go, from What's up; nil leaves the line out.
    var why:String?=nil
    /// The forecast models' range (`CelestialGauge.modelRange`: full forecast, models apart, more
    /// than 4 points), so a shared number is never more certain than the app; nil leaves it out.
    var range:ClosedRange<Int>?=nil
    /// From 5% lit the Moon is drawn; below, a 120 pt disc would read as a dark hole, so the date
    /// line names the Moon in words instead.
    nonisolated static let moonDrawnFrom=0.05
    nonisolated static let numeralSize=120.0
    private var drawsMoon:Bool { night.sky.moon.illumination>=Self.moonDrawnFrom }
    var body:some View {
        ZStack {
            NightBackground(seed:night.park.id,score:night.score.value,park:night.park,night:night.id)
            // Exported art has no accessibility settings to lean on: the sky is veiled behind the
            // words, so no star ever sits beside a letter like stray punctuation.
            RadialGradient(colors:[.black.opacity(0.6),.black.opacity(0.35),.clear],center:UnitPoint(x:0.5,y:0.55),startRadius:0,endRadius:shape.size.height*0.6)
            VStack(spacing:0) {
                Spacer(minLength:0)
                if drawsMoon {
                    // Fixed frames throughout: ImageRenderer proposes no size.
                    MoonView(geometry:AstronomyEngine().moon(for:night).geometry)
                        .frame(width:shape == .story ? 132 : 120,height:shape == .story ? 132 : 120)
                        .padding(.bottom,shape == .story ? 18 : 6)
                }
                VStack(spacing:0) {
                    score
                    if let range {
                        Text(Self.rangeLine(range)).font(.caption).monospacedDigit().foregroundStyle(palette.muted).padding(.top,6)
                    }
                    VStack(spacing:6) {
                        Text(night.park.shortName).font(.system(.title,design:.serif)).foregroundStyle(palette.ink)
                        Text(dateLine).font(.subheadline).foregroundStyle(palette.ink)
                        if let why { Text(why).font(.system(.callout,design:.serif)).foregroundStyle(palette.ink).padding(.top,6) }
                        Text(basis).font(.caption).foregroundStyle(palette.muted).padding(.top,2)
                    }
                    .multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true)
                    .padding(.top,shape == .story ? 28 : 16)
                }
                .padding(.horizontal,22).padding(.vertical,22)
                // Night itself right behind the words: the stars stop short of every letter.
                .background { RoundedRectangle(cornerRadius:48).fill(.black).blur(radius:20) }
                Spacer(minLength:0)
                Text("NYX").font(.caption2.weight(.medium)).tracking(6).foregroundStyle(palette.muted).padding(.top,12)
            }.padding(.horizontal,28).padding(.top,shape == .story ? 40 : 30).padding(.bottom,shape == .story ? 30 : 22)
        }.frame(width:shape.size.width,height:shape.size.height)
            // ImageRenderer does not inherit the window's dark scheme; every color here is explicit.
            .environment(\.colorScheme,.dark)
            // This is fixed-size exported artwork, with a complete spoken alternative.
            .dynamicTypeSize(.large).accessibilityElement(children:.ignore).accessibilityLabel(summary)
    }
    /// The numeral, light and tightly set as on the gauge, with "/100" hung off its right side so
    /// the number itself stays centred; the band word under it.
    private var score:some View {
        VStack(spacing:0) {
            Text(night.score.value,format:.number)
                .font(.system(size:Self.numeralSize,weight:.light,design:.serif)).tracking(-Self.numeralSize*0.046)
                .foregroundStyle(palette.accent).lineLimit(1).fixedSize()
                .overlay(alignment:Alignment(horizontal:.trailing,vertical:.lastTextBaseline)) {
                    Text(verbatim:"/100").font(.system(.title3,design:.serif)).foregroundStyle(palette.muted).fixedSize()
                        .alignmentGuide(.trailing) { $0[.leading]-6 }
                }
                // Trims the numeral's tall line box, so the band sits close under the digits.
                .padding(.vertical,-12)
            Text(night.score.band.label).font(.system(.title3,design:.serif)).foregroundStyle(palette.ink)
        }
    }
    /// "Thu, Oct 8", or with the Moon in words when it is not drawn: "Thu, Oct 8 · New moon", and
    /// "Thu, Oct 8 · Moon 3% lit" for a thin crescent the app itself names a crescent.
    var dateLine:String {
        let day=night.park.dayLabel(night.id)
        guard !drawsMoon else { return day }
        if night.sky.moon.name == String(localized:"New moon") { return String(localized:"\(day) · New moon") }
        return String(localized:"\(day) · Moon \(Self.percent(night))% lit")
    }
    nonisolated static func percent(_ night:Night)->Int { Int((night.sky.moon.illumination*100).rounded()) }
    /// "Forecast models: 70–84"
    nonisolated static func rangeLine(_ range:ClosedRange<Int>)->String {
        String(localized:"Forecast models: \(range.lowerBound)–\(range.upperBound)")
    }
    /// "Joshua Tree, Fri, Oct 9, darkness score 94 out of 100. Pristine. Forecast models: 88 to 96.
    /// Waxing crescent, 12% lit. Moon-free all night. Forecast included…"
    var summary:String {
        var line=String(localized:"\(night.park.shortName), \(night.park.dayLabel(night.id)), darkness score \(night.score.value) out of 100. \(night.score.band.label).")
        if let range { line+=" "+String(localized:"Forecast models: \(range.lowerBound) to \(range.upperBound).") }
        line+=" "+moonPhrase+"."
        if let why { line+=" "+why+"." }
        return line+" "+basis+"."
    }
    /// The Moon as the card shows it: its phase and how much is lit, or in words when not drawn.
    private var moonPhrase:String {
        if drawsMoon { return String(localized:"\(night.sky.moon.name), \(Self.percent(night))% lit") }
        if night.sky.moon.name == String(localized:"New moon") { return String(localized:"New moon") }
        return String(localized:"Moon \(Self.percent(night))% lit")
    }
    /// What travels beside the image: the summary, then where it came from.
    var message:String { summary+" "+String(localized:"Planned with Nyx.")+(Self.storeURL.map { " "+$0.absoluteString } ?? "") }
    /// The App Store page (`SupportLink.storePage`), nil if the app ID is ever unset, so no link is guessed.
    static var storeURL:URL? { SupportLink.storePage }
    private var basis:String {
        switch night.basis {
        case .forecast: String(localized:"Forecast included · conditions may change")
        case .blended: String(localized:"Early look · forecast eased toward usual clouds")
        case .usual: String(localized:"No cloud forecast yet · usual clouds for the month")
        }
    }
    /// The night's one reason, in a few words: the Moon gone through true darkness, else the
    /// Milky Way's core and its hours, else how much of true darkness is Moon-free.
    static func why(night:Night,core:WhatsUp.Item?)->String? {
        guard night.sky.darkHours>0 else { return nil }
        if night.sky.moonBelowFraction>=0.99 { return String(localized:"Moon-free through all of true darkness") }
        if let core, core.timed, let value=core.value { return String(localized:"Milky Way core \(value)") }
        let free=Int((night.sky.moonBelowFraction*100).rounded())
        return free>=25 ? String(localized:"Moon-free for \(free)% of true darkness") : nil
    }
}
/// The card or story as something to share, drawn only when the share sheet asks for it (its
/// preview, then the image itself), never while nights are being scrubbed. The last few drawings
/// are kept, so the preview and the image are drawn once.
///
/// The exported image (`palette` nil) is always drawn in starlight: it goes to someone in daylight,
/// whose screen has no night vision to honour. The share sheet's own preview is drawn in the app's
/// palette (red in night vision), so a night-adapted eye never meets a full-colour flash inside Nyx.
nonisolated struct ShareArtwork: Transferable {
    let night: Night
    let shape: ShareCard.Format
    let why: String?
    let range: ClosedRange<Int>?
    /// Nil for the exported image; the app's palette for the share sheet's preview.
    let palette: NyxPalette?
    let scale: CGFloat
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType:.png) { artwork in try await artwork.png() }
    }
    private enum Failure: Error { case notDrawn }
    @MainActor private static var drawn: [String:Data]=[:]
    /// Everything the drawing depends on: the night's score and its forecast basis (the caption),
    /// the Moon's light (the disc or the words), the shape, the words and the models' range, and
    /// for a preview the palette's red and contrast.
    @MainActor var key: String {
        let look=palette.map { ["preview",String($0.nightVision),String($0.highContrast),String($0.brighterRed)] } ?? ["export"]
        return ([night.park.id,night.id.description,String(night.score.value),String(describing:night.basis),String(ShareCard.percent(night)),String(describing:shape),
                 why ?? "",range.map { "\($0.lowerBound)-\($0.upperBound)" } ?? "",String(Double(scale))]+look).joined(separator:"|")
    }
    @MainActor func png() throws -> Data {
        if let data=Self.drawn[key] { return data }
        guard let data=image()?.pngData() else { throw Failure.notDrawn }
        if Self.drawn.count>=4 { Self.drawn.removeAll() }
        Self.drawn[key]=data
        return data
    }
    /// The card as drawn: still and dark; starlight when exported, the app's palette as a preview.
    @MainActor func image() -> UIImage? {
        let look=palette ?? NyxPalette(nightVision:false,highContrast:false)
        let card=ShareCard(night:night,shape:shape,why:why,range:range).environment(\.nyx,look).environment(\.nyxReduceMotion,true).preferredColorScheme(.dark)
        let renderer=ImageRenderer(content:card.modifier(NightVisionFilter(enabled:look.nightVision,red:look.red))); renderer.scale=max(2,scale)
        return renderer.uiImage
    }
}
/// The share button in the park's toolbar: a menu of the card and the 9:16 story, each sent with
/// its words. The image is drawn for the night shown when a share is chosen, so it always matches.
struct ShareNightMenu:View {
    @Environment(\.nyx) private var palette
    @Environment(PlanModel.self) private var model
    @Environment(\.displayScale) private var displayScale
    let night:Night
    private var why:String? { ShareCard.why(night:night,core:model.whatsUp(night).core) }
    var body:some View {
        let why=why, range=CelestialGauge.modelRange(model.outlook(night),basis:night.basis), card=ShareCard(night:night,why:why,range:range)
        Menu {
            ForEach(ShareCard.Format.allCases) { shape in
                let artwork=ShareArtwork(night:night,shape:shape,why:why,range:range,palette:nil,scale:displayScale)
                let preview=ShareArtwork(night:night,shape:shape,why:why,range:range,palette:palette,scale:displayScale)
                ShareLink(item:artwork,message:Text(card.message),preview:SharePreview(String(localized:"\(night.score.value) out of 100 at \(night.park.shortName)"),image:preview)) {
                    Label(shape == .card ? String(localized:"Share as a card") : String(localized:"Share as a story (9:16)"),systemImage:shape == .card ? "rectangle.portrait" : "rectangle.portrait.fill")
                }
                .accessibilityHint(ShareCard.hint(palette))
            }
        } label:{ Image(systemName:"square.and.arrow.up") }
        .accessibilityLabel("Share this night")
        .accessibilityValue(card.summary)
        .accessibilityHint(ShareCard.hint(palette))
        .accessibilityInputLabels([Text("Share"),Text("Share this night")])
    }
}
/// The bordered share button, for sheets (the score breakdown) where there is no toolbar menu.
struct ShareCardButton:View {
    @Environment(\.nyx) private var palette
    @Environment(PlanModel.self) private var model
    let night:Night
    @Environment(\.displayScale) private var displayScale
    private var why:String? { ShareCard.why(night:night,core:model.whatsUp(night).core) }
    var body:some View {
        let why=why, range=CelestialGauge.modelRange(model.outlook(night),basis:night.basis), card=ShareCard(night:night,why:why,range:range)
        let artwork=ShareArtwork(night:night,shape:.card,why:why,range:range,palette:nil,scale:displayScale)
        let preview=ShareArtwork(night:night,shape:.card,why:why,range:range,palette:palette,scale:displayScale)
        ShareLink(item:artwork,message:Text(card.message),preview:SharePreview(String(localized:"\(night.score.value) out of 100 at \(night.park.shortName)"),image:preview)) { Label("Share this night",systemImage:"square.and.arrow.up") }
            .buttonStyle(.bordered).accessibilityValue(card.summary).accessibilityHint(ShareCard.hint(palette))
    }
}
extension ShareCard {
    /// In night vision the share buttons say what leaves the app: the image is not red.
    static func hint(_ palette:NyxPalette)->String { palette.nightVision ? String(localized:"Shares a full-color image.") : "" }
}
#Preview("Share card") { let m=PlanModel();if let p=m.home { ShareCard(night:m.night(p),why:"Moon-free through all of true darkness").environment(\.nyxReduceMotion,true) } }
#Preview("Share card • crescent and models' range") {
    let m=PlanModel()
    if let p=m.home { ShareCard(night:m.night(p,on:p.date(m.tonight(p),addingDays:6)),why:"Moon-free for 70% of true darkness",range:72...86).environment(\.nyxReduceMotion,true) }
}
#Preview("Share card • preview in night vision") {
    let m=PlanModel()
    if let p=m.home { ShareCard(night:m.night(p,on:p.date(m.tonight(p),addingDays:6))).environment(\.nyx,NyxPalette(nightVision:true,highContrast:false)).environment(\.nyxReduceMotion,true).modifier(NightVisionFilter(enabled:true)) }
}
#Preview("Share story") { let m=PlanModel();if let p=m.home { ShareCard(night:m.night(p),shape:.story,why:"Milky Way core 8:10 PM – 11:30 PM").environment(\.nyxReduceMotion,true) } }
#Preview("Share story • gibbous") { let m=PlanModel();if let p=m.home { ShareCard(night:m.night(p,on:p.date(m.tonight(p),addingDays:12)),shape:.story).environment(\.nyxReduceMotion,true) } }
#if DEBUG
/// `-nyx-screen share`: the card as people receive it, the exported image (fixed-size artwork, never
/// live text) with its spoken summary. The export is always drawn in starlight; in night vision the
/// app's own filter reddens it on this screen, as the share sheet's preview is drawn red.
/// `-nyx-share-night N` shows the night N days ahead (a crescent, a gibbous Moon).
struct ShareCardReview:View {
    @Environment(\.displayScale) private var displayScale
    @Environment(PlanModel.self) private var model
    let night:Night
    @State private var image:UIImage?
    var body:some View {
        let range=CelestialGauge.modelRange(model.outlook(night),basis:night.basis), why=ShareCard.why(night:night,core:model.whatsUp(night).core)
        Group {
            if let image {
                Image(uiImage:image).resizable().scaledToFit().frame(maxWidth:ShareCard.Format.card.size.width)
                    .clipShape(RoundedRectangle(cornerRadius:24)).padding(16)
                    .accessibilityLabel(ShareCard(night:night,why:why,range:range).summary).accessibilityIgnoresInvertColors()
            } else { Color.black }
        }
        .frame(maxWidth:.infinity,maxHeight:.infinity).background(Color.black)
        .task { image=ShareArtwork(night:night,shape:.card,why:why,range:range,palette:nil,scale:displayScale).image() }
    }
}
#endif
