import Foundation

/// Cloud forecasts on Vision Pro: the only network requests this app makes (approved 2026-10-07).
/// The same client as the iPhone (`WeatherService`): all 63 parks' public viewing-spot coordinates
/// in one request to api.open-meteo.com (two, 50 and 13 parks), clouds only, kept in this
/// headset's Application Support so the last forecast is there offline. A park's forecast is asked
/// for again only once it is six hours old, however often the window asks; a refused request
/// waits (`HostBackoff`). Alongside it, Haleakalā's summit cloud layers (`SummitLayerService`):
/// one small request at most every twelve hours, so that park scores from mid and high cloud as
/// on the iPhone. With the switch off nothing is requested and the cached forecast keeps fading
/// toward the usual clouds, as on the iPhone.
extension VisionModel {
    /// Reads the cache, and with `network` (and the switch on) refreshes what is six hours old.
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
    }
    /// Takes in forecasts and summit layers newer than those held; true when anything changed
    /// (and so the night, the list and the nights ahead are being rescored). Only ever newer: a
    /// failed or switched-off request never takes a forecast away.
    @discardableResult func merge(_ fresh: [String: Forecast], layers: [String: HourlySeries]) -> Bool {
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
        return changed || layersChanged
    }
    /// Asks while the window is open: at once, then every half hour (each park only once its
    /// forecast is six hours old, so in practice every six hours).
    func keepForecastsFresh() async {
        while !Task.isCancelled {
            await refreshForecasts()
            try? await Task.sleep(for: .seconds(1800))
        }
    }
    /// The newest forecast on this headset, for Your privacy.
    var lastForecast: Date? { forecasts.values.map(\.updated).max() }
    /// True when a night without clouds simply lies beyond the forecast's reach (past its last
    /// hour, or ten days or more ahead), rather than having a forecast that could not be read or
    /// was switched off. The iPhone's rule (`NightPlanner.beyondForecast`).
    func beyondForecast(_ night: Night) -> Bool {
        NightPlanner.beyondForecast(night, forecast: forecasts[night.park.id], detail: VisionModel.detail(summitLayers[night.park.id]), now: now)
    }
    /// The words under the score for a night's clouds, as the iPhone says them: nothing extra with
    /// a forecast but its average; "Early look: …" days ahead; "No cloud forecast yet. …" beyond.
    /// Over Haleakalā's summit, when its layers count, the iPhone's line on why only mid and high cloud.
    func cloudCaption(_ night: Night) -> String {
        Self.cloudCaption(night, forecast: forecasts[night.park.id], detail: VisionModel.detail(summitLayers[night.park.id]), forecastsOn: forecastsOn, now: now)
    }
    /// The same words from what the caller holds (Siri's answer reads the cache itself). `detail`:
    /// a summit's layers, so a summit night past their reach reads "not yet", as on the iPhone.
    nonisolated static func cloudCaption(_ night: Night, forecast: Forecast?, detail: ForecastDetail? = nil, forecastsOn: Bool, now: Date) -> String {
        let summit = night.upperCloudOnly ? String(localized: "The summit sits above most low cloud, so the score counts mid and high cloud only.") : ""
        switch night.basis {
        case .forecast:
            let cover = night.cloudCover.map { String(localized: "\(Int($0.rounded()))% average cover through true darkness.") } ?? ""
            let issued = night.forecastUpdated.map { String(localized: "Forecast as of \(night.park.timestamp($0))") } ?? ""
            return [cover, summit, issued].filter { !$0.isEmpty }.joined(separator: " ")
        case .blended, .usual:
            let unavailable = !NightPlanner.beyondForecast(night, forecast: forecast, detail: detail, now: now)
            let caption = night.basisCaption(unavailable: unavailable, typical: true) ?? ""
            let off = unavailable && !forecastsOn ? String(localized: "Cloud forecasts are off in Your privacy.") : ""
            return [caption, summit, off].filter { !$0.isEmpty }.joined(separator: " ")
        }
    }

    /// What the window and the plaque in the sky say about what is computed, and about clouds.
    /// `inSky` also owns up to the plaque's illustrative skyline.
    nonisolated static func honesty(_ plan: NightPlan, inSky: Bool = false) -> String {
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
