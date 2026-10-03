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
        var components=calendar.dateComponents([.year,.month,.day,.hour,.minute],from:reminder.fireDate);components.timeZone=reminder.timeZone
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
    func plans(nights:[Night],now:Date = .now,limit:Int=60,delivered:Set<String>=[])->[NightReminder] {
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
            }.prefix(max(0,min(60,limit))).map{$0}
    }
    static func identifier(park:Park,night:Date)->String { "nyx-night-\(park.id)-\(Int(night.timeIntervalSince1970))" }
    /// Replans reminders. A reminder already pending is left exactly as scheduled, so opening
    /// Nyx again never pushes it back or replaces its title; one that no longer qualifies is
    /// cancelled and may be planned again later. `retitle` may offer a calmer title for a newly
    /// added reminder at a fixed time; reminders due within two minutes skip it, so a slow
    /// model can never push their trigger into the past.
    func reschedule(nights:[Night],now:Date = .now,retitle:(@Sendable (NightReminder) async -> String?)?=nil) async {
        guard await center.authorized() else { return }
        let pending=await center.pendingIDs()
        let ours=Set(pending.filter{$0.hasPrefix("nyx-night-")})
        let issued=ledger.ids
        // Issued before and no longer pending: it was delivered, tapped or cleared.
        let finished=issued.subtracting(ours).union(await center.deliveredIDs())
        let available=max(0,64-pending.filter{!$0.hasPrefix("nyx-night-")}.count)
        let planned=plans(nights:nights,now:now,limit:available,delivered:finished)
        let plannedIDs=Set(planned.map(\.id))
        let cancelled=ours.subtracting(plannedIDs)
        await center.remove(cancelled.sorted())
        var added=ours.intersection(plannedIDs)
        for plan in planned where !ours.contains(plan.id) {
            var reminder=plan
            if plan.fireDate>now.addingTimeInterval(120), let title=await retitle?(plan) {
                reminder=NightReminder(id:plan.id,parkID:plan.parkID,title:title,body:plan.body,fireDate:plan.fireDate,timeZone:plan.timeZone)
            }
            if (try? await center.add(reminder)) != nil { added.insert(plan.id) }
        }
        // Read the ledger again: reminders may have been switched off while this ran.
        ledger.record(ledger.ids.subtracting(cancelled).union(added),now:now)
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
