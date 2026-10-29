import SwiftUI

/// The lines under a dial, in one order on Tonight and on a park's page, so the same night reads
/// the same way on both. A closure is not one of them: it sits directly under the score
/// (`ClosureLabel`), before anything here. Then: no true darkness, when so; the night in plain words
/// (`NightVerdict`); what the score rests on; one sky line (`skyLine`); the park's alerts, which
/// each screen words for itself; smoke; and the way there.
struct NightNotes<Alerts: View>: View {
    @Environment(PlanModel.self) private var model
    @Environment(\.nyx) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    let night: Night
    /// Whether the night shown is tonight, which words the models' disagreement ("Check again before you leave").
    let isTonight: Bool
    /// The forecast models' score range (`CelestialGauge.modelRange`), which the gauge also speaks.
    let range: ClosedRange<Int>?
    /// Centred under a centred hero; leading where the hero reads from the edge.
    var align: TextAlignment = .center
    /// The month's usual clouds after the basis, on a night without a forecast (the park's page).
    var typicalClouds=false
    @ViewBuilder let alerts: Alerts
    private var inset: CGFloat { align == .center ? 12 : 0 }
    private var alignment: HorizontalAlignment { align == .center ? .center : .leading }
    var body: some View {
        let park=night.park
        if night.sky.state == .polarNight { Text("The Sun stays below the horizon today.").font(.subheadline).foregroundStyle(palette.muted).multilineTextAlignment(align) }
        if night.sky.darkHours==0 { Text(SkyConditions.noDarknessMessage(tonight:isTonight)).font(.body).foregroundStyle(palette.ink).multilineTextAlignment(align) }
        // The night in plain words first: where the Moon is, and whether the Milky Way is worth the drive.
        if let verdict=NightVerdict.line(sky:night.sky,core:model.whatsUp(night).coreNight,park:park) {
            Text(verdict.text).font(.subheadline).foregroundStyle(palette.ink).multilineTextAlignment(align)
                .fixedSize(horizontal:false,vertical:true).padding(.horizontal,inset)
                .accessibilityLabel(verdict.spoken)
        }
        // Only the exceptions (no forecast yet, an early look); a full forecast is the norm and goes unsaid.
        // The gauge speaks the caption; VoiceOver hears only the month's usual clouds here.
        if let caption=night.basisCaption(typical:typicalClouds) {
            let usual=typicalClouds ? night.typicalClouds : nil
            Text(caption).font(.caption).foregroundStyle(palette.muted).multilineTextAlignment(align)
                .fixedSize(horizontal:false,vertical:true).padding(.horizontal,inset)
                .accessibilityLabel(usual ?? caption).accessibilityHidden(usual == nil)
        }
        skyLine
        alerts
        // A caveat in words, in ink: amber is the score's and the light's.
        if let smoke=model.smokeCaveat(night) {
            Label(smoke,systemImage:"smoke").font(.subheadline).foregroundStyle(palette.ink).multilineTextAlignment(align)
                .fixedSize(horizontal:false,vertical:true).padding(.horizontal,inset)
        }
        AccessNoteLabel(park:park,alignment:alignment).frame(maxWidth:420).padding(.horizontal,inset)
    }
    /// One sky line, the first that applies: the forecast models disagreeing (said first, because a
    /// clear window rests on the same clouds), then a clear, dark stretch that is only part of the
    /// night (a Moon up all evening, cloud clearing late), else the models' range in words, as the
    /// share card and the river say it (`ForecastSpread`; the gauge speaks the range).
    @ViewBuilder private var skyLine: some View {
        let agreement=model.outlook(night)?.agreement
        if agreement?.band == .disagree, let spread=ForecastSpread.line(agreement:agreement,range:range,tonight:isTonight) {
            Text(spread).font(.caption).foregroundStyle(palette.muted).multilineTextAlignment(align)
                .fixedSize(horizontal:false,vertical:true).padding(.horizontal,inset)
        } else if let window=Self.partialWindow(night,window:model.clearWindow(night),now:model.present) {
            // At accessibility sizes the glyph would take a column of its own: the words alone. Under a
            // bright Moon the clear hours are not the night's best, and their glyph says so.
            Label { Text(window.line(park:night.park)).fixedSize(horizontal:false,vertical:true) } icon:{ if !typeSize.isAccessibilitySize { Image(systemName:window.moonlit ? "moon" : "sparkles").accessibilityHidden(true) } }
                .font(.subheadline).foregroundStyle(palette.ink).multilineTextAlignment(align).padding(.horizontal,inset)
                .accessibilityElement(children:.combine)
        } else if let spread=ForecastSpread.line(agreement:agreement,range:range,tonight:isTonight) {
            Text(spread).font(.caption).monospacedDigit().foregroundStyle(palette.muted).multilineTextAlignment(align)
                .fixedSize(horizontal:false,vertical:true).padding(.horizontal,inset).accessibilityHidden(true)
        }
    }
    /// The night's best clear window when it is still ahead and covers at most three quarters of the
    /// true darkness: a score earned late in the night must not read as an evening's promise.
    nonisolated static func partialWindow(_ night: Night, window: ClearWindow?, now: Date) -> ClearWindow? {
        guard let window, window.interval.end>now, night.sky.darkHours>0,
              window.interval.duration<=0.75*night.sky.darkHours*3600 else { return nil }
        return window
    }
}

#Preview("Night notes • tonight") {
    let m=PlanModel()
    if let p=m.home {
        VStack(spacing:10) { NightNotes(night:m.night(p),isTonight:true,range:72...86) { Text(m.alertSummary(p)).font(.caption).foregroundStyle(NyxPalette.starlight.opacity(0.7)) } }
            .padding(24).background(.black).environment(m).preferredColorScheme(.dark)
    }
}
#Preview("Night notes • a later night, leading, AX5") {
    let m=PlanModel()
    if let p=m.home {
        VStack(alignment:.leading,spacing:12) { NightNotes(night:m.night(p,on:p.date(m.tonight(p),addingDays:20)),isTonight:false,range:nil,align:.leading,typicalClouds:true) { EmptyView() } }
            .padding(24).background(.black).environment(m).dynamicTypeSize(.accessibility5).preferredColorScheme(.dark)
    }
}
#Preview("Night notes • no true darkness") {
    let m=PlanModel()
    if let p=m.park("dena") {
        VStack(spacing:10) { NightNotes(night:m.night(p,on:Date(timeIntervalSince1970:1782086400)),isTonight:true,range:nil) { EmptyView() } }
            .padding(24).background(.black).environment(m).preferredColorScheme(.dark)
    }
}
