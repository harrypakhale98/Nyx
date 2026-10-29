import SwiftUI

/// One park's coming week at a glance, in the calendar's vocabulary: a dot per night sized by
/// score, filled with a forecast, half-filled for an early look and hollow without one. The best night is ringed and named, so
/// a list of places also answers "which night". The sizes span the week's own range (`radius`): a
/// week of 40s to 60s reads as a week with a peak, where sizes on the whole 0…100 scale were
/// indistinguishable specks; the fill's strength still follows the score itself.
struct WeekStrip: View {
    @Environment(\.nyx) private var palette
    @Environment(\.nyxAccess) private var access
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The column pitch grows with the caption beside it (16 pt at the default size), so the dots
    /// keep company with the text; capped at 1.8× (`WeekStrip.pitch`), where accessibility sizes
    /// take over with the sentence alone.
    @ScaledMetric(relativeTo:.caption2) private var scaledPitch=WeekStrip.basePitch
    let nights: [Night]
    /// The best night, ties broken as everywhere (`NightPlanner.best`).
    private var best: Night? { NightPlanner.best(nights) }
    var body: some View {
        if let best, let first=nights.first {
            // Said as the week's best: the park page and Best nights name the best of thirty nights.
            let line=Text(WeekBest.label(nights) ?? WeekBest.label(best,first:first))
                .font(.caption2.monospacedDigit()).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
            // At accessibility sizes the sentence carries the week alone: it already names the best
            // night, and dots a few points across beside 40 pt text read as specks.
            if typeSize.isAccessibilitySize { line }
            else {
                let pitch=WeekStrip.pitch(scaledPitch)
                let strip=dots(best:best,pitch:pitch).frame(width:CGFloat(nights.count)*pitch,height:pitch*1.1)
                // In a narrow row the caption moves under the dots whole rather than orphaning its score.
                ViewThatFits(in:.horizontal) {
                    HStack(spacing:10) { strip;line.fixedSize() }
                    VStack(alignment:.leading,spacing:4) { strip;line }
                }
            }
        }
    }
    /// The default column pitch: the best night's ring (`ringRadius`) and a neighbour's largest dot
    /// (5 pt radius) with 4 pt of sky between them; wider and the strip crowds its caption on a 375 pt phone.
    static let basePitch=16.0
    /// The best night's ring at the default size: just outside the largest dot, not the whole column,
    /// so it reads as that night's and never touches the next.
    static let ringRadius=5+1.7
    /// The column pitch for a scaled 16 pt: never below 16, never above 1.8× it.
    static func pitch(_ scaled:Double)->Double { min(max(scaled,basePitch),basePitch*1.8) }
    /// A night's dot radius at the default size: the week's lowest score at 1.6 pt, its highest at
    /// 5, the rest between by score (`NightMark.radius`, the widgets' and the watch's rule too).
    static func radius(score:Int,low:Int,high:Int)->Double { NightMark.radius(score:score,low:low,high:high) }
    private func dots(best:Night,pitch:Double)->some View {
        let scores=nights.map(\.score.value), low=scores.min() ?? 0, high=scores.max() ?? 0
        return Canvas { context,size in
            let scale=pitch/WeekStrip.basePitch
            for (index,night) in nights.enumerated() {
                let center=CGPoint(x:pitch/2+CGFloat(index)*pitch,y:size.height/2)
                let radius=WeekStrip.radius(score:night.score.value,low:low,high:high)*scale
                let mark=NightMark.mark(night,differentiate:access.differentiate)
                mark.draw(in:&context,center:center,radius:radius,fill:night.basis.fill,color:palette.accent,fillOpacity:palette.markOpacity(score:night.score.value),lineWidth:0.8*scale,stroke:palette.stroke)
                if night.id==best.id {
                    let ring=WeekStrip.ringRadius*scale
                    context.stroke(Path(ellipseIn:CGRect(x:center.x-ring,y:center.y-ring,width:2*ring,height:2*ring)),with:.color(palette.accent.opacity(0.75)),lineWidth:0.7*scale*palette.stroke)
                }
            }
        }.accessibilityHidden(true)
    }
    /// For a row's VoiceOver label, with the best night's forecast caveat ("Early look", "No cloud
    /// forecast yet") when it has one, as the dots show it.
    static func summary(_ nights:[Night])->String? {
        guard let first=nights.first, let best=WeekStrip(nights:nights).best else { return nil }
        let line=best.id==first.id ? String(localized:"Tonight is the best night this week.")
            : String(localized:"Best night this week: \(best.park.dayLabel(best.id)), \(best.score.value).")
        return Sentences.join([line]+best.basisLabels.map(Sentences.end))
    }
}
#Preview("Week strip") { let m=PlanModel();if let p=m.home { WeekStrip(nights:m.nights(p,from:m.tonight(p),count:7)).padding().background(.black).preferredColorScheme(.dark) } }
#Preview("Week strip • Bold Text") { let m=PlanModel();if let p=m.home { WeekStrip(nights:m.nights(p,from:m.tonight(p),count:7)).padding().background(.black).environment(\.nyx,NyxPalette(nightVision:false,highContrast:false,boldText:true)).preferredColorScheme(.dark) } }
#Preview("Week strip • xxxLarge") { let m=PlanModel();if let p=m.home { WeekStrip(nights:m.nights(p,from:m.tonight(p),count:7)).padding().background(.black).dynamicTypeSize(.xxxLarge).preferredColorScheme(.dark) } }
#Preview("Week strip • accessibility size") { let m=PlanModel();if let p=m.home { WeekStrip(nights:m.nights(p,from:m.tonight(p),count:7)).padding().background(.black).dynamicTypeSize(.accessibility3).preferredColorScheme(.dark) } }
