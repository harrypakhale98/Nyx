import Foundation

/// What Nyx on Vision Pro knows beside a park's score, and the words it says for what it does not.
/// The headset asks for smoke and park alerts as the iPhone does, each behind its own switch in
/// Your privacy; with a switch off, no key built in, or nothing arrived yet, the score says so, so
/// a score without smoke or closures never passes for the iPhone's. Pure (tested on the iPhone's
/// target); the access lines are the iPhone's own (`AlertRanking.summary`, `.unchecked`).
nonisolated struct ScoreInputs: Sendable, Equatable {
    /// "Smoke and haze" in Your privacy (`smokeEnabled`).
    var smokeOn = true
    /// Parks with an aerosol forecast on this device, of any age. Whether it counts is the night's
    /// (`Night.aerosol`): only a forecast that covers the night's dark window does.
    var smokeKnown: Set<String> = []
    /// "Park alerts" in Your privacy (`npsEnabled`).
    var alertsOn = true
    /// The last park update on this device, whichever switch: a known closure is never hidden.
    var alerts: ParkAlertsCache?
    /// The Park Service refused the last request, or is being left alone after one (`AlertsUpdate.busy`).
    var alertsBusy = false

    /// The closure beside the park's score, from the last park update.
    func closure(_ park: Park) -> String? { alerts?.closure(for: park) }
    /// True when no park update covers the park, so its closures are not known.
    func unchecked(_ park: Park) -> Bool { park.nps.map { alerts?.alerts[$0] == nil } ?? true }
    /// Why smoke is not in the night's score; nil when it is (`Night.aerosol`). A forecast that ends
    /// before the night (beyond its few days, or a cache left from a week offline) is said too, never
    /// passed off as clear air. Without the night (not scored yet), only whether any forecast is here.
    func smokeNote(_ park: Park, night: Night?) -> String? {
        if !smokeOn { return String(localized: "Smoke and haze are off in Your privacy, so smoke is not counted.") }
        guard smokeKnown.contains(park.id) else { return String(localized: "No smoke forecast on this device yet, so smoke is not counted.") }
        guard let night, night.aerosol == nil else { return nil }
        return String(localized: "No smoke forecast on this device reaches this night, so smoke is not counted.")
    }
    /// The line under the score when no closure stands beside it: what the last park update lists,
    /// or why there is none to read (switched off, no key, not fetched yet, or busy).
    func accessNote(_ park: Park) -> String? {
        if let code = park.nps, let listed = alerts?.alerts[code] { return AlertRanking.closure(listed) == nil ? AlertRanking.summary(listed, park: park) : nil }
        if alertsBusy { return AlertRanking.unchecked(busy: true) }
        if !alertsOn { return String(localized: "Park alerts are off in Your privacy, so closures are not checked.") }
        return AlertRanking.unchecked(busy: false)
    }
    /// What a short spoken row says after its score: the closure, or that closures are not
    /// checked, and that smoke is not counted.
    func spoken(_ park: Park, night: Night?) -> [String] {
        var parts: [String] = []
        if let closure = closure(park) { parts.append(Sentences.end(ClosureLine.spoken(closure))) }
        else if unchecked(park) { parts.append(String(localized: "Closures not checked.")) }
        if smokeNote(park, night: night) != nil { parts.append(String(localized: "Smoke not counted.")) }
        return parts
    }
    /// Once above a list of every park: what no score in it counts yet. Nil when smoke and the
    /// park update are both here (a closure then stands in its own row). `nights`: the rows' nights,
    /// by park id; when smoke is here but reaches none of them, that is said too.
    func listNote(_ parks: [Park], nights: [String: Night] = [:]) -> String? {
        var parts: [String] = []
        if !smokeOn { parts.append(String(localized: "Smoke and haze are off in Your privacy, so smoke is not counted.")) }
        else if !parks.contains(where: { smokeKnown.contains($0.id) }) { parts.append(String(localized: "No smoke forecast on this device yet, so smoke is not counted.")) }
        else if !nights.isEmpty, !parks.contains(where: { nights[$0.id]?.aerosol != nil }) { parts.append(String(localized: "No smoke forecast on this device reaches this night, so smoke is not counted.")) }
        if let first = parks.first(where: unchecked) { accessNote(first).map { parts.append($0) } }
        return parts.isEmpty ? nil : Sentences.join(parts)
    }
}
