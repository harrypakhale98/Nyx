import Foundation

/// The offline caches (forecasts, forecast detail and park alerts for 63 parks, about 190 small
/// files), read on background threads from the first moment of launch, while the store opens and
/// the parks load on the main thread. The model takes them just before the first frame, so the
/// first screen shows exactly what it always did, and the services are seeded so no file is read twice.
nonisolated final class CachePreload: @unchecked Sendable {
    nonisolated struct Contents: Sendable {
        var forecasts: [String: Forecast]=[:]
        var details: [String: ForecastDetail]=[:]
        var alerts: ParkAlertsCache?
        /// The week ahead's astronomy at the parks within reach of the starting point: what the
        /// first screen (Tonight) draws, worked out on several threads instead of the main one.
        var conditions: [String: [Date: SkyConditions]]=[:]
        /// Tonight's real sky (`SkyProjection`) at the starting park and the parks in reach: the sky
        /// behind the first screen, built after the reads so the first frame does not build it on the
        /// main thread. Here only when they were done within the first frame's wait; `skies()` always has them.
        var skies: [SkyProjection.Sky]=[]
    }
    /// The reads the scores rest on: forecasts, forecast detail, alerts and the week's astronomy.
    private let group=DispatchGroup()
    /// The launch skies, built once `group` has finished: decoration, so the reads never wait on
    /// them (nor on the first load of the star catalogue).
    private let skyGroup=DispatchGroup()
    private let lock=NSLock()
    /// Written on the reading threads under `lock`, read only after `group` has finished.
    private var contents=Contents()
    /// Written under `lock` before `skyGroup` finishes, read only after it.
    private var builtSkies: [SkyProjection.Sky]=[]
    /// `lights`: a park's light sources for its sky's light domes (`SkyProjection.lightSources`).
    static func start(lights: @escaping @Sendable (Park) -> [SkyProjection.LightSource] = SkyProjection.noLight) -> CachePreload {
        let preload=CachePreload()
        preload.group.enter(); preload.skyGroup.enter()
        // The main thread waits on this at launch, so it runs at the waiting thread's own priority.
        DispatchQueue.global(qos: .userInteractive).async {
            let parks=preload.read()
            preload.group.leave()
            preload.buildSkies(parks, lights: lights)
            preload.skyGroup.leave()
        }
        return preload
    }
    /// The most skies built ahead: the starting park and the nearest parks in reach.
    static let skyLimit=16
    /// Reads the caches and works out the week's astronomy near the starting point; returns the parks read.
    private func read() -> [Park] {
        guard let parks=try? ParkData.load() else { return [] }
        DispatchQueue.concurrentPerform(iterations: parks.count) { index in
            let id=parks[index].id
            let forecast=CacheDirectory.read(Forecast.self, name: "weather-\(id)"), detail=CacheDirectory.read(ForecastDetail.self, name: "detail-\(id)")
            lock.withLock { contents.forecasts[id]=forecast; contents.details[id]=detail }
        }
        let alerts=ParkStore.stored(parks)
        lock.withLock { contents.alerts=alerts }
        let now=Date.now, engine=AstronomyEngine()
        let nights=Self.homeArea(parks).flatMap { park in (0..<7).map { (park, park.evening(park.date(park.currentNight(at: now), addingDays: $0))) } }
        DispatchQueue.concurrentPerform(iterations: nights.count) { index in
            let (park, evening)=nights[index], sky=engine.conditions(for: park, on: evening)
            lock.withLock { contents.conditions[park.id, default: [:]][evening]=sky }
        }
        return parks
    }
    /// Tonight's sky at the starting park (behind every screen) and at the parks in reach (behind
    /// Tonight's answer), from the conditions already worked out: the same sky `SkyProjection` builds.
    private func buildSkies(_ parks: [Park], lights: @Sendable (Park) -> [SkyProjection.LightSource]) {
        let skyParks=Self.skyParks(parks), now=Date.now
        let known=lock.withLock { contents.conditions }
        DispatchQueue.concurrentPerform(iterations: skyParks.count) { index in
            let park=skyParks[index], night=park.currentNight(at: now)
            let sky=SkyProjection.build(park: park, night: night, conditions: known[park.id]?[park.evening(night)], lights: lights(park))
            lock.withLock { builtSkies.append(sky) }
        }
    }
    /// The starting park, then the parks in reach nearest first, at most `skyLimit`.
    static func skyParks(_ parks: [Park], defaults: UserDefaults = .standard, locale: Locale = .current) -> [Park] {
        let home=parks.first { $0.id == (defaults.string(forKey: "homePark") ?? Park.defaultID) } ?? parks.first
        let area=homeArea(parks, defaults: defaults, locale: locale)
        let near=home.map { home in area.sorted { $0.distanceMeters(latitude: home.latitude, longitude: home.longitude)<$1.distanceMeters(latitude: home.latitude, longitude: home.longitude) } } ?? area
        var chosen:[Park]=home.map { [$0] } ?? []
        for park in near where chosen.count<skyLimit && !chosen.contains(where: { $0.id == park.id }) { chosen.append(park) }
        return chosen
    }
    /// The parks within the chosen radius of the starting point, as `PlanModel` reads them from
    /// the same settings (a place's coordinates, else the starting park's; the locale's standard
    /// reach unless chosen, `SearchRadius`).
    static func homeArea(_ parks: [Park], defaults: UserDefaults = .standard, locale: Locale = .current) -> [Park] {
        struct Place: Decodable { let latitude: Double; let longitude: Double }
        let place=defaults.data(forKey: "homePlace").flatMap { try? JSONDecoder().decode(Place.self, from: $0) }
        let home=parks.first { $0.id == (defaults.string(forKey: "homePark") ?? Park.defaultID) } ?? parks.first
        guard let latitude=place?.latitude ?? home?.latitude, let longitude=place?.longitude ?? home?.longitude else { return [] }
        let reach=SearchRadius.meters(defaults, locale: locale)
        return parks.filter { $0.distanceMeters(latitude: latitude, longitude: longitude)<=reach }
    }
    /// Waits for the reads to finish (they began at launch, so usually they already have).
    func wait() -> Contents {
        group.wait()
        return lock.withLock { contents }
    }
    /// Waits at most `timeout` seconds; nil if the reads are still going (a slow disk, a cold
    /// device), so the first frame never waits longer than that for them. The skies come along
    /// when they are done within the same `timeout`; otherwise `skies()` brings them later.
    func wait(timeout: Double) -> Contents? {
        let deadline=DispatchTime.now()+timeout
        guard group.wait(timeout: deadline) == .success else { return nil }
        let skiesDone=skyGroup.wait(timeout: deadline) == .success
        return lock.withLock {
            var taken=contents
            if skiesDone { taken.skies=builtSkies }
            return taken
        }
    }
    /// The launch skies once they are built, without holding any thread meanwhile.
    func skies() async -> [SkyProjection.Sky] {
        await withCheckedContinuation { continuation in
            skyGroup.notify(queue: .global(qos: .utility)) { continuation.resume(returning: self.lock.withLock { self.builtSkies }) }
        }
    }
    /// The reads' contents once they finish, without holding any thread meanwhile.
    func contents() async -> Contents {
        await withCheckedContinuation { continuation in
            group.notify(queue: .global(qos: .userInitiated)) { continuation.resume(returning: self.lock.withLock { self.contents }) }
        }
    }
}
