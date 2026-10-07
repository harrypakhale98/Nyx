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
            Section("In the dark") { Toggle("Night-vision mode",isOn:$nightVision).tint(palette.controlTint);Text("A red palette reduces glare. Lower the screen brightness too. Field mode, from a park's \"I'm here tonight\", turns this on and dims the screen while it is open, then puts both back.").font(.caption).foregroundStyle(palette.muted) }
            Section("Appearance") { NavigationLink("App icon") { AppIconPicker() } }
            Section("Saved parks") {
                Toggle("Promising-night reminders",isOn:Binding(get:{notifications},set:{ value in if value { explainNotifications=true } else { notifications=false;Task { await NotificationScheduler().remove() } } })).tint(palette.controlTint)
                Text("Local reminders for saved parks with scores of 90 or higher. Forecasts may change. Upcoming nights are recalculated whenever Nyx opens.").font(.caption).foregroundStyle(palette.muted)
                if notifications {
                    Toggle("Meteor shower peaks",isOn:$showerReminders).tint(palette.controlTint)
                    Text("On the peak night of a major shower, when at least 20 an hour are expected at a saved park with the Moon down. At most one a night.").font(.caption).foregroundStyle(palette.muted)
                }
                if let permissionMessage { Text(permissionMessage).font(.caption) }
            }
            Section("Accessibility") {
                NavigationLink("Sound and touch") { SoundAndTouchView() }
                Text("Hear a night as sound, feel the Moon's phase, and how Nyx adapts to VoiceOver, Voice Control and your display settings.").font(.caption).foregroundStyle(palette.muted)
            }
            Section("Your iPhone") { NavigationLink("Your privacy") { PrivacyView() };NavigationLink("About the data") { AboutDataView() };LabeledContent("Distance units",value:String(localized:"Device locale"));Text("Distances use your region's units. Radius is always a straight line.").font(.caption).foregroundStyle(palette.muted) }
            Section { Button("Replay the introduction") { replay=true };LabeledContent("Version",value:Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "") }
        }.readableForm().navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented:$explainNotifications) { PermissionExplainer(symbol:"bell",title:"A night worth making time for",message:"Nyx can remind you about promising nights at saved parks. These notifications are scheduled on this iPhone. They are estimates, not confirmations of clear skies or access.",action:"Enable reminders") {
                explainNotifications=false
                Task { notifications=await NotificationScheduler().requestAuthorization(); if !notifications { permissionMessage=String(localized:"Reminders are off. You can enable them in iPhone Settings.") } }
            }.nyxPresentation() }
            .sheet(isPresented:$replay) { OnboardingView { replay=false }.nyxPresentation() }
            .task { await syncPermission() }
            .onChange(of:scenePhase) { _,phase in if phase == .active { Task { await syncPermission() } } }
    }
    /// If reminders were turned off in iPhone Settings, say so instead of showing a switch that lies.
    private func syncPermission() async {
        guard notifications, DebugScenario.screen == nil, !(await SystemNotifications().authorized()) else { return }
        notifications=false
        permissionMessage=String(localized:"Notifications for Nyx are off in iPhone Settings. Turn them on there, then switch reminders back on.")
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
            }
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
            }
            Section("With VoiceOver") {
                Text("The time river, each calendar month and the shape of the night offer an audio graph: choose Audio Graph in the rotor to hear the nights rise and fall as a tone.")
                Text("Rotors jump straight to what matters: Best nights and Moon window in the calendar, Closures and Pristine nights in Parks, Milestones in field mode. On the time river, actions go to the best night and feel the Moon.").foregroundStyle(palette.muted)
            }
            Section("Your display settings") {
                Text("With Differentiate Without Color, Excellent and Pristine nights are drawn as small stars, the river's best nights are marked with a triangle, moonlit hours are hatched and past nights are struck through.")
                Text("Reduce Highlighting Effects dims the glows, halos and the Milky Way and keeps the shooting star away. Prefer Cross-Fade Transitions replaces the zoom and the calendar's slide. When iOS asks apps to use less, the sky holds still.").foregroundStyle(palette.muted)
            }
        }.readableForm().navigationTitle("Sound and touch").navigationBarTitleDisplayMode(.inline)
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
                Text("Requests go to api.open-meteo.com for all 63 parks at once: clouds, three forecast models for comparison, cloud layers, temperature, dew point, wind and visibility. They use park coordinates only, so they never reveal your location or which parks are near you. The service receives network information such as your IP address.").font(.caption).foregroundStyle(palette.muted)
                Toggle("Smoke and haze",isOn:$model.smokeEnabled).tint(palette.controlTint)
                Text("Requests go to air-quality-api.open-meteo.com, the same provider's air-quality service, for all 63 parks at once, using park coordinates only. It returns the CAMS aerosol forecast that warns when smoke or haze will hide faint stars. The service receives network information such as your IP address.").font(.caption).foregroundStyle(palette.muted)
                Toggle("Park alerts and programs",isOn:$model.npsEnabled).tint(palette.controlTint)
                Text("When park updates are available, requests go to developer.nps.gov for parks you open or save and parks within your Tonight radius, which can suggest a broad region. Your coordinates are never sent. The service receives network information such as your IP address.").font(.caption).foregroundStyle(palette.muted)
            }
            Section("Measured on this iPhone") {
                Text("iOS reports how Nyx performs, including how bright its screen was, through MetricKit about once a day. Nyx keeps only the last screen brightness, to show here and in About the data. It is never sent anywhere.")
                if let reading=LuminanceProof.current { Text(reading.sentence) }
            }
            Section { Text("Turning updates off prevents new requests. Previously cached data remains available. Moon, twilight, calendar, saved parks and the journal work offline.");Text("Location is used only while you use Nyx, to compare park distances on this iPhone. Photos are accessed only through the system photo picker. Reminders and alarms are local. In field mode, Nyx uses motion on this iPhone to point the sky where you hold it; nothing is recorded.");Text("Links to nps.gov accessibility pages and to Globe at Night open in Safari when you tap them. Nyx itself sends nothing to those sites.");Text("Adding a night to Calendar opens Calendar's own editor, where you choose and save it. Nyx never reads your calendars.") }
        }.readableForm().navigationTitle("Your privacy").navigationBarTitleDisplayMode(.inline)
    }
}
struct AboutDataView:View {
    @Environment(\.nyx) private var palette
    var body:some View {
        ScrollView { VStack(alignment:.leading,spacing:24) {
            Text("An honest view of the sky").font(.system(.largeTitle,design:.serif))
            block("The score","Moonlight contributes 40%, clouds 25%, estimated light pollution 20%, and the length of true darkness 15%. Without a cloud forecast, the other weights are scaled to 100. No true darkness caps a night below 40, and the cap lifts gradually over the first three hours of true darkness.")
            // Shown only after iOS has delivered a real MetricKit report; nothing is estimated in its place.
            if let reading=LuminanceProof.current {
                VStack(alignment:.leading,spacing:10) {
                    Text("How dark Nyx keeps your screen").font(.system(.title2,design:.serif))
                    Text(reading.sentence).font(.body).lineSpacing(4).foregroundStyle(palette.ink)
                    Text("iOS measures the average brightness of the pixels Nyx draws (MetricKit's average pixel luminance: 0% is an all-black screen, 100% all white) and reports it about once a day. It is measured on this iPhone and never leaves it.").font(.body).lineSpacing(4).foregroundStyle(palette.muted)
                }.accessibilityElement(children:.combine)
            }
            block("Moon and twilight","Solar timing uses NOAA approximations. Moonrise and moonset use a low-precision Meeus-style position; allow about 15 minutes, and more near the poles or a blocked horizon. Moon illumination corrects the mean 29.53-day cycle with the Moon’s calculated position and is approximate. Terrain and atmospheric conditions can shift visible rise and set times. The Moon is drawn from NASA's lunar colour map (NASA's Scientific Visualization Studio, CGI Moon Kit), lit from the Sun's real direction and tilted as it appears from the park at its highest point that night.")
            block("Planets, the Milky Way and meteors","The Milky Way's bright center is Sagittarius A*, counted as up once it is 10° clear of the horizon. Planets use Paul Schlyter's low-precision orbital elements and agree with a professional ephemeris to within about a degree from 2026 to 2032; brightness is given in words, because Mercury's can be off by more than half a magnitude. Rise, set and best times are found to within a minute of the model, but hills, trees and haze can shift what you see by a few minutes or more. Meteor showers come from the International Meteor Organization's calendar (IMO, 2026 edition): dates, radiants and published peak rates. Nyx estimates an hourly rate for one observer from the radiant's height, the Moon and the park's estimated sky brightness; it is a rough guide, and real showers vary from year to year. Lunar eclipse times come from NASA's predictions by Fred Espenak (NASA/GSFC); Nyx checks the Moon's height at the park itself. None of this changes the score.")
            block("Forecasts","Open-Meteo forecasts cover up to 16 days. Many parks share one request, using park coordinates only. Clouds are averaged over the complete window of true darkness; on nights without it, over sunset to sunrise, or 10 PM to 2 AM local time under the midnight sun. Forecasts older than 36 hours or with incomplete coverage are treated as unavailable. Weather data: Open-Meteo, CC BY 4.0. License: creativecommons.org/licenses/by/4.0/.")
            block("How sure the forecast is","For the next seven days, Nyx also asks three independent forecast models (NOAA's GFS, ECMWF's IFS and DWD's ICON) for the same dark window. When their averages are within 15 points of cloud cover they agree; within 35 they roughly agree; beyond that they disagree, and the time river draws the range of scores they allow. The score itself always uses Open-Meteo's best-match forecast. Cloud layers, the coldest hour, dew risk (air within 2 °C of its dew point) and the strongest gust come from the same seven-day forecast. Visibility is a coarse model value and appears only as a haze hint. None of these change the score.")
            block("Smoke and haze","Aerosol optical depth at 550 nm, from the CAMS global forecast (Copernicus Atmosphere Monitoring Service) through Open-Meteo's air-quality service, covers about five days. It is averaged over the dark window: below 0.1 is clear air, 0.1 to 0.25 light haze, 0.25 to 0.5 haze or smoke that makes the Milky Way look faint, and 0.5 or more heavy smoke or haze that hides faint stars. From 0.25 a caveat appears beside the score. Smoke is context, not part of the score. Air-quality data: CAMS via Open-Meteo, CC BY 4.0. You can switch this request off in Your privacy.")
            block("Parks and skyglow","The bundled NPS inventory contains 63 national parks. Bortle classes are conservative estimates, not instrument measurements. Dark-Sky designations are International Dark Sky Park certifications, cross-checked against the NPS list. Viewing coordinates are approximate, not directions. Park data: National Park Service.")
            block("Night lights from space","Light-pollution estimates use NASA Black Marble nighttime lights (VNP46A4, Román et al. 2018), public domain. Nyx adds the 2025 yearly satellite light within 300 km of each park and viewing spot, weakening with distance (Walker's law), and compares the result across the 63 parks. The same sum, split by direction, finds the light domes on the horizon; a town is named only when a known one lies near the light. It is a comparison between places, not a measurement of sky brightness: it models no terrain, haze or light colour, cannot resolve a lit lodge next to a spot, and cannot tell the darkest skies apart. The satellite misses much of the blue light of white LEDs, so towns that switched to LEDs can look darker than they are. The score keeps the conservative Bortle estimate; the satellite view is context. Growth since 2013 is shown only as a comparison between parks, and not for Alaska, lava, oil-field flaring or almost unlit places, where the change is not light pollution.")
            block("Step-free viewing","Step-free notes come from each park's accessibility pages on nps.gov, retrieved October 5, 2026. A spot is marked only where an official page says so, and each note shows the sentence it rests on and a link to the page, which opens in Safari. Spots without an official statement show nothing. Night access, gates and seasonal closures are not covered. Conditions change; check with the park.")
            block("Getting there","Access notes for parks a car cannot simply reach, by boat, plane or a limited road, come from each park's Getting there and directions pages on nps.gov, retrieved October 6, 2026. The trip planner leaves out parks reached only by boat or plane unless you include them. Schedules and seasons change; check with the park.")
            block("The map under your constellation","The faint outline of the United States beneath your stars is simplified from the US Census Bureau's cartographic boundary file of the nation (cb_2023_us_nation_20m), which is in the public domain. It is decoration, drawn at a scale where small islands disappear.")
            block("Access comes first","A score never confirms that a road or park is open. Park updates may be unavailable. Cached alerts and programs show their update time. Check with the park before traveling, especially when Nyx has not checked alerts.")
            block("Park-local time","Each park has an IANA time zone. A night runs from local noon to the following local noon, and “tonight” moves on to the coming evening once the Sun rises. Times shown on detail belong to that park, including changes for daylight saving time. The stars behind each screen are the real sky over that park in the middle of the night's darkness, from the Yale Bright Star Catalogue (Hoffleit and Warren, via NASA HEASARC); they show where the stars are, not whether clouds will hide them.")
        }.padding(24).readableColumn(WideLayout.proseWidth) }.background(NightBackground(veil:0.6)).navigationTitle("About the data").navigationBarTitleDisplayMode(.inline)
    }
    private func block(_ title:LocalizedStringKey,_ content:LocalizedStringKey)->some View { VStack(alignment:.leading,spacing:10) { Text(title).font(.system(.title2,design:.serif)).accessibilityAddTraits(.isHeader);Text(content).font(.body).lineSpacing(4).textSelection(.enabled).foregroundStyle(palette.muted) } }
}
enum Essay: String,CaseIterable,Identifiable {
    case darkness,milkyway,meteors,bortle,etiquette,access
    var id:String { rawValue }
    var title:String { switch self { case .darkness:String(localized:"A sky worth protecting");case .milkyway:String(localized:"Finding the Milky Way");case .meteors:String(localized:"Watching a meteor shower");case .bortle:String(localized:"Reading the Bortle scale");case .etiquette:String(localized:"Sharing the night");case .access:String(localized:"Stargazing for everyone") } }
    var subtitle:String { switch self { case .darkness:String(localized:"Why darkness deserves care");case .milkyway:String(localized:"When, where and how to look");case .meteors:String(localized:"Radiants, rates and patience");case .bortle:String(localized:"Understand artificial sky brightness");case .etiquette:String(localized:"Leave room for everyone to look up");case .access:String(localized:"Dark skies by sound, touch and red light") } }
    var symbol:String { switch self { case .darkness:"sparkles";case .milkyway:"sparkle";case .meteors:"sparkles.2";case .bortle:"circle.lefthalf.filled";case .etiquette:"moon.stars";case .access:"accessibility" } }
    /// About 200 words a minute, never less than one.
    var minutes:Int { max(1,Int((Double(content.split(whereSeparator:\.isWhitespace).count)/200).rounded())) }
    var content:String { switch self { case .darkness:String(localized:"essay.darkness");case .milkyway:String(localized:"essay.milkyway");case .meteors:String(localized:"essay.meteors");case .bortle:String(localized:"essay.bortle");case .etiquette:String(localized:"essay.etiquette");case .access:String(localized:"essay.access") } }
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
struct LearnView:View {
    @Environment(\.nyx) private var palette
    var body:some View {
        ScrollView { VStack(alignment:.leading,spacing:26) { Eyebrow(text:"A little knowledge. A wider sky.");Text("Learn to look up").font(.system(.largeTitle,design:.serif));LazyVGrid(columns:[GridItem(.adaptive(minimum:300),spacing:22,alignment:.top)],spacing:26) { ForEach(Essay.allCases) { essay in NavigationLink { EssayView(essay:essay) } label:{ Panel { VStack(alignment:.leading,spacing:0) { VStack(alignment:.leading,spacing:22) { EssayIcon(essay:essay,size:28);Text(essay.title).font(.system(.title2,design:.serif));Text(essay.subtitle).font(.subheadline).foregroundStyle(palette.muted) };Spacer(minLength:22);HStack { Text("\(essay.minutes) minute read").font(.caption);Spacer();Image(systemName:"arrow.up.right").accessibilityHidden(true) }.foregroundStyle(palette.ink.opacity(palette.nightVision ? 1 : 0.86)) }.frame(maxHeight:.infinity,alignment:.top) }.frame(maxHeight:.infinity) }.buttonStyle(.plain).hoverEffect(.lift) } };NavigationLink { AboutDataView() } label:{ HStack { Label("About the data",systemImage:"info.circle");Spacer();Image(systemName:"chevron.forward").font(.caption.weight(.semibold)).foregroundStyle(palette.muted).accessibilityHidden(true) }.frame(maxWidth:.infinity,minHeight:44,alignment:.leading).contentShape(Rectangle()) }.foregroundStyle(palette.ink) }.padding(24).readableColumn(1080) }.background(NightBackground()).navigationTitle("Learn").navigationBarTitleDisplayMode(.inline)
    }
}
struct EssayView:View {
    @Environment(\.nyx) private var palette
    let essay:Essay
    var body:some View {
        ScrollView { VStack(alignment:.leading,spacing:28) { EssayIcon(essay:essay,size:48);Text(essay.title).font(.system(.largeTitle,design:.serif));ForEach(Array(essay.content.components(separatedBy:"\n\n").dropFirst().enumerated()),id:\.offset) { _,paragraph in Text(paragraph).font(.system(.body,design:.serif)).lineSpacing(7).foregroundStyle(palette.ink).textSelection(.enabled) };if OnDeviceGuide.available { NavigationLink("Explain this another way") { GuideView(mode:.learn(essay)) }.buttonStyle(.bordered) } }.padding(26).readableColumn(WideLayout.proseWidth) }.background(NightBackground(veil:0.6)).navigationTitle("Learn").navigationBarTitleDisplayMode(.inline)
    }
}
struct OnboardingView:View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.nyx) private var palette
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.nyxReduceMotion) private var forcedReduceMotion
    private var reduceMotion:Bool { systemReduceMotion || forcedReduceMotion }
    @State private var page=DebugScenario.onboardingPage
    let finish:()->Void
    private let titles:[LocalizedStringKey]=["Make room\nfor the night","A darker sky.\nA clearer plan.","The night is yours."]
    private let messages:[LocalizedStringKey]=["Find the national parks and nights that give the stars their best chance.","Moonlight, clouds, artificial light and the length of darkness become one score. Every estimate tells you what is still unknown.","Nyx has no account, no ads, no tracking. Your journal never leaves this phone."]
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
                Button(page==2 ? "Begin exploring" : "Continue") { if page==2 { finish() } else { withAnimation(reduceMotion ? nil : NyxMotion.spring) { page+=1 } } }
                    .buttonStyle(.borderedProminent).foregroundStyle(Color.black).controlSize(.large)
            }.padding(.bottom,28)
        }.background(NightBackground(score:page==1 ? 94 : nil)).foregroundStyle(palette.ink)
    }
    @ViewBuilder private func art(_ index:Int)->some View {
        switch index {
        case 0: OnboardingMoon(daysAfterNew:3).frame(width:170,height:170).padding(.vertical,24)
        case 1: ScoreAnatomy(active:page==1)
        default: OnboardingMoon(daysAfterNew:0).frame(width:170,height:170).padding(.vertical,24)
        }
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
/// The four parts of the Darkness Score filling in, one after another, as the example score counts up.
private struct ScoreAnatomy:View {
    @Environment(\.nyx) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.nyxReduceMotion) private var forcedReduceMotion
    let active:Bool
    @State private var filled=0
    private let parts:[(LocalizedStringKey,Int,Int)]=[("Moonlight",40,38),("Clouds",25,24),("Light pollution",20,18),("Length of darkness",15,14)]
    var body:some View {
        VStack(spacing:10) {
            CelestialGauge(score:94).id(active).frame(height:typeSize.isAccessibilitySize ? nil : 188) // fresh count-up each time the page arrives
            VStack(spacing:6) {
                ForEach(parts.indices,id:\.self) { i in
                    VStack(alignment:.leading,spacing:5) {
                        HStack { Text(parts[i].0).font(.caption);Spacer();Text("\(parts[i].1)%").font(.caption.monospacedDigit()).foregroundStyle(palette.muted) }
                        GeometryReader { proxy in
                            ZStack(alignment:.leading) {
                                Capsule().fill(palette.line)
                                Capsule().fill(palette.accent).frame(width:i<filled ? proxy.size.width*Double(parts[i].2)/Double(parts[i].1) : 0)
                            }
                        }.frame(height:3)
                    }
                }
            }.frame(maxWidth:320)
            Text("Example night").font(.caption).foregroundStyle(palette.muted)
        }
        .accessibilityElement(children:.ignore)
        .accessibilityLabel("Example score 94 out of 100. Moonlight counts for 40 percent, clouds 25, light pollution 20, and the length of darkness 15.")
        .task(id:active) {
            guard active else { filled=0; return }
            if systemReduceMotion || forcedReduceMotion { filled=parts.count; return }
            for i in 1...parts.count {
                try? await Task.sleep(for:.milliseconds(260))
                withAnimation(NyxMotion.spring) { filled=i }
            }
        }
    }
}
#Preview("Learn") { NavigationStack { LearnView() }.preferredColorScheme(.dark) }
#Preview("Onboarding") { OnboardingView {}.environment(PlanModel()).preferredColorScheme(.dark) }
#Preview("Privacy AX5") { NavigationStack { PrivacyView() }.environment(PlanModel()).dynamicTypeSize(.accessibility5).preferredColorScheme(.dark) }
