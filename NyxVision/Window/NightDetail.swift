import SwiftUI

/// One park's night: the score and the Moon, the night's hours, what's up, and the sky at the
/// moment on the ornament's clock, as text. That last list is the way to stand under the same sky
/// without the immersive space, and what VoiceOver reads.
struct NightDetail: View {
    @Environment(VisionModel.self) private var model
    @Environment(\.visionPalette) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .largeTitle) private var numeral = 108
    @ScaledMetric(relativeTo: .largeTitle) private var moonSide = 190
    var body: some View {
        if let plan = model.plan, let moment = model.skyMoment {
            ScrollView {
                VStack(alignment: .leading, spacing: 34) {
                    header(plan)
                    facts(plan)
                    whatsUp(plan)
                    skyNow(plan, moment)
                    honesty(plan)
                }
                .padding(.horizontal, 48).padding(.top, 8).padding(.bottom, 120)
                .frame(maxWidth: 860, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle(Text(plan.park.shortName))
            .background {
                // Nyx's night over the glass: deep indigo fading to void black, calm in a bright room.
                // Under Reduce Transparency it is nearly opaque, so nothing in the room shows through.
                LinearGradient(colors: [Color(red: 0.043, green: 0.063, blue: 0.149).opacity(palette.solid ? 0.96 : 0.55), Color.black.opacity(palette.solid ? 0.96 : 0.45)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea().accessibilityHidden(true)
            }
        } else if model.parks.isEmpty {
            ParkDataUnavailable()
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func header(_ plan: NightPlan) -> some View {
        let park = plan.park
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 44) { scoreBlock(plan); Spacer(minLength: 0); moon(plan) }
            VStack(alignment: .leading, spacing: 24) { moon(plan); scoreBlock(plan) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("\(park.name), night of \(park.dateLabel(plan.sky.evening))"))
    }
    private func scoreBlock(_ plan: NightPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VisionEyebrow(text: "\(plan.park.state.replacingOccurrences(of: ",", with: ", ")) · \(model.nightOffset == 0 ? String(localized: "Tonight") : plan.park.dayLabel(plan.sky.evening))")
            Text(plan.score.value, format: .number)
                .font(.system(size: numeral, weight: .light, design: .serif)).kerning(3).monospacedDigit()
                .foregroundStyle(palette.accent)
                .contentTransition(.numericText(value: Double(plan.score.value)))
                .accessibilityLabel(Text("Darkness score"))
                .accessibilityValue(Text("\(plan.score.value) out of 100, \(plan.night.bandWithBasis)"))
            // The band alone: the caption below always opens with the basis ("Early look: …").
            Text(plan.score.band.label).font(.system(.title, design: .serif)).foregroundStyle(palette.ink)
            // The weakest link, when it holds the score below its parts ("Clouds limit tonight to 55.").
            if let limit = limitLine(plan) {
                Text(limit).font(.callout).foregroundStyle(palette.accent).fixedSize(horizontal: false, vertical: true)
            }
            // What the clouds rest on, in the iPhone's words.
            Text(model.cloudCaption(plan.night))
                .font(.callout).foregroundStyle(palette.muted).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 380, alignment: .leading)
        .animation(VisionMotion.spring, value: plan.score.value)
    }
    /// The binding cap, when the four parts add up to more than the score.
    private func limitLine(_ plan: NightPlan) -> String? {
        let score = plan.score
        guard let limit = score.limit else { return nil }
        return limit.cap < score.partsSum ? limit.sentence(tonight: model.nightOffset == 0) : nil
    }
    private func moon(_ plan: NightPlan) -> some View {
        VStack(spacing: 10) {
            VisionMoon(geometry: plan.moon,
                       label: String(localized: "Moon, \(Int((plan.moon.illumination*100).rounded())) percent lit, as seen at \(plan.park.time(plan.moonMoment))"))
                .frame(width: moonSide, height: moonSide)
                .background {
                    // A piece of night behind the Moon, so even a new moon reads as a disc against the sky.
                    Circle().fill(RadialGradient(colors: [Color(red: 0.16, green: 0.12, blue: 0.32).opacity(palette.nightVision ? 0.3 : 0.75), Color(red: 0.043, green: 0.063, blue: 0.149).opacity(0.5), .clear],
                                                 center: .center, startRadius: moonSide*0.3, endRadius: moonSide*0.85))
                        .frame(width: moonSide*1.7, height: moonSide*1.7)
                        .accessibilityHidden(true)
                }
                .shadow(color: palette.ink.opacity(0.12*plan.moon.illumination), radius: 30)
            Text(plan.sky.moon.name).font(.system(.headline, design: .serif))
            Text("\(Int((plan.sky.moon.illumination*100).rounded()))% lit").font(.subheadline).foregroundStyle(palette.muted)
        }
    }

    private func facts(_ plan: NightPlan) -> some View {
        let park = plan.park, sky = plan.sky
        let darkness: String = if let start = sky.darkStart, let end = sky.darkEnd, end > start {
            String(localized: "\(park.time(start)) – \(park.time(end))")
        } else { SkyConditions.noDarknessMessage(tonight: model.nightOffset == 0) }
        let hours = sky.darkHours > 0 ? String(localized: "\(Int(sky.darkHours)) h \(Int((sky.darkHours*60).truncatingRemainder(dividingBy: 60))) min") : nil
        let moonLine: String = switch (sky.moonrise, sky.moonset) {
        case let (rise?, set?): rise < set ? String(localized: "Rises \(park.time(rise)), sets \(park.time(set))") : String(localized: "Sets \(park.time(set)), rises \(park.time(rise))")
        case let (rise?, nil): String(localized: "Rises \(park.time(rise))")
        case let (nil, set?): String(localized: "Sets \(park.time(set))")
        // Neither rises nor sets: the Moon's height at its highest says which (moonBelowFraction
        // is 0 when there is no true darkness to measure it against).
        default: plan.moonAllNight
        }
        // Three columns side by side; stacked at accessibility sizes, where columns would clip.
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14)) : AnyLayout(HStackLayout(alignment: .top, spacing: 14))
        // Without true darkness there is nothing for the Moon to stay out of, so say that instead.
        let moonNote = sky.darkHours > 0 ? String(localized: "Down for \(Int(sky.moonBelowFraction*100))% of true darkness")
            : String(localized: "The Moon counts only in true darkness, and this night has none.")
        return layout { factCells(darkness, hours, moonLine, moonNote, park) }
    }
    @ViewBuilder private func factCells(_ darkness: String, _ hours: String?, _ moonLine: String, _ moonNote: String, _ park: Park) -> some View {
        Fact(title: "True darkness", value: darkness, note: hours.map { "\($0) · \(park.timeZoneName)" } ?? park.timeZoneName)
        Fact(title: "Moon", value: moonLine, note: moonNote)
        Fact(title: "Sky glow", value: String(localized: "Bortle \(park.bortleEstimate)"), note: park.darkSkyDesignated ? String(localized: "Estimate · International Dark Sky Park") : String(localized: "Estimate"))
    }

    private func whatsUp(_ plan: NightPlan) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VisionEyebrow(text: model.nightOffset == 0 ? "What's up tonight" : "What's up this night")
            ForEach(plan.whatsUp.items) { item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(item.title).font(.system(.title3, design: .serif))
                        if let note = item.note { Text(note).font(.subheadline).foregroundStyle(palette.muted) }
                        Spacer(minLength: 8)
                        if let value = item.value { Text(value).font(.headline).monospacedDigit().foregroundStyle(item.timed ? palette.accent : palette.ink) }
                    }
                    Text(item.detail).font(.body).foregroundStyle(palette.muted).fixedSize(horizontal: false, vertical: true)
                    if let footnote = item.footnote { Text(footnote).font(.footnote).foregroundStyle(palette.muted) }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(item.spoken))
            }
        }
    }

    /// The sky at the clock's moment, written out.
    private func skyNow(_ plan: NightPlan, _ moment: SkyMoment) -> some View {
        let park = plan.park
        let bodies = ([moment.moon] + moment.visiblePlanets + (moment.core.up && moment.sunAltitude < -12 ? [moment.core] : [])).filter(\.up)
        return VStack(alignment: .leading, spacing: 18) {
            VisionEyebrow(text: "The sky at \(park.time(moment.date))")
            Text(moment.twilight).font(.system(.title3, design: .serif))
            if bodies.isEmpty {
                Text("No Moon or planets above the horizon. The stars have the sky to themselves.").foregroundStyle(palette.muted)
            }
            ForEach(bodies) { body in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(body.name).font(.body.weight(.medium))
                    Text(body.place).foregroundStyle(palette.muted)
                    if body.kind == .moon { Text("\(Int((moment.moonIllumination*100).rounded()))% lit").foregroundStyle(palette.muted) }
                    if body.kind == .planet { Text(WhatsUp.brightness(body.magnitude)).foregroundStyle(palette.muted) }
                }
                .accessibilityElement(children: .combine)
            }
            clouds(plan, moment)
        }
    }
    /// "Forecast clouds": the hour's cover the sky draws, or why none is drawn.
    private func clouds(_ plan: NightPlan, _ moment: SkyMoment) -> some View {
        let cloud = plan.cloud(at: moment.date)
        let value: String = if let cloud {
            plan.night.basis.isEarlyLook ? String(localized: "About \(Int((cloud*100).rounded()))% of the sky, an early look eased toward usual clouds")
                : String(localized: "About \(Int((cloud*100).rounded()))% of the sky this hour")
        } else if plan.night.basis == .usual {
            String(localized: "None drawn: no cloud forecast reaches this night")
        } else {
            String(localized: "None drawn: the forecast has no value for this hour")
        }
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: cloud == nil ? "cloud" : "cloud.fill").foregroundStyle(palette.muted).accessibilityHidden(true)
            Text("Forecast clouds").font(.body.weight(.medium))
            Text(value).foregroundStyle(palette.muted).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private func honesty(_ plan: NightPlan) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(VisionModel.honesty(plan))
            Text("Times are park-local. Moonrise and moonset are good to within a few minutes, planets to about a degree. In the sky, the Moon is drawn larger than life so its phase reads; its place is true.")
        }
        .font(.footnote).foregroundStyle(palette.muted).fixedSize(horizontal: false, vertical: true)
    }
}

private struct Fact: View {
    @Environment(\.visionPalette) private var palette
    let title: LocalizedStringKey
    let value: String
    let note: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            VisionEyebrow(text: title)
            Text(value).font(.system(.title3, design: .serif)).monospacedDigit().fixedSize(horizontal: false, vertical: true)
            Text(note).font(.footnote).foregroundStyle(palette.muted).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(18)
        .background(background, in: .rect(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(palette.line, lineWidth: 0.5))
        .accessibilityElement(children: .combine)
    }
    /// A full material on glass (a faded one let the room wash the words out), a solid panel under
    /// Reduce Transparency, and nothing in night vision, where the window's dark panel shows.
    private var background: AnyShapeStyle {
        if palette.nightVision { return AnyShapeStyle(Color.clear) }
        return palette.solid ? AnyShapeStyle(Color(red: 0.07, green: 0.08, blue: 0.14)) : AnyShapeStyle(.regularMaterial)
    }
}

/// When the bundled park list cannot be read: say so plainly instead of an endless spinner.
struct ParkDataUnavailable: View {
    var body: some View {
        ContentUnavailableView {
            Label("Park data unavailable", systemImage: "exclamationmark.triangle")
        } description: {
            Text("Nyx could not read the park list that ships inside the app. Reinstalling Nyx restores it.")
        }
    }
}

#Preview("Night detail") {
    NavigationStack { NightDetail() }.environment(VisionModel(now: .now))
}

#Preview("Night detail, Denali in June") {
    // No true darkness: the moon line comes from its height, and the note says why there is no share.
    let model = VisionModel(now: (try? Date("2026-06-21T21:00:00Z", strategy: .iso8601)) ?? .now)
    model.selectedID = "dena"
    return NavigationStack { NightDetail() }.environment(model)
}

#Preview("Night detail, accessibility size") {
    NavigationStack { NightDetail() }.environment(VisionModel(now: .now)).dynamicTypeSize(.accessibility3)
}

#Preview("Night detail, night vision and Reduce Transparency") {
    let model = VisionModel(now: .now)
    model.nightVision = true
    return NavigationStack { NightDetail() }.environment(model).environment(\.visionPalette, VisionPalette(nightVision: true, solid: true))
}

#if DEBUG
#Preview("Night detail, forecast 60% cloud") {
    let model = VisionModel(now: .now)
    model.forecasts = VisionModel.fixture(parks: model.parks, cover: 60, issued: .now)
    return NavigationStack { NightDetail() }.environment(model)
}

#Preview("Night detail, early look") {
    let model = VisionModel(now: .now)
    model.forecasts = VisionModel.fixture(parks: model.parks, cover: 40, issued: .now)
    model.nightOffset = 6
    return NavigationStack { NightDetail() }.environment(model)
}

#Preview("Park data unavailable") {
    NavigationStack { NightDetail() }.environment(VisionModel(now: .now, parks: []))
}
#endif
