import SwiftUI

/// The darkest of the chosen park's next 14 nights, best first (`NightsAhead`), scored as the
/// night above is. A tap opens that night in the planner, as the ornament's arrows would, and the
/// night on show is marked. Nights without a full cloud forecast say so in the iPhone's words:
/// "Early look" or "Estimate" under the score, and the first of them explained beneath. A park
/// closure is marked on every night ("Closure alert", its words above and in VoiceOver), and a
/// night smoke holds down says so, as the iPhone's rows do.
struct DarkestAhead: View {
    @Environment(VisionModel.self) private var model
    @Environment(\.visionPalette) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    let park: Park
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VisionEyebrow(text: "Darkest of the next 14 nights")
            if let ahead = model.ahead, ahead.park.id == park.id {
                // Side by side; stacked at accessibility sizes, where three columns would clip.
                let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(alignment: .top, spacing: 14))
                layout { ForEach(ahead.picks) { pick in row(pick) } }
                footnote(ahead)
            } else {
                ProgressView().frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func row(_ pick: NightsAhead.Pick) -> some View {
        let night = pick.night, chosen = pick.offset == model.nightOffset, inputs = model.inputs
        return Button { model.nightOffset = pick.offset } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(name(pick)).font(.system(.headline, design: .serif)).foregroundStyle(palette.ink)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(night.score.value, format: .number).font(.system(.largeTitle, design: .serif)).monospacedDigit().foregroundStyle(palette.accent)
                    Text(night.compactBandLabel).font(.callout).foregroundStyle(palette.muted)
                }
                HStack(spacing: 8) {
                    // The phase as a symbol, swapped by name for the southern sky (American Samoa), as on every device.
                    Image(systemName: night.sky.moon.symbolName(southern: night.park.latitude < 0)).foregroundStyle(palette.ink)
                    Text("\(Int((night.sky.moon.illumination*100).rounded()))% lit").font(.subheadline).foregroundStyle(palette.muted)
                }
                if let smoke = night.smokeLabel { Text(smoke).font(.subheadline).foregroundStyle(palette.muted) }
                // The closure's own words stand above the score; each night carries the mark.
                if inputs.closure(park) != nil {
                    Label("Closure alert", systemImage: "exclamationmark.triangle").font(.subheadline).foregroundStyle(palette.accent)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(background, in: .rect(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(chosen ? palette.accent : palette.line, lineWidth: chosen ? 2 : 0.5))
            .contentShape(.hoverEffect, .rect(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .hoverEffect()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(name(pick)))
        .accessibilityValue(Text(verbatim: Sentences.join([Sentences.end(String(localized: "\(night.score.value) out of 100, \(night.bandWithBasis)"))]+inputs.spoken(park, night: night))))
        .accessibilityHint(Text("Shows this night in the planner"))
        .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
    }
    private func name(_ pick: NightsAhead.Pick) -> String {
        pick.offset == 0 ? String(localized: "Tonight") : park.dayLabel(pick.night.id)
    }
    /// Why the nights rank low (no true darkness in reach), or what the first night without a full
    /// forecast rests on, in the words under the score above.
    @ViewBuilder private func footnote(_ ahead: NightsAhead) -> some View {
        if ahead.noDarkness {
            Text("No true darkness in the next 14 nights at this latitude.")
                .font(.footnote).foregroundStyle(palette.muted).fixedSize(horizontal: false, vertical: true)
        } else if let estimate = ahead.firstEstimate {
            VStack(alignment: .leading, spacing: 2) {
                Text(name(estimate)).font(.footnote.weight(.semibold))
                Text(model.cloudCaption(estimate.night)).font(.footnote)
            }
            .foregroundStyle(palette.muted).fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
        }
    }
    /// As the night's fact cells: a full material on glass, a solid panel under Reduce
    /// Transparency, and nothing in night vision, where the window's dark panel shows.
    private var background: AnyShapeStyle {
        if palette.nightVision { return AnyShapeStyle(Color.clear) }
        return palette.solid ? AnyShapeStyle(palette.solidPanel) : AnyShapeStyle(.regularMaterial)
    }
}

/// The preview's frame: the night panel's width, on the window's glass.
private struct AheadPreview: View {
    let model: VisionModel
    var palette = VisionPalette()
    var body: some View {
        Group { if let park = model.park { DarkestAhead(park: park) } }
            .padding(40).frame(width: 820)
            .environment(model).environment(\.visionPalette, palette)
            .glassBackgroundEffect()
    }
}

#Preview("Darkest ahead, usual clouds (cached forecast absent)") {
    AheadPreview(model: VisionModel(now: .now))
}

#Preview("Darkest ahead, no true darkness: Denali in June") {
    let model = VisionModel(now: (try? Date("2026-06-21T21:00:00Z", strategy: .iso8601)) ?? .now)
    model.selectedID = "dena"
    return AheadPreview(model: model)
}

#Preview("Darkest ahead, night vision and Reduce Transparency") {
    let model = VisionModel(now: .now)
    model.nightVision = true
    return AheadPreview(model: model, palette: VisionPalette(nightVision: true, solid: true))
}

#Preview("Darkest ahead, accessibility size") {
    AheadPreview(model: VisionModel(now: .now)).dynamicTypeSize(.accessibility3)
}

#if DEBUG
#Preview("Darkest ahead, forecast and early looks, a later night chosen") {
    let model = VisionModel(now: .now)
    model.forecasts = VisionModel.fixture(parks: model.parks, cover: 30, issued: .now)
    model.nightOffset = 3
    return AheadPreview(model: model)
}
#endif
