import Foundation

/// Cloud forecasts, smoke, park alerts and the aurora forecast on Vision Pro: the network requests this app makes, the
/// iPhone's own clients, hosts and pacing, each behind its own switch in Your privacy.
/// Clouds (`WeatherService`): all 63 parks' public viewing-spot coordinates in one request to
/// api.open-meteo.com (two, 50 and 13 parks), kept in this headset's Application Support so the
/// last forecast is there offline, asked for again only once six hours old; Haleakalā's summit
/// cloud layers (`SummitLayerService`) at most every twelve hours. Smoke (`ForecastDetailService`,
/// air only): the same coordinates to air-quality-api.open-meteo.com at most every twelve hours.
/// Park alerts (`ParkStore`): one request for all 63 park codes to developer.nps.gov at most every
/// six hours, with the iPhone's shared key, and none without one. Aurora (`AuroraService`): NOAA's
/// Kp forecast from services.swpc.noaa.gov, one global file at most every three hours. A refused request waits
/// (`HostBackoff`). With a switch off nothing is requested for it: cached clouds keep fading toward
/// the usual clouds, cached smoke is dropped, cached closures still stand, as on the iPhone.
extension VisionModel {
    /// The iPhone's shared NPS key, from this app's Info.plist (`Config/Nyx.xcconfig`); empty in a
    /// build without one, when park alerts are simply not asked for (`ParkStore.usable`).
    nonisolated static var npsKey: String { Bundle.main.object(forInfoDictionaryKey: "NPS_API_KEY") as? String ?? "" }
    /// Reads the cache, and with `network` (and each switch on) refreshes what is due.
    func refreshForecasts(network: Bool = true) async {
        #if DEBUG
        // Screenshot routes never touch the network: a fixed forecast (`-nyx-vision-clouds 60`),
        // or the cache alone when the date is pinned (`-nyx-date`).
        // No summit layers there: the fixture's cover is the cover every park counts.
        if let cover = VisionDebug.clouds { forecasts = Self.fixture(parks: parks, cover: cover, issued: now); return }
        #endif
        let live = VisionDebug.date == nil, asking = network && live && forecastsOn
        let fresh = await weather.forecasts(for: parks, network: asking, force: false)
        // Asked after the forecast, so layers fetched with it are never the older of the two
        // (the score sets aside layers more than twelve hours older than the forecast).
        let layers = await summits.layers(for: parks, network: asking)
        merge(fresh, layers: layers)
        // Smoke and the park update side by side: two other hosts, each paced on its own.
        let smokeOn = smokeOn, parks = parks, details = detailService, store = parkStore, key = Self.npsKey, auroraOn = auroraOn, kp = auroraService
        let smokeNetwork = network && live, alertsNetwork = network && live && alertsOn
        if !smokeOn { await details.forgetAir() }
        async let air = smokeOn ? details.details(for: parks, weather: false, smoke: smokeNetwork, force: false).compactMapValues(\.air) : [:]
        async let update = store.alerts(for: parks, key: key, network: alertsNetwork, force: false)
        async let outlook = auroraOn ? kp.outlook(network: network && live) : nil
        let (smoke, alertsUpdate, auroraOutlook) = await (air, update, outlook)
        take(alertsUpdate)
        // Switched off while the request was out: what arrived is not used.
        if self.auroraOn, auroraOutlook != aurora { aurora = auroraOutlook }
        // Switched off while the request was out: what arrived is not counted.
        merge([:], layers: [:], smoke: self.smokeOn ? smoke : [:])
    }
    /// The park update as the store has it: its alerts (only ever replaced by a newer update) and
    /// whether the Park Service is refusing requests.
    func take(_ update: AlertsUpdate) {
        if alertsBusy != update.busy { alertsBusy = update.busy }
        if let cache = update.cache, cache.updated > (alerts?.updated ?? .distantPast) { alerts = cache }
    }
    /// Takes in forecasts, summit layers and smoke newer than those held; true when anything changed
    /// (and so the night, the list and the nights ahead are being rescored). Only ever newer: a
    /// failed or switched-off request never takes a forecast away (smoke switched off is dropped by its switch).
    @discardableResult func merge(_ fresh: [String: Forecast], layers: [String: HourlySeries], smoke air: [String: HourlySeries] = [:]) -> Bool {
        var merged = forecasts, changed = false
        for park in parks {
            guard let forecast = fresh[park.id], forecast.updated > (merged[park.id]?.updated ?? .distantPast) else { continue }
            merged[park.id] = forecast; changed = true
        }
        if changed { forecasts = merged }
        var mergedLayers = summitLayers, layersChanged = false
        for (id, series) in layers where series.updated > (mergedLayers[id]?.updated ?? .distantPast) {
            mergedLayers[id] = series; layersChanged = true
        }
        if layersChanged { summitLayers = mergedLayers }
        var mergedSmoke = smoke, smokeChanged = false
        for (id, series) in air where series.updated > (mergedSmoke[id]?.updated ?? .distantPast) {
            mergedSmoke[id] = series; smokeChanged = true
        }
        if smokeChanged { smoke = mergedSmoke }
        return changed || layersChanged || smokeChanged
    }
    /// Asks while the window is open: at once, then every half hour (each park only once its
    /// forecast is six hours old, smoke twelve, alerts six, so in practice every six hours).
    func keepForecastsFresh() async {
        while !Task.isCancelled {
            await refreshForecasts()
            try? await Task.sleep(for: .seconds(1800))
        }
    }
    /// The newest forecast on this headset, for Your privacy.
    var lastForecast: Date? { forecasts.values.map(\.updated).max() }
    /// The newest smoke forecast on this headset, for Your privacy.
    var lastSmoke: Date? { smoke.values.map(\.updated).max() }
    /// The words under the score for a night's clouds, as the iPhone says them: nothing extra with
    /// a forecast but its average; "Early look: …" days ahead; "No cloud forecast yet. …" beyond.
    /// Over Haleakalā's summit, when its layers count, the iPhone's line on why only mid and high cloud.
    func cloudCaption(_ night: Night) -> String {
        Self.cloudCaption(night, forecastsOn: forecastsOn)
    }
    /// The same words from what the caller holds (Siri's answer reads the cache itself). Whether a
    /// night is beyond the forecast's reach ("not yet") or within it ("unavailable") comes with the
    /// night (`Night.beyondForecast`), as on the iPhone.
    nonisolated static func cloudCaption(_ night: Night, forecastsOn: Bool) -> String {
        let summit = night.upperCloudOnly ? String(localized: "The summit sits above most low cloud, so the score counts mid and high cloud only.") : ""
        switch night.basis {
        case .forecast:
            let cover = night.cloudCover.map { String(localized: "\(Int($0.rounded()))% average cover through true darkness.") } ?? ""
            let issued = night.forecastUpdated.map { String(localized: "Forecast as of \(night.park.timestamp($0))") } ?? ""
            return Sentences.join([cover, summit, issued])
        case .blended, .usual:
            let unavailable = !(night.basis == .usual && night.beyondForecast)
            let caption = night.basisCaption(typical: true) ?? ""
            let off = unavailable && !forecastsOn ? String(localized: "Cloud forecasts are off in Your privacy.") : ""
            return Sentences.join([caption, summit, off])
        }
    }

    /// What the window and the plaque in the sky say about what is computed, and about clouds.
    /// `inSky` also says what the skyline is: the real terrain, or illustrative.
    nonisolated static func honesty(_ plan: NightPlan, inSky: Bool = false) -> String {
        // The sky draws the real terrain where Nyx has it: said plainly, in place of "illustrative".
        if inSky, let real = Horizon.Table.shared.main(plan.park) {
            let place = real.spot ?? plan.park.shortName
            return Sentences.join([honesty(plan), String(localized: "The skyline is the real terrain around \(place), from elevation data.")])
        }
        let park = plan.park, night = park.dayLabel(plan.sky.evening)
        // Without forecast clouds, why: beyond the forecast's reach, or a forecast this night should
        // have but does not (switched off in Your privacy, never fetched): never "no forecast reaches" for that.
        if plan.night.basis == .usual, !plan.beyondForecast {
            return inSky ? String(localized: "Computed for \(park.shortName), \(night). Not a live view. Cloud forecast unavailable, so no clouds are shown, and the skyline is illustrative.")
                : String(localized: "Computed for \(park.shortName), \(night). Not a live view. Cloud forecast unavailable, so no clouds are shown.")
        }
        switch (plan.night.basis == .usual, inSky) {
        case (true, false): return String(localized: "Computed for \(park.shortName), \(night). Not a live view. No cloud forecast reaches this night, so no clouds are shown.")
        case (true, true): return String(localized: "Computed for \(park.shortName), \(night). Not a live view. No cloud forecast reaches this night, so no clouds are shown, and the skyline is illustrative.")
        case (false, false): return String(localized: "Computed for \(park.shortName), \(night). Not a live view. Clouds follow the hourly forecast; their shapes are illustrative.")
        case (false, true): return String(localized: "Computed for \(park.shortName), \(night). Not a live view. Clouds follow the hourly forecast; their shapes and the skyline are illustrative.")
        }
    }

    #if DEBUG
    /// A forecast of constant cover for every park, issued at `issued`: 16 days of hours from the
    /// day before, like the real one. DEBUG screenshots only.
    nonisolated static func fixture(parks: [Park], cover: Double, issued: Date) -> [String: Forecast] {
        let start = (issued.timeIntervalSince1970/3600).rounded(.down)*3600-86400
        let times = (0..<384).map { start+Double($0)*3600 }
        let forecast = Forecast(updated: issued, times: times, clouds: times.map { _ in cover })
        return Dictionary(uniqueKeysWithValues: parks.map { ($0.id, forecast) })
    }
    #endif
}
