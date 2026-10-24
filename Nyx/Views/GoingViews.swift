import SwiftUI
import UserNotifications

// MARK: I'm going

/// "I'm going" on a chosen night: Nyx keeps the night, with today's score as the one changes are
/// measured from, and keeps watch (`GoingWatch`). On a park's page right under the verdict and the
/// best window, with Add to Calendar under it once kept. A starlight capsule (`secondaryAction`):
/// amber is the score's. A toggle, as Follow buttons are: kept, it reads "Going" with a filled mark,
/// and the line under it says how the night stood when chosen. The first time, with reminders not
/// yet decided, it asks in context.
struct GoingButton: View {
    @Environment(PlanModel.self) private var model
    @Environment(\.nyx) private var palette
    @AppStorage("notificationsEnabled") private var notificationsEnabled=false
    let night: Night
    /// Centred under a centred hero; leading at accessibility sizes, where the hero reads from the edge.
    var alignment=HorizontalAlignment.center
    @State private var explaining=false
    @State private var full=false
    private var store: GoingNights { .shared }
    var body: some View {
        if !FieldNight.isOver(night.sky,at:DebugScenario.date ?? .now) {
            let going=store.going(park:night.park,night:night.id)
            VStack(alignment:alignment,spacing:6) {
                Button { toggle(going) } label:{
                    Label(going == nil ? "I'm going" : "Going",systemImage:going == nil ? "checkmark.circle" : "checkmark.circle.fill")
                        .font(.headline).padding(.horizontal,10).frame(minHeight:44)
                        .contentTransition(.symbolEffect(.replace))
                }
                .secondaryAction()
                .accessibilityLabel(going == nil ? String(localized:"I'm going to \(night.park.shortName) on \(night.park.dayLabel(night.id))")
                                                 : String(localized:"Not going to \(night.park.shortName) on \(night.park.dayLabel(night.id))"))
                .accessibilityValue(caption(going))
                .accessibilityInputLabels(going == nil ? [Text("I'm going"),Text("Going")] : [Text("Not going")])
                .accessibilityAddTraits(going == nil ? .isToggle : [.isToggle,.isSelected])
                // The button's value says it.
                Text(caption(going)).font(.caption).foregroundStyle(palette.muted).multilineTextAlignment(alignment == .center ? .center : .leading)
                    .fixedSize(horizontal:false,vertical:true).accessibilityHidden(true)
            }
            .alert("Nyx keeps watch on four nights at a time",isPresented:$full) { Button("OK",role:.cancel) {} } message:{
                Text("Let one of them go first, on Tonight or on its own page.")
            }
            .sensoryFeedback(.selection,trigger:going == nil)
            .sheet(isPresented:$explaining) { GoingExplainer { granted in notificationsEnabled=granted; Task { await GoingWatch.check(model) } }.nyxPresentation() }
        }
    }
    private func caption(_ going: GoingNight?) -> String {
        guard let going else { return String(localized:"Nyx keeps watch and tells you if this night gets clearly worse.") }
        return notificationsEnabled ? String(localized:"Keeping watch. \(going.chosenScore) when you chose it.")
                                    : String(localized:"\(going.chosenScore) when you chose it. Turn on reminders to hear if it changes.")
    }
    private func toggle(_ going: GoingNight?) {
        if let going { store.stop(going); Task { await GoingWatch.check(model) }; return }
        guard store.go(night) else { full=true; return }
        Task {
            if !notificationsEnabled, await UNUserNotificationCenterStatus.undecided() { explaining=true }
            await GoingWatch.check(model)
        }
    }
}
/// Whether iOS has yet to ask about notifications.
enum UNUserNotificationCenterStatus {
    static func undecided() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .notDetermined
    }
}
/// The in-context explainer before iOS asks: what a going night's alerts are, and that the same
/// switch is the evening-before reminders' (Settings › Reminders).
struct GoingExplainer: View {
    @Environment(\.dismiss) private var dismiss
    let decided: (Bool) -> Void
    var body: some View {
        PermissionExplainer(symbol:"bell",title:"Know if this night changes",message:"Nyx can tell you if a night you are going to gets clearly worse, with a better choice nearby when there is one, and remind you when to leave. The same switch allows the evening-before reminders for Pristine nights at places you save. Everything is scheduled on this iPhone. iOS decides how often Nyx can check while it is closed, so open Nyx before you set off.",action:"Enable reminders") {
            dismiss()
            Task { decided(await NotificationScheduler().requestAuthorization()) }
        }
    }
}

// MARK: Your night

/// At the top of Tonight while a night kept as going is under a week away: how it stands now
/// against when it was chosen, any closure, when to leave, what is saved for offline use, and the
/// plan to send to someone. The soonest night only; the rest are a tap away on their own pages.
struct GoingPanel: View {
    /// The park Tonight's answer shows: when the kept night is tonight there, its name, score and
    /// closure are already on screen just below, and the card keeps only what is its own.
    var hero: Park?=nil
    @Environment(PlanModel.self) private var model
    @Environment(\.nyx) private var palette
    @AppStorage("notificationsEnabled") private var notificationsEnabled=false
    @State private var editingDrive: GoingNight?
    private var store: GoingNights { .shared }
    /// The nights kept; DEBUG captures and audits (`-nyx-going`, `-nyx-screen going`) show the starting park
    /// tomorrow, chosen 18 points higher, with a drive.
    private var kept: [GoingNight] {
        if DebugScenario.isEnabled("going") || DebugScenario.screen == "going", let park=model.home {
            let night=model.night(park,on:park.date(model.tonight(park),addingDays:1))
            return [GoingNight(parkID:park.id,night:night.id,chosenScore:min(100,night.score.value+18),chosenAt:.now,driveMinutes:195)]
        }
        return store.nights
    }
    /// The soonest night kept that is not over and is at most a week away.
    private var soonest: (going: GoingNight, night: Night)? {
        let now=DebugScenario.date ?? .now
        for going in kept {
            guard let park=model.park(going.parkID) else { continue }
            let night=model.night(park,on:going.night)
            if !FieldNight.isOver(night.sky,at:now), going.night.timeIntervalSince(now)<=7*86400 { return (going,night) }
        }
        return nil
    }
    var body: some View {
        if let soonest { panel(soonest.going,soonest.night) }
    }
    private func panel(_ going: GoingNight, _ night: Night) -> some View {
        let park=night.park, outlook=model.outlook(night), closure=model.closure(park)
        let status=GoingCheck.status(chosen:going.chosenScore,night:night,agreement:outlook?.agreement)
        // First on Tonight, under the navigation bar: no horizon rule above it.
        return Panel(rule:false) { VStack(alignment:.leading,spacing:14) {
            Eyebrow(text:"Your night")
            let repeated=hero?.id==park.id && night.id==model.tonight(park)
            if !repeated {
            NavigationLink { ParkDetailView(park:park,initialDate:night.id) } label:{
                HStack(alignment:.firstTextBaseline,spacing:12) {
                    VStack(alignment:.leading,spacing:2) {
                        Text(park.shortName).font(.system(.title3,design:.serif)).foregroundStyle(palette.ink).fixedSize(horizontal:false,vertical:true)
                        Text(park.dayLabel(night.id)).font(.subheadline).foregroundStyle(palette.muted)
                    }
                    Spacer(minLength:8)
                    VStack(alignment:.trailing,spacing:0) {
                        Text("\(night.score.value)").scoreNumeral(.title,accent:palette.accent)
                        Text(night.score.band.label).bandWord(.footnote,ink:palette.muted)
                    }
                }.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children:.ignore)
            .accessibilityLabel(String(localized:"\(park.shortName), \(park.dayLabel(night.id)): \(night.score.value), \(night.score.band.label)"))
            .accessibilityHint("Opens that night at the park.")
            }
            Label { Text(statusLine(status,going:going,night:night,agreement:outlook?.agreement)).fixedSize(horizontal:false,vertical:true) } icon:{
                // A fall is a caution: the glyph in its own red, the words in starlight, amber left to the score.
                Image(systemName:status == .worse ? "exclamationmark.circle" : status == .uncertain ? "questionmark.circle" : "checkmark.circle").foregroundStyle(status == .worse ? palette.caution : palette.ink).accessibilityHidden(true)
            }
            .font(.subheadline).foregroundStyle(palette.ink)
            if let closure, !repeated {
                Label(closure,systemImage:"exclamationmark.triangle").font(.subheadline).labelStyle(.caution).fixedSize(horizontal:false,vertical:true)
                    .accessibilityLabel(ClosureLine.spoken(closure))
            }
            // The time to leave is also the way to the drive time: one row, no extra button.
            if night.sky.sunset != nil {
                Button { editingDrive=going } label:{
                    HStack(alignment:.firstTextBaseline,spacing:8) {
                        Label { Text(LeaveBy.line(park:park,sky:night.sky,driveMinutes:going.driveMinutes) ?? String(localized:"Add your drive time to know when to leave.")).fixedSize(horizontal:false,vertical:true) }
                            icon:{ Image(systemName:"car").accessibilityHidden(true) }
                        Spacer(minLength:4)
                        Image(systemName:"chevron.forward").font(.caption.weight(.semibold)).foregroundStyle(palette.muted).accessibilityHidden(true)
                    }
                    .font(.subheadline).foregroundStyle(palette.ink)
                    .frame(minHeight:44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(going.driveMinutes.map { String(localized:"Drive time, \(LeaveBy.drive($0))") } ?? "")
                .accessibilityHint("Sets how long the drive takes, so Nyx can say when to leave.")
            }
            Text(OfflineReady.line(park:park,forecast:night.forecastUpdated,alerts:model.enrichments[park.id]?.updated,parkServicePlace:park.nps != nil,forecastsOn:model.weatherEnabled))
                .font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
            if !notificationsEnabled {
                Text("Reminders are off, so Nyx can only show changes here. Turn them on in Settings.").font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
            }
            actions(going,night,closure:closure)
        } }
        .sheet(item:$editingDrive) { going in DriveTimeSheet(going:going,park:park).nyxPresentation() }
    }
    private func statusLine(_ status: GoingCheck.Status, going: GoingNight, night: Night, agreement: ModelAgreement?) -> String {
        switch status {
        case .worse: return GoingCheck.summary(going,night:night,alternative:GoingWatch.alternative(model,night:night))
        case .uncertain:
            if night.basis != .forecast { return String(localized:"Too early to call. The full cloud forecast reaches a night about three days ahead.") }
            return agreement?.sentence(tonight:night.id==model.tonight(night.park)) ?? String(localized:"Too early to call.")
        case .good: return String(localized:"Looks good so far: \(going.chosenScore) when you chose it.")
        }
    }
    /// Tell someone, and "Not going" in the menu beside it.
    private func actions(_ going: GoingNight, _ night: Night, closure: String?) -> some View {
        HStack(spacing:10) {
            ShareLink(item:TellSomeone.message(night:night,spot:MapsHandOff.spot(for:night.park)?.spot,closure:closure)) {
                Label("Tell someone",systemImage:"person.wave.2").font(.subheadline).frame(minHeight:44)
            }
            .secondaryAction().accessibilityHint("Shares where you will be and when you expect to be back. You choose who it goes to.")
            Spacer(minLength:0)
            Menu {
                Button("Drive time",systemImage:"car") { editingDrive=going }
                Button("Not going",systemImage:"xmark",role:.destructive) { store.stop(going); Task { await GoingWatch.check(model) } }
            } label:{ Image(systemName:"ellipsis").frame(minWidth:44,minHeight:44).contentShape(Rectangle()) }
            .accessibilityLabel("More for this night")
        }
        // Starlight, as every action: amber is the score's and the light's.
        .tint(palette.ink)
    }
}

/// The drive, as the person knows it: Nyx asks no routing service, so the time is theirs. In
/// quarter hours, up to twelve.
struct DriveTimeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PlanModel.self) private var model
    @Environment(\.nyx) private var palette
    let going: GoingNight
    let park: Park
    @State private var minutes: Int
    init(going: GoingNight, park: Park) {
        self.going=going; self.park=park
        _minutes=State(initialValue:going.driveMinutes ?? 120)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value:$minutes,in:15...720,step:15) {
                        LabeledContent("Drive to \(park.shortName)",value:LeaveBy.drive(minutes))
                    }
                    if let line=LeaveBy.line(park:park,sky:model.night(park,on:going.night).sky,driveMinutes:minutes) {
                        Text(line).foregroundStyle(palette.muted)
                    }
                } footer:{
                    Text("Take it from Maps or from your own trips. Nyx asks no routing service, so the time stays yours.")
                }.listRowBackground(palette.panel)
                if going.driveMinutes != nil {
                    Section { Button("Remove drive time",role:.destructive) { GoingNights.shared.setDrive(nil,for:going); finish() } }.listRowBackground(palette.panel)
                }
            }
            .scrollContentBackground(.hidden).background(Color.black)
            .navigationTitle("Drive time").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement:.cancellationAction) { Button(role:.cancel) { dismiss() } }
                ToolbarItem(placement:.confirmationAction) { Button(role:.confirm) { GoingNights.shared.setDrive(minutes,for:going); finish() }.accessibilityLabel("Save") }
            }
        }
        .presentationDetents([.medium,.large]).presentationSizing(.form)
    }
    private func finish() { dismiss(); Task { await GoingWatch.check(model) } }
}

#Preview("Your night") {
    let m=PlanModel()
    if let p=m.home {
        let _={ GoingNights.shared.go(m.night(p,on:p.date(m.tonight(p),addingDays:2))) }()
        NavigationStack { ScrollView { GoingPanel().padding() } }.environment(m).background(.black).preferredColorScheme(.dark)
    }
}
#Preview("Your night • AX5") {
    let m=PlanModel()
    if let p=m.home {
        let _={ GoingNights.shared.go(m.night(p,on:p.date(m.tonight(p),addingDays:1))) }()
        NavigationStack { ScrollView { GoingPanel().padding() } }.environment(m).dynamicTypeSize(.accessibility5).background(.black).preferredColorScheme(.dark)
    }
}
#Preview("Drive time") {
    let m=PlanModel()
    if let p=m.home { DriveTimeSheet(going:GoingNight(parkID:p.id,night:m.tonight(p),chosenScore:80,chosenAt:.now,driveMinutes:195),park:p).environment(m).preferredColorScheme(.dark) }
}
#Preview("I'm going") {
    let m=PlanModel()
    if let p=m.home { GoingButton(night:m.night(p,on:p.date(m.tonight(p),addingDays:3))).padding().environment(m).background(.black).preferredColorScheme(.dark) }
}
