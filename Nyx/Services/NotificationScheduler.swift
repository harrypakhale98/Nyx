import Foundation
import UserNotifications

nonisolated struct NightReminder:Sendable {
    let id:String
    let parkID:String
    let title:String
    let body:String
    let fireDate:Date
    let timeZone:TimeZone
}
nonisolated protocol LocalNotificationCenter:Sendable {
    func authorized() async -> Bool
    func request() async -> Bool
    func pendingIDs() async -> [String]
    func deliveredIDs() async -> [String]
    func remove(_ ids:[String]) async
    func add(_ reminder:NightReminder) async throws
}
nonisolated struct SystemNotifications:LocalNotificationCenter {
    func authorized() async -> Bool { let settings=await UNUserNotificationCenter.current().notificationSettings();return settings.authorizationStatus == .authorized }
    func request() async -> Bool { (try? await UNUserNotificationCenter.current().requestAuthorization(options:[.alert,.sound])) ?? false }
    func pendingIDs() async -> [String] { await UNUserNotificationCenter.current().pendingNotificationRequests().map(\.identifier) }
    func deliveredIDs() async -> [String] { await UNUserNotificationCenter.current().deliveredNotifications().map(\.request.identifier) }
    func remove(_ ids:[String]) async { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers:ids) }
    func add(_ reminder:NightReminder) async throws {
        guard UserDefaults.standard.bool(forKey:"notificationsEnabled") else { throw URLError(.cancelled) }
        let content=UNMutableNotificationContent();content.title=reminder.title;content.body=reminder.body;content.userInfo=["parkID":reminder.parkID];content.sound = .default
        var calendar=Calendar(identifier:.gregorian);calendar.timeZone=reminder.timeZone
        // Gregorian components need their calendar attached, or a device set to another calendar reads 2026 as a different year.
        var components=calendar.dateComponents([.year,.month,.day,.hour,.minute],from:reminder.fireDate);components.calendar=calendar;components.timeZone=reminder.timeZone
        let request=UNNotificationRequest(identifier:reminder.id,content:content,trigger:UNCalendarNotificationTrigger(dateMatching:components,repeats:false))
        try await UNUserNotificationCenter.current().add(request)
    }
}
/// Every reminder ID Nyx has handed to iOS. iOS forgets a notification once it is tapped or
/// cleared, so this ledger is what guarantees a night is announced at most once.
nonisolated struct ReminderLedger:Sendable {
    /// A suite name for tests; nil is the app's standard defaults.
    let suite:String?
    init(suite:String?=nil) { self.suite=suite }
    private var defaults:UserDefaults { suite.flatMap { UserDefaults(suiteName:$0) } ?? .standard }
    var ids:Set<String> { Set(defaults.stringArray(forKey:"issuedReminders") ?? []) }
    func record(_ issued:Set<String>,now:Date) {
        // Forget nights that ended more than two days ago; their IDs can never be planned again.
        let kept=issued.filter { id in
            guard let stamp=id.split(separator:"-").last.flatMap({ Double($0) }) else { return false }
            return stamp>now.timeIntervalSince1970-3*86400
        }
        defaults.set(Array(kept).sorted(),forKey:"issuedReminders")
    }
}
nonisolated struct NotificationScheduler {
    let center:any LocalNotificationCenter
    let ledger:ReminderLedger
    init(center:any LocalNotificationCenter=SystemNotifications(),ledger:ReminderLedger=ReminderLedger()) { self.center=center;self.ledger=ledger }
    func requestAuthorization() async -> Bool { await center.request() }
    /// Cancels every pending reminder. Cancelled ones were never seen, so they may be planned again later.
    func remove() async {
        let ours=Set(await center.pendingIDs().filter{$0.hasPrefix("nyx-night-")})
        await center.remove(ours.sorted())
        ledger.record(ledger.ids.subtracting(ours),now:.now)
    }
    /// Only full forecasts can trigger a 'pristine' reminder. No fabricated clouds.
    /// Reminders fire at 18:00 park time the evening before. When that moment has passed
    /// (tonight, or tomorrow opened late), they fire in a minute instead, as long as true
    /// darkness has not begun; a reminder already issued is never repeated.
    /// Meteor shower peaks join the same plan, budget, ledger and switch (with their own sub-switch).
    func plans(nights:[Night],now:Date = .now,limit:Int=60,delivered:Set<String>=[],showers:Bool=false,table:SkyEvents = .shared)->[NightReminder] {
        let scored=scorePlans(nights:nights,now:now,delivered:delivered)
        let meteors=showers ? showerPlans(nights:nights,now:now,delivered:delivered,table:table) : []
        return (scored+meteors).sorted { ($0.fireDate,$0.id)<($1.fireDate,$1.id) }.prefix(max(0,min(60,limit))).map{$0}
    }
    private func scorePlans(nights:[Night],now:Date,delivered:Set<String>)->[NightReminder] {
        var seen=Set<String>()
        return nights.filter { $0.score.value>=90 && $0.score.hasForecast && $0.sky.darkHours>0 }
            .sorted { $0.id<$1.id }.compactMap { night in
                let park=night.park
                let previous=park.date(night.id,addingDays:-1)
                guard let evening=park.calendar.date(bySettingHour:18,minute:0,second:0,of:previous) else { return nil }
                let soon=now.addingTimeInterval(60), deadline=night.sky.darkStart ?? night.sky.sunset ?? night.id.addingTimeInterval(6*3600)
                let fire=evening>now ? evening : soon
                guard fire<deadline else { return nil }
                let identifier=Self.identifier(park:park,night:night.id)
                guard !delivered.contains(identifier), seen.insert(identifier).inserted else { return nil }
                return NightReminder(id:identifier,parkID:park.id,title:String(localized:"A promising night at \(park.shortName)"),body:String(localized:"\(park.dayLabel(night.id)): \(night.score.value)/100, \(night.score.band.label). Forecasts can change. Confirm park access before traveling."),fireDate:fire,timeZone:park.timeZone)
            }
    }
    /// A major shower's peak night at a saved park, when at least 20 an hour are expected at its
    /// best moment with the Moon down (`WhatsUp.Events.reminderShower`), whatever the score. One per
    /// night across all saved parks: the park with the highest rate. Skipped when the forecast for
    /// that night is mostly cloud. Fires at 16:00 park time that day, or in a minute when that has
    /// passed, as long as true darkness has not begun.
    func showerPlans(nights:[Night],now:Date,delivered:Set<String>,table:SkyEvents = .shared)->[NightReminder] {
        var best:[String:(night:Night,shower:SkyAlmanac.ShowerNight)]=[:]
        for night in nights where night.sky.darkHours>0 && (night.cloudCover ?? 0)<70 {
            guard let shower=WhatsUp.Events(park:night.park,sky:night.sky,table:table).reminderShower else { continue }
            let day=night.park.isoDay(night.id)
            if shower.hourlyRate>(best[day]?.shower.hourlyRate ?? -1) { best[day]=(night,shower) }
        }
        return best.values.compactMap { night,shower in
            let park=night.park
            guard let afternoon=park.calendar.date(bySettingHour:16,minute:0,second:0,of:night.id), let darkStart=night.sky.darkStart, let moment=shower.best else { return nil }
            let fire=afternoon>now ? afternoon : now.addingTimeInterval(60)
            let identifier=Self.showerIdentifier(park:park,night:night.id)
            guard fire<darkStart, !delivered.contains(identifier) else { return nil }
            return NightReminder(id:identifier,parkID:park.id,title:String(localized:"\(shower.shower.name) peak tonight at \(park.shortName)"),
                body:String(localized:"About \(WhatsUp.rounded(rate:shower.hourlyRate)) an hour \(WhatsUp.whenPhrase(moment,sky:night.sky,park:park)), Moon down. A rough guide; check clouds and park access before you go."),
                fireDate:fire,timeZone:park.timeZone)
        }
    }
    static func identifier(park:Park,night:Date)->String { "nyx-night-\(park.id)-\(Int(night.timeIntervalSince1970))" }
    /// Same prefix and trailing night stamp as score reminders, so the ledger and cancel paths treat both alike.
    static func showerIdentifier(park:Park,night:Date)->String { "nyx-night-\(park.id)-meteors-\(Int(night.timeIntervalSince1970))" }
    /// Replans reminders. A reminder already pending is left exactly as scheduled, so opening
    /// Nyx again never pushes it back or replaces its title; one that no longer qualifies is
    /// cancelled and may be planned again later. `retitle` may offer a calmer title for a newly
    /// added reminder at a fixed time; reminders due within two minutes skip it, so a slow
    /// model can never push their trigger into the past.
    func reschedule(nights:[Night],now:Date = .now,showers:Bool=false,retitle:(@Sendable (NightReminder) async -> String?)?=nil) async {
        guard await center.authorized() else { return }
        let pending=await center.pendingIDs()
        let ours=Set(pending.filter{$0.hasPrefix("nyx-night-")})
        let issued=ledger.ids
        // Issued before and no longer pending: it was delivered, tapped or cleared.
        let finished=issued.subtracting(ours).union(await center.deliveredIDs())
        let available=max(0,64-pending.filter{!$0.hasPrefix("nyx-night-")}.count)
        let planned=plans(nights:nights,now:now,limit:available,delivered:finished,showers:showers)
        let plannedIDs=Set(planned.map(\.id))
        let cancelled=ours.subtracting(plannedIDs)
        await center.remove(cancelled.sorted())
        var added=ours.intersection(plannedIDs)
        for plan in planned where !ours.contains(plan.id) {
            var reminder=plan
            // Only score reminders may be retitled; a shower reminder's title names the shower.
            if plan.fireDate>now.addingTimeInterval(120), !plan.id.contains("-meteors-"), let title=await retitle?(plan) {
                reminder=NightReminder(id:plan.id,parkID:plan.parkID,title:title,body:plan.body,fireDate:plan.fireDate,timeZone:plan.timeZone)
            }
            if (try? await center.add(reminder)) != nil { added.insert(plan.id) }
        }
        // Read the ledger and the pending list again: reminders may have been switched off while
        // this ran, and a reminder cancelled that way was never seen, so it must stay plannable.
        let stillScheduled=Set(await center.pendingIDs()).union(await center.deliveredIDs())
        ledger.record(ledger.ids.subtracting(cancelled).union(added.intersection(stillScheduled)),now:now)
    }
}

/// Opens the park a reminder is about, and shows reminders while Nyx is open.
@MainActor final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared=NotificationRouter()
    private var open:((String)->Void)?
    private var pending:String?
    func connect(_ handler:@escaping (String)->Void) {
        open=handler
        if let pending { self.pending=nil; handler(pending) }
    }
    private func route(_ parkID:String) { if let open { open(parkID) } else { pending=parkID } }
    nonisolated func userNotificationCenter(_ center:UNUserNotificationCenter,didReceive response:UNNotificationResponse) async {
        guard let parkID=response.notification.request.content.userInfo["parkID"] as? String else { return }
        await route(parkID)
    }
    nonisolated func userNotificationCenter(_ center:UNUserNotificationCenter,willPresent notification:UNNotification) async -> UNNotificationPresentationOptions {
        [.banner,.list,.sound]
    }
}
