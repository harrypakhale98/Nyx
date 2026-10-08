import SwiftUI
import SwiftData

/// Field mode: the night itself, at the park. Black everywhere, red through the night-vision
/// filter whatever the app's setting, large serif type, one fact at a time. The milestones scroll
/// like a crown, snapping one by one with a light tick; "Where to look" turns the real sky to the
/// phone. The dark-adaptation clock runs along the bottom.
struct FieldView: View {
    enum Page: Hashable { case night, look }
    let session: FieldSession
    var initialPage: Page = .night
    /// DEBUG: a fixed pose for the compass, so the simulator can show it.
    var fixedPose: SkyCompass.Pose?=nil
    /// DEBUG: open with the "Wake me" sheet showing.
    var showsAlarms=false
    let close: ()->Void
    @State private var page: Page?
    @State private var focused: String?
    @State private var alarmsShown: Bool?
    @State private var aboutEyes=false
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.nyxReduceMotion) private var forcedReduceMotion
    private var reduceMotion: Bool { systemReduceMotion || forcedReduceMotion }
    private var current: Page { page ?? initialPage }
    private var alarms: Binding<Bool> { Binding(get:{ alarmsShown ?? showsAlarms },set:{ alarmsShown=$0 }) }
    /// At accessibility sizes the eye's clock scrolls with the page instead of standing in the
    /// footer, so the countdown keeps the room it needs.
    private var inline: Bool { typeSize.isAccessibilitySize }
    var body: some View {
        let palette=NyxPalette(nightVision:true,highContrast:contrast == .increased)
        VStack(spacing:0) {
            header
            // Without a full cloud forecast (offline with nothing cached, or a stale one) the score says
            // what its clouds rest on, under it, aligned with the park's name.
            if !session.score.hasForecast {
                Text(session.score.basis.isEarlyLook ? String(localized:"Early look: the forecast is eased toward usual clouds.") : String(localized:"No cloud forecast yet. This score uses the park's usual clouds.")).font(.caption)
                    .fixedSize(horizontal:false,vertical:true).frame(maxWidth:.infinity,alignment:.leading).padding(.leading,68).padding(.trailing,20)
            }
            // In the flow, not over it: the countdown under it stays readable.
            if let reset=session.reset { resetNotice(reset).padding(.horizontal,16).padding(.top,8).transition(.opacity.combined(with:.move(edge:.top))) }
            Group {
                switch current {
                case .night: FieldNightPager(session:session,focused:$focused,eyeClock:inline ? $aboutEyes : nil)
                case .look: FieldCompassView(session:session,fixedPose:fixedPose,eyeClock:inline ? $aboutEyes : nil)
                }
            }.frame(maxHeight:.infinity)
            footer
        }
        .background(Color.black.ignoresSafeArea())
        // VoiceOver's two-finger scrub leaves field mode, as it would leave any modal screen. On a
        // container, so the action is not copied onto every caption inside (which would make them
        // read as small buttons).
        .accessibilityElement(children:.contain)
        .accessibilityAction(.escape) { NightListener.shared.stop(); close() }
        .animation(reduceMotion ? nil : NyxMotion.spring,value:session.reset)
        .environment(\.nyx,palette)
        .foregroundStyle(palette.ink,palette.muted,palette.muted).tint(palette.accent)
        .modifier(NightVisionFilter(enabled:true))
        .preferredColorScheme(.dark)
        .statusBarHidden(true).persistentSystemOverlays(.hidden)
        // Remembered so the park's page can offer "Keep this night" the morning after.
        .onAppear { if session.changesPhone { KeepThisNight.record(park:session.park,night:session.night.sky.evening) } }
        .modifier(FieldJournalStore())
        .sensoryFeedback(.selection,trigger:focused)
        .sensoryFeedback(.impact(weight:.light),trigger:session.milestonesPassed)
        .sensoryFeedback(.success,trigger:session.darknessBegan)
        .sheet(isPresented:alarms) {
            NavigationStack {
                ScrollView { FieldAlarmRows(park:session.park,options:session.night.alarmOptions(at:session.now)).padding(24) }
                    .background(Color.black).navigationTitle("Wake me").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement:.confirmationAction) { Button("Done") { alarms.wrappedValue=false } } }
            }
            // The palette goes outside, so the red presentation style reads it (a sheet does not inherit it from here).
            .nyxPresentation().environment(\.nyx,palette).presentationDetents([.medium,.large])
        }
    }
    // MARK: Header: leave, the park and its score, and the night's options

    private var header: some View {
        HStack(alignment:.center,spacing:12) {
            Button { NightListener.shared.stop(); close() } label:{ Image(systemName:"xmark").font(.body.weight(.semibold)).frame(minWidth:44,minHeight:44).contentShape(Rectangle()) }
                .accessibilityLabel("Leave field mode").accessibilityInputLabels([Text("Leave"),Text("Close"),Text("Leave field mode")])
            VStack(alignment:.leading,spacing:2) {
                Text(session.park.shortName).font(.system(.headline,design:.serif)).lineLimit(typeSize.isAccessibilitySize ? 3 : 2).minimumScaleFactor(0.85)
                // Wraps at accessibility sizes rather than cutting the band short.
                Text("\(session.score.value) · \(session.score.band.label)").font(.caption).monospacedDigit().fixedSize(horizontal:false,vertical:true)
            }
            // One spoken line; the visible caption keeps its own short text.
            .accessibilityElement(children:.ignore)
            .accessibilityLabel("\(session.park.shortName). Darkness score \(session.score.value), \(session.score.band.label)")
            Spacer(minLength:8)
            Menu {
                if FieldAlarms.supported && !session.night.alarmOptions(at:session.now).isEmpty { Button("Wake me…",systemImage:"alarm") { alarms.wrappedValue=true } }
                if FieldActivities.enabled || !session.changesPhone {
                    Toggle(isOn:Binding(get:{ session.following },set:{ session.follow($0) })) { Label("Follow on the Lock Screen",systemImage:"lock.rectangle") }
                }
                // Tonight as twelve seconds of sound; best with headphones, out of respect for the dark around you.
                if NightListener.shared.isPlaying { Button("Stop listening",systemImage:"stop.fill") { NightListener.shared.stop() } }
                else { Button("Listen to tonight",systemImage:"waveform") { NightListener.shared.play(NightSonification(park:session.park,sky:session.night.sky)) } }
            } label:{ Image(systemName:"ellipsis").font(.body.weight(.semibold)).frame(minWidth:44,minHeight:44).contentShape(Rectangle()) }
                .accessibilityLabel("Field mode options").accessibilityInputLabels([Text("Options"),Text("Field mode options")])
        }
        .padding(.horizontal,12).padding(.top,8)
    }
    // MARK: Footer: the eye's clock and the two pages

    private var footer: some View {
        VStack(spacing:14) {
            if !inline { EyeClock(session:session,expanded:$aboutEyes) }
            let picker=Picker("View",selection:Binding(get:{ current },set:{ page=$0 })) {
                Text("The night").tag(Page.night)
                Text("Where to look").tag(Page.look)
            }
            // At accessibility sizes a menu, which never clips its labels; segments do not grow.
            if inline { picker.pickerStyle(.menu).frame(maxWidth:.infinity,alignment:.leading) } else { picker.pickerStyle(.segmented) }
        }
        .padding(.horizontal,20).padding(.bottom,12).padding(.top,8)
        .readableColumn(WideLayout.proseWidth)
    }
    private func resetNotice(_ reset:DarkAdaptation.Reset)->some View {
        VStack(alignment:.leading,spacing:12) {
            Text("Your eyes started over at \(session.park.time(reset.at)).").font(.system(.headline,design:.serif))
            Text("Nyx can't see what you looked at while you were away. Bright light resets dark adaptation.").font(.subheadline)
                .fixedSize(horizontal:false,vertical:true)
            ViewThatFits(in:.horizontal) {
                HStack(spacing:12) { resetButtons }
                VStack(alignment:.leading,spacing:8) { resetButtons }
            }
        }
        .padding(18).frame(maxWidth:.infinity,alignment:.leading)
        .background(RoundedRectangle(cornerRadius:20).fill(Color(white:0.07)))
        .overlay(RoundedRectangle(cornerRadius:20).stroke(Color.white.opacity(0.3),lineWidth:0.5))
        .accessibilityElement(children:.contain)
    }
    @ViewBuilder private var resetButtons: some View {
        Button("Start over") { session.reset=nil }.buttonStyle(.bordered)
        Button("My screen stayed dark") { session.keepAdaptation() }.buttonStyle(.bordered)
    }
}

// MARK: The night, one milestone at a time

/// "Now" first, then each milestone still ahead, snapping into place one at a time. Passed
/// milestones collect quietly at the end.
struct FieldNightPager: View {
    let session: FieldSession
    @Binding var focused: String?
    /// At accessibility sizes, the eye's clock scrolls here, under "Now".
    var eyeClock: Binding<Bool>?=nil
    @Environment(\.nyx) private var palette
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.nyxReduceMotion) private var forcedReduceMotion
    @ScaledMetric(relativeTo:.largeTitle) private var numeral=68.0
    var body: some View {
        TimelineView(.periodic(from:.now,by:30)) { _ in
            let now=session.now
            let ahead=session.night.upcoming(after:now), passed=session.night.milestones.filter { $0.date<=now }
            ScrollView(.vertical) {
                LazyVStack(alignment:.leading,spacing:44) {
                    nowCard(now).id("now")
                    if let eyeClock { EyeClock(session:session,expanded:eyeClock) }
                    ForEach(ahead) { milestone in card(milestone,now:now).id(milestone.id) }
                    if !passed.isEmpty { earlier(passed).id("earlier") }
                }
                .scrollTargetLayout()
                // VoiceOver: step through what is still to come tonight, one milestone at a time.
                .accessibilityRotor(Text("Milestones"),entries:ahead.map { MilestoneStop(id:$0.id,label:String(localized:"\($0.title), \(session.night.park.time($0.date))")) },entryID:\.id,entryLabel:\.label)
                .padding(.horizontal,24)
                // An iPad in landscape: one milestone at a time, at a reading width.
                .readableColumn(WideLayout.proseWidth)
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id:$focused,anchor:.top)
            .contentMargins(.vertical,28,for:.scrollContent)
            // Text fades into the dark before it reaches the eye's clock below.
            .mask(LinearGradient(stops:[.init(color:.clear,location:0),.init(color:.black,location:0.03),.init(color:.black,location:0.88),.init(color:.clear,location:1)],startPoint:.top,endPoint:.bottom))
        }
    }
    private func dims(_ content:some View)->some View {
        content.scrollTransition(.interactive) { [still = systemReduceMotion || forcedReduceMotion] view,phase in
            view.scaleEffect(still || phase.isIdentity ? 1 : 0.96,anchor:.leading)
        }
    }
    private func nowCard(_ now:Date)->some View {
        let status=session.night.status(at:now)
        return dims(VStack(alignment:.leading,spacing:10) {
            Eyebrow(text:"Now")
            Text(status.lead).font(.system(.title2,design:.serif)).fixedSize(horizontal:false,vertical:true)
            if let target=status.target { FieldCountdown(target:session.real(target),numeral:numeral) }
            if !status.trailing.isEmpty { Text(status.trailing).font(.system(.title3,design:.serif)).fixedSize(horizontal:false,vertical:true) }
            // Dawn: the night can go straight into the journal, with the park, the date and the score.
            if status.phase == .over, KeepThisNight.container != nil || DebugScenario.screen != nil {
                KeepThisNightButton(prefill:JournalPrefill(parkID:session.park.id,date:session.night.sky.evening,observedBortle:session.park.bortleEstimate,
                    notes:String(localized:"Nyx scored this night \(session.score.value), \(session.score.band.label). \(session.night.sky.moon.name), \(Int((session.night.sky.moon.illumination*100).rounded()))% lit.")),prominent:false)
                    .padding(.top,10)
            }
            Text(moonLine(now)).font(.subheadline).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true).padding(.top,6)
        }
        .frame(maxWidth:.infinity,alignment:.leading)
        .accessibilityElement(children:status.phase == .over ? .contain : .ignore)
        .accessibilityLabel(status.spoken+" "+moonLine(now)))
    }
    private func card(_ milestone:FieldNight.Milestone,now:Date)->some View {
        let park=session.night.park
        let until=String(localized:"in \(FieldNight.span(milestone.date.timeIntervalSince(now)))")
        return dims(VStack(alignment:.leading,spacing:8) {
            HStack(alignment:.firstTextBaseline,spacing:12) {
                Image(systemName:milestone.symbol).font(.title2).accessibilityHidden(true)
                Text(park.time(milestone.date)).font(.system(.largeTitle,design:.serif)).monospacedDigit()
            }
            Text(milestone.title).font(.system(.title2,design:.serif)).fixedSize(horizontal:false,vertical:true)
            Text(until).font(.subheadline.weight(.medium))
            Text(milestone.detail).font(.body).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
        }
        .frame(maxWidth:.infinity,alignment:.leading)
        .accessibilityElement(children:.ignore)
        .accessibilityLabel("\(milestone.title), \(park.time(milestone.date)), \(String(localized:"in \(FieldNight.spokenSpan(milestone.date.timeIntervalSince(now)))")). \(milestone.detail)"))
    }
    private func earlier(_ passed:[FieldNight.Milestone])->some View {
        VStack(alignment:.leading,spacing:10) {
            Eyebrow(text:"Earlier tonight")
            ForEach(passed) { milestone in
                HStack(alignment:.firstTextBaseline) {
                    Text(milestone.title).fixedSize(horizontal:false,vertical:true)
                    Spacer(minLength:8)
                    Text(session.night.park.time(milestone.date)).monospacedDigit()
                }.font(.subheadline).foregroundStyle(palette.muted)
                .accessibilityElement(children:.combine)
            }
        }.padding(.bottom,24)
    }
    /// Where the Moon is now, in one line.
    private func moonLine(_ now:Date)->String {
        let night=session.night, sky=night.sky
        if sky.moon.illumination<0.05 { return String(localized:"New moon: no moonlight tonight.") }
        let lit=Int((sky.moon.illumination*100).rounded())
        let up=AstronomyEngine().lunarAltitude(at:now,park:night.park) > -0.833
        if up { return sky.moonset.flatMap { $0>now ? String(localized:"Moon up, \(lit)% lit. It sets at \(night.park.time($0)).") : nil } ?? String(localized:"Moon up, \(lit)% lit.") }
        return sky.moonrise.flatMap { $0>now ? String(localized:"Moon below the horizon until \(night.park.time($0)).") : nil } ?? String(localized:"Moon below the horizon.")
    }
}

/// A milestone's rotor stop: "Moonrise, 1:12 AM", in park time like its card.
struct MilestoneStop: Identifiable { let id: String; let label: String }

// MARK: The eye's clock

/// How far into dark adaptation the eye should be, from the time spent in red light. An estimate,
/// said plainly; tapping it explains the physiology.
struct EyeClock: View {
    let session: FieldSession
    @Binding var expanded: Bool
    @Environment(\.nyx) private var palette
    var body: some View {
        TimelineView(.periodic(from:.now,by:15)) { _ in
            let now=session.now, adaptation=session.adaptation
            let minutes=Int(adaptation.elapsed(at:now)/60)
            VStack(alignment:.leading,spacing:10) {
                Button { expanded.toggle() } label:{
                    HStack(spacing:14) {
                        ZStack {
                            Circle().stroke(palette.line,lineWidth:3)
                            Circle().trim(from:0,to:adaptation.progress(at:now)).stroke(palette.ink,style:StrokeStyle(lineWidth:3,lineCap:.round)).rotationEffect(.degrees(-90))
                            Image(systemName:"eye").font(.caption2).accessibilityHidden(true)
                        }.frame(width:34,height:34)
                        VStack(alignment:.leading,spacing:2) {
                            Text(title(adaptation.stage(at:now))).font(.subheadline.weight(.medium)).fixedSize(horizontal:false,vertical:true)
                            if adaptation.stage(at:now) == .rods { Text("Your faint-light vision is waking up.").font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true) }
                            Text(adaptation.stage(at:now) == .adapted ? String(localized:"About 30 minutes in red light. An estimate.") : String(localized:"\(minutes) of about 30 minutes. An estimate."))
                                .font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
                        }
                        Spacer(minLength:0)
                        Image(systemName:expanded ? "chevron.down" : "info.circle").font(.caption).accessibilityHidden(true)
                    }.frame(minHeight:44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children:.ignore)
                .accessibilityLabel(adaptation.stage(at:now) == .rods ? String(localized:"Dark adaptation: rods taking over. Your faint-light vision is waking up.") : String(localized:"Dark adaptation: \(title(adaptation.stage(at:now)))"))
                .accessibilityValue(String(localized:"\(minutes) of about 30 minutes. An estimate."))
                .accessibilityHint(expanded ? "Hides how this works" : "Explains how this works")
                if expanded {
                    Text("Eyes adapt to the dark in two steps. Cones settle in about 10 minutes; rods, which see faint stars and the Milky Way, need 20 to 30. Dim red light barely touches rods, and a moment of white light starts them over. This clock counts your time in field mode, so it is only an estimate.")
                        .font(.footnote).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
                }
            }
        }
    }
    private func title(_ stage:DarkAdaptation.Stage)->String {
        switch stage {
        case .cones: String(localized:"Eyes adjusting")
        case .rods: String(localized:"Rods taking over")
        case .adapted: String(localized:"Dark-adapted")
        }
    }
}

// MARK: Wake me

/// The night's alarms as switches: core up, true darkness, half an hour before the Moon sets.
/// Permission is asked in context, after an explainer, the first time one is set.
struct FieldAlarmRows: View {
    let park: Park
    let options: [FieldNight.AlarmOption]
    var showsHeading=false
    @Environment(\.nyx) private var palette
    @Environment(\.openURL) private var openURL
    @State private var set: Set<String>=[]
    @State private var pending: FieldNight.AlarmOption?
    @State private var message: String?
    @State private var working=false
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            if showsHeading { Eyebrow(text:"Wake me") }
            ForEach(options) { option in
                let on=set.contains(FieldAlarms.key(park:park,option:option))
                Button { Task { await toggle(option) } } label:{
                    Label {
                        VStack(alignment:.leading,spacing:2) {
                            Text(option.label).fixedSize(horizontal:false,vertical:true)
                            Text(on ? String(localized:"Set for \(park.time(option.fire))") : park.time(option.fire)).font(.caption).foregroundStyle(palette.muted)
                        }
                    } icon:{ Image(systemName:on ? "alarm.fill" : "alarm").foregroundStyle(palette.accent) }
                    .frame(maxWidth:.infinity,minHeight:44,alignment:.leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain).disabled(working)
                .accessibilityAddTraits(.isToggle).accessibilityValue(on ? "Set" : "Off").accessibilityHint(on ? "Removes the alarm" : "Sets an alarm on this iPhone")
            }
            Text("Alarms ring through Silent and Focus. They are set on this iPhone and nowhere else.").font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
            if let message {
                Text(message).font(.caption).foregroundStyle(palette.accent).fixedSize(horizontal:false,vertical:true)
                if FieldAlarms.access == .denied, let url=URL(string:UIApplication.openSettingsURLString) { Button("Open Settings") { openURL(url) }.font(.caption).frame(minHeight:44).contentShape(Rectangle()) }
            }
        }
        .task { refresh() }
        .sheet(item:$pending) { option in
            PermissionExplainer(symbol:"alarm",title:"An alarm for the sky",message:"Nyx can set an alarm on this iPhone for a moment in the night, like the Milky Way's core rising, so you can rest until the sky is ready. Alarms ring through Silent and Focus. Nothing leaves this phone.",action:"Allow alarms") {
                pending=nil
                Task {
                    if await FieldAlarms.requestAccess() { await toggle(option) }
                    else { message=String(localized:"Alarms for Nyx are off. You can allow them in iPhone Settings.") }
                }
            }.nyxPresentation()
        }
    }
    private func refresh() { set=Set(options.filter { FieldAlarms.isSet(park:park,option:$0) }.map { FieldAlarms.key(park:park,option:$0) }) }
    private func toggle(_ option:FieldNight.AlarmOption) async {
        guard DebugScenario.screen == nil else { return }
        switch FieldAlarms.access {
        case .notAsked: pending=option
        case .denied: message=String(localized:"Alarms for Nyx are off. You can allow them in iPhone Settings.")
        case .allowed:
            working=true; defer { working=false }
            do { try await FieldAlarms.toggle(park:park,option:option); message=nil }
            catch { message=String(localized:"The alarm could not be set. Try again, or use the Clock app.") }
            refresh()
        }
    }
}

// MARK: Entry from park detail

/// "I'm here tonight": opens field mode for tonight at this park. Under it, a quieter way to have
/// the night's countdown on the Lock Screen without opening the field screen.
struct FieldEntry: View {
    @Environment(PlanModel.self) private var model
    @Environment(SceneCommands.self) private var commands: SceneCommands?
    @Environment(\.nyx) private var palette
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage("nightVision",store:SharedSettings.defaults) private var nightVision=false
    @Environment(\.modelContext) private var context
    let park: Park
    let night: Night
    var body: some View {
        VStack(spacing:6) {
            if FieldPresenter.supported {
                Button { FieldPresenter.present(park:park,model:model,from:commands?.topController ?? SceneCommands.top(in:nil)) } label:{
                    Label("I'm here tonight",systemImage:"scope").font(.headline).padding(.horizontal,10).frame(minHeight:44)
                }
                .modifier(FieldButtonStyle())
                .accessibilityHint("Opens field mode: a dark red screen with tonight's milestones and where to look.")
            }
            // Tonight, followed: scheduled for half an hour before sunset, or at once after that (`FollowNight`).
            if FollowNight.offered(night) {
                let following=NightFollowing.shared.isFollowing(park:park,night:night.id)
                Button { Task { await FollowNight.toggle(night,closure:model.closure(park),nightVision:nightVision) } } label:{
                    // The whole 44-point row is the target, not just the line of text.
                    Text(following ? "On your Lock Screen tonight. Stop" : "Follow tonight on the Lock Screen")
                        .font(.footnote).multilineTextAlignment(.center).padding(.horizontal,12).frame(minHeight:44).contentShape(Rectangle())
                }
                .accessibilityValue(FollowNight.caption(night,following:following))
            }
        }
        .task { NightFollowing.shared.reload() }
        // Field mode is presented over the app; its dawn "Keep this night" needs the journal's store.
        .onAppear { KeepThisNight.container=context.container }
    }
}
/// Liquid Glass normally; a plain bordered capsule in night vision and under Reduce Transparency.
private struct FieldButtonStyle:ViewModifier {
    @Environment(\.nyx) private var palette
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder func body(content:Content)->some View {
        if palette.nightVision || reduceTransparency || palette.highContrast { content.buttonStyle(.bordered).buttonBorderShape(.capsule) }
        else { content.buttonStyle(.glass).buttonBorderShape(.capsule) }
    }
}

/// The journal's store for field mode, which is presented over the app without its environment.
private struct FieldJournalStore: ViewModifier {
    @ViewBuilder func body(content:Content)->some View {
        if let container=KeepThisNight.container { content.modelContainer(container) } else { content }
    }
}
/// The time to a moment, in words a dark-adapted eye cannot mistake for a clock: "23 min",
/// "1 h 31 min", serif numerals with smaller units, ticking each minute. Only the last two
/// minutes count down as m:ss. The surrounding card speaks it as a sentence.
struct FieldCountdown: View {
    let target: Date
    var numeral: Double=68
    var body: some View {
        TimelineView(FieldCountdownSchedule(target:target)) { context in
            let remaining=target.timeIntervalSince(context.date)
            Group {
                if remaining<=120 {
                    Text(timerInterval:context.date...max(context.date,target),countsDown:true,showsHours:false)
                        .font(.system(size:numeral,weight:.light,design:.serif)).monospacedDigit().tracking(-1)
                } else {
                    let parts=Self.parts(remaining)
                    ViewThatFits(in:.horizontal) {
                        HStack(alignment:.firstTextBaseline,spacing:6) { units(parts) }
                        VStack(alignment:.leading,spacing:0) { units(parts) }
                    }
                }
            }
            .lineLimit(1)
            .accessibilityHidden(true)
        }
    }
    @ViewBuilder private func units(_ parts:(hours:Int,minutes:Int))->some View {
        if parts.hours>0 {
            HStack(alignment:.firstTextBaseline,spacing:4) { figure(parts.hours); unit(String(localized:"h")) }
        }
        if parts.minutes>0 || parts.hours==0 {
            HStack(alignment:.firstTextBaseline,spacing:4) { figure(parts.minutes); unit(String(localized:"min")) }
        }
    }
    private func figure(_ value:Int)->some View { Text(value,format:.number).font(.system(size:numeral,weight:.light,design:.serif)).monospacedDigit().tracking(-1) }
    private func unit(_ text:String)->some View { Text(text).font(.system(size:numeral*0.36,weight:.regular,design:.serif)) }
    /// Whole hours and minutes, rounded up to the next minute, as a countdown should be.
    nonisolated static func parts(_ seconds:TimeInterval)->(hours:Int,minutes:Int) {
        let minutes=Int((max(0,seconds)/60).rounded(.up))
        return (minutes/60,minutes%60)
    }
}
/// Ticks on each minute boundary counted back from the target, then every second for the last two minutes.
struct FieldCountdownSchedule: TimelineSchedule {
    let target: Date
    func entries(from startDate:Date,mode:TimelineScheduleMode)->AnyIterator<Date> {
        var next=startDate
        return AnyIterator {
            let current=next
            let remaining=target.timeIntervalSince(current)
            if remaining<=120 { next=current.addingTimeInterval(1) }
            else {
                // The next moment the rounded-up minute changes.
                let step=remaining.truncatingRemainder(dividingBy:60)
                next=current.addingTimeInterval(step>0.001 ? step : 60)
            }
            return current
        }
    }
}
#Preview("Countdown • 23 min • 1 h 31 min • 1:40") {
    VStack(alignment:.leading,spacing:24) {
        FieldCountdown(target:.now.addingTimeInterval(22*60+39))
        FieldCountdown(target:.now.addingTimeInterval(90*60+10))
        FieldCountdown(target:.now.addingTimeInterval(100))
    }.padding().foregroundStyle(.white).background(.black)
}
