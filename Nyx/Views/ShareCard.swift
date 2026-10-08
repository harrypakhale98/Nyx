import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

/// The night as artwork to share: the gauge over the park's real sky, the park and the date, one
/// line on why the night is good (Moon-free hours or the Milky Way's core), and what the clouds rest
/// on. Two shapes: a card (4:5-ish, for messages) and a 9:16 story. The words travel with the image
/// as its message, so a VoiceOver recipient hears the night, not "image".
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
    var body:some View {
        ZStack {
            NightBackground(seed:night.park.id,score:night.score.value,park:night.park,night:night.id)
            VStack(spacing:shape == .story ? 24 : 18) {
                if shape == .story { Spacer(minLength:0) }
                Text("NYX").font(.caption).tracking(7).foregroundStyle(palette.muted)
                // ImageRenderer proposes no size; an unsized gauge collapses and truncates the score.
                CelestialGauge(score:night.score.value,hasForecast:night.score.hasForecast,export:true).frame(width:300,height:300)
                Text(night.park.shortName).font(.system(.title,design:.serif)).multilineTextAlignment(.center).foregroundStyle(palette.ink)
                HStack(spacing:10) {
                    MoonView(geometry:AstronomyEngine().moon(for:night).geometry).frame(width:26,height:26)
                    Text(night.park.dayLabel(night.id)).font(.subheadline).foregroundStyle(palette.ink)
                }
                if let why { Text(why).font(.system(.callout,design:.serif)).multilineTextAlignment(.center).foregroundStyle(palette.ink).fixedSize(horizontal:false,vertical:true) }
                Text(basis).font(.caption).multilineTextAlignment(.center).foregroundStyle(palette.muted)
                if shape == .story { Spacer(minLength:0) }
            }.padding(40)
        }.frame(width:shape.size.width,height:shape.size.height)
            // ImageRenderer does not inherit the window's dark scheme; every color here is explicit.
            .environment(\.colorScheme,.dark)
            // This is fixed-size exported artwork, with a complete spoken alternative.
            .dynamicTypeSize(.large).accessibilityElement(children:.ignore).accessibilityLabel(summary)
    }
    /// "Joshua Tree, Fri, Oct 9, darkness score 94 out of 100. Pristine. Moon-free all night. Forecast included…"
    var summary:String {
        var line=String(localized:"\(night.park.shortName), \(night.park.dayLabel(night.id)), darkness score \(night.score.value) out of 100. \(night.score.band.label).")
        if let why { line+=" "+why+"." }
        return line+" "+basis+"."
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
nonisolated struct ShareArtwork: Transferable {
    let night: Night
    let shape: ShareCard.Format
    let why: String?
    let palette: NyxPalette
    let scale: CGFloat
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType:.png) { artwork in try await artwork.png() }
    }
    private enum Failure: Error { case notDrawn }
    @MainActor private static var drawn: [String:Data]=[:]
    /// Everything the drawing depends on: the night's score and its forecast basis (the caption and
    /// the gauge's hollow ring), the shape, the words, and the palette's red and contrast.
    @MainActor private var key: String {
        [night.park.id,night.id.description,String(night.score.value),String(describing:night.basis),String(night.score.hasForecast),String(describing:shape),
         String(palette.nightVision),String(palette.highContrast),String(palette.brighterRed),why ?? "",String(Double(scale))].joined(separator:"|")
    }
    @MainActor func png() throws -> Data {
        if let data=Self.drawn[key] { return data }
        guard let data=image()?.pngData() else { throw Failure.notDrawn }
        if Self.drawn.count>=4 { Self.drawn.removeAll() }
        Self.drawn[key]=data
        return data
    }
    /// The card exactly as exported: still, dark, and red in night vision.
    @MainActor func image() -> UIImage? {
        let card=ShareCard(night:night,shape:shape,why:why).environment(\.nyx,palette).environment(\.nyxReduceMotion,true).preferredColorScheme(.dark)
        let renderer=ImageRenderer(content:card.modifier(NightVisionFilter(enabled:palette.nightVision))); renderer.scale=max(2,scale)
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
        let why=why, card=ShareCard(night:night,why:why)
        Menu {
            ForEach(ShareCard.Format.allCases) { shape in
                let artwork=ShareArtwork(night:night,shape:shape,why:why,palette:palette,scale:displayScale)
                ShareLink(item:artwork,message:Text(card.message),preview:SharePreview(String(localized:"\(night.score.value) out of 100 at \(night.park.shortName)"),image:artwork)) {
                    Label(shape == .card ? String(localized:"Share as a card") : String(localized:"Share as a story (9:16)"),systemImage:shape == .card ? "rectangle.portrait" : "rectangle.portrait.fill")
                }
            }
        } label:{ Image(systemName:"square.and.arrow.up") }
        .accessibilityLabel("Share this night")
        .accessibilityValue(card.summary)
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
        let why=why, card=ShareCard(night:night,why:why)
        let artwork=ShareArtwork(night:night,shape:.card,why:why,palette:palette,scale:displayScale)
        ShareLink(item:artwork,message:Text(card.message),preview:SharePreview(String(localized:"\(night.score.value) out of 100 at \(night.park.shortName)"),image:artwork)) { Label("Share this night",systemImage:"square.and.arrow.up") }
            .buttonStyle(.bordered).accessibilityValue(card.summary)
    }
}
#Preview("Share card") { let m=PlanModel();if let p=m.home { ShareCard(night:m.night(p),why:"Moon-free through all of true darkness").environment(\.nyxReduceMotion,true) } }
#Preview("Share story") { let m=PlanModel();if let p=m.home { ShareCard(night:m.night(p),shape:.story,why:"Milky Way core 8:10 PM – 11:30 PM").environment(\.nyxReduceMotion,true) } }
#if DEBUG
/// `-nyx-screen share`: the card as people receive it, the rendered image (fixed-size artwork, never
/// live text) with its spoken summary. Drawn in starlight; the app's night vision turns it red on screen,
/// as the export does.
struct ShareCardReview:View {
    @Environment(\.displayScale) private var displayScale
    let night:Night
    @State private var image:UIImage?
    var body:some View {
        Group {
            if let image {
                Image(uiImage:image).resizable().scaledToFit().frame(maxWidth:ShareCard.Format.card.size.width)
                    .clipShape(RoundedRectangle(cornerRadius:24)).padding(16)
                    .accessibilityLabel(ShareCard(night:night).summary).accessibilityIgnoresInvertColors()
            } else { Color.black }
        }
        .frame(maxWidth:.infinity,maxHeight:.infinity).background(Color.black)
        .task { image=ShareArtwork(night:night,shape:.card,why:nil,palette:NyxPalette(nightVision:false,highContrast:false),scale:displayScale).image() }
    }
}
#endif
