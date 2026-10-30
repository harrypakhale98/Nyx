import SwiftUI

/// The iPhone's celestial gauge, distilled for the wrist: an arc open at the bottom, ticks every
/// ten points, a leading star where the score has reached, and the Moon resting in the opening.
/// The arc sweeps in on the shared spring once, with the iPhone's haptics: a medium pulse as it
/// passes 70 and 90 (the score milestones) and a light tap as it lands; still and silent under
/// Reduce Motion and wrist-down. Turning the Crown through the week springs the arc to each night's score.
/// Where the iPhone shows the forecast models' range, a hairline along the rim marks it, as on the
/// iPhone's dial, and settles in as the arc lands, so uncertainty comes last and costs no line of text.
/// Where the Sun sets and rises, the track is the night itself, as on the iPhone (`NightTrack`):
/// twilight dim, true darkness lit, the best window in full starlight with a glow, the Moon's hours over the rim, hour
/// ticks inside and the leading star at "now"; it draws in from sunset as the score's arc would
/// have swept, and the score stays in the numeral. The models' range is then said in the words
/// under the dial, as the iPhone does, and the times at the ends are left off: at 40 mm a time
/// under either end would sit against the Moon and the line below, and that line gives park times.
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
    /// The iPhone's picture of this night's Moon (`WatchMoons`): the photographic Moon, tilted for the
    /// park, as on the iPhone and its widgets. Nil draws the vector Moon.
    var moon: CGImage? = nil
    /// The night's best window (`ClearWindow`), from the hourly clouds the iPhone handed over:
    /// brightest on the track. Nil without a full forecast.
    var window: DateInterval? = nil
    /// The watch's minute, for where tonight has got to.
    var now: Date = .now
    @State private var shown = 0.0
    /// The last milestone the sweeping arc passed (70, 90), and whether it has landed: the haptics' triggers.
    @State private var milestone = 0
    @State private var landed = false
    var body: some View {
        let score = night.score.value
        // Nil where the Sun does not set and rise (a polar day or night): the score's arc stays.
        let ring = NightRing(sky: night.sky, park: night.park, best: window, now: now)
        // Proportions follow the dial, not the text size: the numeral is the dial's face. At
        // accessibility sizes the band word leaves the dial for the line below it.
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                if let ring {
                    // Revealed as the arc would sweep, so the haptics' beats still land with it. In
                    // Always-On: no glow, and the hours already past fade, as passed milestones do.
                    let reveal = score > 0 ? min(1, shown/Double(score)) : 1
                    NightTrack(reveal: reveal, ring: ring, palette: palette, glow: dimmed ? 0 : 1, fit: .watch, fadesPast: dimmed)
                    NightNow(reveal: reveal, now: ring.now, dimmed: dimmed, palette: palette)
                } else {
                    GaugeArc(value: shown, target: Double(score), models: models, hasForecast: night.score.hasForecast, dimmed: dimmed, palette: palette)
                }
                // The word sits under the numeral, clear of every tick: smaller if it must, then
                // with a slightly smaller numeral, and only where even that cannot clear the ticks
                // does the numeral stand alone (`WatchDialFace.choose`); VoiceOver always says the band.
                let face = self.face(side: side)
                VStack(spacing: WatchDialFace.spacing(side: side)) {
                    Text(score, format: .number)
                        .scoreNumeral(size: WatchDialFace.numeralSize(side: side)*face.numeral, accent: palette.accent).lineLimit(1).minimumScaleFactor(0.5)
                        // A Crown step rolls the numeral with the arc, as the iPhone's dial does; Reduce Motion cross-fades it.
                        .contentTransition(reduceMotion ? .opacity : .numericText(value: Double(score)))
                    if let word = face.word {
                        Text(night.score.band.label).font(.system(size: WatchDialFace.wordSize(side: side)*word, design: .serif)).lineLimit(1).fixedSize()
                    }
                }
                .padding(.horizontal, side*0.16).offset(y: -WatchDialFace.lift(side: side))
                // Always-On changes without motion; Reduce Motion keeps a short cross-fade.
                .animation(dimmed ? nil : reduceMotion ? NyxMotion.fade : NyxMotion.spring, value: score)
                // Drawn in starlight on the iPhone: the root's night-vision filter turns it red, as it does the vector Moon.
                Group {
                    if let moon { Image(decorative: moon, scale: 2).resizable().interpolation(.high).scaledToFit().accessibilityIgnoresInvertColors() }
                    else { MoonDisc(illumination: night.sky.moon.illumination, waxing: night.sky.moon.waxing, southern: night.park.latitude < 0) }
                }
                    .frame(width: side*0.15, height: side*0.15)
                    .position(x: proxy.size.width/2, y: proxy.size.height/2 + side*0.39)
                    .opacity(dimmed ? 0.7 : 1)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        // The iPhone dial's first words as the label; the rest is the value, which VoiceOver says
        // again whenever the Crown moves the dial to another night.
        .accessibilityLabel("Darkness score")
        .accessibilityValue(spoken(ring: ring))
        .task(id: score) {
            if reduceMotion || dimmed || shown > 0 { withAnimation(reduceMotion || dimmed ? nil : NyxMotion.spring) { shown = Double(score) }; return }
            try? await Task.sleep(for: WatchDebug.revealDelay)
            withAnimation(NyxMotion.spring) { shown = Double(score) }
            // The haptics follow the spring itself: each fires when the arc reaches its mark.
            var elapsed = 0.0
            for beat in Self.beats(score: score) {
                try? await Task.sleep(for: .seconds(beat.at - elapsed))
                // The wrist went down mid-sweep: no tap against a lowered arm.
                guard !Task.isCancelled, !dimmed else { return }
                elapsed = beat.at
                if let mark = beat.milestone { milestone = mark } else { landed = true }
            }
        }
        // The iPhone gauge's vocabulary (`CelestialGauge`): medium at a milestone, light as it lands.
        // Read again as each beat lands, so a wrist lowered mid-sweep is never tapped.
        .sensoryFeedback(.impact(weight: .medium), trigger: milestone) { _, new in new > 0 && !dimmed }
        .sensoryFeedback(.impact(weight: .light), trigger: landed) { _, new in new && !dimmed }
        .onChange(of: dimmed) { _, _ in shown = Double(score) }
    }
    /// When the shared spring, sweeping from 0 to `score`, first reaches 70 and 90 (where the score
    /// does) and then the score itself, in seconds from the start of the sweep, in order.
    nonisolated static func beats(score: Int) -> [(milestone: Int?, at: Double)] {
        guard score > 0 else { return [] }
        var beats: [(milestone: Int?, at: Double)] = [], marks = [70, 90].filter { score >= $0 }
        for step in 1...240 {
            let t = Double(step)/120, value = NyxMotion.model.value(target: Double(score), time: t)
            while let mark = marks.first, value >= Double(mark) { beats.append((mark, t)); marks.removeFirst() }
            if value >= Double(score) - 0.5 { beats.append((nil, t)); return beats }
        }
        beats.append((nil, 2))
        return beats
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
    /// What follows "Darkness score", the same things in the same order and words as the iPhone's
    /// dial (`CelestialGauge`): the night when it is not tonight (said here, so a turn of the Crown
    /// says which night it reached), the score and its band, what the clouds rest on, the forecast
    /// models' range, haze or smoke that caps the score, the night the track shows (`ring`), and
    /// whose time it is where the park's clock is not the watch's. Never the Moon or a closure:
    /// each has its own element.
    private func spoken(ring: NightRing?) -> String {
        return Sentences.join([
            nightLabel.map { Sentences.end($0) } ?? "",
            String(localized: "\(night.score.value) out of 100. \(night.score.band.label)."),
            night.cloudSentence(),
            models.map { String(localized: "Forecast models: \($0.lowerBound) to \($0.upperBound).") } ?? "",
            night.smokeCaveat.map { Sentences.end($0) } ?? "",
            // The Moon drawn inside the dial has no element of its own on the watch, so the dial says it.
            Sentences.end(night.sky.moon.spoken),
            ring?.spoken(sky: night.sky, park: night.park, best: window) ?? "",
            // The words under the dial give park times; where the park's clock is not the watch's, say whose.
            night.park.spokenZone(at: night.sky.evening) ?? ""
        ])
    }
}

/// Tonight's leading star on the night's track, where the night has got to, as on the iPhone's dial:
/// shown once the track has drawn in that far; no glow in Always-On.
private struct NightNow: View, Animatable {
    var reveal: Double
    var animatableData: Double { get { reveal } set { reveal = newValue } }
    let now: Double?
    let dimmed: Bool
    let palette: NyxPalette
    var body: some View {
        Canvas { context, size in
            guard let now, reveal >= now else { return }
            let center = CGPoint(x: size.width/2, y: size.height/2), radius = WatchDialFace.radius(side: min(size.width, size.height))
            let a = NightTrack.angle(now).radians
            let point = CGPoint(x: center.x+cos(a)*radius, y: center.y+sin(a)*radius)
            // "Now" is a time, not the score: its glow is starlight, as the track is (the iPhone dial's rule).
            if !dimmed {
                context.fill(Path(ellipseIn: CGRect(x: point.x-8, y: point.y-8, width: 16, height: 16)),
                             with: .radialGradient(Gradient(colors: [palette.ink.opacity(0.55), palette.ink.opacity(0)]), center: point, startRadius: 0, endRadius: 8))
            }
            context.fill(Path(ellipseIn: CGRect(x: point.x-2.8, y: point.y-2.8, width: 5.6, height: 5.6)), with: .color(palette.ink))
        }
        .accessibilityHidden(true)
    }
}

/// The dial where there is no night to draw (polar night, midnight Sun): its track and ticks, and the
/// models' range beside them, never a fill, as on the iPhone (`DialFace`): the score is the numeral's.
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
            context.stroke(track, with: .color(palette.line), style: StrokeStyle(lineWidth: 2*palette.stroke, lineCap: .round))
            for tick in 0...10 {
                let a = (start + Double(tick)*sweep/10) * .pi/180
                var line = Path()
                line.move(to: CGPoint(x: center.x+cos(a)*(radius-5), y: center.y+sin(a)*(radius-5)))
                line.addLine(to: CGPoint(x: center.x+cos(a)*(radius-(tick%5==0 ? 10 : 8)), y: center.y+sin(a)*(radius-(tick%5==0 ? 10 : 8))))
                context.stroke(line, with: .color(tick%5==0 ? palette.ink.opacity(0.35) : palette.line), lineWidth: palette.stroke)
            }
            if let models {
                // The models' range just outside the track: a hairline with a tick at each end, so it
                // reads as a measured span rather than more arc (the iPhone dial's contrast form, which
                // a 10 pt rim holds). It comes in as the arc lands on its night's score, so a turn of
                // the Crown never shows one night's range around another night's arc; still where the
                // arc is still. No dashes: dashes mean "no full forecast".
                let settle = max(0, 1 - abs(value - target)/12), r = radius + 5
                let from = start + sweep*Double(models.lowerBound)/100, to = start + sweep*Double(models.upperBound)/100
                var span = Path()
                span.addArc(center: center, radius: r, startAngle: .degrees(from), endAngle: .degrees(to), clockwise: false)
                for end in [from, to] {
                    let a = end * .pi/180
                    span.move(to: CGPoint(x: center.x+cos(a)*(r-3), y: center.y+sin(a)*(r-3)))
                    span.addLine(to: CGPoint(x: center.x+cos(a)*(r+3), y: center.y+sin(a)*(r+3)))
                }
                context.stroke(span, with: .color(palette.accent.opacity((dimmed ? 0.6 : 0.85)*settle)), style: StrokeStyle(lineWidth: 1.5*palette.stroke, lineCap: .butt))
            }
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
#Preview("Pictured Moon • red") {
    // The iPhone's picture stands in for the vector Moon; here the vector Moon rendered to an image
    // plays it, since the watch cannot draw the shader. The root's filter turns it red.
    if let park = try? ParkData.load().first(where: { $0.id == "jotr" }) {
        let night = WatchSky.night(park, evening: park.currentNight(at: .now), forecast: nil, detail: nil, now: .now)
        let picture = ImageRenderer(content: MoonDisc(illumination: night.sky.moon.illumination, waxing: night.sky.moon.waxing).frame(width: 48, height: 48)).cgImage
        WatchGauge(night: night, moon: picture)
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
#Preview("Brighter red • Bold Text") {
    // The iPhone's brighter red and Bold Text reach the wrist: a heavier track and ticks, the protan-safe red.
    if let park = try? ParkData.load().first(where: { $0.id == "jotr" }) {
        let palette = NyxPalette(nightVision: true, highContrast: false, brighterRed: true, boldText: true)
        WatchGauge(night: WatchSky.night(park, evening: park.currentNight(at: .now), forecast: nil, detail: nil, now: .now))
            .environment(\.nyx, palette).modifier(NightVisionFilter(enabled: true, red: palette.red)).environment(\.legibilityWeight, .bold)
    }
}
#Preview("Models' range • red") {
    if let park = try? ParkData.load().first(where: { $0.id == "jotr" }) {
        let night = WatchSky.night(park, evening: park.currentNight(at: .now), forecast: nil, detail: nil, now: .now)
        WatchGauge(night: night, models: max(0, night.score.value-12)...min(100, night.score.value+6))
            .environment(\.nyx, NyxPalette(nightVision: true, highContrast: false)).modifier(NightVisionFilter(enabled: true))
    }
}
/// The night on the dial, for the three states the brief names: a moonlit night with a best window
/// (the window stands in for one the hourly clouds would give), a new-moon night, and Always-On.
/// "Now" is set inside each night so the leading star shows.
#Preview("Night • moonlit") {
    if let park = try? ParkData.load().first(where: { $0.id == "jotr" }) {
        let date = Date(timeIntervalSince1970: 1792800000)
        let night = WatchSky.night(park, evening: park.currentNight(at: date), forecast: nil, detail: nil, now: date)
        let window = night.sky.darkStart.map { DateInterval(start: $0.addingTimeInterval(3600), duration: 3*3600) }
        WatchGauge(night: night, window: window, now: night.sky.darkStart?.addingTimeInterval(2*3600) ?? date)
    }
}
#Preview("Night • new moon") {
    if let park = try? ParkData.load().first(where: { $0.id == "jotr" }) {
        let date = Date(timeIntervalSince1970: 1794200000) // the evening of Nov 8, 2026: the Moon new the next morning
        let night = WatchSky.night(park, evening: park.currentNight(at: date), forecast: nil, detail: nil, now: date)
        WatchGauge(night: night, now: night.sky.darkStart?.addingTimeInterval(4*3600) ?? date)
    }
}
#Preview("Night • Always-On") {
    if let park = try? ParkData.load().first(where: { $0.id == "jotr" }) {
        let date = Date(timeIntervalSince1970: 1792800000)
        let night = WatchSky.night(park, evening: park.currentNight(at: date), forecast: nil, detail: nil, now: date)
        WatchGauge(night: night, now: night.sky.darkStart?.addingTimeInterval(2*3600) ?? date)
            .environment(\.isLuminanceReduced, true)
    }
}
