import SwiftUI

/// The score's four parts as an instrument readout under the gauge, so the number always arrives
/// with its reasons. Each meter glides on the shared spring as nights are scrubbed. Without a
/// forecast the cloud meter shows the park's usual clouds and says so. When a cap holds the score
/// below the sum of its parts (moonlight, clouds, sky glow, smoke, short darkness), the part that
/// holds it is ringed and marked "Limits tonight", and one plain line under the meters says the
/// cap and the sum, so the parts and the number never seem to disagree.
/// The whole readout is one button that opens the full breakdown. Within the seven-day model
/// horizon the cloud meter carries one quiet line saying whether three forecast models agree.
struct ScoreReadout: View {
    @Environment(\.nyx) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    @MotionReduced private var reduceMotion: Bool
    @Environment(\.legibilityWeight) private var legibilityWeight
    /// The meters' width, for fitting the four titles (`titleStyle`).
    @State private var gridWidth=0.0
    /// The meters fill from empty once the page can be watched, a beat into the dial's count and
    /// 60 ms apart left to right, so the parts are seen adding up to the number above them.
    @State private var filled=false
    /// True only through the first fill, so the stagger never trails a scrub afterwards.
    @State private var arriving=false
    @Environment(\.nyxRevealHeld) private var revealHeld
    private static let columnSpacing=14.0
    let score: DarknessScore
    var agreement: ModelAgreement?=nil
    /// Words the cap line for tonight ("Clouds limit tonight to 55.") or another night.
    var isTonight=true
    var action: () -> Void = {}
    private struct Part: Identifiable {
        let id: PartID
        let title: String
        let spoken: String
        let points: Double?
        let maximum: Double
        var note: String?=nil
    }
    private var parts: [Part] {
        let scale=score.cloudPoints == nil ? 1/0.75 : 1, shown=score.displayedParts
        return [
            Part(id:.moon,title:String(localized:"Moonlight"),spoken:String(localized:"Moonlight"),points:Double(shown.moon),maximum:40*scale),
            Part(id:.clouds,title:String(localized:"Clouds"),spoken:String(localized:"Clouds"),points:shown.cloud.map(Double.init),maximum:25,note:cloudNote),
            Part(id:.glow,title:String(localized:"Sky glow"),spoken:String(localized:"Sky glow"),points:Double(shown.glow),maximum:20*scale),
            Part(id:.hours,title:String(localized:"True darkness"),spoken:String(localized:"True darkness"),points:Double(shown.length),maximum:15*scale)
        ]
    }
    nonisolated enum PartID: Hashable, Sendable { case moon, clouds, glow, hours }
    /// The part whose cap holds the score below the sum of the parts, if one does; smoke has no part
    /// of its own, so its cap marks none and is said in the line alone.
    nonisolated static func limiting(_ score:DarknessScore)->PartID? {
        guard let limit=score.limit, limit.cap<score.partsSum else { return nil }
        switch limit {
        case .moonlight: return .moon
        case .clouds: return .clouds
        case .skyGlow: return .glow
        case .darkness: return .hours
        case .smoke: return nil
        }
    }
    private var limiting: PartID? { Self.limiting(score) }
    private var cloudNote: String? {
        switch score.basis {
        case .forecast: agreement?.word
        case .blended: String(localized:"Early look")
        case .usual: score.cloudPoints == nil ? nil : String(localized:"Usual clouds")
        }
    }
    /// The binding cap, when the parts add up to more than the score, then their sum, so the reader who
    /// adds the four numbers finds the total said, in plain words: "Moonlight limits tonight to 50.
    /// The four parts alone would give 65." The breakdown says the same (`ScoreBreakdownView`).
    private var limitLine: String? { Self.limitLine(score,tonight:isTonight) }
    nonisolated static func limitLine(_ score:DarknessScore,tonight:Bool)->String? {
        guard let limit=score.limitSentence(tonight:tonight) else { return nil }
        return Sentences.join([limit,String(localized:"The four parts add up to \(score.partsSum), but that limit comes first.")])
    }
    var body: some View {
        Button(action:action) {
            VStack(alignment:.leading,spacing:12) {
                if typeSize.isAccessibilitySize {
                    VStack(alignment:.leading,spacing:18) { ForEach(parts) { part in column(part) } }
                } else {
                    // A grid, so a title that wraps (Spanish "Horas oscuras") keeps every meter on one line.
                    // Four across, or two rows of two when a language's titles cannot fit four columns (`SubscoreTitles.style`).
                    let style=titleStyle
                    VStack(alignment:.leading,spacing:16) {
                        ForEach(Array(stride(from:0,to:parts.count,by:style.columns)),id:\.self) { start in
                            let row=Array(parts[start..<min(parts.count,start+style.columns)])
                            Grid(alignment:.leading,horizontalSpacing:Self.columnSpacing,verticalSpacing:7) {
                                GridRow(alignment:.bottom) { ForEach(row) { part in title(part,style:style).frame(maxWidth:.infinity,alignment:.leading) } }
                                GridRow { ForEach(row) { part in meter(part) } }
                                GridRow(alignment:.top) { ForEach(row) { part in value(part) } }
                            }
                        }
                    }
                    .frame(maxWidth:.infinity,alignment:.leading)
                    // Only a change of a point or more: the style chosen from this width moves the grid by half a
                    // point on a 375 pt phone, which otherwise flipped it forever.
                    .onGeometryChange(for:Double.self) { $0.size.width } action:{ if abs($0-gridWidth)>=1 { gridWidth=$0 } }
                }
                // The weakest link, when it holds the score below its parts: the number and the meters agree.
                // In ink: a reason, not a score.
                if let limitLine {
                    Text(limitLine).font(.caption).foregroundStyle(palette.ink).fixedSize(horizontal:false,vertical:true).frame(maxWidth:.infinity,alignment:.leading)
                }
            }
            .padding(.horizontal,4).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityElement(children:.ignore)
        .accessibilityLabel("Why this score")
        .accessibilityValue(spoken)
        .accessibilityHint("Opens the score breakdown.")
        // Filled at once under Reduce Motion; otherwise a quarter second after the hold lifts, as the
        // dial's count gathers. VoiceOver reads the parts from the first frame either way.
        .task(id:revealHeld) {
            guard !filled, !revealHeld else { return }
            if !reduceMotion { try? await Task.sleep(for:.seconds(0.25)) }
            guard !Task.isCancelled else { return }
            arriving=true; filled=true
            try? await Task.sleep(for:.seconds(0.6))
            arriving=false
        }
    }
    private func column(_ part:Part)->some View {
        VStack(alignment:.leading,spacing:7) { title(part); meter(part); value(part) }
    }
    @ViewBuilder private func title(_ part:Part,style:SubscoreTitles.Style?=nil)->some View {
        // One style for all four, so a row never mixes sizes: titles may wrap between words ("Horas oscuras"),
        // and the four shrink together, drop the spaced capitals or go two by two before any word would break
        // ("Resplandor", "Himmelsaufhellung"); see `SubscoreTitles.style`.
        if let style, !typeSize.isAccessibilitySize {
            let font:Font=style.scale<1 ? .system(size:SubscoreTitles.pointSize(typeSize)*style.scale,weight:.medium) : .caption2.weight(.medium)
            Text(part.title).font(font).kerning(style.spaced ? SubscoreTitles.kerning*style.scale : 0).textCase(style.spaced ? .uppercase : nil)
                .foregroundStyle(palette.muted).lineLimit(2).fixedSize(horizontal:false,vertical:true)
        } else {
            Text(part.title).font(.caption2.weight(.medium)).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
        }
    }
    private var titleStyle:SubscoreTitles.Style {
        // Sentence case, as every heading now is: four spaced-capital labels in a row read as a dashboard.
        guard gridWidth>0 else { return SubscoreTitles.Style(spaced:false,scale:1,columns:4) }
        let bold=legibilityWeight == .bold, titles=parts.map(\.title)
        // Every title on one line when the four can share a size of at least 85%, so the four meters
        // and numbers sit on one line with no title standing taller ("True darkness" on two lines).
        if let whole=SubscoreTitles.wholeLine(widest:SubscoreTitles.widestWord(titles,typeSize:typeSize,spaced:false,bold:bold,whole:true),width:gridWidth,spacing:Self.columnSpacing) { return whole }
        return SubscoreTitles.style(widestSpaced:nil,
                                    widestPlain:SubscoreTitles.widestWord(titles,typeSize:typeSize,spaced:false,bold:bold),width:gridWidth,spacing:Self.columnSpacing)
    }
    private func meter(_ part:Part)->some View {
        let order=Double(parts.firstIndex { $0.id == part.id } ?? 0)
        return Meter(fraction:part.points.map { filled ? min(1,max(0,$0/part.maximum)) : 0 },reduceMotion:reduceMotion,limits:part.id == limiting,delay:arriving ? order*0.06 : 0)
    }
    private func value(_ part:Part)->some View {
        VStack(alignment:.leading,spacing:4) {
            if let points=part.points {
                HStack(alignment:.firstTextBaseline,spacing:2) {
                    Text("\(Int(points.rounded()))").font(.system(.title3,design:.serif)).foregroundStyle(palette.accent).contentTransition(.numericText())
                    Text("/\(Int(part.maximum.rounded()))").font(.caption2.monospacedDigit()).foregroundStyle(palette.muted)
                }
            } else {
                Text("Unknown").font(.system(.subheadline,design:.serif)).foregroundStyle(palette.muted).padding(.top,3)
            }
            // The part that holds the score down, said where the eye already is.
            if part.id == limiting {
                Text(isTonight ? "Limits tonight" : "Limits this night").font(.caption2.weight(.semibold)).foregroundStyle(palette.ink)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 2).fixedSize(horizontal:false,vertical:true)
            }
            if let note=part.note {
                Text(note).font(.caption2).foregroundStyle(palette.muted).lineLimit(typeSize.isAccessibilitySize ? nil : 2).minimumScaleFactor(0.85)
                    .fixedSize(horizontal:false,vertical:true).contentTransition(.opacity)
            }
        }
    }
    private var spoken: String {
        parts.map { part in
            (part.points.map { String(localized:"\(part.spoken), \(Int($0.rounded())) of \(Int(part.maximum.rounded()))") }
                ?? String(localized:"\(part.spoken), unknown"))+(part.note.map { ", "+$0 } ?? "")
        }.joined(separator:". ")+(limitLine.map { ". "+$0 } ?? "")
    }
    /// A hairline track with an amber fill; dashed and empty when the part is unknown. The part that
    /// limits the score is ringed in starlight, a shape as well as words, so it never rests on colour.
    private struct Meter: View {
        @Environment(\.nyx) private var palette
        let fraction: Double?
        let reduceMotion: Bool
        var limits=false
        var delay=0.0
        var body: some View {
            GeometryReader { proxy in
                ZStack(alignment:.leading) {
                    if let fraction {
                        Capsule().fill(palette.line)
                        Capsule().fill(palette.accent).frame(width:fraction>0 ? max(3,proxy.size.width*fraction) : 0)
                            .shadow(color:palette.nightVision ? .clear : palette.accent.opacity(0.55),radius:3)
                    } else {
                        Capsule().stroke(palette.line,style:StrokeStyle(lineWidth:1,dash:[2,3]))
                    }
                }
                .animation(reduceMotion ? nil : NyxMotion.spring.delay(delay),value:fraction)
            }.frame(height:3)
            .overlay { if limits { Capsule().stroke(palette.ink.opacity(palette.highContrast ? 1 : 0.85),lineWidth:palette.stroke).padding(-3.5) } }
        }
    }
}
#Preview("Readout • forecast / no forecast") {
    let m=PlanModel()
    if let p=m.home {
        VStack(spacing:40) {
            ScoreReadout(score:m.night(p).score)
            ScoreReadout(score:m.night(p,on:p.date(m.tonight(p),addingDays:25)).score)
        }.padding(24).background(.black).preferredColorScheme(.dark)
    }
}
#Preview("Readout • models differ") {
    let m=PlanModel()
    if let p=m.home { ScoreReadout(score:m.night(p).score,agreement:ModelAgreement(low:4,high:48)).padding(24).background(.black).preferredColorScheme(.dark) }
}
#Preview("Readout • AX5") { let m=PlanModel();if let p=m.home { ScoreReadout(score:m.night(p).score).padding(24).background(.black).dynamicTypeSize(.accessibility5).preferredColorScheme(.dark) } }
#Preview("Readout • held by clouds / by the Moon / early look / usual clouds") {
    VStack(spacing:40) {
        ScoreReadout(score:DarknessScore(value:28,moonPoints:40,cloudPoints:5,bortlePoints:17.5,lengthPoints:15,basis:.forecast,cloudUsed:80,limit:.clouds(28)))
        ScoreReadout(score:DarknessScore(value:50,moonPoints:10,cloudPoints:25,bortlePoints:15,lengthPoints:15,basis:.forecast,cloudUsed:0,limit:.moonlight(50)))
        ScoreReadout(score:DarknessScore(value:74,moonPoints:38,cloudPoints:16,bortlePoints:10,lengthPoints:14,basis:.blended(weight:0.4,leadDays:7.2),cloudUsed:36,limit:.skyGlow(74)),isTonight:false)
        ScoreReadout(score:DarknessScore(value:60,moonPoints:30,cloudPoints:14,bortlePoints:17.5,lengthPoints:15,basis:.usual,cloudUsed:44,limit:.clouds(60)))
    }.padding(24).background(.black).preferredColorScheme(.dark)
}

/// Measures the sub-score titles as they draw (caption 2, medium, at the reader's text size), so the
/// four can share one style.
enum SubscoreTitles {
    static let kerning=0.8
    struct Style: Equatable { let spaced: Bool; let scale: Double; let columns: Int }
    /// The first that fits every title's longest word, all four titles alike: spaced capitals four across
    /// (shrunk together to no less than 85%), plain words four across (to 80%), then the same two by two;
    /// failing all, plain words two by two at no less than 70%. `widestSpaced` is nil where letters are
    /// never spaced (Japanese).
    static func style(widestSpaced:Double?,widestPlain:Double,width:Double,spacing:Double)->Style {
        for columns in [4,2] {
            let column=(width-Double(columns-1)*spacing)/Double(columns)
            if let spaced=widestSpaced, spaced>0, column/spaced>=0.85 { return Style(spaced:true,scale:min(1,column/spaced),columns:columns) }
            if widestPlain>0, column/widestPlain>=0.8 { return Style(spaced:false,scale:min(1,column/widestPlain),columns:columns) }
        }
        let column=(width-spacing)/2
        return Style(spaced:false,scale:max(0.7,min(1,column/max(1,widestPlain))),columns:2)
    }
    static func pointSize(_ typeSize:DynamicTypeSize)->Double {
        Double(UIFont.preferredFont(forTextStyle:.caption2,compatibleWith:UITraitCollection(preferredContentSizeCategory:UIContentSizeCategory(typeSize))).pointSize)
    }
    /// Four across with every title whole on one line, all shrunk alike to no less than 85%; nil when
    /// the widest title would need more, and the titles may wrap between words (`style`).
    static func wholeLine(widest:Double,width:Double,spacing:Double)->Style? {
        let column=(width-3*spacing)/4
        guard widest>0, column/widest>=0.85 else { return nil }
        return Style(spaced:false,scale:min(1,column/widest),columns:4)
    }
    /// The widest single word among `titles` (or, `whole`, the widest title): spaced capitals, or the words as written.
    static func widestWord(_ titles:[String],typeSize:DynamicTypeSize,spaced:Bool,bold:Bool,whole:Bool=false)->Double {
        // Measured at full size and at the smallest a style sets (70%), taking the wider once scaled back up, and
        // a point to spare: San Francisco tracks small sizes looser, so a word shrunk to fit exactly by its
        // full-size width came out wider and lost its last letter to a second line ("Himmelsaufhellun" / "g",
        // German on iPad).
        let weight:UIFont.Weight=bold ? .semibold : .medium, words=whole ? titles : titles.flatMap { $0.split(whereSeparator:\.isWhitespace).map(String.init) }
        func width(_ word:String,scale:Double)->Double {
            let font=UIFont.systemFont(ofSize:pointSize(typeSize)*scale,weight:weight)
            let attributes:[NSAttributedString.Key:Any]=spaced ? [.font:font,.kern:kerning*scale] : [.font:font]
            return Double(((spaced ? word.uppercased() : word) as NSString).size(withAttributes:attributes).width)/scale
        }
        return words.map { (max(width($0,scale:1),width($0,scale:0.7))+1).rounded(.up) }.max() ?? 0
    }
}
