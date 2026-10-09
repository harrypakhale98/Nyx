#if DEBUG
import SwiftUI

/// `-nyx-screen field` / `field-compass`: field mode for the starting park tonight, with real
/// computed milestones, at a moment in the night (`-nyx-field-minutes N` after sunset, 50 by
/// default; the compass defaults to two hours after true darkness begins). Nothing on the phone
/// is changed. `-nyx-state adapting` starts the eye's clock 12 minutes in, `reset` shows the
/// reset notice, `adapted` 35 minutes in, `alarms` opens the "Wake me" sheet.
struct DebugField: View {
    @State private var session: FieldSession
    private let model: PlanModel
    private let compass: Bool
    private let pose: SkyCompass.Pose?
    init(park: Park, model: PlanModel, compass: Bool) {
        let night=model.night(park)
        let base: Date
        if let minutes=DebugScenario.number("-nyx-field-minutes"), let sunset=night.sky.sunset { base=sunset.addingTimeInterval(minutes*60) }
        else if compass, let dark=night.sky.darkStart { base=dark.addingTimeInterval(7200) }
        else { base=(night.sky.sunset ?? night.sky.evening.addingTimeInterval(6*3600)).addingTimeInterval(50*60) }
        let adapted: TimeInterval=switch DebugScenario.state { case "adapting": 12*60; case "adapted": 35*60; case "reset": 2*60; default: 4*60 }
        let session=FieldSession(park: park, model: model, changesPhone: false, offset: base.timeIntervalSinceNow, adaptedFor: adapted)
        if DebugScenario.state=="reset" { session.reset=DarkAdaptation.Reset(at: session.now.addingTimeInterval(-120), previousStart: session.now.addingTimeInterval(-26*60)) }
        _session=State(initialValue: session)
        self.model=model; self.compass=compass
        // Toward the core when it is up, tipped 10° above it so the band shows rising from it; otherwise south, 30° up.
        let core=FieldSkyTarget.named(park: park, sky: night.sky, at: session.now).first { $0.kind == .core && $0.altitude>5 }
        pose=compass ? SkyCompass.Pose(azimuth: core?.azimuth ?? 180, altitude: max(20, min(50, core.map { $0.altitude+10 } ?? 30))) : nil
    }
    var body: some View {
        FieldView(session: session, initialPage: compass ? .look : .night, fixedPose: pose, showsAlarms: DebugScenario.state=="alarms") {}
            // Under `-nyx-state live`, the same forecast refresh park detail makes, so field mode shows
            // the same score as detail in one capture run (the session is built before any forecast arrives).
            .task {
                guard DebugScenario.state=="live" else { return }
                await model.refreshForecasts(watching: [session.park])
                session.score=model.night(session.park).score
            }
    }
}

/// `-nyx-screen live-activity`: the Live Activity's Lock Screen and Dynamic Island faces for
/// tonight at the starting park, in starlight, in night vision, stale and finished.
struct FieldActivityReview: View {
    let night: Night
    var body: some View {
        let field=FieldNight(park: night.park, sky: night.sky)
        // Shown 50 minutes after sunset, moved to the real clock so the countdown and the line run.
        let moment=(night.sky.sunset ?? night.sky.evening).addingTimeInterval(50*60)
        // An illustrative closure line (sample text, DEBUG only), as a followed night carries one.
        let base=FieldActivityAttributes(night: field, score: night.score.value, band: night.score.band.label, closure: "Keys View Road closed at night")
        let attributes=base.shifted(by: Date.now.timeIntervalSince(moment))
        let now=Date.now
        let state=attributes.state(at: now, nightVision: false)
        // Followed ahead: 40 minutes before sunset, planned the day before.
        let early=base.shifted(by: now.timeIntervalSince(base.dusk.addingTimeInterval(-40*60)))
        let heading=Self.planned(early.state(at: now, nightVision: false, heading: true), at: now.addingTimeInterval(-26*3600))
        // Stale three hours after the moment it was counting down to.
        let stale=attributes.state(at: now.addingTimeInterval(-3*3600), nightVision: false)
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // `-nyx-state stale-score` puts the followed night's later scores first.
                if DebugScenario.state == "stale-score" { rescored(early, heading) }
                Eyebrow(text: "Lock Screen")
                face { FieldActivityLockView(attributes: attributes, state: state, isStale: false) }
                face { FieldActivityLockView(attributes: attributes, state: attributes.state(at: now, nightVision: true), isStale: false) }
                Eyebrow(text: "Heading out: a night followed ahead")
                face { FieldActivityLockView(attributes: early, state: heading, isStale: false) }
                if DebugScenario.state != "stale-score" { rescored(early, heading) }
                Eyebrow(text: "Three hours after its moment, before Nyx updates it")
                face { FieldActivityLockView(attributes: attributes, state: stale, isStale: true) }
                face { FieldActivityLockView(attributes: attributes, state: attributes.state(at: attributes.dawn, nightVision: false), isStale: false) }
                Eyebrow(text: "Apple Watch Smart Stack and CarPlay (small)")
                HStack(spacing: 10) {
                    small { FieldActivitySmallView(attributes: attributes, state: state, isStale: false) }
                    small { FieldActivitySmallView(attributes: attributes, state: attributes.state(at: now, nightVision: true), isStale: false) }
                }
                small { FieldActivitySmallView(attributes: attributes, state: stale, isStale: true) }
                Eyebrow(text: "Dynamic Island")
                HStack(spacing: 10) {
                    island { HStack { FieldActivitySymbol(attributes: attributes, state: state, isStale: false); Spacer(minLength: 40); FieldActivityCountdown(attributes: attributes, state: state, isStale: false) }.padding(.horizontal, 14) }
                    island { FieldActivitySymbol(attributes: attributes, state: state, isStale: false) }.frame(width: 44)
                }
                HStack(spacing: 10) {
                    island { HStack { FieldActivitySymbol(attributes: attributes, state: stale, isStale: true); Spacer(minLength: 40); FieldActivityCountdown(attributes: attributes, state: stale, isStale: true) }.padding(.horizontal, 14) }
                    island { FieldActivitySymbol(attributes: attributes, state: stale, isStale: true) }.frame(width: 44)
                }
                island {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Label { Text(FieldActivityMark(attributes: attributes, state: state, isStale: false).title) } icon: { FieldActivitySymbol(attributes: attributes, state: state, isStale: false) }.font(.system(.subheadline, design: .serif)); Spacer(); FieldActivityCountdown(attributes: attributes, state: state, isStale: false, font: .system(.title3, design: .serif), maxWidth: 90) }
                        FieldNightLine(attributes: attributes, colors: FieldActivityColors(nightVision: false)).frame(height: 14)
                    }.padding(16)
                }.frame(height: 110)
            }.padding(24)
        }.defaultScrollAnchor(DebugScenario.isEnabled("bottom") ? .bottom : .top).background(LinearGradient(colors: [Color(red: 0.05, green: 0.06, blue: 0.14), .black], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
    }
    /// A followed night after its forecast moved: a lower score worked out three days before dusk
    /// (the face names its day), in starlight and in red, and the closure lifted since it was followed.
    @ViewBuilder private func rescored(_ early: FieldActivityAttributes, _ heading: FieldActivityAttributes.ContentState) -> some View {
        let old=early.dusk.addingTimeInterval(-3*24*3600)
        let lower=max(0, night.score.value-23)
        let band=ScoreBand.band(lower).label
        let red=Self.red(heading)
        Eyebrow(text: "Its score from three days before, until Nyx refreshes it")
        face { FieldActivityLockView(attributes: early, state: FieldActivityAttributes.rescored(heading, score: lower, band: band, closure: early.closure, at: old), isStale: false) }
        face { FieldActivityLockView(attributes: early, state: FieldActivityAttributes.rescored(red, score: lower, band: band, closure: early.closure, at: old), isStale: false) }
        Eyebrow(text: "The closure lifted since it was followed")
        face { FieldActivityLockView(attributes: early, state: FieldActivityAttributes.rescored(heading, score: night.score.value, band: night.score.band.label, closure: nil, at: Date.now), isStale: false) }
    }
    private func face<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content().background(Color.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 22))
    }
    private static func red(_ state: FieldActivityAttributes.ContentState) -> FieldActivityAttributes.ContentState {
        var state=state
        state.nightVision=true
        return state
    }
    private static func planned(_ state: FieldActivityAttributes.ContentState, at date: Date) -> FieldActivityAttributes.ContentState {
        var state=state
        state.updated=date
        return state
    }
    /// About the size of a Smart Stack card's Live Activity slot on a 46 mm watch.
    private func small<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content().frame(width: 170, height: 84).background(Color.black, in: RoundedRectangle(cornerRadius: 16))
    }
    private func island<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content().frame(maxWidth: .infinity, minHeight: 36).background(Color.black, in: Capsule()).overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.5))
    }
}
#endif
