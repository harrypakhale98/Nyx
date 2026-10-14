import SwiftUI

/// The score's four parts as an instrument readout under the gauge, so the number always arrives
/// with its reasons. Each meter glides on the shared spring as nights are scrubbed. Without a
/// forecast the cloud meter shows the park's usual clouds and says so. When a cap holds the score
/// below the sum of its parts (clouds, sky glow, smoke, short darkness), one line under the meters
/// names it, so the parts and the number never seem to disagree.
/// The whole readout is one button that opens the full breakdown. Within the seven-day model
/// horizon the cloud meter carries one quiet line saying whether three forecast models agree.
struct ScoreReadout: View {
    @Environment(\.nyx) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    @MotionReduced private var reduceMotion: Bool
    @Environment(\.legibilityWeight) private var legibilityWeight
    /// The meters' width, for fitting the four titles (`titleStyle`).
    @State private var gridWidth=0.0
    private static let columnSpacing=14.0
    let score: DarknessScore
    var agreement: ModelAgreement?=nil
    /// Words the cap line for tonight ("Clouds limit tonight to 55.") or another night.
    var isTonight=true
    var action: () -> Void = {}
    private struct Part: Identifiable {
        let id: String
        let title: String
        let spoken: String
        let points: Double?
        let maximum: Double
        var note: String?=nil
    }
    private var parts: [Part] {
        let scale=score.cloudPoints == nil ? 1/0.75 : 1, shown=score.displayedParts
        return [
            Part(id:"moon",title:String(localized:"Moonlight"),spoken:String(localized:"Moonlight"),points:Double(shown.moon),maximum:40*scale),
            Part(id:"clouds",title:String(localized:"Clouds"),spoken:String(localized:"Clouds"),points:shown.cloud.map(Double.init),maximum:25,note:cloudNote),
            Part(id:"glow",title:String(localized:"Sky glow"),spoken:String(localized:"Sky glow"),points:Double(shown.glow),maximum:20*scale),
            Part(id:"hours",title:String(localized:"True darkness"),spoken:String(localized:"True darkness"),points:Double(shown.length),maximum:15*scale)
        ]
    }
    private var cloudNote: String? {
        switch score.basis {
        case .forecast: agreement?.word
        case .blended: String(localized:"Early look")
        case .usual: score.cloudPoints == nil ? nil : String(localized:"Usual clouds")
        }
    }
    /// The binding cap, when the parts add up to more than the score.
    private var limitLine: String? {
        guard let limit=score.limit else { return nil }
        return limit.cap<score.partsSum ? limit.sentence(tonight:isTonight) : nil
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
                    .onGeometryChange(for:Double.self) { $0.size.width } action:{ gridWidth=$0 }
                }
                // The weakest link, when it holds the score below its parts: the number and the meters agree.
                if let limitLine {
                    Text(limitLine).font(.caption).foregroundStyle(palette.accent).fixedSize(horizontal:false,vertical:true).frame(maxWidth:.infinity,alignment:.leading)
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
        guard gridWidth>0 else { return SubscoreTitles.Style(spaced:Lettering.spaced,scale:1,columns:4) }
        let bold=legibilityWeight == .bold, titles=parts.map(\.title)
        return SubscoreTitles.style(widestSpaced:Lettering.spaced ? SubscoreTitles.widestWord(titles,typeSize:typeSize,spaced:true,bold:bold) : nil,
                                    widestPlain:SubscoreTitles.widestWord(titles,typeSize:typeSize,spaced:false,bold:bold),width:gridWidth,spacing:Self.columnSpacing)
    }
    private func meter(_ part:Part)->some View {
        Meter(fraction:part.points.map { min(1,max(0,$0/part.maximum)) },reduceMotion:reduceMotion)
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
    /// A hairline track with an amber fill; dashed and empty when the part is unknown.
    private struct Meter: View {
        @Environment(\.nyx) private var palette
        let fraction: Double?
        let reduceMotion: Bool
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
                .animation(reduceMotion ? nil : NyxMotion.spring,value:fraction)
            }.frame(height:3)
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
#Preview("Readout • held by clouds / early look / usual clouds") {
    VStack(spacing:40) {
        ScoreReadout(score:DarknessScore(value:28,moonPoints:40,cloudPoints:5,bortlePoints:17.5,lengthPoints:15,basis:.forecast,cloudUsed:80,limit:.clouds(28)))
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
    /// The widest single word among `titles`: spaced capitals, or the words as written.
    static func widestWord(_ titles:[String],typeSize:DynamicTypeSize,spaced:Bool,bold:Bool)->Double {
        let font=UIFont.systemFont(ofSize:pointSize(typeSize),weight:bold ? .semibold : .medium)
        let attributes:[NSAttributedString.Key:Any]=spaced ? [.font:font,.kern:kerning] : [.font:font]
        let words=titles.flatMap { $0.split(whereSeparator:\.isWhitespace).map(String.init) }
        return words.map { word in Double(((spaced ? word.uppercased() : word) as NSString).size(withAttributes:attributes).width.rounded(.up)) }.max() ?? 0
    }
}
