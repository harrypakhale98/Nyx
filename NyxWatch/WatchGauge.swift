import SwiftUI

/// The iPhone's celestial gauge, distilled for the wrist: an arc open at the bottom, ticks every
/// ten points, a leading star where the score has reached, and the Moon resting in the opening.
/// The arc sweeps in on the shared spring once, with one light tap as it lands; still under Reduce
/// Motion and wrist-down. Turning the Crown through the week springs the arc to each night's score.
/// Where the iPhone shows the forecast models' range, a hairline along the rim marks it, as on the
/// iPhone's dial, and settles in as the arc lands, so uncertainty comes last and costs no line of text.
struct WatchGauge: View {
    @Environment(\.nyx) private var palette
    @Environment(\.isLuminanceReduced) private var dimmed
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.legibilityWeight) private var legibility
    let night: Night
    /// The night's day ("Fri, Oct 9") when it is not tonight, read first by VoiceOver.
    var nightLabel: String? = nil
    /// The forecast models' range the iPhone shows for this night (`WatchContext.modelRange`),
    /// drawn along the rim and spoken with the score; the words under the dial are hidden from VoiceOver.
    var models: ClosedRange<Int>? = nil
    @State private var shown = 0.0
    @State private var revealed = false
    var body: some View {
        let score = night.score.value
        // Proportions follow the dial, not the text size: the numeral is the dial's face. At
        // accessibility sizes the band word leaves the dial for the line below it.
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                GaugeArc(value: shown, target: Double(score), models: models, hasForecast: night.score.hasForecast, dimmed: dimmed, palette: palette)
                // The word sits under the numeral, clear of every tick: smaller if it must, then
                // with a slightly smaller numeral, and only where even that cannot clear the ticks
                // does the numeral stand alone (`WatchDialFace.choose`); VoiceOver always says the band.
                let face = self.face(side: side)
                VStack(spacing: WatchDialFace.spacing(side: side)) {
                    Text(score, format: .number)
                        .font(.system(size: WatchDialFace.numeralSize(side: side)*face.numeral, weight: .light, design: .serif)).tracking(-side*0.012*face.numeral)
                        .foregroundStyle(palette.accent).lineLimit(1).minimumScaleFactor(0.5)
                    if let word = face.word {
                        Text(night.score.band.label).font(.system(size: WatchDialFace.wordSize(side: side)*word, design: .serif)).lineLimit(1).fixedSize()
                    }
                }
                .padding(.horizontal, side*0.16).offset(y: -WatchDialFace.lift(side: side))
                MoonDisc(illumination: night.sky.moon.illumination, waxing: night.sky.moon.waxing, southern: night.park.latitude < 0)
                    .frame(width: side*0.15, height: side*0.15)
                    .position(x: proxy.size.width/2, y: proxy.size.height/2 + side*0.39)
                    .opacity(dimmed ? 0.7 : 1)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Darkness score")
        .accessibilityValue(spoken)
        .task(id: score) {
            if reduceMotion || dimmed || shown > 0 { withAnimation(reduceMotion ? nil : NyxMotion.spring) { shown = Double(score) }; return }
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(NyxMotion.spring) { shown = Double(score) }
            revealed = true
        }
        .sensoryFeedback(.selection, trigger: revealed) { _, new in new }
        .onChange(of: dimmed) { _, _ in shown = Double(score) }
    }
    /// The numeral's and band word's sizes for this dial. At accessibility sizes the word leaves
    /// the dial for the line below it.
    private func face(side: Double) -> WatchDialFace.Choice {
        guard !typeSize.isAccessibilitySize, side > 0 else { return WatchDialFace.Choice(numeral: 1, word: nil) }
        let bold = legibility == .bold
        let numeral = WatchDialFace.Line.serif(String(night.score.value), size: WatchDialFace.numeralSize(side: side), weight: .light, bold: bold)
        let word = WatchDialFace.Line.serif(night.score.band.label, size: WatchDialFace.wordSize(side: side), weight: .regular, bold: bold)
        return WatchDialFace.choose(side: side, numeral: numeral, word: word, wordSize: WatchDialFace.wordSize(side: side))
    }
    /// The night, the score and its band, what the clouds rest on (with the models' range on a
    /// night that has one, as the iPhone's dial says it), then the Moon.
    private var spoken: String {
        var clouds = night.basisCaption() ?? String(localized: "Includes cloud forecast.")
        if let models { clouds += " " + String(localized: "Forecast models: \(models.lowerBound) to \(models.upperBound).") }
        let day = nightLabel.map { $0 + ", " } ?? "", lit = Int((night.sky.moon.illumination*100).rounded())
        return String(localized: "\(day)\(night.score.value) out of 100, \(night.score.band.label). \(clouds) \(night.sky.moon.name), \(lit) percent lit.")
    }
}

private struct GaugeArc: View, Animatable {
    var value: Double
    var animatableData: Double { get { value } set { value = newValue } }
    /// The score the arc is heading for, and the models' range around it.
    let target: Double
    let models: ClosedRange<Int>?
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
            if let models {
                // The models' range just outside the track: a hairline with a tick at each end, so it
                // reads as a measured span rather than more arc (the iPhone dial's contrast form, which
                // a 10 pt rim holds). It comes in as the arc lands on its night's score, so a turn of
                // the Crown never shows one night's range around another night's arc; still where the
                // arc is still. No dashes: dashes mean "no full forecast". A tick under the leading
                // star is left out, the star standing for that end.
                let settle = max(0, 1 - abs(value - target)/12), r = radius + 5
                let from = start + sweep*Double(models.lowerBound)/100, to = start + sweep*Double(models.upperBound)/100
                var span = Path()
                span.addArc(center: center, radius: r, startAngle: .degrees(from), endAngle: .degrees(to), clockwise: false)
                let tip = start + sweep*min(100, target)/100, clearance = 7/r * 180 / .pi
                for end in [from, to] where abs(end - tip) >= clearance {
                    let a = end * .pi/180
                    span.move(to: CGPoint(x: center.x+cos(a)*(r-3), y: center.y+sin(a)*(r-3)))
                    span.addLine(to: CGPoint(x: center.x+cos(a)*(r+3), y: center.y+sin(a)*(r+3)))
                }
                context.stroke(span, with: .color(palette.accent.opacity((dimmed ? 0.6 : 0.85)*settle)), style: StrokeStyle(lineWidth: 1.5, lineCap: .butt))
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
        WatchGauge(night: WatchSky.night(park, evening: park.currentNight(at: .now), forecast: nil, detail: nil, now: .now))
            .environment(\.nyx, NyxPalette(nightVision: true, highContrast: false)).modifier(NightVisionFilter(enabled: true))
    }
}
#Preview("Starlight • AX") {
    if let park = try? ParkData.load().first(where: { $0.id == "dena" }) {
        WatchGauge(night: WatchSky.night(park, evening: park.currentNight(at: .now), forecast: nil, detail: nil, now: .now)).dynamicTypeSize(.accessibility3)
    }
}
#Preview("Models' range") {
    if let park = try? ParkData.load().first(where: { $0.id == "jotr" }) {
        let night = WatchSky.night(park, evening: park.currentNight(at: .now), forecast: nil, detail: nil, now: .now)
        WatchGauge(night: night, models: max(0, night.score.value-12)...min(100, night.score.value+6))
    }
}
#Preview("Models' range • red") {
    if let park = try? ParkData.load().first(where: { $0.id == "jotr" }) {
        let night = WatchSky.night(park, evening: park.currentNight(at: .now), forecast: nil, detail: nil, now: .now)
        WatchGauge(night: night, models: max(0, night.score.value-12)...min(100, night.score.value+6))
            .environment(\.nyx, NyxPalette(nightVision: true, highContrast: false)).modifier(NightVisionFilter(enabled: true))
    }
}
