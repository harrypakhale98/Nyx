import SwiftUI

/// The ornament under the window: step between nights, and scrub one night from sunset to
/// sunrise. The immersive sky turns with it; the Moon and planets move against the stars.
struct NightControls: View {
    @Environment(VisionModel.self) private var model
    @Environment(\.visionPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    /// While the slider is held in the immersive sky: where the hand has put it. The sky follows
    /// no faster than `VisionModel.comfortableTurn` (or, under Reduce Motion, once on letting go),
    /// so the thumb shows the hand and the time above it shows the sky.
    @State private var held: Double?
    @State private var editing = false
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
        .colorMultiply(model.nightVision ? palette.red : .white)
    }

    private var nightStepper: some View {
        @Bindable var model = model
        return HStack(spacing: 10) {
            Button { model.nightOffset -= 1 } label: { Image(systemName: "chevron.backward") }
                .disabled(model.nightOffset == 0)
                .accessibilityLabel(Text("Previous night"))
            VStack(spacing: 0) {
                Text(nightTitle).font(.system(.headline, design: .serif))
                if model.nightOffset > 0 {
                    // Regular control size: a full 44 pt target, set small by its type.
                    Button("Back to tonight") { model.nightOffset = 0 }
                        .font(.callout).buttonStyle(.bordered).buttonBorderShape(.capsule).padding(.top, 6)
                }
            }
            .frame(minWidth: 130)
            Button { model.nightOffset += 1 } label: { Image(systemName: "chevron.forward") }
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
                Slider(value: Binding(get: { held ?? model.fraction }, set: { scrub(to: $0) }), in: 0...1) {
                    Text("Time of night")
                } onEditingChanged: { began in
                    editing = began
                    guard !began, let target = held else { return }
                    held = nil
                    // Reduce Motion in the sky: one move, without a sweep, once the hand lets go.
                    if reduceMotion, model.immersiveOpen { model.move(to: target, reduceMotion: true) }
                }
                .frame(minWidth: 280)
                .accessibilityValue(model.skyMoment.map { Text("\(park.time(now)), \($0.twilight)") } ?? Text(park.time(now)))
            }
            Text(park.time(span.end)).font(.caption).foregroundStyle(palette.muted).monospacedDigit().accessibilityHidden(true)
            // With no true darkness (an Alaskan summer), the same button goes to the middle of the night.
            let dark = plan.sky.darkHours > 0
            Button { model.darkest(reduceMotion: reduceMotion) } label: {
                Label(dark ? "Middle of darkness" : "Middle of the night", systemImage: "moon.stars")
            }
            .help(dark ? Text("Middle of true darkness") : Text("Middle of the night, halfway from sunset to sunrise"))
            .accessibilityHint(dark ? Text("Moves the clock to the middle of true darkness") : Text("Moves the clock halfway from sunset to sunrise"))
        }
    }
    /// The slider in the window moves the clock directly. In the immersive sky it is a drag of
    /// the whole sky, so it takes the sky's rules: the comfortable turn while held, and under
    /// Reduce Motion a single jump when let go (a VoiceOver adjustment, with no hold, jumps at once).
    private func scrub(to value: Double) {
        guard model.immersiveOpen else { model.cancelSweep(); model.fraction = value; return }
        if editing { held = value }
        if !reduceMotion { model.turn(toward: value) } else if !editing { model.move(to: value, reduceMotion: true) }
    }
}

#Preview("Night controls") {
    NightControls().environment(VisionModel(now: .now))
}

#Preview("Night controls, a later night, no true darkness") {
    // Denali in June: no true darkness, and a night after tonight (Back to tonight shown).
    let model = VisionModel(now: (try? Date("2026-06-21T21:00:00Z", strategy: .iso8601)) ?? .now)
    model.selectedID = "dena"
    model.nightOffset = 2
    return NightControls().environment(model)
}

#Preview("Night controls, night vision") {
    let model = VisionModel(now: .now)
    model.nightVision = true
    return NightControls().environment(model).environment(\.visionPalette, VisionPalette(nightVision: true))
}
