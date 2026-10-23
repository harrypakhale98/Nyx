import Foundation

/// Keeps watch on the nights kept as going. Every run that publishes (Nyx opening, a background
/// refresh when iOS allows one) scores each night still ahead again from what Nyx has, says a clear
/// fall once in a local notification with the better choice when there is one, and keeps one
/// "time to leave" reminder for each night with a drive time. iOS decides when a background refresh
/// runs, so nothing here is promised to arrive at a given hour; the Tonight card says what Nyx knows
/// whenever it is opened. Only with reminders switched on, and only on this iPhone.
@MainActor enum GoingWatch {
    static let prefix="nyx-going-"
    /// The leave reminder comes this long before the time to leave.
    static let leaveWarning: TimeInterval=30*60
    /// The better choice for a night: the same place two nights either side (none already past),
    /// or a place within about 100 miles that same night.
    static func alternative(_ model: PlanModel, night: Night) -> GoingCheck.Alternative? {
        let park=night.park, tonight=model.tonight(park)
        let first=max(tonight,park.date(night.id,addingDays:-2))
        let sameplace=model.nights(park,from:first,count:5).filter { $0.id>=tonight && $0.id<=park.date(night.id,addingDays:2) }
        let nearby=model.places.compactMap { place -> (night:Night,meters:Double,closed:Bool)? in
            let meters=place.distanceMeters(latitude:park.latitude,longitude:park.longitude)
            guard place.id != park.id, meters<=GoingCheck.nearby else { return nil }
            return (model.night(place,on:night.id),meters,model.closure(place) != nil)
        }
        return GoingCheck.alternative(to:night,sameplace:sameplace,nearby:nearby)
    }
    static func check(_ model: PlanModel, now: Date = .now, center: any LocalNotificationCenter = SystemNotifications()) async {
        guard DebugScenario.screen == nil else { return }
        let store=GoingNights.shared
        store.prune(now:now)
        guard UserDefaults.standard.bool(forKey:"notificationsEnabled"), await center.authorized() else { return }
        var leaving=Set<String>()
        for going in store.nights {
            guard let park=model.park(going.parkID) else { continue }
            let night=model.night(park,on:going.night)
            guard !FieldNight.isOver(night.sky,at:now) else { continue }
            let closure=model.closure(park)
            if GoingCheck.announces(going,night:night) {
                let body=Sentences.join([GoingCheck.summary(going,night:night,alternative:alternative(model,night:night)),String(localized:"As of \(park.time(now)).")])
                let alert=NightReminder(id:"\(prefix)fall-\(going.id)-\(night.score.value)",parkID:park.id,
                                        title:String(localized:"\(park.dayLabel(night.id)) at \(park.shortName) has changed"),
                                        body:ClosureLine.first(body,closure:closure),fireDate:now.addingTimeInterval(5),timeZone:park.timeZone,night:park.isoDay(night.id))
                if (try? await center.add(alert)) != nil { store.announced(night.score.value,for:going) }
            }
            if let leave=LeaveBy.time(sky:night.sky,driveMinutes:going.driveMinutes), leave.addingTimeInterval(-leaveWarning)>now,
               let line=LeaveBy.line(park:park,sky:night.sky,driveMinutes:going.driveMinutes) {
                let id="\(prefix)leave-\(going.id)"
                let body=Sentences.join([line,String(localized:"Last score there: \(night.score.value), \(night.score.band.label).")])
                let reminder=NightReminder(id:id,parkID:park.id,title:String(localized:"Time to get ready for \(park.shortName)"),
                                           body:ClosureLine.first(body,closure:closure),fireDate:leave.addingTimeInterval(-leaveWarning),timeZone:park.timeZone,night:park.isoDay(night.id))
                if (try? await center.add(reminder)) != nil { leaving.insert(id) }
            }
        }
        // A leave reminder for a night no longer kept, or with its drive time removed, goes.
        let stale=await center.pendingIDs().filter { $0.hasPrefix(prefix+"leave-") && !leaving.contains($0) }
        if !stale.isEmpty { await center.remove(stale) }
    }
}
