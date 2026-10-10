import SwiftUI

/// One park's coming week at a glance, in the calendar's vocabulary: a dot per night sized by
/// score, filled with a forecast, half-filled for an early look and hollow without one. The best night is ringed and named, so
/// a list of places also answers "which night".
struct WeekStrip: View {
    @Environment(\.nyx) private var palette
    @Environment(\.nyxAccess) private var access
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The column pitch grows with the caption beside it (13 pt at the default size), so the dots
    /// keep company with the text; capped at 1.8× (`WeekStrip.pitch`), where accessibility sizes
    /// take over with the sentence alone.
    @ScaledMetric(relativeTo:.caption2) private var scaledPitch=13.0
    let nights: [Night]
    /// The best night, ties broken as everywhere (`NightPlanner.best`).
    private var best: Night? { NightPlanner.best(nights) }
    var body: some View {
        if let best, let first=nights.first {
            let line=Text(best.id==first.id ? String(localized:"Best tonight") : String(localized:"Best \(weekday(best)) · \(best.score.value)"))
                .font(.caption2.monospacedDigit()).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
            // At accessibility sizes the sentence carries the week alone: it already names the best
            // night, and dots a few points across beside 40 pt text read as specks.
            if typeSize.isAccessibilitySize { line }
            else {
                let pitch=WeekStrip.pitch(scaledPitch)
                HStack(spacing:10) {
                    dots(best:best,pitch:pitch).frame(width:CGFloat(nights.count)*pitch,height:16*pitch/13)
                    line
                }
            }
        }
    }
    /// The column pitch for a scaled 13 pt: never below 13, never above 1.8× it.
    static func pitch(_ scaled:Double)->Double { min(max(scaled,13),13*1.8) }
    private func dots(best:Night,pitch:Double)->some View {
        Canvas { context,size in
            let scale=pitch/13
            for (index,night) in nights.enumerated() {
                let center=CGPoint(x:pitch/2+CGFloat(index)*pitch,y:size.height/2)
                let radius=(1.3+3.6*pow(Double(night.score.value)/100,1.5))*scale
                let mark=NightMark.mark(night,differentiate:access.differentiate)
                mark.draw(in:&context,center:center,radius:radius,fill:night.basis.fill,color:palette.accent,fillOpacity:palette.markOpacity(score:night.score.value),lineWidth:0.8*scale,stroke:palette.stroke)
                if night.id==best.id {
                    let ring=pitch/2
                    context.stroke(Path(ellipseIn:CGRect(x:center.x-ring,y:center.y-ring,width:2*ring,height:2*ring)),with:.color(palette.accent.opacity(0.75)),lineWidth:0.7*scale*palette.stroke)
                }
            }
        }.accessibilityHidden(true)
    }
    private func weekday(_ night:Night)->String {
        night.id.formatted(Date.FormatStyle(timeZone:night.park.timeZone).weekday(.abbreviated))
    }
    /// For a row's VoiceOver label, with the best night's forecast caveat ("Early look", "No cloud
    /// forecast yet") when it has one, as the dots show it.
    static func summary(_ nights:[Night])->String? {
        guard let first=nights.first, let best=WeekStrip(nights:nights).best else { return nil }
        let line=best.id==first.id ? String(localized:"Tonight is the best night this week.")
            : String(localized:"Best night this week: \(best.park.dayLabel(best.id)), \(best.score.value).")
        return best.basisLabel.map { line+" "+$0+"." } ?? line
    }
}
#Preview("Week strip") { let m=PlanModel();if let p=m.home { WeekStrip(nights:m.nights(p,from:m.tonight(p),count:7)).padding().background(.black).preferredColorScheme(.dark) } }
#Preview("Week strip • Bold Text") { let m=PlanModel();if let p=m.home { WeekStrip(nights:m.nights(p,from:m.tonight(p),count:7)).padding().background(.black).environment(\.nyx,NyxPalette(nightVision:false,highContrast:false,boldText:true)).preferredColorScheme(.dark) } }
#Preview("Week strip • xxxLarge") { let m=PlanModel();if let p=m.home { WeekStrip(nights:m.nights(p,from:m.tonight(p),count:7)).padding().background(.black).dynamicTypeSize(.xxxLarge).preferredColorScheme(.dark) } }
#Preview("Week strip • accessibility size") { let m=PlanModel();if let p=m.home { WeekStrip(nights:m.nights(p,from:m.tonight(p),count:7)).padding().background(.black).dynamicTypeSize(.accessibility3).preferredColorScheme(.dark) } }
