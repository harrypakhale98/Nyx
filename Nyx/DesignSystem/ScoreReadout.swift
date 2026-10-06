import SwiftUI

/// The score's four parts as an instrument readout under the gauge, so the number always arrives
/// with its reasons. Each meter glides on the shared spring as nights are scrubbed. Without a
/// forecast the cloud meter reads "Unknown" and the other maxima scale up, exactly as the score does.
/// The whole readout is one button that opens the full breakdown. Within the seven-day model
/// horizon the cloud meter carries one quiet line saying whether three forecast models agree.
struct ScoreReadout: View {
    @Environment(\.nyx) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.nyxReduceMotion) private var forcedReduceMotion
    let score: DarknessScore
    var agreement: ModelAgreement?=nil
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
        let scale=score.hasForecast ? 1 : 1/0.75
        return [
            Part(id:"moon",title:String(localized:"Moon"),spoken:String(localized:"Moonlight"),points:score.moonPoints,maximum:40*scale),
            Part(id:"clouds",title:String(localized:"Clouds"),spoken:String(localized:"Cloud cover"),points:score.cloudPoints,maximum:25,note:score.hasForecast ? agreement?.word : nil),
            Part(id:"glow",title:String(localized:"Sky glow"),spoken:String(localized:"Light pollution"),points:score.bortlePoints,maximum:20*scale),
            Part(id:"hours",title:String(localized:"Dark hours"),spoken:String(localized:"Length of darkness"),points:score.lengthPoints,maximum:15*scale)
        ]
    }
    var body: some View {
        Button(action:action) {
            Group {
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
        }.joined(separator:". ")
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
