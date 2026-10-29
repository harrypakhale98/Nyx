import Foundation

/// At dusk, worked out on this device: night vision from civil dusk to civil dawn (the Sun 6° down)
/// at the place the person plans from. Civil dusk rather than sunset: at sunset the sky is still
/// bright enough for a white screen to feel right, and eyes begin to adapt only as twilight deepens.
/// It is also the watch's rule (`WristSky`), and the iPhone hands the watch its chosen town or starting
/// park (`WatchContext.dusk`), so wrist and phone turn red at the same minute (while Near me has found
/// you, the phone follows where you are, which never leaves it).
nonisolated enum NightVisionSchedule {
    struct Plan: Equatable, Sendable {
        /// What night vision should be now.
        let on: Bool
        /// A turn by hand still holds, until `next`.
        let held: Bool
        /// The next dusk or dawn within a day; nil where none comes.
        let next: Date?
        /// No dusk or dawn within a day (the midnight Sun, polar night): At dusk changes nothing and
        /// night vision stays as it was set.
        var polar: Bool { next == nil }
    }
    /// How far ahead a dusk or dawn is looked for.
    static let horizon: TimeInterval = WristSky.dayAhead
    /// A hold this old has met a dusk or dawn wherever one comes (outside polar seasons they are at
    /// most about a day apart), so it is not searched further back than this.
    static let holdLimit: TimeInterval = 2*86_400

    /// The Sun alone decides, so any place stands in for the starting point: a park, a town, or where
    /// you are. The time zone plays no part in the Sun's altitude.
    static func place(latitude: Double, longitude: Double) -> Park { WristSky.place(latitude: latitude, longitude: longitude) }
    /// A chosen town or starting park as the watch is handed it (`WatchContext.dusk`): to a tenth of
    /// a degree, and read that way here too, so phone and wrist follow one Sun and turn together.
    static func startingPoint(latitude: Double, longitude: Double) -> [Double]? { WatchContext.duskPoint([latitude, longitude]) }

    /// What At dusk wants at `now`, given the switch as it stands (`current`) and when it was last
    /// turned by hand (`heldAt`). A turn by hand holds until the first dusk or dawn after it; where no
    /// dusk or dawn comes within a day, the switch stays as it is.
    static func plan(current: Bool, heldAt: Date?, at place: Park, now: Date) -> Plan {
        let next = WristSky.paletteChanges(at: place, from: now, to: now.addingTimeInterval(horizon)).first
        // A hold from the future (the clock was set back) or older than two days has lapsed.
        if let heldAt, heldAt.timeIntervalSince(now) <= 60, now.timeIntervalSince(heldAt) < holdLimit,
           WristSky.paletteChanges(at: place, from: heldAt, to: now).isEmpty {
            return Plan(on: current, held: true, next: next)
        }
        guard next != nil else { return Plan(on: current, held: false, next: nil) }
        return Plan(on: WristSky.isCivilNight(at: place, now), held: false, next: next)
    }
}

/// At dusk in the running app: reads the starting point from the model, writes the switch at the
/// moment, and never runs in the background (`RootView` calls it while a window is active).
@MainActor enum NightVisionDusk {
    /// The place At dusk follows and how to name it: where you are while "Near me" has found you
    /// (nil name), else the chosen town or the starting park.
    static func place(_ model: PlanModel) -> (park: Park, name: String?)? {
        if let lat = model.location.latitude, let lon = model.location.longitude {
            return (NightVisionSchedule.place(latitude: lat, longitude: lon), nil)
        }
        guard let point = startingPoint(model) else { return nil }
        return (NightVisionSchedule.place(latitude: point[0], longitude: point[1]), model.originName)
    }
    /// The chosen town or starting park, as At dusk reads it and the watch is handed it.
    static func startingPoint(_ model: PlanModel) -> [Double]? {
        model.origin.flatMap { NightVisionSchedule.startingPoint(latitude: $0.latitude, longitude: $0.longitude) }
    }
    /// At dusk's plan now, without changing anything; nil unless At dusk is chosen.
    static func plan(_ model: PlanModel, defaults: UserDefaults = SharedSettings.defaults, now: Date = .now) -> NightVisionSchedule.Plan? {
        guard NightVisionMode.current(defaults) == .dusk, let place = place(model) else { return nil }
        return NightVisionSchedule.plan(current: defaults.bool(forKey: NightLook.nightVisionKey), heldAt: NightVisionMode.heldAt(defaults), at: place.park, now: now)
    }
    /// Puts the switch where At dusk wants it. Returns the plan (nil unless At dusk is chosen) and
    /// whether the switch moved, so the caller can say so to VoiceOver.
    @discardableResult static func apply(_ model: PlanModel, defaults: UserDefaults = SharedSettings.defaults, now: Date = .now) -> (plan: NightVisionSchedule.Plan, changed: Bool)? {
        guard let plan = plan(model, defaults: defaults, now: now) else { return nil }
        if !plan.held, defaults.object(forKey: NightVisionMode.heldKey) != nil { defaults.removeObject(forKey: NightVisionMode.heldKey) }
        let current = defaults.bool(forKey: NightLook.nightVisionKey)
        // Field mode, a Stargazing Focus and an alarm's "Open sky" hold red themselves and put back
        // what they found when they end: dawn never turns it off under them.
        if plan.on != current, plan.on || !redHeldElsewhere(defaults, now: now) {
            defaults.set(plan.on, forKey: NightLook.nightVisionKey)
            return (plan, true)
        }
        return (plan, false)
    }
    /// The three choices, as Settings sets them. At dusk takes effect at once.
    static func choose(_ mode: NightVisionMode, model: PlanModel, defaults: UserDefaults = SharedSettings.defaults) {
        defaults.removeObject(forKey: NightVisionMode.heldKey)
        defaults.set(mode == .dusk, forKey: NightVisionMode.atDuskKey)
        if mode == .dusk { apply(model, defaults: defaults) } else { defaults.set(mode == .on, forKey: NightLook.nightVisionKey) }
    }
    private static func redHeldElsewhere(_ defaults: UserDefaults, now: Date) -> Bool {
        let openSky = (defaults.dictionary(forKey: OpenSkyPrior.key)?["at"] as? Double).map { abs(now.timeIntervalSince1970-$0) < OpenSkyPrior.lifetime } ?? false
        return openSky || FieldPresenter.isOpen(in: nil) || StargazingFocus.holdsNightVision(defaults)
    }
}
