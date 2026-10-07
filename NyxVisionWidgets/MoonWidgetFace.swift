import SwiftUI
import UIKit
import WidgetKit

/// Tonight's Moon for a wall or a desk in visionOS: its phase, how much of it is lit, and when the
/// next new moon comes (the dark nights stargazers plan around). Computed on device from the
/// date alone; no park, no network, no shared data. Also compiled into the app, for its DEBUG
/// renders of the widget's faces.
nonisolated struct MoonFacts: Sendable, Equatable {
    let date: Date
    let phaseName: String
    /// The lit fraction, from the true phase angle.
    let illumination: Double
    let waxing: Bool
    let phaseAngle: Double
    let nextNewMoon: Date

    init(at date: Date) {
        let engine = AstronomyEngine(), phase = engine.moonPhase(at: date)
        self.date = date
        phaseName = phase.name
        waxing = phase.waxing
        // Elongation from the phase cycle; the phase angle is its supplement to within a few
        // hundredths of a degree, so the lit fraction agrees with the planner's.
        phaseAngle = Double.pi-2*Double.pi*(phase.fraction < 0.5 ? phase.fraction : 1-phase.fraction)
        illumination = (1+cos(phaseAngle))/2
        nextNewMoon = Self.newMoon(after: date)
    }
    var percent: Int { Int((illumination*100).rounded()) }
    /// The first new moon after `date`: the phase cycle wraps from 1 to 0 there. Found by
    /// six-hour steps, then halving to under a minute.
    static func newMoon(after date: Date) -> Date {
        let engine = AstronomyEngine()
        var before = date, previous = engine.moonPhase(at: date).fraction
        for step in 1...130 {
            let next = date.addingTimeInterval(Double(step)*6*3600), fraction = engine.moonPhase(at: next).fraction
            if fraction < previous {
                var low = before, high = next
                while high.timeIntervalSince(low) > 30 {
                    let middle = low.addingTimeInterval(high.timeIntervalSince(low)/2)
                    if engine.moonPhase(at: middle).fraction > 0.5 { low = middle } else { high = middle }
                }
                return high
            }
            before = next; previous = fraction
        }
        return date.addingTimeInterval(AstronomyEngine.synodicDays*86400)
    }
    /// "Moon, waxing crescent, 23 percent lit. Next new moon Tuesday, October 21."
    var spoken: String {
        String(localized: "Moon, \(phaseName.lowercased()), \(percent) percent lit. Next new moon \(nextNewMoon.formatted(.dateTime.weekday(.wide).month(.wide).day())).")
    }
}

/// The widget's faces. `simplified` is the far-away look (visionOS `levelOfDetail`): the Moon and
/// its percentage, large.
struct MoonWidgetFace: View {
    let facts: MoonFacts
    let family: WidgetFamily
    var simplified = false
    private static let ink = Color(red: 0.961, green: 0.945, blue: 0.902)
    private static let amber = Color(red: 1, green: 0.706, blue: 0.329)
    var body: some View {
        Group {
            if simplified {
                VStack(spacing: 10) {
                    WidgetMoon(facts: facts).frame(maxWidth: 120, maxHeight: 120)
                    Text("\(facts.percent)%").font(.system(size: 44, weight: .light, design: .serif)).monospacedDigit().foregroundStyle(Self.amber)
                }
            } else if family == .systemSmall {
                VStack(alignment: .leading, spacing: 6) {
                    WidgetMoon(facts: facts).frame(width: 64, height: 64)
                    Spacer(minLength: 4)
                    Text(facts.phaseName).font(.system(.headline, design: .serif)).foregroundStyle(Self.ink).lineLimit(2).minimumScaleFactor(0.85)
                    Text("\(facts.percent)% lit").font(.subheadline).monospacedDigit().foregroundStyle(Self.amber)
                    Text("New moon \(facts.nextNewMoon.formatted(.dateTime.month(.abbreviated).day()))").font(.caption).foregroundStyle(Self.ink.opacity(0.75))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 20) {
                    WidgetMoon(facts: facts).frame(width: 112, height: 112)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("TONIGHT'S MOON").font(.caption2.weight(.semibold)).kerning(1.4).foregroundStyle(Self.ink.opacity(0.7))
                        Text(facts.phaseName).font(.system(.title2, design: .serif)).foregroundStyle(Self.ink)
                        Text("\(facts.percent)% lit").font(.headline).monospacedDigit().foregroundStyle(Self.amber)
                        Spacer(minLength: 6)
                        Text("Next new moon").font(.caption).foregroundStyle(Self.ink.opacity(0.75))
                        Text(facts.nextNewMoon.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())).font(.system(.headline, design: .serif)).foregroundStyle(Self.ink)
                        Text("The darkest nights of the month come in the week around it.").font(.caption2).foregroundStyle(Self.ink.opacity(0.75))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(facts.spoken))
    }
    /// Deep indigo to void black, Nyx's night.
    static var background: LinearGradient {
        LinearGradient(colors: [Color(red: 0.043, green: 0.063, blue: 0.149), .black], startPoint: .top, endPoint: .bottom)
    }
}

/// The Moon from NASA's map, lit at tonight's phase, drawn once by the Moon shader into an image
/// (a widget cannot run a shader as it draws). Textbook orientation: north up, lit on the right
/// while waxing, as seen from the northern states. A phase symbol stands in if the render fails.
struct WidgetMoon: View {
    let facts: MoonFacts
    var body: some View {
        Group {
            if let image = Self.render(facts) {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: Self.symbol(facts)).resizable().scaledToFit().foregroundStyle(.white)
            }
        }
        .accessibilityIgnoresInvertColors()
    }
    static func render(_ facts: MoonFacts) -> UIImage? {
        guard let map = UIImage(named: "MoonMap") else { return nil }
        let side = 240.0, i = facts.phaseAngle, a = facts.waxing ? -Double.pi/2 : Double.pi/2
        let earthshine = 0.09*(1-cos(i))/2
        let shader = ShaderLibrary.nyxMoon(.float2(CGSize(width: side, height: side)), .float4(sin(i) * -sin(a), sin(i)*cos(a), cos(i), earthshine),
                                           .float4(1, 0, 0, 0), .image(Image(uiImage: map)))
        let renderer = ImageRenderer(content: Rectangle().fill(.black).frame(width: side, height: side).colorEffect(shader))
        renderer.scale = 2
        return renderer.uiImage
    }
    static func symbol(_ facts: MoonFacts) -> String {
        let lit = facts.illumination, waxing = facts.waxing
        if lit < 0.03 { return "moonphase.new.moon" }
        if lit > 0.97 { return "moonphase.full.moon" }
        if abs(lit-0.5) < 0.06 { return waxing ? "moonphase.first.quarter" : "moonphase.last.quarter" }
        return lit < 0.5 ? (waxing ? "moonphase.waxing.crescent" : "moonphase.waning.crescent") : (waxing ? "moonphase.waxing.gibbous" : "moonphase.waning.gibbous")
    }
}

#Preview("Widget faces") {
    let facts = MoonFacts(at: .now)
    VStack(spacing: 30) {
        MoonWidgetFace(facts: facts, family: .systemSmall).padding(16).frame(width: 170, height: 170).background(MoonWidgetFace.background, in: .rect(cornerRadius: 24))
        MoonWidgetFace(facts: facts, family: .systemMedium).padding(16).frame(width: 360, height: 170).background(MoonWidgetFace.background, in: .rect(cornerRadius: 24))
        MoonWidgetFace(facts: facts, family: .systemSmall, simplified: true).padding(16).frame(width: 170, height: 170).background(MoonWidgetFace.background, in: .rect(cornerRadius: 24))
    }
    .padding(40)
}

#Preview("Widget faces, accessibility size") {
    MoonWidgetFace(facts: MoonFacts(at: .now), family: .systemMedium).padding(16).frame(width: 360, height: 260)
        .background(MoonWidgetFace.background, in: .rect(cornerRadius: 24)).dynamicTypeSize(.accessibility2)
}
