import SwiftUI

/// Your privacy on Vision Pro: what leaves the headset, the iPhone's four optional services (cloud
/// forecasts with Haleakalā's summit cloud layers, smoke and haze, park alerts, the aurora forecast), each with its
/// switch, and that nothing else does. Each switch is the preference the transport checks before
/// any connection (`SafeHTTP`), so off means no request at all.
struct YourPrivacyView: View {
    @Environment(VisionModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.visionPalette) private var palette
    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section {
                    Text("Nyx has no account, no ads, no tracking.").font(.system(.title3, design: .serif))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Only the four optional updates below leave this Apple Vision Pro, each with its own switch. Your location is never requested here, and nothing is measured or shared.")
                        .fixedSize(horizontal: false, vertical: true)
                }
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("What is sent").font(.subheadline.weight(.semibold))
                        Text("The public coordinates and park codes of the \(model.parks.count) national parks. Nothing about you.")
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
                    Toggle("Cloud forecasts (Open-Meteo)", isOn: $model.forecastsOn)
                        .accessibilityHint(Text("Shows each night's forecast clouds in the score and the sky"))
                    Text("Clouds only, from api.open-meteo.com: the forecast for all the parks at most every six hours while Nyx is open, and the cloud layers above Haleakalā's summit at most every twelve hours. The service receives network information such as your IP address.")
                        .font(.callout).foregroundStyle(palette.muted).fixedSize(horizontal: false, vertical: true)
                    Text(status).font(.callout).foregroundStyle(palette.muted).fixedSize(horizontal: false, vertical: true)
                    Toggle("Smoke and haze", isOn: $model.smokeOn)
                        .accessibilityHint(Text("Counts forecast smoke and haze in every score"))
                    Text("Requests go to air-quality-api.open-meteo.com, the same provider's air-quality service, for all \(model.parks.count) parks together, up to 50 in each request, using the same viewing-spot coordinates only. It returns the CAMS aerosol forecast that warns when smoke or haze will hide faint stars. The service receives network information such as your IP address.")
                        .font(.callout).foregroundStyle(palette.muted).fixedSize(horizontal: false, vertical: true)
                    Text(smokeStatus).font(.callout).foregroundStyle(palette.muted).fixedSize(horizontal: false, vertical: true)
                    Toggle("Park alerts", isOn: $model.alertsOn)
                        .accessibilityHint(Text("Shows park closures beside every score"))
                    Text("Alerts for all \(model.parks.count) U.S. national parks arrive in one request to developer.nps.gov, at most every six hours, so it never reveals which parks interest you. Your coordinates are never sent. The service receives network information such as your IP address.")
                        .font(.callout).foregroundStyle(palette.muted).fixedSize(horizontal: false, vertical: true)
                    Text(alertsStatus).font(.callout).foregroundStyle(palette.muted).fixedSize(horizontal: false, vertical: true)
                    Toggle("Aurora forecast", isOn: $model.auroraOn)
                        .accessibilityHint(Text("Shows when aurora may reach a park, in What's up"))
                    Text("Nyx asks services.swpc.noaa.gov, the U.S. Space Weather Prediction Center at NOAA, for its forecast of geomagnetic activity (the Kp index) for the next three days: one file for the whole world, at most every three hours. The request names no place and nothing about you. The service receives network information such as your IP address.")
                        .font(.callout).foregroundStyle(palette.muted).fixedSize(horizontal: false, vertical: true)
                } header: {
                    Text("Optional data updates")
                }
                Section {
                    Text("Turning forecasts off stops new requests. The last forecast stays on this device and counts less as it ages, then the park's usual clouds take over. Turning smoke and haze off removes the smoke forecast, and scores say smoke is not counted. Turning park alerts off stops new requests; closures already here stay beside the score. Turning the aurora forecast off removes it from this device. The Moon, the stars and every score still work offline.")
                        .font(.callout).foregroundStyle(palette.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
            .navigationTitle(Text("Your privacy"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .frame(minWidth: 560, minHeight: 600)
        // A sheet is its own presentation: it takes night vision's red here, as the window does.
        .saturation(palette.nightVision ? 0 : 1)
        .colorMultiply(palette.nightVision ? palette.red : .white)
        .background { if palette.nightVision { palette.nightPanel } }
    }
    /// When the last forecast arrived, in this headset's time.
    private var status: String {
        guard let last = model.lastForecast else { return String(localized: "No forecast on this device yet.") }
        return String(localized: "Last forecast: \(last.formatted(date: .abbreviated, time: .shortened)).")
    }
    private var smokeStatus: String {
        guard let last = model.lastSmoke else { return String(localized: "No smoke forecast on this device yet.") }
        return String(localized: "Last smoke forecast: \(last.formatted(date: .abbreviated, time: .shortened)).")
    }
    /// When the last park update arrived; without a key built in, that none is asked for.
    private var alertsStatus: String {
        if let last = model.alerts?.updated { return String(localized: "Last park update: \(last.formatted(date: .abbreviated, time: .shortened)).") }
        return ParkStore.usable(VisionModel.npsKey) ? String(localized: "No park update on this device yet.") : String(localized: "This copy of Nyx has no park service key, so park alerts are not requested.")
    }
}

#Preview("Your privacy") {
    YourPrivacyView().environment(VisionModel(now: .now))
}

#Preview("Your privacy, accessibility size") {
    YourPrivacyView().environment(VisionModel(now: .now)).dynamicTypeSize(.accessibility3)
}

#Preview("Your privacy, night vision") {
    YourPrivacyView().environment(VisionModel(now: .now)).environment(\.visionPalette, VisionPalette(nightVision: true))
}
