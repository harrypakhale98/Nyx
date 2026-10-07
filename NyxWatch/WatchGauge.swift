import SwiftUI

/// The iPhone's celestial gauge, distilled for the wrist: an arc open at the bottom, ticks every
/// ten points, a leading star where the score has reached, and the Moon resting in the opening.
/// The arc sweeps in on the shared spring once, with one light tap as it lands; still under Reduce
/// Motion and wrist-down. Turning the Crown through the week springs the arc to each night's score.
struct WatchGauge: View {
    @Environment(\.nyx) private var palette
    @Environment(\.isLuminanceReduced) private var dimmed
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    let night: Night
    /// The night's day ("Fri, Oct 9") when it is not tonight, read first by VoiceOver.
    var nightLabel: String? = nil
    @State private var shown = 0.0
    @State private var revealed = false
    var body: some View {
        let score = night.score.value
        // Proportions follow the dial, not the text size: the numeral is the dial's face. At
        // accessibility sizes the band word leaves the dial for the line below it.
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                GaugeArc(value: shown, hasForecast: night.score.hasForecast, dimmed: dimmed, palette: palette)
                VStack(spacing: -side*0.02) {
                    Text(score, format: .number)
                        .font(.system(size: side*0.36, weight: .light, design: .serif)).tracking(-side*0.012)
                        .foregroundStyle(palette.accent).lineLimit(1).minimumScaleFactor(0.5)
                    if !typeSize.isAccessibilitySize {
                        Text(night.score.band.label).font(.system(size: max(10, side*0.11), design: .serif)).lineLimit(1).minimumScaleFactor(0.7)
                    }
                }
                .padding(.horizontal, side*0.16).offset(y: -side*0.045)
                MoonDisc(illumination: night.sky.moon.illumination, waxing: night.sky.moon.waxing, southern: night.park.latitude < 0)
                    .frame(width: side*0.15, height: side*0.15)
                    .position(x: proxy.size.width/2, y: proxy.size.height/2 + side*0.39)
                    .opacity(dimmed ? 0.7 : 1)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Darkness score")
        .accessibilityValue("\(nightLabel.map { $0 + ", " } ?? "")\(score) out of 100, \(night.score.band.label). \(night.basisCaption() ?? String(localized: "Includes cloud forecast.")) \(night.sky.moon.name), \(Int((night.sky.moon.illumination*100).rounded())) percent lit.")
        .task(id: score) {
            if reduceMotion || dimmed || shown > 0 { withAnimation(reduceMotion ? nil : NyxMotion.spring) { shown = Double(score) }; return }
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(NyxMotion.spring) { shown = Double(score) }
            revealed = true
        }
        .sensoryFeedback(.selection, trigger: revealed) { _, new in new }
        .onChange(of: dimmed) { _, _ in shown = Double(score) }
    }
}

private struct GaugeArc: View, Animatable {
    var value: Double
    var animatableData: Double { get { value } set { value = newValue } }
    let hasForecast: Bool
    let dimmed: Bool
    let palette: NyxPalette
    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width/2, y: size.height/2), radius = min(size.width, size.height)/2 - 10 // room for the glow
            let start = 140.0, sweep = 260.0
            var track = Path()
            track.addArc(center: center, radius: radius, startAngle: .degrees(start), endAngle: .degrees(start+sweep), clockwise: false)
            context.stroke(track, with: .color(palette.line), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            for tick in 0...10 {
                let a = (start + Double(tick)*sweep/10) * .pi/180
                let lit = Double(tick*10) <= value
                var line = Path()
                line.move(to: CGPoint(x: center.x+cos(a)*(radius-5), y: center.y+sin(a)*(radius-5)))
                line.addLine(to: CGPoint(x: center.x+cos(a)*(radius-(tick%5==0 ? 10 : 8)), y: center.y+sin(a)*(radius-(tick%5==0 ? 10 : 8))))
                context.stroke(line, with: .color(lit ? palette.accent.opacity(0.7) : palette.line), lineWidth: 1)
            }
            guard value > 0.5 else { return }
            let tip = start + sweep*min(100, value)/100
            var arc = Path()
            arc.addArc(center: center, radius: radius, startAngle: .degrees(start), endAngle: .degrees(tip), clockwise: false)
            // Dashed without a full forecast, as on the iPhone: the clouds are an early look or the usual ones.
            let dash: [CGFloat] = hasForecast ? [] : [3, 5]
            if !dimmed {
                context.drawLayer { glow in
                    glow.addFilter(.blur(radius: 4))
                    glow.stroke(arc, with: .color(palette.accent.opacity(0.2+0.3*value/100)), style: StrokeStyle(lineWidth: 6, lineCap: .round, dash: dash))
                }
            }
            context.stroke(arc, with: .color(palette.accent), style: StrokeStyle(lineWidth: 3.5, lineCap: .round, dash: dash))
            let point = CGPoint(x: center.x+cos(tip * .pi/180)*radius, y: center.y+sin(tip * .pi/180)*radius)
            if !dimmed {
                context.fill(Path(ellipseIn: CGRect(x: point.x-8, y: point.y-8, width: 16, height: 16)),
                             with: .radialGradient(Gradient(colors: [palette.accent.opacity(0.55), palette.accent.opacity(0)]), center: point, startRadius: 0, endRadius: 8))
            }
            context.fill(Path(ellipseIn: CGRect(x: point.x-2.8, y: point.y-2.8, width: 5.6, height: 5.6)), with: .color(palette.ink))
        }
        .accessibilityHidden(true)
    }
}

#Preview("Pristine • red") {
    if let park = try? ParkData.load().first(where: { $0.id == "jotr" }) {
        WatchGauge(night: WatchSky.night(park, evening: park.currentNight(at: .now), forecast: nil, now: .now))
            .environment(\.nyx, NyxPalette(nightVision: true, highContrast: false)).modifier(NightVisionFilter(enabled: true))
    }
}
#Preview("Starlight • AX") {
    if let park = try? ParkData.load().first(where: { $0.id == "dena" }) {
        WatchGauge(night: WatchSky.night(park, evening: park.currentNight(at: .now), forecast: nil, now: .now)).dynamicTypeSize(.accessibility3)
    }
}
