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
    let toggleSky: () async -> Void
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
            VisionEyebrow(text: "\(plan.park.state) · \(model.nightOffset == 0 ? String(localized: "Tonight") : plan.park.dayLabel(plan.sky.evening))")
            Text(plan.score.value, format: .number)
                .font(.system(size: numeral, weight: .light, design: .serif)).kerning(3).monospacedDigit()
                .foregroundStyle(palette.accent)
                .contentTransition(.numericText(value: Double(plan.score.value)))
                .accessibilityLabel(Text("Darkness score"))
                .accessibilityValue(Text("\(plan.score.value) out of 100, \(plan.score.band.label)"))
            Text(plan.score.band.label).font(.system(.title, design: .serif)).foregroundStyle(palette.ink)
            Text("Moon and darkness only. Nyx on Vision Pro fetches no cloud forecast; check one before you go.")
                .font(.callout).foregroundStyle(palette.muted).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 380, alignment: .leading)
        .animation(VisionMotion.spring, value: plan.score.value)
    }
    private func moon(_ plan: NightPlan) -> some View {
        VStack(spacing: 10) {
            VisionMoon(geometry: plan.moon,
                       label: String(localized: "Moon, \(Int((plan.moon.illumination*100).rounded())) percent illuminated, as seen at \(plan.park.time(plan.moonMoment))"))
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
        default: sky.moonBelowFraction > 0.5 ? String(localized: "Down all night") : String(localized: "Up all night")
        }
        // Three columns side by side; stacked at accessibility sizes, where columns would clip.
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14)) : AnyLayout(HStackLayout(alignment: .top, spacing: 14))
        return layout { factCells(darkness, hours, moonLine, park) }
    }
    @ViewBuilder private func factCells(_ darkness: String, _ hours: String?, _ moonLine: String, _ park: Park) -> some View {
        Fact(title: "True darkness", value: darkness, note: hours.map { "\($0) · \(park.timeZoneName)" } ?? park.timeZoneName)
        Fact(title: "Moon", value: moonLine, note: String(localized: "Down for \(Int((model.plan?.sky.moonBelowFraction ?? 0)*100))% of true darkness"))
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
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) { skyTitle(park, moment); Spacer(); skyButton }
                VStack(alignment: .leading, spacing: 14) { skyTitle(park, moment); skyButton }
            }
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
        }
    }
    private func skyTitle(_ park: Park, _ moment: SkyMoment) -> some View {
        VisionEyebrow(text: "The sky at \(park.time(moment.date))")
    }
    private var skyButton: some View {
        Button { Task { await toggleSky() } } label: {
            Label(model.immersiveOpen ? "Leave the sky" : "Stand under this sky", systemImage: model.immersiveOpen ? "xmark" : "sparkles")
                .font(.headline).padding(.horizontal, 6)
        }
        .buttonStyle(.borderedProminent).tint(palette.accent.opacity(0.85))
        .accessibilityHint(Text("Surrounds you with this park's computed sky at the time on the clock below"))
    }

    private func honesty(_ plan: NightPlan) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Computed for \(plan.park.shortName), \(plan.park.dayLabel(plan.sky.evening)). Not a live view; clouds not shown.")
            Text("Times are park time. Moonrise and moonset are good to about a quarter of an hour, planets to about a degree. In the sky, the Moon is drawn larger than life so its phase reads; its place is true.")
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
        .background(palette.solid && !palette.nightVision ? AnyShapeStyle(Color(red: 0.07, green: 0.08, blue: 0.14)) : AnyShapeStyle(.thinMaterial.opacity(palette.nightVision ? 0 : 0.6)), in: .rect(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(palette.line, lineWidth: 0.5))
        .accessibilityElement(children: .combine)
    }
}
