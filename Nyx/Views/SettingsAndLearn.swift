import SwiftUI

struct SettingsView:View {
    @Environment(\.nyx) private var palette
    @Environment(PlanModel.self) private var model
    @AppStorage("nightVision",store:SharedSettings.defaults) private var nightVision=false
    @AppStorage(NightTint.key,store:SharedSettings.defaults) private var brighterRed=false
    @AppStorage("notificationsEnabled") private var notifications=false
    @AppStorage("showerReminders") private var showerReminders=true
    @State private var explainNotifications=false
    @State private var permissionMessage:String?
    @State private var replay=false
    @Environment(\.scenePhase) private var scenePhase
    var body:some View {
        Form {
            Section("In the dark") {
                Toggle("Night vision",isOn:$nightVision).tint(palette.controlTint)
                Text("A red palette reduces glare. Lower the screen brightness too. The flashlight button at the top of each tab and the Control Center control switch it as well. Field mode, from a park's \"I'm here tonight\", turns it on and dims the screen while it is open, then puts both back.").font(.caption).foregroundStyle(palette.muted)
                Toggle(isOn:$brighterRed) {
                    VStack(alignment:.leading,spacing:4) {
                        Text("Brighter red")
                        Text("A slightly lighter red that keeps text clear for red-blind and green-blind eyes. Increase Contrast turns it on too.").font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
                    }
                }.tint(palette.controlTint)
            }.listRowBackground(palette.panel)
            Section("Reminders") {
                Toggle("Promising-night reminders",isOn:Binding(get:{notifications},set:{ value in if value { explainNotifications=true } else { notifications=false;Task { await NotificationScheduler().remove() } } })).tint(palette.controlTint)
                Text("Local reminders for saved parks with scores of 90 or higher. Forecasts may change. Upcoming nights are recalculated whenever Nyx opens.").font(.caption).foregroundStyle(palette.muted)
                if notifications {
                    Toggle("Meteor shower peaks",isOn:$showerReminders).tint(palette.controlTint)
                    Text("On the peak night of a major shower, when at least 20 an hour are expected at a saved park with the Moon down. At most one a night.").font(.caption).foregroundStyle(palette.muted)
                }
                if let permissionMessage { Text(permissionMessage).font(.caption) }
            }.listRowBackground(palette.panel)
            Section("Appearance") { NavigationLink("App icon") { AppIconPicker() } }.listRowBackground(palette.panel)
            Section("Accessibility") {
                NavigationLink("Sound and touch") { SoundAndTouchView() }
                Text("Hear a night as sound, feel the Moon's phase, and see how Nyx adapts to VoiceOver, Voice Control and your display settings.").font(.caption).foregroundStyle(palette.muted)
            }.listRowBackground(palette.panel)
            Section("Privacy and data") { NavigationLink("Your privacy") { PrivacyView() };NavigationLink("About the data") { AboutDataView() } }.listRowBackground(palette.panel)
            Section("About the sky") {
                NavigationLink { LearnView() } label:{
                    VStack(alignment:.leading,spacing:4) {
                        Text("Learn to look up")
                        Text("Short essays on the darkness score, the Milky Way and its photos, meteors, forecasts, staying safe and sharing the night.").font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
                    }.padding(.vertical,4)
                }
            }.listRowBackground(palette.panel)
            Section("Support") {
                if let url=SupportLink.privacyPolicy { Link(destination:url) { ExternalRow(title:"Privacy policy") }.accessibilityHint("Opens the policy in Safari.") }
                if let url=SupportLink.support { Link(destination:url) { ExternalRow(title:"Support and contact") }.accessibilityHint("Opens the support page in Safari.") }
                if let url=SupportLink.email { Link(destination:url) { ExternalRow(title:"Email the developer") }.accessibilityHint("Opens a new email in Mail.") }
                if let url=SupportLink.review { Link(destination:url) { ExternalRow(title:"Rate Nyx") }.accessibilityHint("Opens Nyx in the App Store.") }
                NavigationLink("Credits") { CreditsView() }
                NavigationLink("Diagnostics") { DiagnosticsView().nightForm() }
                Button("Replay the introduction") { replay=true }
                LabeledContent("Version",value:Self.version)
            }.listRowBackground(palette.panel)
        }.readableForm().nightForm().navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented:$explainNotifications) { RemindersExplainer { granted in
                notifications=granted; permissionMessage=granted ? nil : String(localized:"Reminders are off. You can enable them in iPhone Settings.")
            }.nyxPresentation() }
            .sheet(isPresented:$replay) { OnboardingView { replay=false }.nyxPresentation() }
            .task { await syncPermission() }
            .onChange(of:scenePhase) { _,phase in if phase == .active { Task { await syncPermission() } } }
    }
    /// "1.1 (8)": the version and build, from the bundle.
    static var version:String {
        let short=Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? ""
        let build=Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? ""
        return build.isEmpty ? short : "\(short) (\(build))"
    }
    /// If reminders were turned off in iPhone Settings, say so instead of showing a switch that lies.
    private func syncPermission() async {
        guard notifications, DebugScenario.screen == nil, !(await SystemNotifications().authorized()) else { return }
        notifications=false
        permissionMessage=String(localized:"Notifications for Nyx are off in iPhone Settings. Turn them on there, then switch reminders back on.")
    }
}
/// The in-context explainer before iOS asks about notifications: from Settings, and the first time
/// a park is saved. `decided` hears whether iOS allowed them.
struct RemindersExplainer:View {
    @Environment(\.dismiss) private var dismiss
    let decided:(Bool)->Void
    var body:some View {
        PermissionExplainer(symbol:"bell",title:"A night worth making time for",message:"Nyx can remind you about promising nights at saved parks. These notifications are scheduled on this iPhone. They are estimates, not confirmations of clear skies or access.",action:"Enable reminders") {
            dismiss()
            Task { decided(await NotificationScheduler().requestAuthorization()) }
        }
    }
}
/// Settings › Accessibility › Sound and touch: what the non-visual features do, each with a way to try it.
struct SoundAndTouchView:View {
    @Environment(\.nyx) private var palette
    @Environment(PlanModel.self) private var model
    @AppStorage(MoonHaptics.settingKey) private var moonHaptics=true
    private var listener:NightListener { .shared }
    var body:some View {
        Form {
            Section("Listen to a night") {
                Text("Under the shape of the night on a park's page, Nyx can play that night as twelve seconds of sound, from sunset to sunrise.")
                Text(NightSonification.key).foregroundStyle(palette.muted)
                if let park=model.home {
                    Button { if listener.isPlaying { listener.stop() } else { listener.play(NightSonification(park:park,sky:model.night(park).sky)) } } label:{
                        HStack(alignment:.firstTextBaseline,spacing:12) {
                            Image(systemName:listener.isPlaying ? "stop.fill" : "waveform").accessibilityHidden(true)
                            Text(listener.isPlaying ? String(localized:"Stop listening") : String(localized:"Play tonight at \(park.shortName)")).fixedSize(horizontal:false,vertical:true)
                        }.foregroundStyle(palette.accent).frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle())
                    }.accessibilityInputLabels([Text("Play"),Text("Listen"),Text("Stop")])
                }
                Text("It plays even when your iPhone is set to silent, because you asked for it, and other audio lowers while it plays. A transcript is always beside the button.").font(.caption).foregroundStyle(palette.muted)
            }.listRowBackground(palette.panel)
            Section("Feel the Moon") {
                if MoonHaptics.supported {
                    Toggle("Moon texture on the time river",isOn:$moonHaptics).tint(palette.controlTint)
                    Text("A new moon is a few sharp, sparse taps. As it fills, the taps soften over a broad hum, until a full moon is one wide swell. A waxing Moon swells across the pattern; a waning one fades. Each night's tick on the river is firmer and crisper as its score rises.").foregroundStyle(palette.muted)
                    if moonHaptics {
                        ForEach([(String(localized:"Feel a new moon"),0.0),(String(localized:"Feel a half moon"),0.5),(String(localized:"Feel a full moon"),1.0)],id:\.0) { title,lit in
                            Button(title) { MoonHaptics.shared.play(.moon(illumination:lit,waxing:true)) }.foregroundStyle(palette.accent)
                        }
                        // The whole night in the hand, at the starting park.
                        if let park=model.home { FeelTonightView(night:model.night(park)) }
                    }
                } else {
                    Text("This device has no Taptic Engine, so Nyx keeps its simple ticks. The Moon's phase is always written beside it.").foregroundStyle(palette.muted)
                }
            }.listRowBackground(palette.panel)
            Section("With VoiceOver") {
                Text("The time river, each calendar month and the shape of the night offer an audio graph: choose Audio Graph in the rotor to hear the nights rise and fall as a tone.")
                Text("VoiceOver rotors jump straight to what matters: Best nights and the best stretch in Plan, Closures and Pristine nights in Parks, Milestones in field mode. On the time river, actions go to the best night and feel the Moon.").foregroundStyle(palette.muted)
            }.listRowBackground(palette.panel)
            Section("Your display settings") {
                Text("With Differentiate Without Color, Excellent and Pristine nights are drawn as small stars, the river's best nights are marked with a triangle, moonlit hours are hatched and past nights are struck through.")
                Text("Reduce Highlighting Effects dims the glows, halos and the Milky Way and keeps the shooting star away. Prefer Cross-Fade Transitions replaces the zoom and the month slide in Plan. When iOS asks apps to use less, the sky holds still.").foregroundStyle(palette.muted)
            }.listRowBackground(palette.panel)
        }.readableForm().nightForm().navigationTitle("Sound and touch").navigationBarTitleDisplayMode(.inline)
            .onDisappear { listener.stop() }
    }
}
struct PrivacyView:View {
    @Environment(\.nyx) private var palette
    @Environment(PlanModel.self) private var model
    var body:some View {
        @Bindable var model=model
        Form {
            Section {
                Text("Nyx has no account, no ads, no tracking. Your journal never leaves this phone.").font(.system(.title3,design:.serif))
                Text("Saved parks and spots, journal entries and selected photos are stored on this iPhone. iCloud sync is not used. Your device backup settings may include app data.")
                // 2.0: saved spots are the one place of the person's own that a request carries.
                Text("The one place of yours that Nyx sends anywhere is a spot you save: only its position, rounded to about \(SpotForecast.roundingDistance()), for its cloud forecast. You can turn that off below.")
            }.listRowBackground(palette.panel)
            Section("Optional data updates") {
                Toggle("Cloud forecasts",isOn:$model.weatherEnabled).tint(palette.controlTint)
                Text("Requests go to api.open-meteo.com for all \(model.parks.count) U.S. national parks together, up to 50 in each request: clouds, three forecast models for comparison, cloud layers, temperature, dew point, wind, visibility, the chance of rain, the weather (such as fog or thunderstorms) and water vapour. They use the coordinates of each park's main viewing spot only, so they never reveal your location or which parks are near you. The service receives network information such as your IP address.").font(.caption).foregroundStyle(palette.muted)
                // Haleakalā scores from its summit's cloud layers, which may be asked for before any park page opens.
                Text("The cloud layers above Haleakalā's summit may also be asked for on their own, with that park's coordinates only: the same request in every copy of Nyx.").font(.caption).foregroundStyle(palette.muted)
                // The world catalogue: asked for by whole 10° squares, never one place.
                Text("The parks and dark-sky places beyond the U.S. national parks are never asked about one at a time. The world is divided into squares of 10° of latitude and longitude, and a request carries the public coordinates of every listed place in one square, at most 1,000; squares with only a few places are asked about together. The service can tell which part of the world interests you, a region about the size of a country, but never the place you look at or where you are.").font(.caption).foregroundStyle(palette.muted)
                // Saved spots: the one request that carries a place the person chose, so it says exactly what it sends.
                Toggle("Clouds at your saved spots",isOn:$model.spotForecastsEnabled).tint(palette.controlTint).disabled(!model.weatherEnabled)
                Text("For each spot you save, Nyx asks api.open-meteo.com for its clouds with the spot's coordinates rounded to 0.1°, about \(SpotForecast.roundingDistance()). The service learns roughly where your spots are, never the exact point and never their names. Spots are asked about in a request of their own, never mixed with the parks. Your current location is sent only if you save it as a spot. With this off, nothing is sent for spots: they keep their last forecast, then use their usual clouds. The service receives network information such as your IP address.").font(.caption).foregroundStyle(palette.muted)
                Toggle("Smoke and haze",isOn:$model.smokeEnabled).tint(palette.controlTint)
                Text("Requests go to air-quality-api.open-meteo.com, the same provider's air-quality service, for all \(model.parks.count) U.S. national parks together, up to 50 in each request, using the same viewing-spot coordinates only. Parks and dark-sky places elsewhere are asked about by the same whole squares as their clouds, once you have opened one of their pages. It returns the CAMS aerosol and dust forecast that warns when smoke, dust or haze will hide faint stars. Nothing is asked about smoke at saved spots. The service receives network information such as your IP address.").font(.caption).foregroundStyle(palette.muted)
                Toggle("Aurora forecast",isOn:$model.auroraEnabled).tint(palette.controlTint)
                Text("Nyx asks services.swpc.noaa.gov, the U.S. Space Weather Prediction Center at NOAA, for its forecast of geomagnetic activity (the Kp index) for the next three days: one file for the whole world, at most every three hours. The request names no place and nothing about you. The service receives network information such as your IP address.").font(.caption).foregroundStyle(palette.muted)
                Toggle("Park alerts and programs",isOn:$model.npsEnabled).tint(palette.controlTint)
                Text("Alerts for all \(model.parks.count) U.S. national parks arrive in one request to developer.nps.gov, at most every six hours, so it never reveals which parks are near you. Nothing is asked about any other place. Ranger programs are requested only for a park whose page you open. Campgrounds for all \(model.parks.count) parks arrive in one request, at most once a week, the first time a park's Where to stay appears; it names every park and nothing about you. Your coordinates are never sent. The service receives network information such as your IP address.").font(.caption).foregroundStyle(palette.muted)
            }.listRowBackground(palette.panel)
            Section { NPSKeyField();ForecastRequestsToday() } header:{ Text("Advanced") }.listRowBackground(palette.panel)
            Section("Measured on this iPhone") {
                Text("iOS reports how Nyx performs, including how bright its screen was, through MetricKit about once a day. Nyx keeps only the last screen brightness, to show here and in About the data. It is never sent anywhere.")
                if let reading=LuminanceProof.current { Text(reading.sentence) }
            }.listRowBackground(palette.panel)
            Section {
                Text("Turning updates off prevents new requests. Previously cached data remains available. Moon, twilight, Plan, saved parks and the journal work offline.")
                // Every use of location, as the purpose string iOS shows lists them.
                Text("Location is used only while you use Nyx: to measure distances, for From home tonight and a trip's starting point, to notice in the evening that you are at a U.S. national park, to point the sky to true north, and, only when you ask, to save where you stand as a spot. Where you are stays on this iPhone; a spot you save is sent only as its position, rounded to about \(SpotForecast.roundingDistance()).")
                Text("Photos are accessed only through the system photo picker. Reminders and alarms are local. In field mode, Nyx uses motion on this iPhone to point the sky where you hold it; nothing is recorded.")
                Text("Links open only when you tap them, in Safari, Maps, Mail or the App Store: nps.gov pages, Recreation.gov campground reservations, Globe at Night, Open-Meteo and the Creative Commons licence, a place's Wikidata page or official website, get-nyx.com, directions to a viewing spot or a saved spot, an email to the developer, and Nyx's App Store page. Nyx itself sends nothing to those sites.")
                Text("Adding a night to Calendar opens Calendar's own editor, where you choose and save it. Nyx never reads your calendars.")
            }.listRowBackground(palette.panel)
        }.readableForm().nightForm().navigationTitle("Your privacy").navigationBarTitleDisplayMode(.inline)
    }
}
struct AboutDataView:View {
    @Environment(\.nyx) private var palette
    @Environment(PlanModel.self) private var model
    var body:some View {
        ScrollView { VStack(alignment:.leading,spacing:24) {
            Text("An honest view of the sky").font(.system(.largeTitle,design:.serif))
            block("The score","Moonlight contributes 40%, clouds 25%, sky glow (estimated) 20%, and true darkness 15%. Moonlight follows the Moon's phase and its height through true darkness (Krisciunas and Schaefer, 1991), so a low crescent costs less than a high gibbous Moon. The four parts are added, then the weakest link caps the sum: clouds hold a night to 100 minus 0.9 points for each percent of cloud (overcast at most 10, half cloud 55); sky glow holds a Bortle 3 park to 89, Bortle 4 to 84, Bortle 5 to 74, Bortle 6 to 59 and brighter skies to 39, so only Bortle 2 or darker can read Pristine; heavy smoke or haze (aerosol optical depth 0.5 or more) holds a night to 59, and lighter smoke (0.25 to 0.5) to 74. No true darkness caps a night below 40, and that cap lifts gradually over the first three hours of true darkness. The breakdown names the cap that applies. When scores tie, parks with darker skies in NASA's satellite night lights come first, then longer true darkness.")
            // Shown only after iOS has delivered a real MetricKit report; nothing is estimated in its place.
            if let reading=LuminanceProof.current {
                VStack(alignment:.leading,spacing:10) {
                    Text("How dark Nyx keeps your screen").font(.system(.title2,design:.serif))
                    Text(reading.sentence).font(.body).lineSpacing(4).foregroundStyle(palette.ink)
                    Text("iOS measures the average brightness of the pixels Nyx draws (MetricKit's average pixel luminance: 0% is an all-black screen, 100% all white) and reports it about once a day. It is measured on this iPhone and never leaves it.").font(.body).lineSpacing(4).foregroundStyle(palette.muted)
                }.accessibilityElement(children:.combine)
            }
            block("Moon and twilight","Solar timing uses NOAA approximations. Moonrise and moonset use a low-precision Meeus-style position. Checked against the U.S. Naval Observatory, they agree to within a few minutes: a minute or less at the parks checked in Alaska, Hawaiʻi, American Samoa and the Virgin Islands, and under 4 minutes at mid-latitude parks. Sunrise, sunset and twilight agree to within a minute. Moon illumination corrects the mean 29.53-day cycle with the Moon's calculated position and is approximate. Terrain and atmospheric conditions can shift visible rise and set times. The Moon is drawn from NASA's lunar color map, lit from the Sun's real direction and tilted as it appears from the park at its highest point that night. Moon imagery: NASA's Scientific Visualization Studio (CGI Moon Kit); LRO LROC and LOLA teams.")
            block("Planets, the Milky Way and meteors","The Milky Way's bright center is taken as the direction of Sagittarius A*, counted as up once it is 10° clear of the horizon. Planets use Paul Schlyter's low-precision orbital elements and agree with a professional ephemeris to within about a degree from 2026 to 2032; brightness is given in words, because Mercury's can be off by more than half a magnitude. A planet is listed once it is 8° up in a sky dark enough for its brightness: civil twilight for Venus and Jupiter at their brightest, the Sun 9° down for planets brighter than magnitude 0, 12° down for the rest; Mercury fainter than magnitude 1.5 is left out. Rise, set and best times are found to within a minute of the model, but hills, trees and haze can shift what you see by a few minutes or more. Meteor showers come from the International Meteor Organization's 2026 Meteor Shower Calendar (IMO, edited by Jürgen Rendtel): dates, radiants and published peak rates. Nyx estimates an hourly rate for one observer from the radiant's height, the Moon and the park's estimated sky brightness, shown as a range: the upper figure is what a trained observer could count, and casual watchers see about half. It is a rough guide, and real showers vary from year to year. Lunar eclipse times: Eclipse Predictions by Fred Espenak, NASA's GSFC. Nyx checks the Moon's height at the park itself and names the deepest stage you can see, so a Moon that rises during the partial phase is shown, not hidden. Satellites are counted as sunlit while the Sun is less than about 23° below the horizon, for a 550 km orbit overhead. The faintest-star figure is an estimate from the park's Bortle class, moonlight, twilight and haze. Aurora notes come from how far a place lies from Earth's magnetic pole, traced along the magnetic field itself with the International Geomagnetic Reference Field (IGRF-14), and appear only on nights dark enough to see one. For the next three nights, NOAA's Space Weather Prediction Center forecasts geomagnetic activity as the Kp index (0 to 9): when the highest Kp during true darkness puts the aurora's usual edge nearest the equator, near 66° minus twice the Kp of magnetic latitude (Kp 5 near 56°), at or beyond a place, What's up says aurora is possible there. Kp forecasts a day or more ahead often miss, and aurora comes and goes within a night. Highlights are worked out the same way as the planets: the Moon within 4° of a planet or two planets within 3° (said to the nearest degree, never closer than about 1°, since the planets are placed within about a degree), a Full Moon nearer than 360,000 km, Mercury or Venus within three days of its greatest distance from the Sun, the solstices, and the gegenschein, a faint glow opposite the Sun, under Bortle 3 or darker skies with the Moon down, at least 35° up and 25° from the Milky Way. Checked against NASA JPL's Horizons for 2026 to 2028. None of this changes the score.")
            block("Forecasts","Open-Meteo forecasts cover up to 16 days. The U.S. national parks are asked for together, up to 50 in each request, and each request carries only the public coordinates of each park's main viewing spot; parks and dark-sky places elsewhere are asked for by whole regions, and saved spots in a request of their own. Clouds are averaged over the complete window of true darkness; on nights without it, over sunset to sunrise, or the four hours around the Sun's lowest point under the midnight sun. A forecast counts in full up to about three days ahead of a night. From there to ten days it is eased toward the park's usual clouds for the month, and these nights are marked as an early look; past ten days, or with no forecast, the usual clouds count alone. Where a place has no usual clouds for the month, an early look counts the forecast as it stands, and past ten days the score counts the Moon and darkness only. Where usual clouds are known, an old forecast is never dropped; it simply counts for less, so going offline cannot make a night look clearer than its clouds allow. A forecast with incomplete coverage of a night is not used. At Haleakalā, whose summit sits above the trade-wind inversion, the score counts mid and high cloud when that forecast is available. Open-Meteo's data is licensed under CC BY 4.0. Nyx changes it: each night's clouds are averaged over that night's true darkness and eased toward the usual clouds, as described here.") { openMeteoLink;licenseLink }
            block("How sure the forecast is","For the next seven days, Nyx also asks three independent forecast models (NOAA's GFS, ECMWF's IFS and DWD's ICON) for the same hours of true darkness. When their averages are within 15 points of cloud cover they agree; within 35 they roughly agree; beyond that they disagree, and the time river draws the range of scores they allow. The score itself uses Open-Meteo's best-match forecast; on a tie, closer model agreement ranks first. Cloud layers, the coldest hour, dew risk (air within 2 °C of its dew point) and the strongest gust come from the same seven-day forecast. So do rain and snow (named when some hour's chance reaches 25%), thunderstorms and fog (from the forecast's weather codes; fog in particular is hard to forecast, so it reads \"possible\"), and the water vapour above a place: under 10 kg/m², with no haze and a cloudless sky, the air is called very dry, which usually means faint stars stand out well. Visibility is a coarse model value and appears only as a haze hint. None of these change the score.")
            block("Usual clouds","Beyond the forecast, Nyx knows how cloudy each park's nights usually are in each month: ten years (2015 to 2024) of ERA5, a record of past weather rebuilt from observations, averaged over each night's true darkness at the park's coordinates. Nights without a forecast are scored with these usual clouds and say so (\"No cloud forecast yet\"), so a park whose winter nights are mostly overcast does not tie a desert and a night nobody can forecast is never treated as clear. They also say how often that month's nights are mostly clear (under 30% cloud). It is a long-term average, never a forecast. Contains modified Copernicus Climate Change Service information (2026), from ERA5, 2015 to 2024 (Hersbach et al. 2020; DOI 10.24381/cds.adbb2d47), read from its hourly time series (DOI 10.24381/1cf1ad76) and averaged over each night's true darkness by Nyx. Licensed under CC BY 4.0. Neither the European Commission nor ECMWF is responsible for any use that may be made of the Copernicus information or data it contains.") { licenseLink }
            block("Smoke and haze","Aerosol optical depth at 550 nm, from the CAMS global forecast (Copernicus Atmosphere Monitoring Service) through Open-Meteo's air-quality service, covers about five days. It is averaged over the hours of true darkness: below 0.1 is clear air, 0.1 to 0.25 light haze, 0.25 to 0.5 haze or smoke that makes the Milky Way look faint, and 0.5 or more heavy smoke or haze that hides faint stars. From 0.25 a caveat appears beside the score, and smoke caps it: at most 74 from 0.25, at most 59 from 0.5. When no smoke forecast reaches a night, nothing is capped. The same service's dust forecast tells dust from smoke: where at least 50 µg/m³ of dust outweighs all fine particles, the park's air details say dust instead of smoke. Air-quality data: Contains modified Copernicus Atmosphere Monitoring Service information (2026), through Open-Meteo, averaged over the night's true darkness by Nyx. Neither the European Commission nor ECMWF is responsible for any use that may be made of the Copernicus information or data it contains. You can switch this request off in Your privacy.") { openMeteoLink;licenseLink }
            block("Parks and sky glow","The bundled NPS inventory contains \(model.parks.count) national parks. Bortle classes are conservative estimates, not instrument measurements. Dark Sky designations are International Dark Sky Park certifications as of July 2026, cross-checked against the NPS list; a park certified later is not yet marked. Viewing coordinates are approximate, not directions. The sky drawings (Tonight's sky, the Bortle figure and the city comparison) show stars on a moonless night down to the faintest magnitude Bortle's 2001 scale gives each class, about 7.3 at class 2 and 4.5 at class 8; their faintest stars are placed for illustration, not from a catalogue. Park data: National Park Service.")
            block("Terrain at the viewing spots","For the U.S. national parks' viewing spots, Nyx knows the real terrain horizon: the ground's height and the highest land in every 5° of compass direction out to 100 km, seen from eye level, with Earth's curvature and normal refraction. It comes from the U.S. Geological Survey's 3D Elevation Program (bare earth, 1 arc-second), checked against Copernicus's WorldDEM, and a spot where the two disagreed is left out. Each spot shows its elevation and how high the land stands; the Milky Way core's line in What's up says when the terrain at the park's main viewing spot hides it, to the nearest ten minutes, and Vision Pro draws that terrain as its skyline. Trees, buildings and anything within 300 m are not included, so a forest edge can stand higher than shown. The score does not use the terrain.")
            block("Binocular sights","What's up names up to three deep-sky objects best placed that night, at least 30° up in true darkness, from a list of 44 naked-eye and binocular objects of both hemispheres: positions and magnitudes from Wikidata, checked against SIMBAD, the Harris globular cluster catalogue and the SEDS Messier pages. Faint galaxies and nebulae are offered only under a Bortle 4 sky or darker with the Moon down, and under a Moon more than a quarter lit only objects brighter than magnitude 4 (star clusters 5.5). \"Visible to the eye too\" follows the darkest sky class J. E. Bortle gave each object (class 4 where he named none), with the Moon down.")
            block("The Moon's names","The names of the Moon's seas and craters come from the IAU's Gazetteer of Planetary Nomenclature (USGS), placed on the drawn Moon by the same rotation that draws its map, so each name sits on its feature with the night's tilt and libration. Only features in sunlight are named, more of them on a larger Moon, and a name that would overlap another is left out.")
            block("After dark and busy months","For the U.S. national parks, the After dark panel lists what the National Park Service says about reaching the dark skies at night and through the year: gates and roads closed at night, seasonal road closures that cut off a viewing spot, and reservations that bear on arriving after dark. Each rule was read on its nps.gov page on October 15, 2026, with the sentence it rests on checked against the page, and links to that page. A rule usually in effect in the month of the night shown says so. These are usual patterns, not live road status: closures in force tonight come from the park's alerts. Busy and quiet months are the Park Service's recreation visits, averaged month by month over 2021 to 2025; counting changed at a few parks in those years, so only the pattern is shown.")
            block("Usual night temperatures","Past the seven days of hourly forecast detail, the night's temperatures are the month's usual ones: ERA5, a record of past weather rebuilt from observations, averaged hour by hour over 2015 to 2024. \"Before dawn\" is the coldest of the two hours before sunrise, a usual value about 1 to 3 °C warmer than the average nightly low, so Nyx never calls it the low. For the U.S. national parks it stands for the main viewing spot's own elevation, moved there at 6.5 °C a kilometre; elsewhere it comes from a world grid half a degree across. Checked against NOAA's 1991–2020 normals at 31 stations near parks, it agrees to about 1.4 °C on the same definition, but a valley floor can be 2 to 4 °C colder on clear winter nights than said. Clear nights, the ones worth going out on, are often several degrees colder than the usual night, and the app says so. Dew is mentioned when the air is usually within 2 °C of its dew point before dawn.")
            block("Measured night skies","For \(MeasuredSky.shared.parks.count) of the \(model.parks.count) parks, the park page also shows what the National Park Service's Night Skies Program measured on the ground: the brightness of the sky overhead, from the Park Service's calibrated all-sky camera, in magnitudes per square arcsecond (higher is darker; the darkest natural skies read about 22), with the observers' Bortle class where they gave one. Each night is the middle value of that night's sets of images. Most sites were measured on one night or a few, between 2001 and 2025 and mostly before 2013, and sky glow has grown since, so these readings are context beside the estimate, not part of the score. A viewing spot shows a reading when a measured site lies within 1 km of it. The data is the Park Service's public night-sky data map, a U.S. Government work in the public domain.")
            block("Night lights from space","Sky glow estimates use NASA Black Marble nighttime lights (VNP46A4, DOI 10.5067/VIIRS/VNP46A4.002; Román et al. 2018), public domain. Nyx adds the 2025 yearly satellite light within 300 km of each park and viewing spot, weakening with distance (Walker's law), and compares the result across the \(SkyGlow.shared.parks.count) parks. The same sum, split by direction, finds the light domes on the horizon; a town is named only when a known one lies near the light. It is a comparison between places, not a measurement of sky brightness: it models no terrain, haze or light color, cannot resolve a lit lodge next to a spot, and cannot tell the darkest skies apart. The satellite misses much of the blue light of white LEDs, so towns that switched to LEDs can look darker than they are. The score keeps the conservative Bortle estimate; the satellite view is context. Growth since 2013 is shown only as a comparison between parks, and not for Alaska, lava, oil-field flaring or almost unlit places, where the change is not light pollution.")
            block("Away from the parks","For a place that is not one of the U.S. national parks, such as your starting city, a spot you save or a park or dark-sky place in another country, Nyx reads two grids that come with the app. Sky brightness comes from the same 2025 NASA night lights, summed within 300 km of every point and checked against 77 published measurements from dark sites to city centres: typically within half a magnitude, closer in dark places. It is shown as an estimate with its Bortle class. Usual clouds come from the same ten years of ERA5, averaged over each month's night on a quarter-degree grid; how often nights are mostly clear is estimated from that average, so it reads \"about\". The U.S. national parks keep their own checked values. Contains modified Copernicus Climate Change Service information (2026), from ERA5, 2015 to 2024.")
            block("The nearest dark sky","When nothing is in reach, or the darkest place in reach has a suburban or brighter sky (Bortle 5 or more), Tonight points to the nearest land that the same sky-brightness grid puts at Bortle 4 or darker and at least two classes darker than what is in reach, within your radius or 500 miles (800 km), whichever is farther. It shows the darkest such stretch a little beyond the first one found, about 5 km inland by Natural Earth's coastline. It has no name and no score, and nobody has checked it for roads, access or safety. Saved as a spot, it gets nights like any other place.")
            // Credited only when the world catalogue is in this build.
            if Bundle.main.url(forResource:"catalog",withExtension:"json") != nil {
                block("Parks around the world","Beyond the U.S. national parks, the national parks and certified dark-sky places Nyx knows come from Wikidata, a free shared database, under CC0 (no rights reserved). A few certified dark-sky places missing there were added by hand, each checked against its own published source. Each place is one point for what is often a large area, so the sky can differ across it. Its Bortle class and usual clouds are estimates read from the grids described above, not measured there. Nyx has no closure alerts outside the U.S. national parks, so check the park's own site before you go. Forecasts are asked for by whole regions, every place in a 10° square (about 1,100 km from north to south), so a request never shows which place you are looking at.")
            }
            block("Step-free viewing","Step-free notes come from each park's accessibility pages on nps.gov, retrieved October 5, 2026. A spot is marked only where an official page says so, and each note shows the sentence it rests on and a link to the page, which opens in Safari. Spots without an official statement show nothing. Night access, gates and seasonal closures are not covered. Conditions change; check with the park.")
            block("Getting there","Access notes for parks a car cannot simply reach, by boat, plane or a limited road, come from each park's Getting there and directions pages on nps.gov, retrieved October 6, 2026. The trip planner leaves out parks reached only by boat or plane unless you include them. Schedules and seasons change; check with the park.")
            block("The maps","The land beneath your constellation and on the Parks map is simplified from Natural Earth's 1:50m land and lakes, which are in the public domain. It is decoration, drawn at a scale where small islands disappear. Whether a point lies in the United States, which decides a saved spot's nearest town and which places Tonight weighs, is read from the U.S. Census Bureau's cartographic boundary file of the nation (cb_2023_us_nation_20m), also in the public domain.")
            // Credited only when the starting-places list is in this build.
            if Bundle.main.url(forResource:"places",withExtension:"json") != nil {
                block("Starting points","The towns and cities you can start from come, in the United States, from the U.S. Census Bureau's 2025 Gazetteer Files (Places) and its Vintage 2025 population estimates, which are in the public domain, and everywhere else from GeoNames (geonames.org): every place of 15,000 people or more, under the Creative Commons Attribution 4.0 license (CC BY 4.0). Each place is a single point, not a boundary, and only straight-line distances are measured from it. A spot you save takes its time zone and region from the nearest of these places; near a border, that can be the neighbor's.") { licenseLink }
            }
            block("Access comes first","Nyx is a planning aid, not a guarantee. A score never confirms that a road or park is open. Park updates may be unavailable. Cached alerts and programs show their update time. Check with the park before traveling, especially when Nyx has not checked alerts.")
            block("Park-local time","Each park and place has an IANA time zone. A night runs from local noon to the following local noon, and \"tonight\" moves on to the coming evening once the Sun rises. Times shown on detail belong to that park, including changes for daylight saving time. The stars behind each screen are the real sky over that park in the middle of the night's darkness, from the Yale Bright Star Catalogue (Hoffleit and Warren, via NASA HEASARC); they show where the stars are, not whether clouds will hide them. Star names come from the IAU Working Group on Star Names (IAU WGSN); the constellation figures are drawn for Nyx between catalogue stars.")
            block("Independent","One independent developer makes Nyx. Nyx is not affiliated with or endorsed by the National Park Service, NASA or DarkSky International, and no organization credited here endorses it.")
        }.padding(24).readableColumn(WideLayout.proseWidth) }
        // `-nyx-scroll 0.5` (DEBUG) opens partway down, for review captures of the lower blocks.
        .defaultScrollAnchor(DebugScenario.number("-nyx-scroll").map { UnitPoint(x:0.5,y:$0) })
        .background(NightBackground(veil:0.6)).navigationTitle("About the data").navigationBarTitleDisplayMode(.inline)
    }
    private func block(_ title:LocalizedStringKey,_ content:LocalizedStringKey)->some View { block(title,content) { EmptyView() } }
    private func block<Links:View>(_ title:LocalizedStringKey,_ content:LocalizedStringKey,@ViewBuilder links:()->Links)->some View { VStack(alignment:.leading,spacing:10) { Text(title).font(.system(.title2,design:.serif)).accessibilityAddTraits(.isHeader);Text(content).font(.body).lineSpacing(4).textSelection(.enabled).foregroundStyle(palette.muted);links() } }
    /// Open-Meteo's licence asks for this exact credit as a link beside its data. Both open in Safari.
    @ViewBuilder private var openMeteoLink:some View { if let url=BrowserLink.openMeteo { sourceLink("Weather data by Open-Meteo.com",url) } }
    @ViewBuilder private var licenseLink:some View { if let url=BrowserLink.creativeCommonsBY { sourceLink("Creative Commons Attribution 4.0 (CC BY 4.0)",url) } }
    private func sourceLink(_ title:LocalizedStringKey,_ url:URL)->some View {
        Link(destination:url) { Label(title,systemImage:"safari").frame(maxWidth:.infinity,minHeight:44,alignment:.leading).contentShape(Rectangle()) }
            .font(.body.weight(.medium)).foregroundStyle(palette.accent).accessibilityHint(Text("Opens in Safari."))
    }
}
/// "About the data" as a row with a mark and a chevron, the same at the foot of Learn and of a park.
struct AboutDataLink:View {
    @Environment(\.nyx) private var palette
    var body:some View {
        NavigationLink { AboutDataView() } label:{
            HStack { Label("About the data",systemImage:"info.circle");Spacer();Image(systemName:"chevron.forward").font(.caption.weight(.semibold)).foregroundStyle(palette.muted).accessibilityHidden(true) }
                .frame(maxWidth:.infinity,minHeight:44,alignment:.leading).contentShape(Rectangle())
        }.foregroundStyle(palette.ink)
    }
}
#Preview("Privacy AX5") { NavigationStack { PrivacyView() }.environment(PlanModel()).dynamicTypeSize(.accessibility5).preferredColorScheme(.dark) }
/// Your privacy → Advanced: how many forecast requests this iPhone sent today, and what Open-Meteo
/// counts them as (`CallLedger`, kept on this iPhone and never sent). Quiet and closed by default.
struct ForecastRequestsToday: View {
    @Environment(\.nyx) private var palette
    /// `-nyx-advanced` (DEBUG) opens it for screenshots.
    @State private var expanded=DebugScenario.isEnabled("advanced")
    var body: some View {
        DisclosureGroup(isExpanded:$expanded) {
            // Read when shown: the ledger is a small file's worth of entries.
            let today=CallLedger.shared.today()
            VStack(alignment:.leading,spacing:10) {
                LabeledContent("Requests today") { Text(today.requests,format:.number).monospacedDigit() }
                LabeledContent("Calls, as Open-Meteo counts them") { Text(Int(today.calls.rounded()),format:.number).monospacedDigit() }
                Text("Counted on this iPhone since midnight and never sent anywhere. Open-Meteo counts each place in a request as one call. Its free service allows 10,000 calls a day from each network address, shared by every device on that network, so Nyx paces its requests and waits whenever the service asks.")
                    .font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
            }.padding(.top,6)
        } label:{ Text("Forecast requests on this iPhone").frame(minHeight:44,alignment:.leading) }
        .tint(palette.accent)
    }
}
/// Your privacy → Advanced: an NPS key of the person's own, used instead of the key every install
/// shares. Free from nps.gov; kept in the Keychain on this device; never shown again in full.
struct NPSKeyField: View {
    @Environment(\.nyx) private var palette
    @Environment(PlanModel.self) private var model
    /// `-nyx-advanced` (DEBUG) opens it for screenshots.
    @State private var expanded=DebugScenario.isEnabled("advanced")
    @State private var draft=""
    @State private var saved=NPSKeyStore().key != nil
    @State private var message:String?
    var body: some View {
        DisclosureGroup(isExpanded:$expanded) {
            VStack(alignment:.leading,spacing:10) {
                Text("Park alerts use a key every copy of Nyx shares, limited to 1,000 requests an hour. If alerts are often busy, you can use a free key of your own from the National Park Service. It stays in this device's Keychain and is sent only to developer.nps.gov.")
                    .font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
                if saved {
                    Label("Using your own key.",systemImage:"key").font(.subheadline)
                    Button("Remove my key",role:.destructive) { NPSKeyStore().remove(); saved=false; message=nil }.frame(minHeight:44)
                } else {
                    SecureField("Your National Park Service key",text:$draft).textContentType(.password).autocorrectionDisabled().textInputAutocapitalization(.never).font(.body.monospaced())
                        .submitLabel(.done).onSubmit(save)
                    Button("Use this key",action:save).disabled(draft.isEmpty).frame(minHeight:44)
                }
                if let message { Text(message).font(.caption).foregroundStyle(palette.accent).fixedSize(horizontal:false,vertical:true) }
            }.padding(.top,6)
        } label:{ Text("Use your own park service key").frame(minHeight:44,alignment:.leading) }
        .tint(palette.accent)
    }
    private func save() {
        guard NPSKeyStore.plausible(draft) else { message=String(localized:"That does not look like a National Park Service key. Keys are about 40 letters and numbers."); return }
        if NPSKeyStore().save(draft) {
            draft=""; saved=true; message=nil
            Task { await model.refreshParkUpdates([],force:true) }
        } else { message=String(localized:"The key could not be saved. Try again.") }
    }
}
