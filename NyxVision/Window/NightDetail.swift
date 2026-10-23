import SwiftUI

/// One park's night: the score and the Moon, the night's hours, the darkest nights ahead, what's
/// up, and the sky at the moment on the ornament's clock, as text. That last list is the way to stand under the same sky
/// without the immersive space, and what VoiceOver reads.
struct NightDetail: View {
    @Environment(VisionModel.self) private var model
    @Environment(\.visionPalette) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var numeral = 108
    @ScaledMetric(relativeTo: .largeTitle) private var moonSide = 190
    /// The Moon's named seas and craters over the disc, as on the iPhone (`MoonLabels`).
    @AppStorage("moonNames") private var names = false
    var body: some View {
        // Only the plan here: the clock's moment changes every frame of a sweep, and only the
        // written sky below (`SkyNow`) reads it, so nothing else in the window re-evaluates.
        if let plan = model.plan {
            ScrollView {
                VStack(alignment: .leading, spacing: 34) {
                    header(plan)
                    facts(plan)
                    // The darkest nights from tonight on: a tap brings one here.
                    DarkestAhead(park: plan.park)
                    whatsUp(plan)
                    SkyNow(plan: plan)
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
                LinearGradient(colors: [NyxPalette.indigo.opacity(palette.solid ? 0.96 : 0.55), Color.black.opacity(palette.solid ? 0.96 : 0.45)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea().accessibilityHidden(true)
            }
        } else if model.parks.isEmpty {
            ParkDataUnavailable()
        } else {
            // The iPhone's constellation loader: a figure traced star by star, its words read to
            // VoiceOver as progress, standing still beside the system spinner under Reduce Motion.
            ConstellationTrace(ink: palette.ink, accent: palette.accent, reduceMotion: reduceMotion)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        let inputs = model.inputs, park = plan.park
        return VStack(alignment: .leading, spacing: 10) {
            VisionEyebrow(text: "\(park.region.replacingOccurrences(of: ",", with: ", ")) · \(model.nightOffset == 0 ? String(localized: "Tonight") : park.dayLabel(plan.sky.evening))")
            // The closure is the one line that must never be lost: beside the score, in the accent, as on the iPhone.
            if let closure = inputs.closure(park) {
                Label(closure, systemImage: "exclamationmark.triangle").font(.headline).foregroundStyle(palette.accent)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(Text(ClosureLine.spoken(closure)))
            }
            Text(plan.score.value, format: .number)
                .scoreNumeral(size: numeral, accent: palette.accent)
                .contentTransition(.numericText(value: Double(plan.score.value)))
                .accessibilityLabel(Text("Darkness score"))
                .accessibilityValue(Text("\(plan.score.value) out of 100, \(plan.night.bandWithBasis)"))
            // The band alone: the caption below always opens with the basis ("Early look: …").
            Text(plan.score.band.label).bandWord(.title, ink: palette.ink)
            // Haze or smoke thick enough to wash out the Milky Way, in the accent beside the score, by
            // the iPhone's rule and words (`Night.smokeCaveat`), whether or not it holds the score down.
            if let smoke = plan.night.smokeCaveat {
                Label(smoke, systemImage: "smoke").font(.callout).foregroundStyle(palette.accent).fixedSize(horizontal: false, vertical: true)
            }
            // The weakest link, when it holds the score below its parts ("Clouds limit tonight to 55.").
            if let limit = limitLine(plan) {
                Text(limit).font(.callout).foregroundStyle(palette.accent).fixedSize(horizontal: false, vertical: true)
            }
            // What the clouds rest on, in the iPhone's words.
            Text(model.cloudCaption(plan.night))
                .font(.callout).foregroundStyle(palette.muted).fixedSize(horizontal: false, vertical: true)
            // What the score could not count (smoke switched off or not here yet), and where the
            // park's access stands when no closure does, in the iPhone's words.
            ForEach([inputs.smokeNote(park, night: plan.night), inputs.accessNote(park)].compactMap { $0 }, id: \.self) { note in
                Text(note).font(.footnote).foregroundStyle(palette.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: 380, alignment: .leading)
        // A new score rolls in on the shared spring; under Reduce Motion it simply changes.
        .animation(reduceMotion ? nil : VisionMotion.spring, value: plan.score.value)
    }
    /// The binding cap, when the four parts add up to more than the score.
    private func limitLine(_ plan: NightPlan) -> String? {
        let score = plan.score
        guard let limit = score.limit else { return nil }
        return limit.cap < score.partsSum ? limit.sentence(tonight: model.nightOffset == 0) : nil
    }
    private func moon(_ plan: NightPlan) -> some View {
        // One figure for the eye and VoiceOver: the night's, as the list, the Moon volume and the
        // iPhone give it. The picture is the Moon at its highest that night, and says so.
        let lit = Int((plan.sky.moon.illumination*100).rounded())
        return VStack(spacing: 10) {
            VisionMoon(geometry: plan.moon,
                       label: Sentences.join([Sentences.end(String(localized: "Moon, \(plan.sky.moon.name), \(lit) percent lit")),
                                              Sentences.end(String(localized: "Drawn as seen at \(plan.park.time(plan.moonMoment))")),
                                              names ? MoonFeatures.shared.spoken(geometry: plan.moon, side: moonSide) ?? "" : ""]))
                .frame(width: moonSide, height: moonSide)
                .overlay { if names { MoonLabels(geometry: plan.moon, side: moonSide, ink: palette.ink).transition(.opacity) } }
                .background {
                    // A piece of night behind the Moon, so even a new moon reads as a disc against the sky.
                    Circle().fill(RadialGradient(colors: [NyxPalette.nebula.opacity(palette.nightVision ? 0.3 : 0.75), NyxPalette.indigo.opacity(0.5), .clear],
                                                 center: .center, startRadius: moonSide*0.3, endRadius: moonSide*0.85))
                        .frame(width: moonSide*1.7, height: moonSide*1.7)
                        .accessibilityHidden(true)
                }
                .shadow(color: palette.ink.opacity(0.12*plan.moon.illumination), radius: 30)
            Text(plan.sky.moon.name).font(.system(.headline, design: .serif))
            Text("\(lit)% lit").font(.subheadline).foregroundStyle(palette.muted)
            if !MoonFeatures.shared.features.isEmpty {
                Button { names.toggle() } label: { Label(names ? "Hide names" : "Show names", systemImage: names ? "tag.slash" : "tag") }
                    .accessibilityHint(Text("Shows or hides the names of the Moon's seas and craters in sunlight."))
            }
        }
    }

    private func facts(_ plan: NightPlan) -> some View {
        let park = plan.park, sky = plan.sky
        let darkness: String = if let start = sky.darkStart, let end = sky.darkEnd, end > start {
            String(localized: "\(park.time(start)) – \(park.time(end))")
        } else { SkyConditions.noDarknessMessage(tonight: model.nightOffset == 0) }
        // The reader's own units ("6 hr, 40 min", "6 Std., 40 Min."), as the iPhone writes a span.
        let hours = sky.darkHours > 0 ? Duration.seconds(sky.darkHours*3600).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)) : nil
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
        let moonNote = sky.darkHours > 0 ? String(localized: "Down for \(sky.moonDownPercent)% of true darkness")
            : String(localized: "The Moon counts only in true darkness, and this night has none.")
        // The month's usual night (ERA5), in the iPhone's words: there is no hourly forecast detail here.
        let month = park.calendar.component(.month, from: plan.sky.evening)
        let usual = NightClimate.shared.lines(park, month: month)
        return VStack(alignment: .leading, spacing: 12) {
            layout { factCells(darkness, hours, moonLine, moonNote, park) }
            if let usual {
                Text(Sentences.join([usual.temperatures, usual.dew ?? ""])).font(.callout).foregroundStyle(palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    @ViewBuilder private func factCells(_ darkness: String, _ hours: String?, _ moonLine: String, _ moonNote: String, _ park: Park) -> some View {
        Fact(title: "True darkness", value: darkness, note: hours.map { "\($0) · \(park.timeZoneName)" } ?? park.timeZoneName)
        Fact(title: "Moon", value: moonLine, note: moonNote)
        // The iPhone's words (`ScoreBreakdownView`): the class on its scale, called an estimate, and what it means.
        let glow = String(localized: "Artificial light in the sky, as a conservative Bortle estimate. It is not a measurement.")
        Fact(title: "Sky glow", value: String(localized: "Bortle class \(park.bortleEstimate) of 9, estimated."),
             note: park.darkSkyDesignated ? Sentences.join([glow, String(localized: "An International Dark Sky Park.")]) : glow)
    }

    private func whatsUp(_ plan: NightPlan) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VisionEyebrow(text: model.nightOffset == 0 ? "What's up tonight" : "What's up this night")
            // The iPhone's and the watch's order (`WhatsUp.layout`): rows, then a line each for the quieter things.
            let layout = plan.whatsUp.layout
            ForEach(layout.first + plan.whatsUp.planets + layout.after) { item in
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
            ForEach(layout.mentions) { item in
                Text(verbatim: [item.title, item.value ?? item.note].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline).foregroundStyle(palette.muted).fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(Text(item.spoken))
            }
        }
    }

    private func honesty(_ plan: NightPlan) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(VisionModel.honesty(plan))
            Text("Times are park-local. Moonrise and moonset are good to within a few minutes, planets to about a degree. In the sky, the Moon is drawn larger than life so its phase reads; its place is true.")
        }
        .font(.footnote).foregroundStyle(palette.muted).fixedSize(horizontal: false, vertical: true)
    }
}

/// The sky at the clock's moment, written out: the one part of the night that reads the clock, so
/// a sweep re-evaluates this list and nothing else.
private struct SkyNow: View {
    @Environment(VisionModel.self) private var model
    @Environment(\.visionPalette) private var palette
    let plan: NightPlan
    var body: some View {
        if let moment = model.skyMoment { skyNow(plan, moment) }
    }
    private func skyNow(_ plan: NightPlan, _ moment: SkyMoment) -> some View {
        let park = plan.park
        // The core by the immersive sky's own rule (`SkyDome.coreVisible`), as it labels the core and VoiceOver hears it there.
        let bodies = ([moment.moon] + moment.visiblePlanets + (moment.coreShown ? [moment.core] : [])).filter(\.up)
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
        // An early look where the place has no usual clouds draws the hour as forecast (`SkyDome.cloud`).
        let value: String = if let cloud {
            !plan.night.basis.isEarlyLook ? String(localized: "About \(Int((cloud*100).rounded()))% of the sky this hour")
                : plan.night.usualCloud == nil ? String(localized: "About \(Int((cloud*100).rounded()))% of the sky, an early look counted as it stands")
                : String(localized: "About \(Int((cloud*100).rounded()))% of the sky, an early look eased toward usual clouds")
        } else if plan.night.basis == .usual {
            plan.beyondForecast ? String(localized: "None drawn: no cloud forecast reaches this night") : String(localized: "None drawn: cloud forecast unavailable")
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
        return palette.solid ? AnyShapeStyle(palette.solidPanel) : AnyShapeStyle(.regularMaterial)
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

#Preview("Loading, and loading under Reduce Motion") {
    let palette = VisionPalette()
    return HStack {
        ConstellationTrace(ink: palette.ink, accent: palette.accent, reduceMotion: false)
        ConstellationTrace(ink: palette.ink, accent: palette.accent, reduceMotion: true)
    }
    .glassBackgroundEffect()
}

#Preview("Park data unavailable") {
    NavigationStack { NightDetail() }.environment(VisionModel(now: .now, parks: []))
}
#endif
