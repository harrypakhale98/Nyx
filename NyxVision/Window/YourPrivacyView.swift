import SwiftUI

/// Your privacy on Vision Pro: what leaves the headset (one optional request, the parks' cloud
/// forecast), its switch, and that nothing else does. The switch is the same preference the
/// transport checks before any connection (`SafeHTTP`), so off means no request at all.
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
                    Text("Nothing else leaves this Apple Vision Pro. Park alerts, smoke forecasts and your location are never requested here, and nothing is measured or shared.")
                        .fixedSize(horizontal: false, vertical: true)
                }
                Section {
                    Toggle("Cloud forecasts (Open-Meteo)", isOn: $model.forecastsOn)
                        .accessibilityHint(Text("Shows each night's forecast clouds in the score and the sky"))
                    VStack(alignment: .leading, spacing: 6) {
                        Text("What is sent").font(.subheadline.weight(.semibold))
                        Text("The public coordinates of the 63 national parks. Nothing about you.")
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
                    Text("One request to api.open-meteo.com for all the parks at once, at most every six hours while Nyx is open, for clouds only. The service receives network information such as your IP address.")
                        .font(.callout).foregroundStyle(palette.muted).fixedSize(horizontal: false, vertical: true)
                    Text(status).font(.callout).foregroundStyle(palette.muted).fixedSize(horizontal: false, vertical: true)
                } header: {
                    Text("Optional data update")
                }
                Section {
                    Text("Turning forecasts off stops new requests. The last forecast stays on this device and counts less as it ages, then the park's usual clouds take over. The Moon, the stars and every score still work offline.")
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
        .colorMultiply(palette.nightVision ? Color(red: 1, green: 0.27, blue: 0.23) : .white)
        .background { if palette.nightVision { palette.nightPanel } }
    }
    /// When the last forecast arrived, in this headset's time.
    private var status: String {
        guard let last = model.lastForecast else { return String(localized: "No forecast on this device yet.") }
        return String(localized: "Last forecast: \(last.formatted(date: .abbreviated, time: .shortened)).")
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
