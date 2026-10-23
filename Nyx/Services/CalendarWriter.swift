import EventKit
import Foundation

/// Adds chosen nights to the person's calendar with iOS's write-only access: Nyx can add events and
/// can never read the calendar. Each night reads as the single "Add to Calendar" event does
/// (`CalendarDraft`). Since Nyx cannot see what is already there, it keeps the nights it has added
/// on this iPhone and does not add one twice.
@MainActor enum CalendarWriter {
    enum Outcome: Equatable { case added(Int), alreadyAdded, denied, failed }
    static let key="calendarAddedNights"
    static var undecided: Bool { EKEventStore.authorizationStatus(for:.event) == .notDetermined }
    /// "jotr-2026-11-06": a night as the ledger keeps it.
    static func id(_ night: Night) -> String { "\(night.park.id)-\(night.park.isoDay(night.id))" }
    static func added(_ defaults: UserDefaults = .standard) -> Set<String> { Set(defaults.stringArray(forKey:key) ?? []) }
    /// The nights not yet added, in order.
    static func fresh(_ nights: [Night], defaults: UserDefaults = .standard) -> [Night] {
        let done=added(defaults)
        return nights.filter { !done.contains(id($0)) }
    }
    static func add(_ nights: [Night], closure: String?, defaults: UserDefaults = .standard) async -> Outcome {
        let wanted=fresh(nights,defaults:defaults)
        guard !wanted.isEmpty else { return .alreadyAdded }
        let store=EKEventStore()
        guard (try? await store.requestWriteOnlyAccessToEvents()) == true else { return .denied }
        guard let calendar=store.defaultCalendarForNewEvents else { return .failed }
        var saved: [String]=[]
        for night in wanted {
            let draft=CalendarDraft(night:night,closure:closure), event=EKEvent(eventStore:store)
            event.title=draft.title; event.startDate=draft.start; event.endDate=draft.end; event.timeZone=draft.timeZone
            event.location=draft.location; event.notes=draft.notes; event.url=draft.url; event.calendar=calendar
            if (try? store.save(event,span:.thisEvent,commit:false)) != nil { saved.append(id(night)) }
        }
        guard !saved.isEmpty, (try? store.commit()) != nil else { return .failed }
        defaults.set(Array(added(defaults).union(saved)).sorted(),forKey:key)
        return .added(saved.count)
    }
}
