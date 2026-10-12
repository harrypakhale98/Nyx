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
        // The phase and its lit fraction as the large face's week computes them (`MoonWeek`).
        let glance = MoonWeek.Glance(at: date)
        self.date = date
        phaseName = glance.phaseName
        waxing = glance.waxing
        phaseAngle = glance.phaseAngle
        illumination = glance.illumination
        nextNewMoon = MoonWeek.newMoon(after: date)
    }
    var percent: Int { Int((illumination*100).rounded()) }
    /// "Moon, waxing crescent, 23 percent lit. Next new moon Tuesday, October 21."
    var spoken: String {
        String(localized: "Moon, \(phaseName), \(percent) percent lit. Next new moon \(nextNewMoon.formatted(.dateTime.weekday(.wide).month(.wide).day())).")
    }
}

/// Letter-spaced capitals are a Latin-script convention: Japanese kana and kanji spread apart read
/// as broken words, so spaced labels set solid when Nyx speaks Japanese (the iPhone's `Lettering`,
/// in NyxTheme.swift, which neither Vision Pro target compiles). Here for both: the app compiles this file.
nonisolated enum Lettering {
    static let spaced = !(Bundle.main.preferredLocalizations.first ?? "en").hasPrefix("ja")
}

/// The widget's faces. `simplified` is the far-away look (visionOS `levelOfDetail`): the Moon and
/// its percentage, large (and on the large face, the next new moon). The large face adds the
/// next seven nights' Moons (`MoonWeek`), the new moon's night ringed in amber.
struct MoonWidgetFace: View {
    @Environment(\.colorSchemeContrast) private var contrast
    let facts: MoonFacts
    let family: WidgetFamily
    var simplified = false
    private static let ink = NyxPalette.starlight
    private static let amber = NyxPalette.amber
    /// Increase Contrast lifts the quieter lines, as the iPhone's palette does (`NyxPalette.muted`, 0.9).
    private var high: Bool { contrast == .increased }
    private var eyebrowInk: Color { Self.ink.opacity(high ? 0.9 : 0.7) }
    private var quiet: Color { Self.ink.opacity(high ? 0.92 : 0.75) }
    var body: some View {
        // The large face's week, from the entry's date alone.
        let week = family == .systemLarge && !simplified ? MoonWeek(at: facts.date) : nil
        Group {
            if simplified {
                VStack(spacing: 10) {
                    WidgetMoon(facts: facts).frame(maxWidth: family == .systemLarge ? 200 : 120, maxHeight: family == .systemLarge ? 200 : 120)
                    Text("\(facts.percent)%").font(.system(size: 44, weight: .light, design: .serif)).monospacedDigit().foregroundStyle(Self.amber)
                    if family == .systemLarge {
                        Text("New moon \(facts.nextNewMoon.formatted(.dateTime.month(.abbreviated).day()))").font(.system(.title3, design: .serif)).foregroundStyle(Self.ink)
                    }
                }
            } else if let week {
                large(week)
            } else if family == .systemSmall {
                VStack(alignment: .leading, spacing: 6) {
                    WidgetMoon(facts: facts).frame(width: 64, height: 64)
                    Spacer(minLength: 4)
                    Text(facts.phaseName).font(.system(.headline, design: .serif)).foregroundStyle(Self.ink).lineLimit(2).minimumScaleFactor(0.85)
                    Text("\(facts.percent)% lit").font(.subheadline).monospacedDigit().foregroundStyle(Self.amber)
                    Text("New moon \(facts.nextNewMoon.formatted(.dateTime.month(.abbreviated).day()))").font(.caption).foregroundStyle(quiet)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 20) {
                    WidgetMoon(facts: facts).frame(width: 112, height: 112)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tonight's Moon").textCase(Lettering.spaced ? .uppercase : nil).font(.caption2.weight(.semibold)).kerning(Lettering.spaced ? 1.4 : 0).foregroundStyle(eyebrowInk)
                        Text(facts.phaseName).font(.system(.title2, design: .serif)).foregroundStyle(Self.ink)
                        Text("\(facts.percent)% lit").font(.headline).monospacedDigit().foregroundStyle(Self.amber)
                        Spacer(minLength: 6)
                        Text("Next new moon").font(.caption).foregroundStyle(quiet)
                        Text(facts.nextNewMoon.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())).font(.system(.headline, design: .serif)).foregroundStyle(Self.ink)
                        Text("The darkest nights of the month come in the week around it.").font(.caption2).foregroundStyle(quiet)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(week.map { facts.spoken+" "+Self.spokenWeek($0) } ?? facts.spoken))
    }
    /// Tonight's Moon above the week: each night's weekday, its Moon and how much is lit.
    private func large(_ week: MoonWeek) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 18) {
                WidgetMoon(facts: facts).frame(width: 112, height: 112)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tonight's Moon").textCase(Lettering.spaced ? .uppercase : nil).font(.caption2.weight(.semibold)).kerning(Lettering.spaced ? 1.4 : 0).foregroundStyle(eyebrowInk)
                    Text(facts.phaseName).font(.system(.title2, design: .serif)).foregroundStyle(Self.ink).lineLimit(2).minimumScaleFactor(0.85)
                    Text("\(facts.percent)% lit").font(.headline).monospacedDigit().foregroundStyle(Self.amber)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("The next seven nights").textCase(Lettering.spaced ? .uppercase : nil).font(.caption2.weight(.semibold)).kerning(Lettering.spaced ? 1.4 : 0).foregroundStyle(eyebrowInk)
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(week.nights.enumerated()), id: \.element.id) { index, night in
                    let newMoon = index == week.newMoonNight
                    VStack(spacing: 5) {
                        Text(night.date.formatted(.dateTime.weekday(.abbreviated))).font(.caption2.weight(.semibold))
                            .foregroundStyle(newMoon ? Self.amber : quiet)
                        WidgetMoon(glance: night, side: 64).frame(width: 30, height: 30)
                            .padding(3)
                            .overlay { if newMoon { Circle().stroke(Self.amber, lineWidth: 1.5) } }
                        Text("\(night.percent)%").font(.caption2).monospacedDigit().foregroundStyle(quiet)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .lineLimit(1).minimumScaleFactor(0.7)
            // Seven columns hold their shape; the face's spoken label carries every night at any size.
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 2) {
                Text("Next new moon").font(.caption).foregroundStyle(quiet)
                Text(facts.nextNewMoon.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())).font(.system(.headline, design: .serif)).foregroundStyle(Self.ink)
                Text("The darkest nights of the month come in the week around it.").font(.caption2).foregroundStyle(quiet)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    /// "The next seven nights: Saturday, 48 percent lit; Sunday, 59 percent lit; …"
    static func spokenWeek(_ week: MoonWeek) -> String {
        let nights = week.nights.map { String(localized: "\($0.date.formatted(.dateTime.weekday(.wide))), \($0.percent) percent lit") }
        return String(localized: "The next seven nights: \(nights.joined(separator: "; ")).")
    }
    /// Deep indigo to void black, Nyx's night.
    static var background: LinearGradient {
        LinearGradient(colors: [NyxPalette.indigo, .black], startPoint: .top, endPoint: .bottom)
    }
}

/// The Moon from NASA's map, lit at tonight's phase, drawn once by the Moon shader into an image
/// (a widget cannot run a shader as it draws). Textbook orientation: north up, lit on the right
/// while waxing, as seen from the northern states. A phase symbol stands in if the render fails.
struct WidgetMoon: View {
    let phaseAngle: Double
    let waxing: Bool
    let illumination: Double
    /// The rendered image's side in points (drawn at 2×): 240 for the face's Moon, less for the week's small ones.
    var side = 240.0
    init(facts: MoonFacts) { phaseAngle = facts.phaseAngle; waxing = facts.waxing; illumination = facts.illumination }
    init(glance: MoonWeek.Glance, side: Double) { phaseAngle = glance.phaseAngle; waxing = glance.waxing; illumination = glance.illumination; self.side = side }
    var body: some View {
        Group {
            if let image = Self.render(phaseAngle: phaseAngle, waxing: waxing, side: side) {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: Self.symbol(illumination: illumination, waxing: waxing)).resizable().scaledToFit().foregroundStyle(.white)
            }
        }
        .accessibilityIgnoresInvertColors()
    }
    static func render(phaseAngle: Double, waxing: Bool, side: Double = 240) -> UIImage? {
        guard let map = UIImage(named: "MoonMap") else { return nil }
        let i = phaseAngle, a = waxing ? -Double.pi/2 : Double.pi/2
        let earthshine = 0.09*(1-cos(i))/2
        let shader = ShaderLibrary.nyxMoon(.float2(CGSize(width: side, height: side)), .float4(sin(i) * -sin(a), sin(i)*cos(a), cos(i), earthshine),
                                           .float4(1, 0, 0, 0), .image(Image(uiImage: map)))
        let renderer = ImageRenderer(content: Rectangle().fill(.black).frame(width: side, height: side).colorEffect(shader))
        renderer.scale = 2
        return renderer.uiImage
    }
    static func symbol(illumination lit: Double, waxing: Bool) -> String {
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

#Preview("Large face: tonight and the week") {
    MoonWidgetFace(facts: MoonFacts(at: .now), family: .systemLarge).padding(16).frame(width: 364, height: 382)
        .background(MoonWidgetFace.background, in: .rect(cornerRadius: 24)).padding(40)
}

#Preview("Large face: the new moon's week, and far away") {
    // A week holding a new moon (ringed in amber), and the simplified look from across the room.
    let date = MoonWeek.newMoon(after: .now).addingTimeInterval(-3*86400)
    HStack(spacing: 30) {
        MoonWidgetFace(facts: MoonFacts(at: date), family: .systemLarge).padding(16).frame(width: 364, height: 382)
            .background(MoonWidgetFace.background, in: .rect(cornerRadius: 24))
        MoonWidgetFace(facts: MoonFacts(at: date), family: .systemLarge, simplified: true).padding(16).frame(width: 364, height: 382)
            .background(MoonWidgetFace.background, in: .rect(cornerRadius: 24))
    }
    .padding(40)
}

#Preview("Large face, accessibility size") {
    MoonWidgetFace(facts: MoonFacts(at: .now), family: .systemLarge).padding(16).frame(width: 364, height: 382)
        .background(MoonWidgetFace.background, in: .rect(cornerRadius: 24)).dynamicTypeSize(.accessibility2).padding(40)
}

#Preview("Widget faces, accessibility size") {
    MoonWidgetFace(facts: MoonFacts(at: .now), family: .systemMedium).padding(16).frame(width: 360, height: 260)
        .background(MoonWidgetFace.background, in: .rect(cornerRadius: 24)).dynamicTypeSize(.accessibility2)
}
