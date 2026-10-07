import AppIntents
import Foundation
import UserNotifications

nonisolated struct NightReminder:Sendable {
    let id:String
    let parkID:String
    let title:String
    let body:String
    let fireDate:Date
    let timeZone:TimeZone
    /// The night it is about, as the park's local date ("2026-10-09"), so a tap opens that night.
    var night:String?=nil
    /// A shower reminder opens the night at What's up.
    var whatsUp=false
    var userInfo:[String:String] {
        var info=["parkID":parkID]
        if let night { info["night"]=night }
        if whatsUp { info["whatsUp"]="1" }
        return info
    }
}
/// Where a tapped reminder leads: the park, at the night it announced.
nonisolated struct ReminderRoute:Sendable,Equatable {
    let parkID:String
    let day:TripDay?
    let whatsUp:Bool
    init(parkID:String,day:TripDay?=nil,whatsUp:Bool=false) { self.parkID=parkID; self.day=day; self.whatsUp=whatsUp }
    init?(userInfo:[AnyHashable:Any]) {
        guard let parkID=userInfo["parkID"] as? String else { return nil }
        self.init(parkID:parkID,day:(userInfo["night"] as? String).flatMap(TripDay.init(iso:)),whatsUp:userInfo["whatsUp"] as? String == "1")
    }
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
        let content=UNMutableNotificationContent();content.title=reminder.title;content.body=reminder.body;content.userInfo=reminder.userInfo;content.sound = .default
        // iOS 27: the reminder is about a park Siri knows, so "open this park" works from the notification.
        if #available(iOS 27.0,*) { content.appEntityIdentifiers=[EntityIdentifier(for:ParkEntity.self,identifier:reminder.parkID)] }
        var calendar=Calendar(identifier:.gregorian);calendar.timeZone=reminder.timeZone
        // Gregorian components need their calendar attached, or a device set to another calendar reads 2026 as a different year.
        // Seconds too: a reminder due "in a minute" rounded down to the minute could already be past.
        var components=calendar.dateComponents([.year,.month,.day,.hour,.minute,.second],from:reminder.fireDate);components.calendar=calendar;components.timeZone=reminder.timeZone
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
    /// A score reminder is planned only for a night at most this far ahead...
    static let horizon:TimeInterval=5*86400
    /// ...and only when its forecast will be at most this old when it fires: the age after which
    /// the app itself stops using a forecast. A background refresh brings later nights in range.
    static let maxForecastAge:TimeInterval=36*3600
    /// At most one score reminder per park in this many nights: the best of a run, the earliest on a tie.
    static let spacing=7
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
        let candidates:[(night:Night,fire:Date)]=nights.compactMap { night in
            guard night.score.value>=90, night.score.hasForecast, night.sky.darkHours>0, let updated=night.forecastUpdated,
                  night.id.timeIntervalSince(now)<=Self.horizon else { return nil }
            let park=night.park
            let previous=park.date(night.id,addingDays:-1)
            guard let evening=park.calendar.date(bySettingHour:18,minute:0,second:0,of:previous) else { return nil }
            let soon=now.addingTimeInterval(60), deadline=night.sky.darkStart ?? night.sky.sunset ?? night.id.addingTimeInterval(6*3600)
            let fire=evening>now ? evening : soon
            guard fire<deadline, fire.timeIntervalSince(updated)<=Self.maxForecastAge else { return nil }
            return (night,fire)
        }
        // Nights already announced hold their park for the spacing either side.
        var taken:[String:[Date]]=[:]
        for id in delivered {
            let parts=id.split(separator:"-")
            guard parts.count==4, let stamp=Double(parts[3]) else { continue }
            taken[String(parts[2]),default:[]].append(Date(timeIntervalSince1970:stamp))
        }
        let window=Double(Self.spacing)*86400-12*3600
        var plans:[NightReminder]=[]
        // Best first, the earliest on a tie; each pick holds its park for the spacing either side.
        let ranked=candidates.sorted { a,b in a.night.score.value != b.night.score.value ? a.night.score.value>b.night.score.value : a.night.id<b.night.id }
        for (night,fire) in ranked {
            let park=night.park
            let identifier=Self.identifier(park:park,night:night.id)
            guard !delivered.contains(identifier), !(taken[park.id] ?? []).contains(where:{ abs($0.timeIntervalSince(night.id))<window }) else { continue }
            taken[park.id,default:[]].append(night.id)
            plans.append(NightReminder(id:identifier,parkID:park.id,title:Self.title(night),body:Self.body(night),fireDate:fire,timeZone:park.timeZone,night:park.isoDay(night.id)))
        }
        return plans
    }
    /// "Pristine night at Joshua Tree, Friday": the news first, in the title.
    static func title(_ night:Night)->String {
        var weekday=Date.FormatStyle.dateTime.weekday(.wide)
        weekday.timeZone=night.park.timeZone
        return String(localized:"\(night.score.band.label) night at \(night.park.shortName), \(night.id.formatted(weekday))")
    }
    /// "94 out of 100. Moon down all night. Check park alerts before you go." Never "94/100",
    /// which VoiceOver reads as "slash".
    static func body(_ night:Night)->String {
        String(localized:"\(night.score.value) out of 100. \(reason(night)). Check park alerts before you go.")
    }
    /// One thing that is true of this night and makes it dark, the most telling first.
    static func reason(_ night:Night)->String {
        let sky=night.sky
        if sky.moonBelowFraction>=0.99 { return String(localized:"Moon down all night") }
        if sky.moon.illumination<0.05 { return String(localized:"Almost no moonlight") }
        if let set=sky.moonset, let start=sky.darkStart, let end=sky.darkEnd, set>start, set<end, sky.moonrise.map({ $0<start || $0>end }) ?? true {
            return String(localized:"Moon sets at \(night.park.time(set))")
        }
        if let clouds=night.cloudCover, clouds<=10 { return String(localized:"Forecast \(Int(clouds.rounded()))% cloud") }
        return String(localized:"About \(Int(sky.darkHours.rounded())) hours of true darkness")
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
            return NightReminder(id:identifier,parkID:park.id,title:String(localized:"\(shower.shower.localizedName) at \(park.shortName) tonight"),
                body:String(localized:"\(WhatsUp.rateText(shower.hourlyRate).sentenceStart) \(WhatsUp.whenPhrase(moment,sky:night.sky,park:park)), Moon down. A rough guide; check clouds and park alerts."),
                fireDate:fire,timeZone:park.timeZone,night:park.isoDay(night.id),whatsUp:true)
        }
    }
    static func identifier(park:Park,night:Date)->String { "nyx-night-\(park.id)-\(Int(night.timeIntervalSince1970))" }
    /// Same prefix and trailing night stamp as score reminders, so the ledger and cancel paths treat both alike.
    static func showerIdentifier(park:Park,night:Date)->String { "nyx-night-\(park.id)-meteors-\(Int(night.timeIntervalSince1970))" }
    /// Replans reminders, off the main actor (planning works out What's up for every saved park's
    /// nights). A reminder already pending is left exactly as scheduled, so opening Nyx again never
    /// pushes it back or replaces its title; one that no longer qualifies is cancelled and may be
    /// planned again later. The copy is written by rule, never by a model.
    /// Without permission nothing is added, but reminders that no longer qualify are still
    /// cancelled: iOS keeps pending ones while notifications are off and delivers them if they
    /// are turned back on.
    @concurrent func reschedule(nights:[Night],now:Date = .now,showers:Bool=false) async {
        let allowed=await center.authorized()
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
        for plan in planned where allowed && !ours.contains(plan.id) {
            if (try? await center.add(plan)) != nil { added.insert(plan.id) }
        }
        // Read the ledger and the pending list again: reminders may have been switched off while
        // this ran, and a reminder cancelled that way was never seen, so it must stay plannable.
        let stillScheduled=Set(await center.pendingIDs()).union(await center.deliveredIDs())
        ledger.record(ledger.ids.subtracting(cancelled).union(added.intersection(stillScheduled)),now:now)
    }
}

/// Opens the night a reminder is about, and shows reminders while Nyx is open.
@MainActor final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared=NotificationRouter()
    private var open:((ReminderRoute)->Void)?
    private var pending:ReminderRoute?
    func connect(_ handler:@escaping (ReminderRoute)->Void) {
        open=handler
        if let pending { self.pending=nil; handler(pending) }
    }
    private func deliver(_ route:ReminderRoute) { if let open { open(route) } else { pending=route } }
    nonisolated func userNotificationCenter(_ center:UNUserNotificationCenter,didReceive response:UNNotificationResponse) async {
        guard let route=ReminderRoute(userInfo:response.notification.request.content.userInfo) else { return }
        await deliver(route)
    }
    nonisolated func userNotificationCenter(_ center:UNUserNotificationCenter,willPresent notification:UNNotification) async -> UNNotificationPresentationOptions {
        [.banner,.list,.sound]
    }
}

private extension String {
    /// "60–130 an hour" stays as is; "about 60 an hour" opens a sentence as "About 60 an hour".
    nonisolated var sentenceStart:String { prefix(1).uppercased()+dropFirst() }
}
