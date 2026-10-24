import SwiftUI

/// The night the dial's track shows, sunset at its left end and sunrise at its right, so the
/// instrument that gives the score also shows the night it scores: twilight dim, true darkness a
/// quiet step above it, the Moon's hours washed pale, the best window brightest and, tonight, where
/// the night has got to. All in starlight: amber is the score's alone. Only the best window is bright,
/// so a long dark window never reads as a nearly full gauge around the score.
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
    /// The share of true darkness with the Moon down, 0…1 (`SkyConditions.moonBelowFraction`).
    let moonFree: Double
    /// The best window (`ClearWindow`): forecast nights only.
    let best: ClosedRange<Double>?
    /// Where the night has got to, tonight while it lasts.
    let now: Double?
    /// Midnight and each whole hour between, park-local, for the track's hour ticks.
    let hours: [(position: Double, midnight: Bool)]
    /// How much of true darkness the Moon washes: the share it is up, by how strongly it lights the sky.
    var wash: Double { (1-moonFree)*moonlight }

    static func == (a: NightRing, b: NightRing) -> Bool {
        a.sunset == b.sunset && a.sunrise == b.sunrise && a.dark == b.dark && a.moon == b.moon && a.moonlight == b.moonlight && a.moonFree == b.moonFree && a.best == b.best && a.now == b.now
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
        moonFree=min(1, max(0, sky.moonBelowFraction))
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
/// (`reveal`, 0…1, animatable on the shared spring), then still. Drawn in the dial's own hand and in
/// starlight only, brighter for a better hour: hairline night, dim twilight, true darkness a quiet
/// step above it, the best window at full ink with one soft glow. The same night on the iPhone's dial
/// and Apple Watch's (`Fit`), so the face is one object across devices.
struct NightTrack: View, Animatable {
    /// Where the track sits in its frame and how its marks scale. The iPhone's dial (`DialMetrics`)
    /// has a glass rim and a well under the numeral. The watch's (`WatchDialFace`) leaves 10 pt for
    /// the glow, draws no well (its face is the black screen), and sets its marks at the sizes of
    /// the watch's own score ticks, a little heavier to read at arm's length, with tighter glows:
    /// the iPhone's blur on a dial half the size washed the whole face and was cut at its frame.
    nonisolated enum Fit: Sendable {
        case phone, watch
        func radius(side: CGFloat) -> CGFloat { self == .phone ? side/2-DialMetrics.inset(side: side) : WatchDialFace.radius(side: side) }
        func scale(side: CGFloat) -> CGFloat { self == .phone ? DialMetrics.scale(side: side) : 0.6 }
        var weight: CGFloat { self == .phone ? 1 : 1.35 }
        var blur: CGFloat { self == .phone ? 1 : 0.45 }
    }
    var reveal: Double
    let ring: NightRing
    let palette: NyxPalette
    let glow: Double
    var fit = Fit.phone
    /// Always-On on the watch: the night already behind "now" fades, as passed milestones do in
    /// the words under the dial (`nonEssential`), so a lowered wrist shows what is still to come.
    var fadesPast = false
    var animatableData: Double { get { reveal } set { reveal=newValue } }
    nonisolated static func angle(_ position: Double) -> Angle { .degrees(140+260*position) }
    /// Twilight's ink over the hairline (`NyxPalette.line`, itself 3:1 on black): together about half.
    nonisolated static func twilightInk(contrast: Bool) -> Double { contrast ? 0.25 : 0.15 }
    /// True darkness's ink over twilight: 0.3 (a quiet step, about 0.65 with what lies under it) when a
    /// best window outshines it, so only the best hours read bright. Without one (no forecast, or a bright
    /// Moon over the clear hours), the dark hours are the best the night is known to offer, as bright as
    /// the Moon leaves them: 0.85 with it down, down to 0.3 as moonlight washes all of them (`wash`, 0…1).
    /// Under Increase Contrast never under 0.5, so the steps from twilight and to the best stay plain.
    nonisolated static func darkInk(best: Bool, wash: Double=0, contrast: Bool) -> Double {
        let low=contrast ? 0.5 : 0.3
        return best ? low : 0.85-(0.85-low)*min(1, max(0, wash))
    }
    var body: some View {
        Canvas { context, size in
            let dial=min(size.width, size.height), k=fit.scale(side: dial), w=fit.weight, soft=fit.blur
            let center=CGPoint(x: size.width/2, y: size.height/2), radius=fit.radius(side: dial)
            if fit == .phone {
                // The same well the score's dial has: the numeral sits inside the instrument.
                let well=radius-14*k
                context.fill(Path(ellipseIn: CGRect(x: center.x-well, y: center.y-well, width: 2*well, height: 2*well)), with: .radialGradient(Gradient(stops: [.init(color: .black.opacity(0.55), location: 0), .init(color: .black.opacity(0.35), location: 0.8), .init(color: .clear, location: 1)]), center: center, startRadius: 0, endRadius: well))
            }
            func arc(_ range: ClosedRange<Double>, at r: CGFloat=radius) -> Path {
                var path=Path(); path.addArc(center: center, radius: r, startAngle: Self.angle(range.lowerBound), endAngle: Self.angle(range.upperBound), clockwise: false); return path
            }
            // One layer, so Always-On's fade (below) takes back only the track, never what lies under it.
            context.drawLayer { context in
                // The whole night as a hairline, so its ends (sunset, sunrise) always read.
                context.stroke(arc(0...1), with: .color(palette.line), style: StrokeStyle(lineWidth: 1.2*w*palette.stroke, lineCap: .round))
                // Everything after it is drawn as far as the night has been revealed.
                let shown=min(1, max(0, reveal))
                guard shown>0.001 else { return }
                // Clipped only while it draws in, from well below sunset's end, so the glows' soft ends
                // are never cut along a radius (on the watch's small dial that cut showed as a hard edge).
                if shown<1 {
                    var wedge=Path(); wedge.move(to: center)
                    wedge.addArc(center: center, radius: dial, startAngle: .degrees(115), endAngle: Self.angle(shown), clockwise: false); wedge.closeSubpath()
                    context.clip(to: wedge)
                }
                // Twilight: the night before and after true darkness, a little brighter than the hairline.
                context.stroke(arc(0...1), with: .color(palette.ink.opacity(Self.twilightInk(contrast: palette.highContrast))), style: StrokeStyle(lineWidth: 1.6*w*palette.stroke, lineCap: .butt))
                // True darkness: a quiet step above twilight, well under the best window. Without one the
                // dark hours are the best the night is known to offer, as bright as the Moon leaves them.
                if let dark=ring.dark {
                    context.stroke(arc(dark), with: .color(palette.ink.opacity(Self.darkInk(best: ring.best != nil, wash: ring.wash, contrast: palette.highContrast))), style: StrokeStyle(lineWidth: 2.2*w*palette.stroke, lineCap: .round))
                }
                // The best window: full starlight with one soft glow, the brightest stretch of the night.
                if let best=ring.best {
                    context.drawLayer { layer in
                        layer.addFilter(.blur(radius: 6*soft))
                        layer.stroke(arc(best), with: .color(palette.ink.opacity(0.28*glow)), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    }
                    context.stroke(arc(best), with: .color(palette.ink), style: StrokeStyle(lineWidth: 2.8*w*palette.stroke, lineCap: .round))
                }
                // The Moon's hours: pale light spilling over the rim outside the track, stronger the more it
                // fills the sky, so the track's own colours stay readable underneath. A hairline marks its
                // edge where glows are dimmed (Increase Contrast, night vision). Kept pale: a full Moon up
                // all night must not draw the bright ring round the score that the dark hours no longer do.
                // The hairline never under `NyxPalette.line` (3:1), higher under Increase Contrast.
                for span in ring.moon {
                    let rim=radius+7*k
                    context.drawLayer { layer in
                        layer.addFilter(.blur(radius: (4+2*k)*soft))
                        layer.stroke(arc(span, at: rim), with: .color(palette.ink.opacity((0.12+0.28*ring.moonlight)*glow)), style: StrokeStyle(lineWidth: max(6, 9*k), lineCap: .round))
                    }
                    context.stroke(arc(span, at: rim), with: .color(palette.ink.opacity(palette.highContrast ? 0.75 : 0.4+0.2*ring.moonlight)), style: StrokeStyle(lineWidth: 1.2*w*palette.stroke, lineCap: .round))
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
                    context.stroke(line, with: .color(lit ? palette.ink.opacity(hour.midnight ? 0.8 : 0.5) : palette.line), lineWidth: (hour.midnight ? 0.9 : 0.6)*w*palette.stroke)
                }
                if fadesPast, let now=ring.now {
                    // Take back 45% of what lies between sunset and now, the words' Always-On fade.
                    var past=Path(); past.move(to: center)
                    past.addArc(center: center, radius: dial, startAngle: .degrees(115), endAngle: Self.angle(now), clockwise: false); past.closeSubpath()
                    context.blendMode = .destinationOut
                    context.fill(past, with: .color(.black.opacity(0.45)))
                }
            }
        }
    }
}

/// Sunset and sunrise at the dial's two open ends, in the park's time, each with its small Sun on
/// the horizon, so the ends read as times of day and the track as the night between them.
struct NightRingEnds: View {
    @Environment(\.nyx) private var palette
    let ring: NightRing
    let park: Park
    var body: some View {
        GeometryReader { proxy in
            let dial=min(proxy.size.width, proxy.size.height), radius=dial/2-DialMetrics.inset(side: dial)
            let center=CGPoint(x: proxy.size.width/2, y: proxy.size.height/2)
            ForEach([(ring.sunset, 0.0, "sunset"), (ring.sunrise, 1.0, "sunrise")], id: \.1) { time, position, symbol in
                let a=NightTrack.angle(position).radians
                // Starlight, and below the glass rim's end, not on it: in grey over the glass they failed contrast.
                // The glyph is quieter than the time it marks.
                HStack(spacing: 3) {
                    Image(systemName: symbol).symbolRenderingMode(.monochrome).foregroundStyle(palette.muted)
                    Text(park.time(time)).monospacedDigit().foregroundStyle(palette.ink)
                }
                .font(.caption2).fixedSize()
                // Hung by its top a clear gap under the rim's rounded end, at any text size: centred 10 pt
                // under it, the caption's top sat 3 pt from the cap and read as stuck to the glass.
                .frame(height: 0, alignment: .top)
                .position(x: center.x+cos(a)*radius, y: center.y+sin(a)*radius+DialMetrics.ringWidth(side: dial)/2+8)
            }
        }
        .accessibilityHidden(true)
    }
}

/// How the dial's drawing scales with its side: everything keeps its proportions below the
/// standard 300 pt dial, and the glass rim thins with it (never under 16 pt), so a small dial
/// (onboarding, 176 pt) is an instrument, not a thick ring crowding the numeral.
nonisolated enum DialMetrics {
    static let standard: CGFloat=300
    static func scale(side:CGFloat)->CGFloat { min(1,max(0,side)/standard) }
    /// The rim's width.
    static func ringWidth(side:CGFloat)->CGFloat { max(16,26*scale(side:side)) }
    /// From the frame's edge to the arc's radius.
    static func inset(side:CGFloat)->CGFloat { 18*scale(side:side) }
}
