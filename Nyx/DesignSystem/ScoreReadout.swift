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
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.nyxReduceMotion) private var forcedReduceMotion
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
                    Grid(alignment:.leading,horizontalSpacing:14,verticalSpacing:7) {
                        GridRow(alignment:.bottom) { ForEach(parts) { part in title(part).frame(maxWidth:.infinity,alignment:.leading) } }
                        GridRow { ForEach(parts) { part in meter(part) } }
                        GridRow(alignment:.top) { ForEach(parts) { part in value(part) } }
                    }
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
    private func title(_ part:Part)->some View {
        // Two words may wrap ("Horas oscuras"); one long word shrinks a little rather than break ("Resplandor").
        let oneWord = !part.title.contains(" ")
        return Text(part.title).font(.caption2.weight(.medium)).kerning(typeSize.isAccessibilitySize ? 0 : 0.8).textCase(typeSize.isAccessibilitySize ? nil : .uppercase)
            .foregroundStyle(palette.muted).lineLimit(typeSize.isAccessibilitySize ? nil : oneWord ? 1 : 2).minimumScaleFactor(0.7).allowsTightening(true).fixedSize(horizontal:false,vertical:true)
    }
    private func meter(_ part:Part)->some View {
        Meter(fraction:part.points.map { min(1,max(0,$0/part.maximum)) },reduceMotion:systemReduceMotion || forcedReduceMotion)
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
