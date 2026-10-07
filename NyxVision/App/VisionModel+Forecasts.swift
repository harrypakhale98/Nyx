import Foundation

/// Cloud forecasts on Vision Pro: the one network request this app makes (approved 2026-10-07).
/// The same client as the iPhone (`WeatherService`): all 63 parks' public viewing-spot coordinates
/// in one request to api.open-meteo.com (two, 50 and 13 parks), clouds only, kept in this
/// headset's Application Support so the last forecast is there offline. A park's forecast is asked
/// for again only once it is six hours old, however often the window asks; a refused request
/// waits (`HostBackoff`). With the switch off nothing is requested and the cached forecast keeps
/// fading toward the usual clouds, as on the iPhone.
extension VisionModel {
    /// Reads the cache, and with `network` (and the switch on) refreshes what is six hours old.
    func refreshForecasts(network: Bool = true) async {
        #if DEBUG
        // Screenshot routes never touch the network: a fixed forecast (`-nyx-vision-clouds 60`),
        // or the cache alone when the date is pinned (`-nyx-date`).
        if let cover = VisionDebug.clouds { forecasts = Self.fixture(parks: parks, cover: cover, issued: now); return }
        #endif
        let live = VisionDebug.date == nil
        let fresh = await weather.forecasts(for: parks, network: network && live && forecastsOn, force: false)
        // Only ever newer: a failed or switched-off request never takes a forecast away.
        var merged = forecasts, changed = false
        for park in parks {
            guard let forecast = fresh[park.id], forecast.updated > (merged[park.id]?.updated ?? .distantPast) else { continue }
            merged[park.id] = forecast; changed = true
        }
        if changed { forecasts = merged }
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
    /// True when a night without clouds simply lies past the forecast's last hour (or about two
    /// weeks out when no forecast has arrived), rather than having a forecast that could not be
    /// read or was switched off. The iPhone's rule (`PlanModel.beyondForecast`).
    func beyondForecast(_ night: Night) -> Bool {
        guard night.basis == .usual else { return false }
        if let last = forecasts[night.park.id]?.times.last { return night.sky.cloudWindow.end.timeIntervalSince1970 > last+3600 }
        return night.id.timeIntervalSince(night.park.currentNight(at: now)) > 14*86400
    }
    /// The words under the score for a night's clouds, as the iPhone says them: nothing extra with
    /// a forecast but its average; "Early look: …" days ahead; "No cloud forecast yet. …" beyond.
    func cloudCaption(_ night: Night) -> String {
        switch night.basis {
        case .forecast:
            let cover = night.cloudCover.map { String(localized: "\(Int($0.rounded()))% average cover across the dark window.") } ?? ""
            let issued = night.forecastUpdated.map { String(localized: "Forecast as of \(night.park.timestamp($0))") } ?? ""
            return [cover, issued].filter { !$0.isEmpty }.joined(separator: " ")
        case .blended, .usual:
            let unavailable = !beyondForecast(night)
            let caption = night.basisCaption(unavailable: unavailable, typical: true) ?? ""
            return unavailable && !forecastsOn ? caption+" "+String(localized: "Cloud forecasts are off in Your privacy.") : caption
        }
    }

    /// What the window and the plaque in the sky say about what is computed, and about clouds.
    nonisolated static func honesty(_ plan: NightPlan) -> String {
        let park = plan.park, night = park.dayLabel(plan.sky.evening)
        return plan.night.basis == .usual
            ? String(localized: "Computed for \(park.shortName), \(night). Not a live view. No cloud forecast reaches this night, so no clouds are shown.")
            : String(localized: "Computed for \(park.shortName), \(night). Not a live view. Clouds follow the hourly forecast; their shapes are illustrative.")
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
