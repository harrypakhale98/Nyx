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
            Section("Privacy and data") { NavigationLink("Your privacy") { PrivacyView().nightForm() };NavigationLink("About the data") { AboutDataView() } }.listRowBackground(palette.panel)
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
                notifications=granted; if !granted { permissionMessage=String(localized:"Reminders are off. You can enable them in iPhone Settings.") }
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
            Section { Text("Nyx has no account, no ads, no tracking. Your journal never leaves this phone.").font(.system(.title3,design:.serif));Text("Saved parks and spots, journal entries and selected photos are stored on this iPhone. iCloud sync is not used. Your device backup settings may include app data.") }
            Section("Optional data updates") {
                Toggle("Cloud forecasts",isOn:$model.weatherEnabled).tint(palette.controlTint)
                Text("Requests go to api.open-meteo.com for all \(model.parks.count) parks together, up to 50 in each request: clouds, three forecast models for comparison, cloud layers, temperature, dew point, wind and visibility. They use the coordinates of each park's main viewing spot only, so they never reveal your location or which parks are near you. The service receives network information such as your IP address.").font(.caption).foregroundStyle(palette.muted)
                // The world catalogue (G4, owner's decision D3): asked for by whole 10° squares, never one place.
                Text("The parks and dark-sky places beyond the U.S. national parks are never asked about one at a time. The world is divided into squares of 10° of latitude and longitude, and a request carries the public coordinates of every listed place in one square, at most 1,000; squares with only a few places are asked about together. The service can tell which part of the world interests you, a region about the size of a country, but never the place you look at or where you are.").font(.caption).foregroundStyle(palette.muted)
                // Saved spots (G3): the one request that carries a place the person chose, so it says exactly what it sends.
                Toggle("Clouds at your saved spots",isOn:$model.spotForecastsEnabled).tint(palette.controlTint).disabled(!model.weatherEnabled)
                Text("For each spot you save, Nyx asks api.open-meteo.com for its clouds with the spot's coordinates rounded to 0.1°, about 11 km. The service learns roughly where your spots are, never the exact point and never their names. Spots are asked about in a request of their own, never mixed with the parks. Your current location is sent only if you save it as a spot. With this off, nothing is sent for spots: they keep their last forecast, then use their usual clouds. The service receives network information such as your IP address.").font(.caption).foregroundStyle(palette.muted)
                Toggle("Smoke and haze",isOn:$model.smokeEnabled).tint(palette.controlTint)
                Text("Requests go to air-quality-api.open-meteo.com, the same provider's air-quality service, for all \(model.parks.count) parks together, up to 50 in each request, using the same viewing-spot coordinates only. It returns the CAMS aerosol forecast that warns when smoke or haze will hide faint stars. The service receives network information such as your IP address.").font(.caption).foregroundStyle(palette.muted)
                Toggle("Park alerts and programs",isOn:$model.npsEnabled).tint(palette.controlTint)
                Text("Alerts for all \(model.parks.count) parks arrive in one request to developer.nps.gov, at most every six hours, so it never reveals which parks are near you. Ranger programs are requested only for a park whose page you open. Campgrounds for all \(model.parks.count) parks arrive in one request, at most once a week, the first time a park's Where to stay appears; it names every park and nothing about you. Your coordinates are never sent. The service receives network information such as your IP address.").font(.caption).foregroundStyle(palette.muted)
            }
            Section { NPSKeyField() } header:{ Text("Advanced") }
            Section("Measured on this iPhone") {
                Text("iOS reports how Nyx performs, including how bright its screen was, through MetricKit about once a day. Nyx keeps only the last screen brightness, to show here and in About the data. It is never sent anywhere.")
                if let reading=LuminanceProof.current { Text(reading.sentence) }
            }
            Section { Text("Turning updates off prevents new requests. Previously cached data remains available. Moon, twilight, Plan, saved parks and the journal work offline.");Text("Location is used only while you use Nyx, to compare park distances on this iPhone and to work out the sky From home tonight, which asks no service for anything. Photos are accessed only through the system photo picker. Reminders and alarms are local. In field mode, Nyx uses motion on this iPhone to point the sky where you hold it; nothing is recorded.");Text("Links to nps.gov pages, Recreation.gov campground reservations and Globe at Night open in Safari when you tap them. Nyx itself sends nothing to those sites.");Text("Adding a night to Calendar opens Calendar's own editor, where you choose and save it. Nyx never reads your calendars.") }
        }.readableForm().navigationTitle("Your privacy").navigationBarTitleDisplayMode(.inline)
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
            block("Planets, the Milky Way and meteors","The Milky Way's bright center is taken as the direction of Sagittarius A*, counted as up once it is 10° clear of the horizon. Planets use Paul Schlyter's low-precision orbital elements and agree with a professional ephemeris to within about a degree from 2026 to 2032; brightness is given in words, because Mercury's can be off by more than half a magnitude. A planet is listed once it is 8° up in a sky dark enough for its brightness: civil twilight for Venus and Jupiter at their brightest, the Sun 9° down for planets brighter than magnitude 0, 12° down for the rest; Mercury fainter than magnitude 1.5 is left out. Rise, set and best times are found to within a minute of the model, but hills, trees and haze can shift what you see by a few minutes or more. Meteor showers come from the International Meteor Organization's 2026 Meteor Shower Calendar (IMO, edited by Jürgen Rendtel): dates, radiants and published peak rates. Nyx estimates an hourly rate for one observer from the radiant's height, the Moon and the park's estimated sky brightness, shown as a range: the upper figure is what a trained observer could count, and casual watchers see about half. It is a rough guide, and real showers vary from year to year. Lunar eclipse times: Eclipse Predictions by Fred Espenak, NASA's GSFC. Nyx checks the Moon's height at the park itself and names the deepest stage you can see, so a Moon that rises during the partial phase is shown, not hidden. Satellites are counted as sunlit while the Sun is less than about 23° below the horizon, for a 550 km orbit overhead. The faintest-star figure is an estimate from the park's Bortle class, moonlight, twilight and haze. Aurora notes come from how far a place lies from Earth's magnetic pole, traced along the magnetic field itself with the International Geomagnetic Reference Field (IGRF-14), and appear only on nights dark enough to see one; Nyx does not forecast aurora. None of this changes the score.")
            block("Forecasts","Open-Meteo forecasts cover up to 16 days. Every park is asked for together, up to 50 in each request, and each request carries only the public coordinates of each park's main viewing spot. Clouds are averaged over the complete window of true darkness; on nights without it, over sunset to sunrise, or the four hours around the Sun's lowest point under the midnight sun. A forecast counts in full up to about three days ahead of a night. From there to ten days it is eased toward the park's usual clouds for the month, and these nights are marked as an early look; past ten days, or with no forecast, the usual clouds count alone. An old forecast is never dropped; it simply counts for less, so going offline cannot make a night look clearer than its clouds allow. A forecast with incomplete coverage of a night is not used. At Haleakalā, whose summit sits above the trade-wind inversion, the score counts mid and high cloud when that forecast is available. Open-Meteo's data is licensed under CC BY 4.0. Nyx changes it: each night's clouds are averaged over that night's true darkness and eased toward the usual clouds, as described here.") { openMeteoLink;licenseLink }
            block("How sure the forecast is","For the next seven days, Nyx also asks three independent forecast models (NOAA's GFS, ECMWF's IFS and DWD's ICON) for the same dark window. When their averages are within 15 points of cloud cover they agree; within 35 they roughly agree; beyond that they disagree, and the time river draws the range of scores they allow. The score itself uses Open-Meteo's best-match forecast; on a tie, closer model agreement ranks first. Cloud layers, the coldest hour, dew risk (air within 2 °C of its dew point) and the strongest gust come from the same seven-day forecast. Visibility is a coarse model value and appears only as a haze hint. None of these change the score.")
            block("Usual clouds","Beyond the forecast, Nyx knows how cloudy each park's nights usually are in each month: ten years (2015 to 2024) of ERA5, a record of past weather rebuilt from observations, averaged over each night's true darkness at the park's coordinates. Nights without a forecast are scored with these usual clouds and say so (\"No cloud forecast yet\"), so a park whose winter nights are mostly overcast does not tie a desert and a night nobody can forecast is never treated as clear. They also say how often that month's nights are mostly clear (under 30% cloud). It is a long-term average, never a forecast. Generated using Copernicus Climate Change Service information [2015–2024]: ERA5 (Hersbach et al. 2020; DOI 10.24381/cds.adbb2d47), read from its hourly time series (DOI 10.24381/1cf1ad76) and averaged over each night's true darkness by Nyx. Licensed under CC BY 4.0. Neither the European Commission nor ECMWF is responsible for any use that may be made of the Copernicus information or data it contains.") { licenseLink }
            block("Smoke and haze","Aerosol optical depth at 550 nm, from the CAMS global forecast (Copernicus Atmosphere Monitoring Service) through Open-Meteo's air-quality service, covers about five days. It is averaged over the dark window: below 0.1 is clear air, 0.1 to 0.25 light haze, 0.25 to 0.5 haze or smoke that makes the Milky Way look faint, and 0.5 or more heavy smoke or haze that hides faint stars. From 0.25 a caveat appears beside the score, and smoke caps it: at most 74 from 0.25, at most 59 from 0.5. When no smoke forecast reaches a night, nothing is capped. Air-quality data: Copernicus Atmosphere Monitoring Service (CAMS) through Open-Meteo, CC BY 4.0, averaged over the night's true darkness by Nyx. Neither the European Commission nor ECMWF is responsible for any use that may be made of the Copernicus information or data it contains. You can switch this request off in Your privacy.") { openMeteoLink;licenseLink }
            block("Parks and sky glow","The bundled NPS inventory contains \(model.parks.count) national parks. Bortle classes are conservative estimates, not instrument measurements. Dark Sky designations are International Dark Sky Park certifications as of July 2026, cross-checked against the NPS list; a park certified later is not yet marked. Viewing coordinates are approximate, not directions. The sky drawings (Tonight's sky, the Bortle figure and the city comparison) show stars on a moonless night down to the faintest magnitude Bortle's 2001 scale gives each class, about 7.3 at class 2 and 4.5 at class 8; their faintest stars are placed for illustration, not from a catalogue. Park data: National Park Service.")
            block("Night lights from space","Light-pollution estimates use NASA Black Marble nighttime lights (VNP46A4, DOI 10.5067/VIIRS/VNP46A4.002; Román et al. 2018), public domain. Nyx adds the 2025 yearly satellite light within 300 km of each park and viewing spot, weakening with distance (Walker's law), and compares the result across the \(SkyGlow.shared.parks.count) parks. The same sum, split by direction, finds the light domes on the horizon; a town is named only when a known one lies near the light. It is a comparison between places, not a measurement of sky brightness: it models no terrain, haze or light color, cannot resolve a lit lodge next to a spot, and cannot tell the darkest skies apart. The satellite misses much of the blue light of white LEDs, so towns that switched to LEDs can look darker than they are. The score keeps the conservative Bortle estimate; the satellite view is context. Growth since 2013 is shown only as a comparison between parks, and not for Alaska, lava, oil-field flaring or almost unlit places, where the change is not light pollution.")
            block("Away from the parks","For a place that is not one of the parks, such as your starting city, Nyx reads two grids that come with the app. Sky brightness comes from the same 2025 NASA night lights, summed within 300 km of every point and checked against 77 published measurements from dark sites to city centres: typically within half a magnitude, closer in dark places. It is shown as an estimate with its Bortle class. Usual clouds come from the same ten years of ERA5, averaged over each month's night on a quarter-degree grid; how often nights are mostly clear is estimated from that average, so it reads \"about\". The parks keep their own values. Generated using Copernicus Climate Change Service information [2015–2024].")
            // Credited only when the world catalogue is in this build.
            if Bundle.main.url(forResource:"catalog",withExtension:"json") != nil {
                block("Parks around the world","Beyond the U.S. national parks, the national parks and certified dark-sky places Nyx knows come from Wikidata, a free shared database, under CC0 (no rights reserved). A few certified dark-sky places missing there were added by hand, each checked against its own published source. Each place is one point for what is often a large area, so the sky can differ across it. Its Bortle class and usual clouds are estimates read from the grids described above, not measured there. Nyx has no closure alerts outside the U.S. national parks, so check the park's own site before you go. Forecasts are asked for by whole regions, every place in a 10° square (about 1,100 km from north to south), so a request never shows which place you are looking at.")
            }
            block("Step-free viewing","Step-free notes come from each park's accessibility pages on nps.gov, retrieved October 5, 2026. A spot is marked only where an official page says so, and each note shows the sentence it rests on and a link to the page, which opens in Safari. Spots without an official statement show nothing. Night access, gates and seasonal closures are not covered. Conditions change; check with the park.")
            block("Getting there","Access notes for parks a car cannot simply reach, by boat, plane or a limited road, come from each park's Getting there and directions pages on nps.gov, retrieved October 6, 2026. The trip planner leaves out parks reached only by boat or plane unless you include them. Schedules and seasons change; check with the park.")
            block("The map under your constellation","The faint outline of the United States beneath your stars is simplified from the U.S. Census Bureau's cartographic boundary file of the nation (cb_2023_us_nation_20m), which is in the public domain. It is decoration, drawn at a scale where small islands disappear.")
            // Credited only when the starting-places list is in this build.
            if Bundle.main.url(forResource:"places",withExtension:"json") != nil {
                block("Starting points","The towns and cities you can start from come, in the United States, from the U.S. Census Bureau's 2025 Gazetteer Files (Places) and its Vintage 2025 population estimates, which are in the public domain, and everywhere else from GeoNames (geonames.org): every place of 15,000 people or more, under the Creative Commons Attribution 4.0 license (CC BY 4.0). Each place is a single point, not a boundary, and only straight-line distances are measured from it. A spot you save takes its time zone and region from the nearest of these places; near a border, that can be the neighbor's.")
            }
            block("Access comes first","Nyx is a planning aid, not a guarantee. A score never confirms that a road or park is open. Park updates may be unavailable. Cached alerts and programs show their update time. Check with the park before traveling, especially when Nyx has not checked alerts.")
            block("Park-local time","Each park has an IANA time zone. A night runs from local noon to the following local noon, and \"tonight\" moves on to the coming evening once the Sun rises. Times shown on detail belong to that park, including changes for daylight saving time. The stars behind each screen are the real sky over that park in the middle of the night's darkness, from the Yale Bright Star Catalogue (Hoffleit and Warren, via NASA HEASARC); they show where the stars are, not whether clouds will hide them. Star names come from the IAU Working Group on Star Names (IAU WGSN); the constellation figures are drawn for Nyx between catalogue stars.")
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
