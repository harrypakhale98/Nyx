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
/// A pending reminder as iOS holds it: what it says and when it fires.
nonisolated struct ScheduledReminder:Sendable,Equatable {
    let id:String
    let title:String
    let body:String
    let fireDate:Date?
}
nonisolated protocol LocalNotificationCenter:Sendable {
    func authorized() async -> Bool
    func request() async -> Bool
    func pendingIDs() async -> [String]
    func pendingReminders() async -> [ScheduledReminder]
    func deliveredIDs() async -> [String]
    func remove(_ ids:[String]) async
    func add(_ reminder:NightReminder) async throws
}
nonisolated struct SystemNotifications:LocalNotificationCenter {
    /// When a reminder fires, as the calendar trigger reads it: the park's wall clock in its zone.
    /// Gregorian components need their calendar attached, or a device set to another calendar reads
    /// 2026 as a different year. Seconds too: a reminder due "in a minute" rounded down to the minute
    /// could already be past.
    static func fireComponents(_ date:Date,in zone:TimeZone)->DateComponents {
        var calendar=Calendar(identifier:.gregorian);calendar.timeZone=zone
        var components=calendar.dateComponents([.year,.month,.day,.hour,.minute,.second],from:date);components.calendar=calendar;components.timeZone=zone
        return components
    }
    func authorized() async -> Bool { let settings=await UNUserNotificationCenter.current().notificationSettings();return settings.authorizationStatus == .authorized }
    func request() async -> Bool { (try? await UNUserNotificationCenter.current().requestAuthorization(options:[.alert,.sound])) ?? false }
    func pendingIDs() async -> [String] { await UNUserNotificationCenter.current().pendingNotificationRequests().map(\.identifier) }
    func pendingReminders() async -> [ScheduledReminder] {
        await UNUserNotificationCenter.current().pendingNotificationRequests().map { request in
            ScheduledReminder(id:request.identifier,title:request.content.title,body:request.content.body,
                              fireDate:(request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate())
        }
    }
    func deliveredIDs() async -> [String] { await UNUserNotificationCenter.current().deliveredNotifications().map(\.request.identifier) }
    func remove(_ ids:[String]) async { UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers:ids) }
    func add(_ reminder:NightReminder) async throws {
        guard UserDefaults.standard.bool(forKey:"notificationsEnabled") else { throw URLError(.cancelled) }
        let content=UNMutableNotificationContent();content.title=reminder.title;content.body=reminder.body;content.userInfo=reminder.userInfo;content.sound = .default
        // iOS 27: the reminder is about a park Siri knows, so "open this park" works from the notification.
        if #available(iOS 27.0,*) { content.appEntityIdentifiers=[EntityIdentifier(for:ParkEntity.self,identifier:reminder.parkID)] }
        let components=Self.fireComponents(reminder.fireDate,in:reminder.timeZone)
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
    /// The app's language when the pending reminders were written; nil before any was.
    var language:String? { defaults.string(forKey:"remindersLanguage") }
    func record(language:String) { defaults.set(language,forKey:"remindersLanguage") }
}
nonisolated struct NotificationScheduler {
    let center:any LocalNotificationCenter
    let ledger:ReminderLedger
    init(center:any LocalNotificationCenter=SystemNotifications(),ledger:ReminderLedger=ReminderLedger()) { self.center=center;self.ledger=ledger }
    func requestAuthorization() async -> Bool { await center.request() }
    /// Cancels every pending reminder. Cancelled ones were never seen, so they may be planned again later.
    func remove() async {
        let pending=await center.pendingIDs()
        let ours=Set(pending.filter{$0.hasPrefix("nyx-night-")})
        await center.remove(ours.sorted())
        // A going night's leave reminder goes with the switch too (`GoingWatch`); it is in no ledger.
        let going=pending.filter { $0.hasPrefix("nyx-going-") }
        if !going.isEmpty { await center.remove(going) }
        ledger.record(ledger.ids.subtracting(ours),now:.now)
    }
    /// A score reminder is planned only for a night at most this far ahead...
    static let horizon:TimeInterval=5*86400
    /// ...and only when its forecast will be at most this old when it fires: the age after which
    /// the app itself stops using a forecast. A background refresh brings later nights in range.
    static let maxForecastAge=Forecast.recentFor
    /// At most one score reminder per park in this many nights: the best of a run (`NightPlanner.better`).
    static let spacing=7
    /// Only full forecasts can trigger a 'pristine' reminder. No fabricated clouds.
    /// Reminders fire at 18:00 park time the evening before. When that moment has passed
    /// (tonight, or tomorrow opened late), they fire in a minute instead, as long as true
    /// darkness has not begun; a reminder already issued is never repeated.
    /// Meteor shower peaks join the same plan, budget, ledger and switch (with their own sub-switch).
    /// `details` are the saved parks' forecast details (the widget snapshot's), so a reminder can say
    /// when all three forecast models agree the night is clear. `closures` are the snapshot's (park id →
    /// closure as Nyx words it): a reminder for a closed park still fires, since the sky is as dark, but
    /// says the closure first, as the park page, the widget and Siri do.
    /// `pending`: reminders already scheduled; one keeps its night against a tie (`scorePlans`).
    func plans(nights:[Night],now:Date = .now,limit:Int=60,delivered:Set<String>=[],pending:Set<String>=[],showers:Bool=false,details:[String:ForecastDetail]=[:],
               closures:[String:String]=[:],table:SkyEvents = .shared)->[NightReminder] {
        let scored=scorePlans(nights:nights,now:now,delivered:delivered,pending:pending,details:details,closures:closures)
        let meteors=showers ? showerPlans(nights:nights,now:now,delivered:delivered,closures:closures,table:table) : []
        return (scored+meteors).sorted { ($0.fireDate,$0.id)<($1.fireDate,$1.id) }.prefix(max(0,min(60,limit))).map{$0}
    }
    private func scorePlans(nights:[Night],now:Date,delivered:Set<String>,pending:Set<String>,details:[String:ForecastDetail],closures:[String:String])->[NightReminder] {
        let candidates:[(night:Night,fire:Date)]=nights.compactMap { night in
            guard Self.worthAReminder(night), let updated=night.forecastUpdated,
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
            guard let (park,night)=Self.scoreReminder(id) else { continue }
            taken[park,default:[]].append(night)
        }
        let window=Double(Self.spacing)*86400-12*3600
        var plans:[NightReminder]=[]
        // Best first, ties broken as every best night is picked (`NightPlanner.better(_:_:closures:)`;
        // within one park a closure shifts every night alike); each pick holds its park for the spacing either side.
        var ranked=candidates.sorted { NightPlanner.better($0.night,$1.night,closures:closures) }
        // A pending reminder keeps its night against another at its park scoring the same: the tie's
        // finer terms (parts, models' spread) move with every forecast, and a reminder should not swap
        // nights each refresh. Only the slots one park's equal scores hold are reordered, so every other
        // pick stands as `better` ranks it; with nothing pending, the night every surface names.
        if !pending.isEmpty {
            let tied=Dictionary(grouping:ranked.indices) { "\(ranked[$0].night.park.id)|\(ranked[$0].night.score.value)" }
            for slots in tied.values where slots.count>1 {
                let held=slots.map { ranked[$0] }
                let kept=held.filter { pending.contains(Self.identifier(park:$0.night.park,night:$0.night.id)) }
                guard !kept.isEmpty, kept.count<held.count else { continue }
                for (slot,candidate) in zip(slots,kept+held.filter { !pending.contains(Self.identifier(park:$0.night.park,night:$0.night.id)) }) { ranked[slot]=candidate }
            }
        }
        for (night,fire) in ranked {
            let park=night.park
            let identifier=Self.identifier(park:park,night:night.id)
            guard !delivered.contains(identifier), !(taken[park.id] ?? []).contains(where:{ abs($0.timeIntervalSince(night.id))<window }) else { continue }
            taken[park.id,default:[]].append(night.id)
            let models=Self.agreement(night,detail:details[park.id],now:now)
            plans.append(NightReminder(id:identifier,parkID:park.id,title:Self.title(night),body:Self.body(night,models:models,closure:closures[park.id]),fireDate:fire,timeZone:park.timeZone,night:park.isoDay(night.id)))
        }
        return plans
    }
    /// How the three forecast models compare over the night's dark window, as the park page shows
    /// it: only beside a score that includes clouds, and not when only high cloud was forecast.
    static func agreement(_ night:Night,detail:ForecastDetail?,now:Date)->ModelAgreement? {
        guard let detail, night.score.hasForecast, !night.upperCloudOnly else { return nil }
        let window=night.sky.cloudWindow
        return detail.agreement(from:window.start,to:window.end,now:now)
    }
    /// True when all three models agree on a clear night (at most 15% cloud in the cloudiest).
    static func modelsClear(_ models:ModelAgreement?)->Bool { models.map { $0.band == .agree && $0.high<=15 } ?? false }
    /// "Pristine night at Joshua Tree, Friday": the news first, in the title.
    /// A night a score reminder can announce: Pristine, with a full cloud forecast and some true
    /// darkness. Tonight's double tap uses the same rule.
    static func worthAReminder(_ night:Night)->Bool { night.score.value>=ScoreBand.pristine.minimum && night.score.hasForecast && night.sky.darkHours>0 }
    static func title(_ night:Night)->String {
        var weekday=Date.FormatStyle.dateTime.weekday(.wide)
        weekday.timeZone=night.park.timeZone
        return String(localized:"\(night.score.band.label) night at \(night.park.shortName), \(night.id.formatted(weekday))")
    }
    /// "94 out of 100. Moon down. Check park alerts before you go." Never "94/100",
    /// which VoiceOver reads as "slash". A place the Park Service does not run has no park alerts to
    /// check: it says "closures and access" instead. With a closure in the last park update, the
    /// closure comes first in the app's words (`ClosureLine`) and stands in for the advice.
    static func body(_ night:Night,models:ModelAgreement?=nil,closure:String?=nil)->String {
        let why=reason(night,models:models)
        if let closure=closure?.trimmingCharacters(in:.whitespacesAndNewlines), !closure.isEmpty {
            return ClosureLine.first(String(localized:"\(night.score.value) out of 100. \(why)."),closure:closure)
        }
        guard night.park.nps != nil else { return String(localized:"\(night.score.value) out of 100. \(why). Check closures and access before you go.") }
        return String(localized:"\(night.score.value) out of 100. \(why). Check park alerts before you go.")
    }
    /// One thing that is true of this night and makes it dark, the most telling first; with it,
    /// when true, that all three forecast models are clear ("Moon down; all three
    /// forecast models clear").
    static func reason(_ night:Night,models:ModelAgreement?=nil)->String {
        let moon=moonReason(night)
        guard modelsClear(models) else { return moon ?? cloudReason(night) }
        guard let moon else { return String(localized:"All three forecast models clear") }
        return String(localized:"\(moon); all three forecast models clear")
    }
    /// The Moon's part, when it is the reason (out of the way for all of true darkness, or from a
    /// moonset inside it), in the words every glance uses (`MoonInDarkness.short`); nil when it is not.
    private static func moonReason(_ night:Night)->String? {
        switch night.sky.moonInDarkness {
        case .allFree, .negligible, .setsAt: night.sky.moonShort(park:night.park)
        case .noDarkness, .allUp, .risesAt, .partial: nil
        }
    }
    /// Without a Moon reason: a clear forecast, else the hours of true darkness.
    private static func cloudReason(_ night:Night)->String {
        if let clouds=night.cloudCover, clouds<=10 { return String(localized:"Forecast \(Int(clouds.rounded()))% cloud") }
        return String(localized:"About \(Int(night.sky.darkHours.rounded())) hours of true darkness")
    }
    /// A major shower's peak night at a saved park, when at least 20 an hour are expected at its
    /// best moment with the Moon down (`WhatsUp.Events.reminderShower`), whatever the score. One per
    /// night across all saved parks: an open park before a closed one (a closed road beats a higher
    /// rate, as on every best surface), then the highest rate. Skipped when the forecast for that night
    /// is mostly cloud. Fires at 16:00 park time that day, or in a minute when that has passed, as long
    /// as true darkness has not begun. A closed park's says the closure first. A night whose shower
    /// reminder was delivered gets no other, whichever park would now be picked (a closure since).
    func showerPlans(nights:[Night],now:Date,delivered:Set<String>,closures:[String:String]=[:],table:SkyEvents = .shared)->[NightReminder] {
        var best:[String:(night:Night,shower:SkyAlmanac.ShowerNight)]=[:]
        let told=Self.showerDays(delivered,nights:nights)
        for night in nights where night.sky.darkHours>0 && (night.cloudCover ?? 0)<70 {
            let day=night.park.isoDay(night.id)
            guard !told.contains(day), let shower=WhatsUp.Events(park:night.park,sky:night.sky,table:table).reminderShower else { continue }
            let open=closures[night.park.id] == nil
            if let held=best[day] {
                let heldOpen=closures[held.night.park.id] == nil
                guard open != heldOpen ? open : shower.hourlyRate>held.shower.hourlyRate else { continue }
            }
            best[day]=(night,shower)
        }
        return best.values.compactMap { night,shower in
            let park=night.park
            guard let afternoon=park.calendar.date(bySettingHour:16,minute:0,second:0,of:night.id), let darkStart=night.sky.darkStart, let moment=shower.best else { return nil }
            let fire=afternoon>now ? afternoon : now.addingTimeInterval(60)
            let identifier=Self.showerIdentifier(park:park,night:night.id)
            guard fire<darkStart, !delivered.contains(identifier) else { return nil }
            return NightReminder(id:identifier,parkID:park.id,title:String(localized:"\(shower.shower.localizedName) at \(park.shortName) tonight"),
                body:ClosureLine.first(String(localized:"\(WhatsUp.rateText(shower.hourlyRate).sentenceStart) \(WhatsUp.whenPhrase(moment,sky:night.sky,park:park)), Moon down. A rough guide. Check clouds and closures before you go."),closure:closures[park.id]),
                fireDate:fire,timeZone:park.timeZone,night:park.isoDay(night.id),whatsUp:true)
        }
    }
    /// The days (park-local, as `showerPlans` keys them) a shower reminder was delivered for: from
    /// the night it names among `nights`, else (a place no longer saved) its stamp, the place's local
    /// noon, read in the place's own time zone when `zone` knows it, since Hawaii's noon and Tonga's
    /// fall in the same UTC hours a day apart; a removed spot falls back to the UTC day, right from
    /// UTC−11 to UTC+12.
    static func showerDays(_ delivered:Set<String>,nights:[Night],zone:(String)->TimeZone? = Self.placeZone)->Set<String> {
        let shown=delivered.filter { $0.hasPrefix("nyx-night-") && $0.contains("-meteors-") }
        guard !shown.isEmpty else { return [] }
        let known=Dictionary(nights.map { (showerIdentifier(park:$0.park,night:$0.id),$0.park.isoDay($0.id)) },uniquingKeysWith:{ first,_ in first })
        return Set(shown.compactMap { id in
            if let day=known[id] { return day }
            let rest=id.dropFirst("nyx-night-".count)
            guard let marker=rest.range(of:"-meteors-"), let stamp=Double(rest[marker.upperBound...]) else { return nil }
            let place=String(rest[..<marker.lowerBound])
            var calendar=Calendar(identifier:.gregorian)
            calendar.timeZone=zone(place) ?? TimeZone(identifier:"UTC") ?? .gmt
            let parts=calendar.dateComponents([.year,.month,.day],from:Date(timeIntervalSince1970:stamp))
            return String(format:"%04d-%02d-%02d",parts.year ?? 2000,parts.month ?? 1,parts.day ?? 1)
        })
    }
    /// A place's time zone by id: a curated park, then a world catalogue place (both read once per process).
    static func placeZone(_ id:String)->TimeZone? {
        // A removed spot (`pin:`) is in neither, so the catalogue is never read for one.
        guard !id.hasPrefix(SavedSpots.prefix) else { return nil }
        return ((try? ParkData.load())?.first { $0.id==id } ?? (try? CatalogData.load())?.first { $0.id==id })?.timeZone
    }
    /// Whether a pending reminder no longer says what the plan says: its title or words changed
    /// (the score moved from 94 to 91, the Moon reason or the models' agreement changed, a closure
    /// appeared or cleared), or, for one
    /// set for a fixed evening, its moment did. A reminder due "in a minute" keeps its moment, since
    /// working that out again later would only push it back.
    static func needsRewrite(_ pending:ScheduledReminder,to plan:NightReminder,now:Date)->Bool {
        if pending.title != plan.title || pending.body != plan.body { return true }
        guard plan.fireDate>now.addingTimeInterval(60), let fire=pending.fireDate else { return false }
        // The trigger keeps whole seconds.
        return abs(fire.timeIntervalSince(plan.fireDate))>=1
    }
    static func identifier(park:Park,night:Date)->String { "nyx-night-\(park.id)-\(Int(night.timeIntervalSince1970))" }
    /// A score reminder's place and night, read back from its identifier: the stamp after the last dash,
    /// the place between the prefix and that dash, so a spot's id (`pin:` and a UUID, itself hyphenated)
    /// reads as whole as a park's. Nil for a shower reminder or anything else.
    static func scoreReminder(_ id:String)->(parkID:String,night:Date)? {
        let prefix="nyx-night-"
        guard id.hasPrefix(prefix), !id.contains("-meteors-"), let dash=id.lastIndex(of:"-") else { return nil }
        let start=id.index(id.startIndex,offsetBy:prefix.count)
        guard start<dash, let stamp=Double(id[id.index(after:dash)...]) else { return nil }
        return (String(id[start..<dash]),Date(timeIntervalSince1970:stamp))
    }
    /// Same prefix and trailing night stamp as score reminders, so the ledger and cancel paths treat both alike.
    static func showerIdentifier(park:Park,night:Date)->String { "nyx-night-\(park.id)-meteors-\(Int(night.timeIntervalSince1970))" }
    /// Replans reminders, off the main actor (planning works out What's up for every saved park's
    /// nights). A reminder already pending is left as scheduled while it still says what the plan
    /// says, so opening Nyx again never pushes it back; when the night's score or reason moved, it is
    /// written again under the same identifier, which replaces it (`needsRewrite`). One that no
    /// longer qualifies is cancelled and may be planned again later. The copy is written by rule,
    /// never by a model.
    /// Without permission nothing is added, but reminders that no longer qualify are still
    /// cancelled: iOS keeps pending ones while notifications are off and delivers them if they
    /// are turned back on.
    /// A reminder's words are in the app's language when it was planned (`language`, the app's own
    /// localization): after the language changes, every pending reminder is taken back and planned
    /// again in the new one, at the same moment. None of them was seen, so each stays plannable.
    /// `closures`: the widget snapshot's, so a reminder names the closure the park page shows.
    @concurrent func reschedule(nights:[Night],now:Date = .now,showers:Bool=false,details:[String:ForecastDetail]=[:],closures:[String:String]=[:],
                                language:String=PlaceNames.appLanguage) async {
        let allowed=await center.authorized()
        let scheduled=await center.pendingReminders()
        let pending=scheduled.map(\.id)
        var ours=Set(pending.filter{$0.hasPrefix("nyx-night-")})
        if let written=ledger.language, written != language, !ours.isEmpty {
            await center.remove(ours.sorted())
            ledger.record(ledger.ids.subtracting(ours),now:now)
            ours=[]
        }
        ledger.record(language:language)
        let issued=ledger.ids
        // Issued before and no longer pending: it was delivered, tapped or cleared.
        let finished=issued.subtracting(ours).union(await center.deliveredIDs())
        let available=max(0,64-pending.filter{!$0.hasPrefix("nyx-night-")}.count)
        let planned=plans(nights:nights,now:now,limit:available,delivered:finished,pending:ours,showers:showers,details:details,closures:closures)
        let plannedIDs=Set(planned.map(\.id))
        let cancelled=ours.subtracting(plannedIDs)
        await center.remove(cancelled.sorted())
        var added=ours.intersection(plannedIDs)
        let current=Dictionary(scheduled.map { ($0.id,$0) },uniquingKeysWith:{ first,_ in first })
        for plan in planned where allowed {
            // The same identifier replaces a pending reminder in place: the budget is unchanged.
            if ours.contains(plan.id) { guard let old=current[plan.id], Self.needsRewrite(old,to:plan,now:now) else { continue } }
            if (try? await center.add(plan)) != nil { added.insert(plan.id) }
        }
        // Read the ledger and the pending list again: reminders may have been switched off while
        // this ran, and a reminder cancelled that way was never seen, so it must stay plannable.
        let stillScheduled=Set(await center.pendingIDs()).union(await center.deliveredIDs())
        ledger.record(ledger.ids.subtracting(cancelled).union(added.intersection(stillScheduled)),now:now)
    }
}

/// Opens the night a reminder is about, and shows reminders while Nyx is open. Each main window
/// connects as it opens and again whenever it becomes active, and leaves as it closes: a tapped
/// reminder opens in the window used last that is still open.
@MainActor final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared=NotificationRouter()
    /// The windows' handlers, the one used last at the end.
    private var windows:[(id:UUID,open:(ReminderRoute)->Void)]=[]
    private var pending:ReminderRoute?
    func connect(_ id:UUID,_ handler:@escaping (ReminderRoute)->Void) {
        windows.removeAll { $0.id==id }
        windows.append((id,handler))
        if let pending { self.pending=nil; handler(pending) }
    }
    func disconnect(_ id:UUID) { windows.removeAll { $0.id==id } }
    func deliver(_ route:ReminderRoute) { if let open=windows.last?.open { open(route) } else { pending=route } }
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
