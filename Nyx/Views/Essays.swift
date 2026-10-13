import SwiftUI

/// The Learn essays in reading order: the score first, then the sky, then the trip. Each has one
/// English source, `Nyx/Resources/learn/<case>.md`, and a catalog key `essay.<case>`.
enum Essay: String,CaseIterable,Identifiable {
    case score,darkness,milkyway,photo,meteors,bortle,forecast,safety,etiquette,access
    var id:String { rawValue }
    var title:String { switch self { case .score:String(localized:"Reading the darkness score");case .darkness:String(localized:"A sky worth protecting");case .milkyway:String(localized:"Finding the Milky\u{00A0}Way");case .photo:String(localized:"Your first Milky\u{00A0}Way photo");case .meteors:String(localized:"Watching a meteor shower");case .bortle:String(localized:"Reading the Bortle scale");case .forecast:String(localized:"What a forecast can't tell you");case .safety:String(localized:"Safe in the dark");case .etiquette:String(localized:"Sharing the night");case .access:String(localized:"Stargazing for everyone") } }
    var subtitle:String { switch self { case .score:String(localized:"Four parts, the weakest link and the bands");case .darkness:String(localized:"Why darkness deserves care");case .milkyway:String(localized:"When, where and how to look");case .photo:String(localized:"A tripod, a wide lens and a dark night");case .meteors:String(localized:"Radiants, rates and patience");case .bortle:String(localized:"Reading artificial sky brightness");case .forecast:String(localized:"Models, thin cloud, smoke and fog");case .safety:String(localized:"Roads, cold, no signal and red light");case .etiquette:String(localized:"Leave room for everyone to look up");case .access:String(localized:"Dark skies by sound, touch and red light") } }
    var symbol:String { switch self { case .score:"gauge.with.dots.needle.67percent";case .darkness:"sparkles";case .milkyway:"sparkle";case .photo:"camera.aperture";case .meteors:"sparkles.2";case .bortle:"circle.lefthalf.filled";case .forecast:"cloud.moon";case .safety:"figure.hiking";case .etiquette:"moon.stars";case .access:"accessibility" } }
    /// About 200 words a minute, never less than one.
    var minutes:Int { max(1,Int((Double(content.split(whereSeparator:\.isWhitespace).count)/200).rounded())) }
    /// Essays that quote a percentage ("60%") read their text without formatting, so a "%" stays a "%".
    var content:String { switch self { case .milkyway:String(localized:"essay.milkyway");case .meteors:String(localized:"essay.meteors");case .bortle:String(localized:"essay.bortle");case .etiquette:String(localized:"essay.etiquette");case .access:String(localized:"essay.access");case .score,.darkness,.photo,.forecast,.safety:Self.text(rawValue) } }
    /// One way from the essay into Nyx itself: the place where what it explains can be seen tonight.
    func link(model:PlanModel)->(label:String,url:URL)? {
        link(home:model.home,tonight:model.home.map { $0.isoDay(model.tonight($0)) })
    }
    /// The same, from the starting park and its tonight (park-local `YYYY-MM-DD`); pure, so it is tested.
    func link(home:Park?,tonight:String?)->(label:String,url:URL)? {
        switch self {
        case .score,.darkness: return URL(string:"nyx://tonight").map { (String(localized:"Tonight's darkest park"),$0) }
        case .safety: return home.flatMap { URL(string:"nyx://park/\($0.id)") }.map { (String(localized:"Your starting park's alerts"),$0) }
        case .photo,.milkyway,.meteors:
            guard let park=home,let tonight else { return nil }
            return URL(string:"nyx://whatsup?date=\(tonight)&park=\(park.id)").map { (String(localized:"What's up tonight at \(park.shortName)"),$0) }
        case .forecast: return home.flatMap { URL(string:"nyx://calendar/\($0.id)") }.map { (String(localized:"The month ahead"),$0) }
        case .bortle,.etiquette,.access: return nil
        }
    }
    /// A closing paragraph that lists sources ("Sources: …", "Fuentes: …"), drawn as a footnote.
    static func isSources(_ paragraph:String)->Bool { paragraph.hasPrefix(String(localized:"Sources")+":") }
    /// The catalog's `essay.<name>` in the reader's language; until the catalog holds it, the
    /// bundled English source, so a new essay never shows its key.
    static func text(_ name:String,bundle:Bundle = .main)->String {
        let key="essay.\(name)", local=bundle.localizedString(forKey:key,value:nil,table:nil)
        if local != key, !local.isEmpty { return local }
        let source=bundle.url(forResource:name,withExtension:"md").flatMap { try? String(contentsOf:$0,encoding:.utf8) } ?? ""
        return source.trimmingCharacters(in:.whitespacesAndNewlines)
    }
}
/// The essay's mark: an SF Symbol, or for meteors (which SF Symbols lacks) the app's own streak glyph.
private struct EssayIcon:View {
    @Environment(\.nyx) private var palette
    let essay:Essay
    let size:Double
    var body:some View {
        // One square box for every symbol, so the titles beneath line up across the grid.
        Group {
            if essay == .meteors { SkyGlyph(.meteors,color:palette.accent).frame(width:size,height:size) }
            else { Image(systemName:essay.symbol).font(.system(size:size,weight:.ultraLight)).foregroundStyle(palette.accent).accessibilityHidden(true) }
        }.frame(width:size*1.3,height:size*1.3,alignment:.leading)
    }
}
/// The essays, from Settings › About the sky (and the `learn` screenshot route). Compact cards, so a
/// phone shows most of them at once; two or three columns on a wide iPad.
struct LearnView:View {
    @Environment(\.nyx) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    /// One column at accessibility text sizes: three 300 pt cards on a wide iPad broke the titles mid-word at AX5
    /// ("Watchi / ng a / mete- / or", 2026-10-13); one card across the column keeps whole words.
    private var columns:[GridItem] {
        typeSize.isAccessibilitySize ? [GridItem(.flexible(),alignment:.top)] : [GridItem(.adaptive(minimum:300),spacing:18,alignment:.top)]
    }
    var body:some View {
        ScrollView { VStack(alignment:.leading,spacing:24) {
            LazyVGrid(columns:columns,spacing:18) { ForEach(Essay.allCases) { essay in
                NavigationLink { EssayView(essay:essay) } label:{ Panel { HStack(alignment:.top,spacing:14) {
                    EssayIcon(essay:essay,size:24)
                    VStack(alignment:.leading,spacing:6) {
                        // Each line takes the card's whole width, not the width its last wrap left: the system lifts a
                        // lone last word onto the line before ("Watching a / meteor shower"), and a frame hugging that
                        // line by a fraction of a point measured as clipped (iPad audit, 2026-10-09).
                        Text(essay.title).font(.system(.title3,design:.serif)).foregroundStyle(palette.ink).fixedSize(horizontal:false,vertical:true).frame(maxWidth:.infinity,alignment:.leading)
                        Text(essay.subtitle).font(.subheadline).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true).frame(maxWidth:.infinity,alignment:.leading)
                        Text("\(essay.minutes)-minute read").font(.caption).foregroundStyle(palette.ink.opacity(palette.nightVision ? 1 : 0.86))
                    }
                    Spacer(minLength:0)
                    Image(systemName:"chevron.forward").font(.caption.weight(.semibold)).foregroundStyle(palette.muted).accessibilityHidden(true)
                }.frame(maxHeight:.infinity,alignment:.top) }.frame(maxHeight:.infinity) }.buttonStyle(.plain).hoverEffect(.lift)
            } }
            AboutDataLink()
        }.padding(24).readableColumn(1080) }.background(NightBackground()).navigationTitle("Learn").navigationBarTitleDisplayMode(.inline)
    }
}
struct EssayView:View {
    @Environment(\.nyx) private var palette
    @Environment(PlanModel.self) private var model:PlanModel?
    @Environment(SceneCommands.self) private var commands:SceneCommands?
    @Environment(\.openURL) private var openURL
    let essay:Essay
    var body:some View {
        let figure=EssayFigure(essay)
        ScrollView { VStack(alignment:.leading,spacing:28) { EssayIcon(essay:essay,size:48);Text(essay.title).font(.system(.largeTitle,design:.serif));ForEach(Array(essay.content.components(separatedBy:"\n\n").dropFirst().enumerated()),id:\.offset) { index,paragraph in
            if Essay.isSources(paragraph) {
                // The essay's sources: a quiet footnote, after the Globe at Night invitation's link.
                if essay == .darkness { GlobeAtNightLink() }
                Text(paragraph).font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true).textSelection(.enabled)
            } else { Text(paragraph).font(.system(.body,design:.serif)).lineSpacing(7).foregroundStyle(palette.ink).textSelection(.enabled) }
            if let figure, index==figure.afterParagraph { figure.view }
        };if let model,let link=essay.link(model:model) { Button { follow(link.url) } label:{ Label(link.label,systemImage:"arrow.up.right") }.buttonStyle(.bordered).accessibilityHint("Leaves the essay and opens it in Nyx.") };if OnDeviceGuide.available { NavigationLink("Explain this another way") { GuideView(mode:.learn(essay)) }.buttonStyle(.bordered) } }.padding(26).readableColumn(WideLayout.proseWidth) }.defaultScrollAnchor(DebugScenario.isEnabled("bottom") ? .bottom : .top).background(NightBackground(veil:0.6)).navigationTitle("Learn").navigationBarTitleDisplayMode(.inline)
    }
    /// Settings closes first (Learn lives in it), then the link opens where the essay points.
    private func follow(_ url:URL) {
        commands?.closeSettings+=1
        Task { try? await Task.sleep(for:.milliseconds(450)); openURL(url) }
    }
}
#Preview("Learn") { NavigationStack { LearnView() }.preferredColorScheme(.dark) }
