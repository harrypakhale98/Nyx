import SwiftUI
import SwiftData

// MARK: Add to Calendar

/// "Add to Calendar" for one chosen night: the system's own event editor, filled in with the
/// park, the hours of true darkness and the score as Nyx last saw it (the trip planner's draft).
/// The editor runs outside Nyx, so no calendar permission is asked and nothing is read.
/// Used on a park's selected night; the calendar's night peek and breakdown can place it too.
struct AddNightToCalendar: View {
    @Environment(PlanModel.self) private var model
    @Environment(\.nyx) private var palette
    let night: Night
    @State private var editing=false
    var body: some View {
        Button { editing=true } label:{
            Label("Add to Calendar",systemImage:"calendar.badge.plus").font(.subheadline)
                .frame(maxWidth:.infinity,minHeight:44,alignment:.leading).contentShape(Rectangle())
        }
        .buttonStyle(.nyxAction).foregroundStyle(palette.accent)
        .accessibilityLabel(String(localized:"Add \(night.park.shortName) on \(night.park.dayLabel(night.id)) to Calendar"))
        .accessibilityHint("Opens a calendar event to review and save. Nyx does not read your calendars.")
        .accessibilityInputLabels([Text("Add to Calendar"),Text("Calendar")])
        .sheet(isPresented:$editing) {
            CalendarEditor(draft:CalendarDraft(night:night,closure:model.closure(night.park))) { editing=false }.ignoresSafeArea()
        }
    }
}

// MARK: Keep this night

/// What a new journal entry starts from when a night is kept: the park, the night it began on,
/// the park's estimated Bortle class as the observed default, and one line with the score and
/// the Moon, which the person can keep or replace.
nonisolated struct JournalPrefill: Equatable, Identifiable, Sendable {
    var id: String { "\(parkID)-\(Int(date.timeIntervalSince1970))" }
    let parkID: String
    let date: Date
    let observedBortle: Int
    let notes: String
    init(parkID: String, date: Date, observedBortle: Int, notes: String) {
        self.parkID=parkID; self.date=date; self.observedBortle=observedBortle; self.notes=notes
    }
    init(night: Night) {
        let moon=night.sky.moon
        self.init(parkID:night.park.id,date:night.park.evening(night.id),observedBortle:night.park.bortleEstimate,
                  notes:String(localized:"Nyx scored this night \(night.score.value), \(night.score.band.label). \(moon.name), \(Int((moon.illumination*100).rounded()))% lit."))
    }
}
/// Field mode remembers the nights it was used at each park, so the park's page can offer
/// "Keep this night" the morning after. Only the park and the night are kept, on this iPhone.
@MainActor enum KeepThisNight {
    static let key="fieldNights"
    /// The journal's store, handed over by the screens that have it, for field mode's own sheet
    /// (field mode is presented over the app and does not inherit the app's environment).
    static weak var container: ModelContainer?
    static func record(park: Park, night: Date, defaults: UserDefaults = .standard) {
        var nights=defaults.dictionary(forKey:key) as? [String:Double] ?? [:]
        nights[park.id]=park.evening(night).timeIntervalSince1970
        defaults.set(nights,forKey:key)
    }
    static func fieldNight(park: Park, defaults: UserDefaults = .standard) -> Date? {
        (defaults.dictionary(forKey:key) as? [String:Double])?[park.id].map { Date(timeIntervalSince1970:$0) }
    }
    /// True the morning after a night in the field: that night has ended (after sunrise), the next
    /// has not begun (before sunset), and nothing is in the journal for it yet.
    nonisolated static func offersMorningAfter(fieldNight: Date?, lastNightBegun: Date, nightIsOver: Bool, journaled: Bool, calendar: Calendar) -> Bool {
        guard let fieldNight, nightIsOver, !journaled else { return false }
        return calendar.isDate(fieldNight,inSameDayAs:lastNightBegun)
    }
}
/// The button that opens the journal editor prefilled with a night.
struct KeepThisNightButton: View {
    @Environment(\.nyx) private var palette
    let prefill: JournalPrefill
    var prominent=true
    @State private var editing: JournalPrefill?
    var body: some View {
        Button { editing=prefill } label:{
            Label("Keep this night",systemImage:"book.closed").font(.headline).padding(.horizontal,10).frame(minHeight:44)
        }
        .modifier(KeepButtonStyle(prominent:prominent))
        .accessibilityHint("Opens a journal entry for this night, with the park, the date and the score filled in.")
        .accessibilityInputLabels([Text("Keep this night"),Text("Journal")])
        .sheet(item:$editing) { prefill in
            NavigationStack { JournalEditorView(prefill:prefill) }.nyxPresentation()
        }
    }
}
private struct KeepButtonStyle: ViewModifier {
    @Environment(\.nyx) private var palette
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let prominent: Bool
    @ViewBuilder func body(content:Content)->some View {
        if !prominent || palette.nightVision || reduceTransparency || palette.highContrast { content.buttonStyle(.bordered).buttonBorderShape(.capsule) }
        else { content.buttonStyle(.glass).buttonBorderShape(.capsule) }
    }
}
/// On a park's page the morning after a night in field mode: "Keep this night", until the night
/// is in the journal or the next night begins. `-nyx-keep-night` shows it in DEBUG captures.
struct KeepThisNightOffer: View {
    @Environment(PlanModel.self) private var model
    @Environment(\.nyx) private var palette
    @Query private var entries: [JournalEntry]
    let park: Park
    init(park: Park) {
        self.park=park
        let id=park.id
        _entries=Query(filter:#Predicate<JournalEntry> { $0.parkID == id })
    }
    private var night: Night? {
        let now=DebugScenario.date ?? .now
        let last=park.lastNightBegun(at:now)
        let candidate=model.night(park,on:last)
        let journaled=entries.contains { park.calendar.isDate($0.date,inSameDayAs:last) }
        if DebugScenario.isEnabled("keep-night") { return journaled ? nil : candidate }
        return KeepThisNight.offersMorningAfter(fieldNight:KeepThisNight.fieldNight(park:park),lastNightBegun:last,
            nightIsOver:FieldNight.isOver(candidate.sky,at:now),journaled:journaled,calendar:park.calendar) ? candidate : nil
    }
    var body: some View {
        // Never offered when the journal could not open: the entry would be gone on the next launch.
        if !model.journalUnavailable, let night {
            VStack(spacing:6) {
                Text("You were here last night.").font(.subheadline).foregroundStyle(palette.muted).multilineTextAlignment(.center)
                KeepThisNightButton(prefill:JournalPrefill(night:night))
            }
        }
    }
}
#Preview("Keep this night") {
    let m=PlanModel()
    if let p=m.home { KeepThisNightButton(prefill:JournalPrefill(night:m.night(p))).padding().background(.black).environment(m).preferredColorScheme(.dark) }
}
#Preview("Add to Calendar") {
    let m=PlanModel()
    if let p=m.home { AddNightToCalendar(night:m.night(p)).padding().background(.black).environment(m).preferredColorScheme(.dark) }
}
