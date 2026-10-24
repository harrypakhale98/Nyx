import SwiftUI

/// The night the dial's track shows, sunset at its left end and sunrise at its right, so the
/// instrument that gives the score also shows the night it scores: twilight dim, true darkness lit,
/// the Moon's hours washed pale, the best window in amber and, tonight, where the night has got to.
/// Positions are fractions of sunset to sunrise. Nil where the Sun does not set and rise (a polar
/// day or night): the dial then keeps its 0–100 track.
nonisolated struct NightRing: Equatable, Sendable {
    let sunset: Date
    let sunrise: Date
    /// True darkness; nil on a night without it (high summer far north).
    let dark: ClosedRange<Double>?
    /// The Moon above the horizon.
    let moon: [ClosedRange<Double>]
    /// How strongly moonlight washes the sky, 0…1 (`SkyConditions.moonlight`, else illumination).
    let moonlight: Double
    /// The best window (`ClearWindow`): forecast nights only.
    let best: ClosedRange<Double>?
    /// Where the night has got to, tonight while it lasts.
    let now: Double?
    /// Midnight and each whole hour between, park-local, for the track's hour ticks.
    let hours: [(position: Double, midnight: Bool)]

    static func == (a: NightRing, b: NightRing) -> Bool {
        a.sunset == b.sunset && a.sunrise == b.sunrise && a.dark == b.dark && a.moon == b.moon && a.moonlight == b.moonlight && a.best == b.best && a.now == b.now
    }

    init?(sky: SkyConditions, park: Park, best: DateInterval?=nil, now: Date?=nil) {
        guard let sunset=sky.sunset, let sunrise=sky.sunrise, sunrise.timeIntervalSince(sunset)>3600 else { return nil }
        self.sunset=sunset; self.sunrise=sunrise
        let span=sunrise.timeIntervalSince(sunset)
        func f(_ date: Date) -> Double { min(1, max(0, date.timeIntervalSince(sunset)/span)) }
        func range(_ a: Date, _ b: Date) -> ClosedRange<Double>? { let lo=f(a), hi=f(b); return hi-lo>0.004 ? lo...hi : nil }
        dark=sky.darkStart.flatMap { start in sky.darkEnd.flatMap { range(start, $0) } }
        // The Moon's hours from its rise and set, wherever they fall; with neither, it is up all
        // night or down all night, as the share of darkness it leaves says.
        let early=sunset.addingTimeInterval(-86400), late=sunrise.addingTimeInterval(86400)
        var up: [(Date, Date)]=[]
        switch (sky.moonrise, sky.moonset) {
        case let (rise?, set?): up = rise<set ? [(rise, set)] : [(early, set), (rise, late)]
        case let (rise?, nil): up=[(rise, late)]
        case let (nil, set?): up=[(early, set)]
        case (nil, nil): up = sky.moonDownPercent == 0 && sky.moon.illumination>0.01 ? [(early, late)] : []
        }
        moon=up.compactMap { range($0.0, $0.1) }
        moonlight=min(1, max(0, sky.moonlight ?? sky.moon.illumination))
        self.best=best.flatMap { range($0.start, $0.end) }
        self.now=now.flatMap { $0>sunset && $0<sunrise ? f($0) : nil }
        var hours: [(Double, Bool)]=[]
        let calendar=park.calendar
        if var hour=calendar.nextDate(after: sunset, matching: DateComponents(minute: 0), matchingPolicy: .nextTime) {
            while hour<sunrise {
                hours.append((f(hour), calendar.component(.hour, from: hour) == 0))
                hour=hour.addingTimeInterval(3600)
            }
        }
        self.hours=hours
    }

    /// What the ring shows, for VoiceOver, in the park's time: "Sunset 5:58 PM, true darkness 7:23 PM
    /// to 5:32 AM, Moon up until 5:18 AM, sunrise 6:43 AM."
    func spoken(sky: SkyConditions, park: Park, best window: DateInterval?) -> String {
        var parts=[String(localized: "The dial shows the night: sunset \(park.time(sunset))")]
        if let start=sky.darkStart, let end=sky.darkEnd, dark != nil { parts.append(String(localized: "true darkness from \(park.time(start)) to \(park.time(end))")) }
        if let window, best != nil { parts.append(String(localized: "best window from \(park.time(window.start)) to \(park.time(window.end))")) }
        parts.append(String(localized: "sunrise \(park.time(sunrise))"))
        return parts.joined(separator: ", ")+"."
    }
}

/// The night along the dial's track (`NightRing`), revealed from sunset as the score counts up
/// (`reveal`, 0…1, animatable on the shared spring), then still. Drawn in the dial's own hand:
/// hairlines, one soft glow, amber only for the best window.
struct NightTrack: View, Animatable {
    var reveal: Double
    let ring: NightRing
    let palette: NyxPalette
    let glow: Double
    var animatableData: Double { get { reveal } set { reveal=newValue } }
    nonisolated static func angle(_ position: Double) -> Angle { .degrees(140+260*position) }
    var body: some View {
        Canvas { context, size in
            let dial=min(size.width, size.height), k=DialMetrics.scale(side: dial)
            let center=CGPoint(x: size.width/2, y: size.height/2), radius=dial/2-DialMetrics.inset(side: dial)
            // The same well the score's dial has: the numeral sits inside the instrument.
            let well=radius-14*k
            context.fill(Path(ellipseIn: CGRect(x: center.x-well, y: center.y-well, width: 2*well, height: 2*well)), with: .radialGradient(Gradient(stops: [.init(color: .black.opacity(0.55), location: 0), .init(color: .black.opacity(0.35), location: 0.8), .init(color: .clear, location: 1)]), center: center, startRadius: 0, endRadius: well))
            func arc(_ range: ClosedRange<Double>, at r: CGFloat=radius) -> Path {
                var path=Path(); path.addArc(center: center, radius: r, startAngle: Self.angle(range.lowerBound), endAngle: Self.angle(range.upperBound), clockwise: false); return path
            }
            // The whole night as a hairline, so its ends (sunset, sunrise) always read.
            context.stroke(arc(0...1), with: .color(palette.line), style: StrokeStyle(lineWidth: 1.2*palette.stroke, lineCap: .round))
            // Everything after it is drawn as far as the night has been revealed.
            let shown=min(1, max(0, reveal))
            guard shown>0.001 else { return }
            var wedge=Path(); wedge.move(to: center)
            wedge.addArc(center: center, radius: dial, startAngle: .degrees(138), endAngle: Self.angle(shown) + .degrees(shown>=1 ? 2 : 0), clockwise: false); wedge.closeSubpath()
            context.clip(to: wedge)
            // Twilight: the night before and after true darkness, a little brighter than the hairline.
            context.stroke(arc(0...1), with: .color(palette.ink.opacity(0.32)), style: StrokeStyle(lineWidth: 1.6*palette.stroke, lineCap: .butt))
            if let dark=ring.dark {
                context.drawLayer { layer in
                    layer.addFilter(.blur(radius: 6))
                    layer.stroke(arc(dark), with: .color(palette.ink.opacity(0.22*glow)), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                }
                context.stroke(arc(dark), with: .color(palette.ink.opacity(0.9)), style: StrokeStyle(lineWidth: 2.3*palette.stroke, lineCap: .round))
            }
            if let best=ring.best {
                context.drawLayer { layer in
                    layer.addFilter(.blur(radius: 7))
                    layer.stroke(arc(best), with: .color(palette.accent.opacity(0.45*glow)), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                }
                context.stroke(arc(best), with: .color(palette.accent), style: StrokeStyle(lineWidth: 2.6*palette.stroke, lineCap: .round))
            }
            // The Moon's hours: pale light spilling over the rim outside the track, stronger the more it
            // fills the sky, so the track's own colours stay readable underneath. A hairline marks its
            // edge where glows are dimmed (Increase Contrast, night vision).
            for span in ring.moon {
                let rim=radius+7*k
                context.drawLayer { layer in
                    layer.addFilter(.blur(radius: 4+2*k))
                    layer.stroke(arc(span, at: rim), with: .color(palette.ink.opacity((0.25+0.45*ring.moonlight)*glow)), style: StrokeStyle(lineWidth: max(6, 9*k), lineCap: .round))
                }
                context.stroke(arc(span, at: rim), with: .color(palette.ink.opacity(0.35+0.4*ring.moonlight)), style: StrokeStyle(lineWidth: 1.2*palette.stroke, lineCap: .round))
                // A small Moon where it rises or sets within the night, so the halo explains itself.
                for end in [span.lowerBound, span.upperBound] where end>0.004 && end<0.996 {
                    let a=Self.angle(end).radians, d=max(3.2, 4.2*k)
                    let point=CGPoint(x: center.x+cos(a)*rim, y: center.y+sin(a)*rim)
                    context.fill(Path(ellipseIn: CGRect(x: point.x-d, y: point.y-d, width: 2*d, height: 2*d)), with: .color(palette.ink))
                }
            }
            // Hour ticks inside the track, midnight longer; lit while the sky is truly dark.
            for hour in ring.hours {
                let a=Self.angle(hour.position).radians
                let outer=radius-8*k, inner=radius-(hour.midnight ? 17 : 12)*k
                var line=Path()
                line.move(to: CGPoint(x: center.x+cos(a)*outer, y: center.y+sin(a)*outer))
                line.addLine(to: CGPoint(x: center.x+cos(a)*inner, y: center.y+sin(a)*inner))
                let lit=ring.dark?.contains(hour.position) ?? false
                context.stroke(line, with: .color(lit ? palette.ink.opacity(hour.midnight ? 0.8 : 0.5) : palette.line), lineWidth: (hour.midnight ? 0.9 : 0.6)*palette.stroke)
            }
        }
    }
}

/// Sunset and sunrise at the dial's two open ends, in the park's time.
struct NightRingEnds: View {
    @Environment(\.nyx) private var palette
    let ring: NightRing
    let park: Park
    var body: some View {
        GeometryReader { proxy in
            let dial=min(proxy.size.width, proxy.size.height), radius=dial/2-DialMetrics.inset(side: dial)
            let center=CGPoint(x: proxy.size.width/2, y: proxy.size.height/2)
            ForEach([(ring.sunset, 0.0), (ring.sunrise, 1.0)], id: \.1) { time, position in
                let a=NightTrack.angle(position).radians
                // Starlight, and below the glass rim's end, not on it: in grey over the glass they failed contrast.
                Text(park.time(time)).font(.caption2.monospacedDigit()).foregroundStyle(palette.ink).fixedSize()
                    .position(x: center.x+cos(a)*radius, y: center.y+sin(a)*radius+DialMetrics.ringWidth(side: dial)/2+10)
            }
        }
        .accessibilityHidden(true)
    }
}

extension PlanModel {
    /// A night's ring for the dial, with its best window and, while the night lasts, where it has got to.
    func ring(_ night: Night, now: Date = .now) -> (ring: NightRing, park: Park, spoken: String)? {
        let window=clearWindow(night)?.interval
        guard let ring=NightRing(sky: night.sky, park: night.park, best: window, now: now) else { return nil }
        return (ring, night.park, ring.spoken(sky: night.sky, park: night.park, best: window))
    }
}
#Preview("Night ring • moonlit") {
    let m=PlanModel()
    if let p=m.park("jotr") { let n=m.night(p,on:Date(timeIntervalSince1970:1792800000)); CelestialGauge(score:n.score.value,night:m.ring(n)).environment(\.nyxReduceMotion,true).frame(height:300).background(.black) }
}
#Preview("Night ring • new moon") {
    let m=PlanModel()
    if let p=m.park("jotr") { let n=m.night(p,on:Date(timeIntervalSince1970:1794700000)); CelestialGauge(score:n.score.value,night:m.ring(n)).frame(height:300).background(.black) }
}
#Preview("Night ring • Alaska June, no true darkness") {
    let m=PlanModel()
    if let p=m.park("dena") { let n=m.night(p,on:Date(timeIntervalSince1970:1813564800)); CelestialGauge(score:n.score.value,night:m.ring(n)).environment(\.nyxReduceMotion,true).frame(height:300).background(.black) }
}
#Preview("Night ring • night vision • AX5") {
    let m=PlanModel()
    if let p=m.park("grba") { let n=m.night(p); CelestialGauge(score:n.score.value,night:m.ring(n)).environment(\.nyx,NyxPalette(nightVision:true,highContrast:false)).modifier(NightVisionFilter(enabled:true)).dynamicTypeSize(.accessibility5).background(.black) }
}
