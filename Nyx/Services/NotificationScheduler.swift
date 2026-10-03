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
nonisolated struct NotificationScheduler {
    let center:any LocalNotificationCenter
    init(center:any LocalNotificationCenter=SystemNotifications()) { self.center=center }
    func requestAuthorization() async -> Bool { await center.request() }
    func remove() async { await center.remove(await center.pendingIDs().filter{$0.hasPrefix("nyx-night-")}) }
    /// Only full forecasts can trigger a 'pristine' reminder. No fabricated clouds.
    /// Reminders fire at 18:00 park time the evening before. When that moment has passed
    /// (tonight, or tomorrow opened late), they fire in a minute instead, as long as true
    /// darkness has not begun; a reminder already delivered is never repeated.
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
                let identifier="nyx-night-\(park.id)-\(Int(night.id.timeIntervalSince1970))"
                guard !delivered.contains(identifier), seen.insert(identifier).inserted else { return nil }
                return NightReminder(id:identifier,parkID:park.id,title:String(localized:"A promising night at \(park.shortName)"),body:String(localized:"\(park.dayLabel(night.id)): \(night.score.value)/100, \(night.score.band.label). Forecasts can change. Confirm park access before traveling."),fireDate:fire,timeZone:park.timeZone)
            }.prefix(max(0,min(60,limit))).map{$0}
    }
    func reschedule(nights:[Night],now:Date = .now) async {
        guard await center.authorized() else { return }
        let pending=await center.pendingIDs()
        await center.remove(pending.filter{$0.hasPrefix("nyx-night-")})
        let available=max(0,64-pending.filter{!$0.hasPrefix("nyx-night-")}.count)
        let delivered=Set(await center.deliveredIDs())
        for plan in plans(nights:nights,now:now,limit:available,delivered:delivered) { try? await center.add(plan) }
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
