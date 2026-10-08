import SwiftUI

struct SettingsView:View {
    @Environment(\.nyx) private var palette
    @Environment(PlanModel.self) private var model
    @AppStorage("nightVision",store:SharedSettings.defaults) private var nightVision=false
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
                Text("A red palette reduces glare. Lower the screen brightness too. The moon button at the top of each tab and the Control Center control switch it as well. Field mode, from a park's \"I'm here tonight\", turns it on and dims the screen while it is open, then puts both back.").font(.caption).foregroundStyle(palette.muted)
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
                Text("Hear a night as sound, feel the Moon's phase, and how Nyx adapts to VoiceOver, Voice Control and your display settings.").font(.caption).foregroundStyle(palette.muted)
            }.listRowBackground(palette.panel)
            Section("Privacy and data") { NavigationLink("Your privacy") { PrivacyView().nightForm() };NavigationLink("About the data") { AboutDataView() } }.listRowBackground(palette.panel)
            Section("About the sky") {
                NavigationLink { LearnView() } label:{
                    VStack(alignment:.leading,spacing:4) {
                        Text("Learn to look up")
                        Text("Short essays on the Darkness Score, the Milky Way and its photos, meteors, forecasts, staying safe and sharing the night.").font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
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
                    Text("A new Moon is a few sharp, sparse taps. As it fills, the taps soften over a broad hum, until a full Moon is one wide swell. A waxing Moon swells across the pattern; a waning one fades. Each night's tick on the river is firmer and crisper as its score rises.").foregroundStyle(palette.muted)
                    if moonHaptics {
                        ForEach([(String(localized:"Feel a new Moon"),0.0),(String(localized:"Feel a half Moon"),0.5),(String(localized:"Feel a full Moon"),1.0)],id:\.0) { title,lit in
                            Button(title) { MoonHaptics.shared.play(.moon(illumination:lit,waxing:true)) }.foregroundStyle(palette.accent)
                        }
                    }
                } else {
                    Text("This device has no Taptic Engine, so Nyx keeps its simple ticks. The Moon's phase is always written beside it.").foregroundStyle(palette.muted)
                }
            }.listRowBackground(palette.panel)
            Section("With VoiceOver") {
                Text("The time river, each calendar month and the shape of the night offer an audio graph: choose Audio Graph in the rotor to hear the nights rise and fall as a tone.")
                Text("Rotors jump straight to what matters: Best nights and the best stretch in Plan, Closures and Pristine nights in Parks, Milestones in field mode. On the time river, actions go to the best night and feel the Moon.").foregroundStyle(palette.muted)
            }.listRowBackground(palette.panel)
            Section("Your display settings") {
                Text("With Differentiate Without Color, Excellent and Pristine nights are drawn as small stars, the river's best nights are marked with a triangle, moonlit hours are hatched and past nights are struck through.")
                Text("Reduce Highlighting Effects dims the glows, halos and the Milky Way and keeps the shooting star away. Prefer Cross-Fade Transitions replaces the zoom and the calendar's slide. When iOS asks apps to use less, the sky holds still.").foregroundStyle(palette.muted)
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
            Section { Text("Nyx has no account, no ads, no tracking. Your journal never leaves this phone.").font(.system(.title3,design:.serif));Text("Saved parks, journal entries and selected photos are stored on this iPhone. iCloud sync is not used. Your device backup settings may include app data.") }
            Section("Optional data updates") {
                Toggle("Cloud forecasts",isOn:$model.weatherEnabled).tint(palette.controlTint)
                Text("Requests go to api.open-meteo.com for all 63 parks at once: clouds, three forecast models for comparison, cloud layers, temperature, dew point, wind and visibility. They use the coordinates of each park's main viewing spot only, so they never reveal your location or which parks are near you. The service receives network information such as your IP address.").font(.caption).foregroundStyle(palette.muted)
                Toggle("Smoke and haze",isOn:$model.smokeEnabled).tint(palette.controlTint)
                Text("Requests go to air-quality-api.open-meteo.com, the same provider's air-quality service, for all 63 parks at once, using the same viewing-spot coordinates only. It returns the CAMS aerosol forecast that warns when smoke or haze will hide faint stars. The service receives network information such as your IP address.").font(.caption).foregroundStyle(palette.muted)
                Toggle("Park alerts and programs",isOn:$model.npsEnabled).tint(palette.controlTint)
                Text("Alerts for all 63 parks arrive in one request to developer.nps.gov, at most every six hours, so it never reveals which parks are near you. Ranger programs are requested only for a park whose page you open. Campgrounds for all 63 parks arrive in one request, at most once a week, the first time a park's Where to stay appears; it names every park and nothing about you. Your coordinates are never sent. The service receives network information such as your IP address.").font(.caption).foregroundStyle(palette.muted)
            }
            Section { NPSKeyField() } header:{ Text("Advanced") }
            Section("Measured on this iPhone") {
                Text("iOS reports how Nyx performs, including how bright its screen was, through MetricKit about once a day. Nyx keeps only the last screen brightness, to show here and in About the data. It is never sent anywhere.")
                if let reading=LuminanceProof.current { Text(reading.sentence) }
            }
            Section { Text("Turning updates off prevents new requests. Previously cached data remains available. Moon, twilight, calendar, saved parks and the journal work offline.");Text("Location is used only while you use Nyx, to compare park distances on this iPhone and to work out the sky From home tonight, which asks no service for anything. Photos are accessed only through the system photo picker. Reminders and alarms are local. In field mode, Nyx uses motion on this iPhone to point the sky where you hold it; nothing is recorded.");Text("Links to nps.gov pages, Recreation.gov campground reservations and Globe at Night open in Safari when you tap them. Nyx itself sends nothing to those sites.");Text("Adding a night to Calendar opens Calendar's own editor, where you choose and save it. Nyx never reads your calendars.") }
        }.readableForm().navigationTitle("Your privacy").navigationBarTitleDisplayMode(.inline)
    }
}
struct AboutDataView:View {
    @Environment(\.nyx) private var palette
    var body:some View {
        ScrollView { VStack(alignment:.leading,spacing:24) {
            Text("An honest view of the sky").font(.system(.largeTitle,design:.serif))
            block("The score","Moonlight contributes 40%, clouds 25%, estimated light pollution 20%, and the length of true darkness 15%. Moonlight follows the Moon's phase and its height through true darkness (Krisciunas and Schaefer, 1991), so a low crescent costs less than a high gibbous Moon. The four parts are added, then the weakest link caps the sum: clouds hold a night to 100 minus 0.9 points for each percent of cloud (overcast at most 10, half cloud 55); sky glow holds a Bortle 3 park to 89, Bortle 4 to 84, Bortle 5 to 74, Bortle 6 to 59 and brighter skies to 39, so only Bortle 2 or darker can read Pristine; heavy smoke or haze (aerosol optical depth 0.5 or more) holds a night to 59, and lighter smoke (0.25 to 0.5) to 74. No true darkness caps a night below 40, and that cap lifts gradually over the first three hours of true darkness. The breakdown names the cap that applies. When scores tie, parks with darker skies in NASA's satellite night lights come first, then longer true darkness.")
            // Shown only after iOS has delivered a real MetricKit report; nothing is estimated in its place.
            if let reading=LuminanceProof.current {
                VStack(alignment:.leading,spacing:10) {
                    Text("How dark Nyx keeps your screen").font(.system(.title2,design:.serif))
                    Text(reading.sentence).font(.body).lineSpacing(4).foregroundStyle(palette.ink)
                    Text("iOS measures the average brightness of the pixels Nyx draws (MetricKit's average pixel luminance: 0% is an all-black screen, 100% all white) and reports it about once a day. It is measured on this iPhone and never leaves it.").font(.body).lineSpacing(4).foregroundStyle(palette.muted)
                }.accessibilityElement(children:.combine)
            }
            block("Moon and twilight","Solar timing uses NOAA approximations. Moonrise and moonset use a low-precision Meeus-style position. Checked against the U.S. Naval Observatory, they agree to within a few minutes: a minute or less at the parks checked in Alaska, Hawaiʻi, American Samoa and the Virgin Islands, and under 4 minutes at mid-latitude parks. Sunrise, sunset and twilight agree to within a minute. Moon illumination corrects the mean 29.53-day cycle with the Moon’s calculated position and is approximate. Terrain and atmospheric conditions can shift visible rise and set times. The Moon is drawn from NASA's lunar colour map, lit from the Sun's real direction and tilted as it appears from the park at its highest point that night. Moon imagery: NASA's Scientific Visualization Studio (CGI Moon Kit); LRO LROC and LOLA teams.")
            block("Planets, the Milky Way and meteors","The Milky Way's bright center is Sagittarius A*, counted as up once it is 10° clear of the horizon. Planets use Paul Schlyter's low-precision orbital elements and agree with a professional ephemeris to within about a degree from 2026 to 2032; brightness is given in words, because Mercury's can be off by more than half a magnitude. A planet is listed once it is 8° up in a sky dark enough for its brightness: civil twilight for Venus and Jupiter at their brightest, the Sun 9° down for planets brighter than magnitude 0, 12° down for the rest; Mercury fainter than magnitude 1.5 is left out. Rise, set and best times are found to within a minute of the model, but hills, trees and haze can shift what you see by a few minutes or more. Meteor showers come from the International Meteor Organization's 2026 Meteor Shower Calendar (IMO, edited by Jürgen Rendtel): dates, radiants and published peak rates. Nyx estimates an hourly rate for one observer from the radiant's height, the Moon and the park's estimated sky brightness, shown as a range: the upper figure is what a trained observer could count, and casual watchers see about half. It is a rough guide, and real showers vary from year to year. Lunar eclipse times: Eclipse Predictions by Fred Espenak, NASA's GSFC. Nyx checks the Moon's height at the park itself and names the deepest stage you can see, so a Moon that rises during the partial phase is shown, not hidden. Satellites are counted as sunlit while the Sun is less than about 23° below the horizon, for a 550 km orbit overhead. The faintest-star figure is an estimate from the park's Bortle class, moonlight, twilight and haze. Aurora season in Alaska is a calendar note; Nyx does not forecast aurora. None of this changes the score.")
            block("Forecasts","Open-Meteo forecasts cover up to 16 days. All 63 parks share each request, which carries only the public coordinates of each park's main viewing spot. Clouds are averaged over the complete window of true darkness; on nights without it, over sunset to sunrise, or the four hours around the Sun's lowest point under the midnight sun. A forecast counts in full up to about three days ahead of a night. From there to ten days it is eased toward the park's usual clouds for the month, and these nights are marked as an early look; past ten days, or with no forecast, the usual clouds count alone. An old forecast is never dropped; it simply counts for less, so going offline cannot make a night look clearer than its clouds allow. A forecast with incomplete coverage of a night is not used. At Haleakalā, whose summit sits above the trade-wind inversion, the score counts mid and high cloud when that forecast is available. Open-Meteo's data is licensed under CC BY 4.0. Nyx changes it: each night's clouds are averaged over that night's true darkness and eased toward the usual clouds, as described here.") { openMeteoLink;licenseLink }
            block("How sure the forecast is","For the next seven days, Nyx also asks three independent forecast models (NOAA's GFS, ECMWF's IFS and DWD's ICON) for the same dark window. When their averages are within 15 points of cloud cover they agree; within 35 they roughly agree; beyond that they disagree, and the time river draws the range of scores they allow. The score itself uses Open-Meteo's best-match forecast; on a tie, closer model agreement ranks first. Cloud layers, the coldest hour, dew risk (air within 2 °C of its dew point) and the strongest gust come from the same seven-day forecast. Visibility is a coarse model value and appears only as a haze hint. None of these change the score.")
            block("Usual clouds","Beyond the forecast, Nyx knows how cloudy each park's nights usually are in each month: ten years (2015 to 2024) of ERA5 reanalysis, averaged over each night's true darkness at the park's coordinates. Nights without a forecast are scored with these usual clouds and say so (“No cloud forecast yet”), so a park whose winter nights are mostly overcast does not tie a desert and a night nobody can forecast is never treated as clear. They also say how often that month's nights are mostly clear (under 30% cloud). It is a long-term average, never a forecast. Generated using Copernicus Climate Change Service information [2015–2024]: ERA5 (Hersbach et al. 2020; DOI 10.24381/cds.adbb2d47), read from its hourly time series (DOI 10.24381/1cf1ad76) and averaged over each night's true darkness by Nyx. Licensed under CC BY 4.0. Neither the European Commission nor ECMWF is responsible for any use that may be made of the Copernicus information or data it contains.") { licenseLink }
            block("Smoke and haze","Aerosol optical depth at 550 nm, from the CAMS global forecast (Copernicus Atmosphere Monitoring Service) through Open-Meteo's air-quality service, covers about five days. It is averaged over the dark window: below 0.1 is clear air, 0.1 to 0.25 light haze, 0.25 to 0.5 haze or smoke that makes the Milky Way look faint, and 0.5 or more heavy smoke or haze that hides faint stars. From 0.25 a caveat appears beside the score, and smoke caps it: at most 74 from 0.25, at most 59 from 0.5. When no smoke forecast reaches a night, nothing is capped. Air-quality data: Copernicus Atmosphere Monitoring Service (CAMS) through Open-Meteo, CC BY 4.0, averaged over the night's true darkness by Nyx. Neither the European Commission nor ECMWF is responsible for any use that may be made of the Copernicus information or data it contains. You can switch this request off in Your privacy.") { openMeteoLink;licenseLink }
            block("Parks and skyglow","The bundled NPS inventory contains 63 national parks. Bortle classes are conservative estimates, not instrument measurements. Dark-Sky designations are International Dark Sky Park certifications as of July 2026, cross-checked against the NPS list; a park certified later is not yet marked. Viewing coordinates are approximate, not directions. Park data: National Park Service.")
            block("Night lights from space","Light-pollution estimates use NASA Black Marble nighttime lights (VNP46A4, DOI 10.5067/VIIRS/VNP46A4.002; Román et al. 2018), public domain. Nyx adds the 2025 yearly satellite light within 300 km of each park and viewing spot, weakening with distance (Walker's law), and compares the result across the 63 parks. The same sum, split by direction, finds the light domes on the horizon; a town is named only when a known one lies near the light. It is a comparison between places, not a measurement of sky brightness: it models no terrain, haze or light colour, cannot resolve a lit lodge next to a spot, and cannot tell the darkest skies apart. The satellite misses much of the blue light of white LEDs, so towns that switched to LEDs can look darker than they are. The score keeps the conservative Bortle estimate; the satellite view is context. Growth since 2013 is shown only as a comparison between parks, and not for Alaska, lava, oil-field flaring or almost unlit places, where the change is not light pollution.")
            block("Step-free viewing","Step-free notes come from each park's accessibility pages on nps.gov, retrieved October 5, 2026. A spot is marked only where an official page says so, and each note shows the sentence it rests on and a link to the page, which opens in Safari. Spots without an official statement show nothing. Night access, gates and seasonal closures are not covered. Conditions change; check with the park.")
            block("Getting there","Access notes for parks a car cannot simply reach, by boat, plane or a limited road, come from each park's Getting there and directions pages on nps.gov, retrieved October 6, 2026. The trip planner leaves out parks reached only by boat or plane unless you include them. Schedules and seasons change; check with the park.")
            block("The map under your constellation","The faint outline of the United States beneath your stars is simplified from the US Census Bureau's cartographic boundary file of the nation (cb_2023_us_nation_20m), which is in the public domain. It is decoration, drawn at a scale where small islands disappear.")
            // Credited only when the starting-places list is in this build.
            if Bundle.main.url(forResource:"places",withExtension:"json") != nil {
                block("Starting places","The towns and cities you can start from come from the U.S. Census Bureau's 2025 Gazetteer Files (Places) and its Vintage 2025 population estimates, which are in the public domain. Each place is a single interior point, not a city center, and only straight-line distances are measured from it.")
            }
            block("Access comes first","Nyx is a planning aid, not a guarantee. A score never confirms that a road or park is open. Park updates may be unavailable. Cached alerts and programs show their update time. Check with the park before traveling, especially when Nyx has not checked alerts.")
            block("Park-local time","Each park has an IANA time zone. A night runs from local noon to the following local noon, and “tonight” moves on to the coming evening once the Sun rises. Times shown on detail belong to that park, including changes for daylight saving time. The stars behind each screen are the real sky over that park in the middle of the night's darkness, from the Yale Bright Star Catalogue (Hoffleit and Warren, via NASA HEASARC); they show where the stars are, not whether clouds will hide them. On Apple Vision Pro, star names come from the IAU Working Group on Star Names (IAU WGSN).")
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
/// The Learn essays in reading order: the score first, then the sky, then the trip. Each has one
/// English source, `Nyx/Resources/learn/<case>.md`, and a catalog key `essay.<case>`.
enum Essay: String,CaseIterable,Identifiable {
    case score,darkness,milkyway,photo,meteors,bortle,forecast,safety,etiquette,access
    var id:String { rawValue }
    var title:String { switch self { case .score:String(localized:"Reading the Darkness Score");case .darkness:String(localized:"A sky worth protecting");case .milkyway:String(localized:"Finding the Milky Way");case .photo:String(localized:"Your first Milky Way photo");case .meteors:String(localized:"Watching a meteor shower");case .bortle:String(localized:"Reading the Bortle scale");case .forecast:String(localized:"What a forecast can't tell you");case .safety:String(localized:"Safe in the dark");case .etiquette:String(localized:"Sharing the night");case .access:String(localized:"Stargazing for everyone") } }
    var subtitle:String { switch self { case .score:String(localized:"Four parts, the weakest link and the bands");case .darkness:String(localized:"Why darkness deserves care");case .milkyway:String(localized:"When, where and how to look");case .photo:String(localized:"A tripod, a wide lens and a dark night");case .meteors:String(localized:"Radiants, rates and patience");case .bortle:String(localized:"Understand artificial sky brightness");case .forecast:String(localized:"Models, thin cloud, smoke and fog");case .safety:String(localized:"Roads, cold, no signal and red light");case .etiquette:String(localized:"Leave room for everyone to look up");case .access:String(localized:"Dark skies by sound, touch and red light") } }
    var symbol:String { switch self { case .score:"gauge.with.dots.needle.67percent";case .darkness:"sparkles";case .milkyway:"sparkle";case .photo:"camera.aperture";case .meteors:"sparkles.2";case .bortle:"circle.lefthalf.filled";case .forecast:"cloud.moon";case .safety:"figure.hiking";case .etiquette:"moon.stars";case .access:"accessibility" } }
    /// About 200 words a minute, never less than one.
    var minutes:Int { max(1,Int((Double(content.split(whereSeparator:\.isWhitespace).count)/200).rounded())) }
    var content:String { switch self { case .darkness:String(localized:"essay.darkness");case .milkyway:String(localized:"essay.milkyway");case .meteors:String(localized:"essay.meteors");case .bortle:String(localized:"essay.bortle");case .etiquette:String(localized:"essay.etiquette");case .access:String(localized:"essay.access");case .score,.photo,.forecast,.safety:Self.text(rawValue) } }
    /// One way from the essay into Nyx itself: the place where what it explains can be seen tonight.
    func link(model:PlanModel)->(label:String,url:URL)? {
        link(home:model.home,tonight:model.home.map { $0.isoDay(model.tonight($0)) })
    }
    /// The same, from the starting park and its tonight (park-local `YYYY-MM-DD`); pure, so it is tested.
    func link(home:Park?,tonight:String?)->(label:String,url:URL)? {
        switch self {
        case .score,.darkness: return URL(string:"nyx://tonight").map { (String(localized:"Tonight's darkest park"),$0) }
        case .safety: return home.flatMap { URL(string:"nyx://park/\($0.id)") }.map { (String(localized:"Your starting park's alerts"),$0) }
        case .photo,.milkyway,.meteors:
            guard let park=home,let tonight else { return nil }
            return URL(string:"nyx://whatsup?date=\(tonight)&park=\(park.id)").map { (String(localized:"What's up tonight at \(park.shortName)"),$0) }
        case .forecast: return home.flatMap { URL(string:"nyx://calendar/\($0.id)") }.map { (String(localized:"The month ahead"),$0) }
        case .bortle,.etiquette,.access: return nil
        }
    }
    /// The catalog's `essay.<name>` in the reader's language; until the catalog holds it, the
    /// bundled English source, so a new essay never shows its key.
    static func text(_ name:String,bundle:Bundle = .main)->String {
        let key="essay.\(name)", local=bundle.localizedString(forKey:key,value:nil,table:nil)
        if local != key, !local.isEmpty { return local }
        let source=bundle.url(forResource:name,withExtension:"md").flatMap { try? String(contentsOf:$0,encoding:.utf8) } ?? ""
        return source.trimmingCharacters(in:.whitespacesAndNewlines)
    }
}
/// The essay's mark: an SF Symbol, or for meteors (which SF Symbols lacks) the app's own streak glyph.
private struct EssayIcon:View {
    @Environment(\.nyx) private var palette
    let essay:Essay
    let size:Double
    var body:some View {
        // One square box for every symbol, so the titles beneath line up across the grid.
        Group {
            if essay == .meteors { SkyGlyph(.meteors,color:palette.accent).frame(width:size,height:size) }
            else { Image(systemName:essay.symbol).font(.system(size:size,weight:.ultraLight)).foregroundStyle(palette.accent).accessibilityHidden(true) }
        }.frame(width:size*1.3,height:size*1.3,alignment:.leading)
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
/// The essays, from Settings › About the sky (and the `learn` screenshot route). Compact cards, so a
/// phone shows most of them at once; two or three columns on a wide iPad.
struct LearnView:View {
    @Environment(\.nyx) private var palette
    var body:some View {
        ScrollView { VStack(alignment:.leading,spacing:24) {
            Text("Learn to look up").font(.system(.largeTitle,design:.serif)).fixedSize(horizontal:false,vertical:true)
            LazyVGrid(columns:[GridItem(.adaptive(minimum:300),spacing:18,alignment:.top)],spacing:18) { ForEach(Essay.allCases) { essay in
                NavigationLink { EssayView(essay:essay) } label:{ Panel { HStack(alignment:.top,spacing:14) {
                    EssayIcon(essay:essay,size:24)
                    VStack(alignment:.leading,spacing:6) {
                        Text(essay.title).font(.system(.title3,design:.serif)).foregroundStyle(palette.ink).fixedSize(horizontal:false,vertical:true)
                        Text(essay.subtitle).font(.subheadline).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
                        Text("\(essay.minutes) minute read").font(.caption).foregroundStyle(palette.ink.opacity(palette.nightVision ? 1 : 0.86))
                    }
                    Spacer(minLength:0)
                    Image(systemName:"chevron.forward").font(.caption.weight(.semibold)).foregroundStyle(palette.muted).accessibilityHidden(true)
                }.frame(maxHeight:.infinity,alignment:.top) }.frame(maxHeight:.infinity) }.buttonStyle(.plain).hoverEffect(.lift)
            } }
            AboutDataLink()
        }.padding(24).readableColumn(1080) }.background(NightBackground()).navigationTitle("Learn").navigationBarTitleDisplayMode(.inline)
    }
}
struct EssayView:View {
    @Environment(\.nyx) private var palette
    @Environment(PlanModel.self) private var model:PlanModel?
    @Environment(SceneCommands.self) private var commands:SceneCommands?
    @Environment(\.openURL) private var openURL
    let essay:Essay
    var body:some View {
        let figure=EssayFigure(essay)
        ScrollView { VStack(alignment:.leading,spacing:28) { EssayIcon(essay:essay,size:48);Text(essay.title).font(.system(.largeTitle,design:.serif));ForEach(Array(essay.content.components(separatedBy:"\n\n").dropFirst().enumerated()),id:\.offset) { index,paragraph in Text(paragraph).font(.system(.body,design:.serif)).lineSpacing(7).foregroundStyle(palette.ink).textSelection(.enabled); if let figure, index==figure.afterParagraph { figure.view } };if let model,let link=essay.link(model:model) { Button { follow(link.url) } label:{ Label(link.label,systemImage:"arrow.up.right") }.buttonStyle(.bordered).accessibilityHint("Leaves the essay and opens it in Nyx.") };if OnDeviceGuide.available { NavigationLink("Explain this another way") { GuideView(mode:.learn(essay)) }.buttonStyle(.bordered) } }.padding(26).readableColumn(WideLayout.proseWidth) }.background(NightBackground(veil:0.6)).navigationTitle("Learn").navigationBarTitleDisplayMode(.inline)
    }
    /// Settings closes first (Learn lives in it), then the link opens where the essay points.
    private func follow(_ url:URL) {
        commands?.closeSettings+=1
        Task { try? await Task.sleep(for:.milliseconds(450)); openURL(url) }
    }
}
struct OnboardingView:View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.nyx) private var palette
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.nyxReduceMotion) private var forcedReduceMotion
    private var reduceMotion:Bool { systemReduceMotion || forcedReduceMotion }
    @Environment(PlanModel.self) private var model
    @AppStorage("nightVision",store:SharedSettings.defaults) private var nightVision=false
    @State private var page=DebugScenario.onboardingPage
    let finish:()->Void
    private let titles:[LocalizedStringKey]=["Where and when\nthe sky is darkest","A darker sky.\nA clearer plan.","Made for dark eyes"]
    private var messages:[LocalizedStringKey] {[
        "Nyx compares the \(model.parks.isEmpty ? 63 : model.parks.count) national parks night by night, so you know which park to drive to and which night to take off.",
        "Moonlight, clouds, artificial light and the length of darkness become one score. Every estimate tells you what is still unknown.",
        "Turn the screen red at any time, here or from Control Center. Nyx has no account, no ads, no tracking. Your journal never leaves this phone.",
    ]}
    var body:some View {
        VStack(spacing:0) {
            // Tracking trails the X, so the wordmark is inset by one tracking step to sit on centre.
            HStack { Spacer();Button("Skip") { finish() }.frame(minWidth:44,minHeight:44).contentShape(Rectangle()) }.overlay { if !typeSize.isAccessibilitySize { Text("NYX").font(.caption).tracking(8).padding(.leading,8).accessibilityHidden(true) } }.padding(.horizontal,28).padding(.top,28)
            TabView(selection:$page) {
                ForEach(0..<3,id:\.self) { index in
                    ScrollView {
                        VStack(spacing:index==1 && !typeSize.isAccessibilitySize ? 16 : 28) {
                            art(index)
                            Text(titles[index]).font(.system(.largeTitle,design:.serif)).multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true)
                            Text(messages[index]).font(.body).foregroundStyle(palette.muted).multilineTextAlignment(.center).lineSpacing(4).fixedSize(horizontal:false,vertical:true)
                            if index==2 { redToggle }
                        }.padding(.horizontal,28).padding(.vertical,index==1 ? 12 : 28).frame(maxWidth:560).frame(maxWidth:.infinity)
                    }.scrollBounceBehavior(.basedOnSize).defaultScrollAnchor(.center,for:.alignment)
                    // Copy that runs past the controls fades out instead of being cut mid-line.
                    .mask { VStack(spacing:0) { Color.black;LinearGradient(colors:[.black,.clear],startPoint:.top,endPoint:.bottom).frame(height:24) } }
                    .tag(index)
                }
            }.tabViewStyle(.page(indexDisplayMode:.never))
            VStack(spacing:20) {
                HStack(spacing:12) { ForEach(0..<3,id:\.self) { i in Capsule().fill(i==page ? palette.accent : palette.line).frame(width:i==page ? 18 : 5,height:5) } }
                    .animation(reduceMotion ? nil : NyxMotion.spring,value:page)
                    .frame(minWidth:88,minHeight:44).contentShape(Rectangle())
                    .accessibilityElement().accessibilityLabel("Introduction, page \(page+1) of 3")
                Button(page==2 ? "Show me tonight" : "Continue") { if page==2 { finish() } else { withAnimation(reduceMotion ? nil : NyxMotion.spring) { page+=1 } } }
                    .buttonStyle(.borderedProminent).foregroundStyle(Color.black).controlSize(.large)
            }.padding(.bottom,28)
        }.background(NightBackground(score:page==1 ? 94 : nil)).foregroundStyle(palette.ink)
    }
    @ViewBuilder private func art(_ index:Int)->some View {
        switch index {
        case 0: OnboardingMoon(daysAfterNew:3).frame(width:170,height:170).padding(.vertical,24)
        case 1: ScoreAnatomy(active:page==1)
        // The last page ends bright: a waxing gibbous Moon, which turns red with the switch below it.
        default: OnboardingMoon(daysAfterNew:11).frame(width:170,height:170).padding(.vertical,24)
        }
    }
    /// The real night-vision switch: the whole app, this page included, turns red on the shared spring.
    private var redToggle:some View {
        Toggle(isOn:$nightVision) {
            Label { Text("Night vision") } icon:{ Image(systemName:nightVision ? "moon.circle.fill" : "moon.circle").foregroundStyle(palette.accent) }.font(.headline)
        }
        .tint(palette.controlTint)
        .padding(.horizontal,20).padding(.vertical,12).frame(maxWidth:340,minHeight:56)
        .background(Capsule().fill(palette.panel)).overlay(Capsule().stroke(palette.line,lineWidth:0.5))
        .sensoryFeedback(.impact(flexibility:.soft,intensity:0.7),trigger:nightVision)
        .accessibilityHint("Turns the screen red. You can change it any time.")
    }
}
/// A real Moon over the starting park: a young crescent, or the new Moon's earthlit disc.
/// Computed from the coming new moon, so the art always matches this month's sky.
private struct OnboardingMoon:View {
    @Environment(PlanModel.self) private var model
    let daysAfterNew:Double
    var body:some View {
        let engine=AstronomyEngine(), park=model.home
        // Walk forward to the next new moon (phase fraction wraps past 0), then add the offset.
        let now=Date.now, fraction=engine.moonPhase(at:now).fraction
        let newMoon=now.addingTimeInterval((1-fraction)*AstronomyEngine.synodicDays*86400)
        let evening=newMoon.addingTimeInterval(daysAfterNew*86400)
        if let park {
            let sky=engine.conditions(for:park,on:park.evening(evening))
            // A young crescent is seen low in the west after sunset, not at its highest (often in daylight).
            let at=daysAfterNew>0 ? (sky.sunset ?? evening).addingTimeInterval(3600) : engine.moonViewTime(for:sky,park:park)
            MoonView(geometry:engine.moonGeometry(for:park,at:at))
        } else { MoonDisc(illumination:daysAfterNew>0 ? 0.18 : 0,waxing:true) }
    }
}
/// The recipe of the Darkness Score: one bar split into its four shares, lit one after another as
/// the example score counts up, then the band words. Shares, not marks: the bar is always whole.
struct ScoreAnatomy:View {
    @Environment(\.nyx) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.nyxReduceMotion) private var forcedReduceMotion
    let active:Bool
    @State private var filled=0
    private let parts:[(LocalizedStringKey,Int)]=[("Moonlight",40),("Clouds",25),("Light pollution",20),("Length of darkness",15)]
    /// Each share a step dimmer, so the four read apart without colour; gaps divide them too.
    private func shade(_ i:Int)->Double { [1,0.75,0.55,0.4][i] }
    var body:some View {
        VStack(spacing:12) {
            CelestialGauge(score:94).id(active).frame(height:typeSize.isAccessibilitySize ? nil : 176) // fresh count-up each time the page arrives
            VStack(alignment:.leading,spacing:8) {
                Text("Share of the score").font(.caption.weight(.medium)).foregroundStyle(palette.muted)
                GeometryReader { proxy in
                    HStack(spacing:3) {
                        ForEach(parts.indices,id:\.self) { i in
                            Capsule().fill(i<filled ? palette.accent.opacity(shade(i)) : palette.line)
                                .frame(width:max(0,(proxy.size.width-9)*Double(parts[i].1)/100))
                        }
                    }
                }.frame(height:6)
                ViewThatFits(in:.horizontal) {
                    Grid(alignment:.leading,horizontalSpacing:18,verticalSpacing:6) {
                        GridRow { legend(0); legend(1) }
                        GridRow { legend(2); legend(3) }
                    }
                    VStack(alignment:.leading,spacing:6) { ForEach(parts.indices,id:\.self) { legend($0) } }
                }
            }.frame(maxWidth:320)
            Text("90 Pristine · 75 Excellent · 60 Good").font(.caption).foregroundStyle(palette.ink).multilineTextAlignment(.center)
            Text("Example night").font(.caption).foregroundStyle(palette.muted)
        }
        .accessibilityElement(children:.ignore)
        .accessibilityLabel("Example score 94 out of 100. Share of the score: moonlight 40 percent, clouds 25, light pollution 20, and the length of darkness 15. 90 and above is Pristine, 75 Excellent, 60 Good.")
        .task(id:active) {
            guard active else { filled=0; return }
            if systemReduceMotion || forcedReduceMotion { filled=parts.count; return }
            for i in 1...parts.count {
                try? await Task.sleep(for:.milliseconds(260))
                withAnimation(NyxMotion.spring) { filled=i }
            }
        }
    }
    private func legend(_ i:Int)->some View {
        HStack(spacing:6) {
            Capsule().fill(palette.accent.opacity(shade(i))).frame(width:10,height:4)
            Text(parts[i].0).font(.caption)
            Text("\(parts[i].1)%").font(.caption.monospacedDigit()).foregroundStyle(palette.muted)
        }
    }
}
#Preview("Score anatomy") { ScoreAnatomy(active:true).padding().background(.black).preferredColorScheme(.dark) }
#Preview("Score anatomy AX5") { ScrollView { ScoreAnatomy(active:true).padding() }.background(.black).dynamicTypeSize(.accessibility5).preferredColorScheme(.dark) }
#Preview("Learn") { NavigationStack { LearnView() }.preferredColorScheme(.dark) }
#Preview("Onboarding") { OnboardingView {}.environment(PlanModel()).preferredColorScheme(.dark) }
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
                    SecureField("Your NPS API key",text:$draft).textContentType(.password).autocorrectionDisabled().textInputAutocapitalization(.never).font(.body.monospaced())
                        .submitLabel(.done).onSubmit(save)
                    Button("Use this key",action:save).disabled(draft.isEmpty).frame(minHeight:44)
                }
                if let message { Text(message).font(.caption).foregroundStyle(palette.accent).fixedSize(horizontal:false,vertical:true) }
            }.padding(.top,6)
        } label:{ Text("Use your own NPS key").frame(minHeight:44,alignment:.leading) }
        .tint(palette.accent)
    }
    private func save() {
        guard NPSKeyStore.plausible(draft) else { message=String(localized:"That doesn't look like an NPS key. Keys are about 40 letters and numbers."); return }
        if NPSKeyStore().save(draft) {
            draft=""; saved=true; message=nil
            Task { await model.refreshParkUpdates([],force:true) }
        } else { message=String(localized:"The key could not be saved. Try again.") }
    }
}
