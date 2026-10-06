import SwiftUI

/// The ornament under the window: step between nights, and scrub one night from sunset to
/// sunrise. The immersive sky turns with it; the Moon and planets move against the stars.
struct NightControls: View {
    @Environment(VisionModel.self) private var model
    @Environment(\.visionPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 16)) : AnyLayout(HStackLayout(spacing: 26))
        layout {
            nightStepper
            if let plan = model.plan { clock(plan) }
        }
        .padding(.horizontal, 28).padding(.vertical, 18)
        .frame(minWidth: 760)
        .glassBackgroundEffect(displayMode: model.nightVision ? .never : .always)
        .background { if model.nightVision { Capsule().fill(palette.nightPanel) } }
        .saturation(model.nightVision ? 0 : 1)
        .colorMultiply(model.nightVision ? Color(red: 1, green: 0.27, blue: 0.23) : .white)
    }

    private var nightStepper: some View {
        @Bindable var model = model
        return HStack(spacing: 10) {
            Button { model.nightOffset -= 1 } label: { Image(systemName: "chevron.left") }
                .disabled(model.nightOffset == 0)
                .accessibilityLabel(Text("Previous night"))
            VStack(spacing: 0) {
                Text(nightTitle).font(.system(.headline, design: .serif))
                if model.nightOffset > 0 { Button("Back to tonight") { model.nightOffset = 0 }.font(.caption).buttonStyle(.borderless) }
            }
            .frame(minWidth: 130)
            Button { model.nightOffset += 1 } label: { Image(systemName: "chevron.right") }
                .disabled(model.nightOffset >= 365)
                .accessibilityLabel(Text("Next night"))
        }
        .buttonBorderShape(.circle)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Night"))
    }
    private var nightTitle: String {
        guard let park = model.park else { return "" }
        return model.nightOffset == 0 ? String(localized: "Tonight") : park.dayLabel(model.night(for: park))
    }

    private func clock(_ plan: NightPlan) -> some View {
        @Bindable var model = model
        let park = plan.park, span = plan.span
        let now = SkyDome.moment(model.fraction, in: span)
        return HStack(spacing: 14) {
            Text(park.time(span.start)).font(.caption).foregroundStyle(palette.muted).monospacedDigit().accessibilityHidden(true)
            VStack(spacing: 4) {
                Text(park.time(now)).font(.system(.title3, design: .serif)).monospacedDigit().foregroundStyle(palette.accent)
                    .contentTransition(.numericText())
                Slider(value: Binding(get: { model.fraction }, set: { model.cancelSweep(); model.fraction = $0 }), in: 0...1) {
                    Text("Time of night")
                }
                .frame(minWidth: 280)
                .accessibilityValue(Text("\(park.time(now)), \(SkyMoment(park: park, at: now).twilight)"))
            }
            Text(park.time(span.end)).font(.caption).foregroundStyle(palette.muted).monospacedDigit().accessibilityHidden(true)
            Button { model.darkest(reduceMotion: reduceMotion) } label: {
                Label("Middle of darkness", systemImage: "moon.stars")
            }
            .help(Text("Middle of true darkness"))
            .accessibilityHint(Text("Moves the clock to the middle of true darkness"))
        }
    }
}
