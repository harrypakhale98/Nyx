import SwiftUI

/// One park's coming week at a glance, in the calendar's vocabulary: a dot per night sized by
/// score, filled with a forecast, half-filled for an early look and hollow without one. The best night is ringed and named, so
/// a list of places also answers "which night".
struct WeekStrip: View {
    @Environment(\.nyx) private var palette
    @Environment(\.nyxAccess) private var access
    let nights: [Night]
    /// The earliest of the highest-scoring nights.
    private var best: Night? { nights.reduce(nil) { best,night in best.map { night.score.value>$0.score.value ? night : $0 } ?? night } }
    var body: some View {
        if let best, let first=nights.first {
            HStack(spacing:10) {
                dots(best:best).frame(width:CGFloat(nights.count)*13,height:16)
                Text(best.id==first.id ? String(localized:"Best tonight") : String(localized:"Best \(weekday(best)) · \(best.score.value)"))
                    .font(.caption2.monospacedDigit()).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
            }
        }
    }
    private func dots(best:Night)->some View {
        Canvas { context,size in
            for (index,night) in nights.enumerated() {
                let center=CGPoint(x:6.5+CGFloat(index)*13,y:size.height/2)
                let radius=1.3+3.6*pow(Double(night.score.value)/100,1.5)
                let mark=NightMark.mark(night,differentiate:access.differentiate)
                mark.draw(in:&context,center:center,radius:radius,fill:night.basis.fill,color:palette.accent,fillOpacity:0.45+Double(night.score.value)/200,lineWidth:0.8)
                if night.id==best.id {
                    context.stroke(Path(ellipseIn:CGRect(x:center.x-6.5,y:center.y-6.5,width:13,height:13)),with:.color(palette.accent.opacity(0.75)),lineWidth:0.7)
                }
            }
        }.accessibilityHidden(true)
    }
    private func weekday(_ night:Night)->String {
        night.id.formatted(Date.FormatStyle(timeZone:night.park.timeZone).weekday(.abbreviated))
    }
    /// For a row's VoiceOver label.
    static func summary(_ nights:[Night])->String? {
        guard let first=nights.first, let best=WeekStrip(nights:nights).best else { return nil }
        if best.id==first.id { return String(localized:"Tonight is the best night this week.") }
        return String(localized:"Best night this week: \(best.park.dayLabel(best.id)), \(best.score.value).")
    }
}
#Preview("Week strip") { let m=PlanModel();if let p=m.home { WeekStrip(nights:m.nights(p,from:m.tonight(p),count:7)).padding().background(.black).preferredColorScheme(.dark) } }
