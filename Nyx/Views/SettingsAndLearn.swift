import SwiftUI

struct SettingsView:View {
    @Environment(\.nyx) private var palette
    @Environment(PlanModel.self) private var model
    @AppStorage("nightVision",store:SharedSettings.defaults) private var nightVision=false
    @AppStorage("notificationsEnabled") private var notifications=false
    @State private var explainNotifications=false
    @State private var permissionMessage:String?
    @State private var replay=false
    @Environment(\.scenePhase) private var scenePhase
    var body:some View {
        Form {
            Section("In the dark") { Toggle("Night-vision mode",isOn:$nightVision).tint(palette.controlTint);Text("A red palette reduces glare. Lower the screen brightness too; Nyx does not change it for you.").font(.caption).foregroundStyle(palette.muted) }
            Section("Saved parks") {
                Toggle("Promising-night reminders",isOn:Binding(get:{notifications},set:{ value in if value { explainNotifications=true } else { notifications=false;Task { await NotificationScheduler().remove() } } })).tint(palette.controlTint)
                Text("Local reminders for saved parks with scores of 90 or higher. Forecasts may change. Upcoming nights are recalculated whenever Nyx opens.").font(.caption).foregroundStyle(palette.muted)
                if let permissionMessage { Text(permissionMessage).font(.caption) }
            }
            Section("Your iPhone") { NavigationLink("Your privacy") { PrivacyView() };NavigationLink("About the data") { AboutDataView() };LabeledContent("Distance units",value:String(localized:"Device locale"));Text("Distances use your region's units. Radius is always a straight line.").font(.caption).foregroundStyle(palette.muted) }
            Section { Button("Replay the introduction") { replay=true };LabeledContent("Version",value:Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "") }
        }.navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
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
struct PrivacyView:View {
    @Environment(\.nyx) private var palette
    @Environment(PlanModel.self) private var model
    var body:some View {
        @Bindable var model=model
        Form {
            Section { Text("Nyx has no account, no ads, no tracking. Your journal never leaves this phone.").font(.system(.title3,design:.serif));Text("Saved parks, journal entries and selected photos are stored on this iPhone. iCloud sync is not used. Your device backup settings may include app data.") }
            Section("Optional data updates") {
                Toggle("Cloud forecasts",isOn:$model.weatherEnabled).tint(palette.controlTint)
                Text("Requests go to api.open-meteo.com using the park's coordinates, never your device location. The service receives network information such as your IP address.").font(.caption).foregroundStyle(palette.muted)
                Toggle("Park alerts and programs",isOn:$model.npsEnabled).tint(palette.controlTint)
                Text("When park updates are available, requests go to developer.nps.gov for the selected park. The service receives network information such as your IP address.").font(.caption).foregroundStyle(palette.muted)
            }
            Section { Text("Turning updates off prevents new requests. Previously cached data remains available. Moon, twilight, calendar, saved parks and the journal work offline.");Text("Location is used only while you use Nyx, to compare park distances on this iPhone. Photos are accessed only through the system photo picker. Reminders are local.") }
        }.navigationTitle("Your privacy").navigationBarTitleDisplayMode(.inline)
    }
}
struct AboutDataView:View {
    @Environment(\.nyx) private var palette
    var body:some View {
        ScrollView { VStack(alignment:.leading,spacing:24) {
            Text("An honest view of the sky").font(.system(.largeTitle,design:.serif))
            block("The score","Moonlight contributes 40%, clouds 25%, estimated light pollution 20%, and the length of true darkness 15%. Without a cloud forecast, the other weights are scaled to 100. No true darkness caps a night below 40.")
            block("Moon and twilight","Solar timing uses NOAA approximations. Moonrise and moonset use a low-precision Meeus-style position; allow about 15 minutes, and more near the poles or a blocked horizon. Moon illumination corrects the mean 29.53-day cycle with the Moon’s calculated position and is approximate. Terrain and atmospheric conditions can shift visible rise and set times.")
            block("Forecasts","Open-Meteo forecasts cover up to 16 days. Clouds are averaged over the complete dark window. Forecasts older than 36 hours or with incomplete coverage are treated as unavailable. Smoke, haze, transparency and seeing are not part of this score. Weather data: Open-Meteo, CC BY 4.0. License: creativecommons.org/licenses/by/4.0/.")
            block("Parks and skyglow","The bundled NPS inventory contains 63 national parks. Bortle classes are conservative estimates, not instrument measurements. Designations are checked against the NPS dark-sky list. Viewing coordinates are approximate, not directions. Park data: National Park Service.")
            block("Access comes first","A score never confirms that a road or park is open. Park updates may be unavailable. Cached alerts and programs show their update time. Check with the park before traveling, especially when Nyx has not checked alerts.")
            block("Park-local time","Each park has an IANA time zone. A night runs from local noon to the following local noon. Times shown on detail belong to that park, including changes for daylight saving time. Milky Way guidance is seasonal, not a precise visibility forecast.")
        }.padding(24) }.background(NightBackground()).navigationTitle("About the data").navigationBarTitleDisplayMode(.inline)
    }
    private func block(_ title:LocalizedStringKey,_ content:LocalizedStringKey)->some View { VStack(alignment:.leading,spacing:10) { Text(title).font(.system(.title2,design:.serif));Text(content).font(.body).lineSpacing(4).textSelection(.enabled).foregroundStyle(palette.muted) } }
}
enum Essay: String,CaseIterable,Identifiable {
    case darkness,bortle,etiquette
    var id:String { rawValue }
    var title:String { switch self { case .darkness:String(localized:"A sky worth protecting");case .bortle:String(localized:"Reading the Bortle scale");case .etiquette:String(localized:"Sharing the night") } }
    var subtitle:String { switch self { case .darkness:String(localized:"Why darkness deserves care");case .bortle:String(localized:"Understand artificial sky brightness");case .etiquette:String(localized:"Leave room for everyone to look up") } }
    var symbol:String { switch self { case .darkness:"sparkles";case .bortle:"circle.lefthalf.filled";case .etiquette:"moon.stars" } }
    /// About 200 words a minute, never less than one.
    var minutes:Int { max(1,Int((Double(content.split(whereSeparator:\.isWhitespace).count)/200).rounded())) }
    var content:String { switch self { case .darkness:String(localized:"essay.darkness");case .bortle:String(localized:"essay.bortle");case .etiquette:String(localized:"essay.etiquette") } }
}
struct LearnView:View {
    @Environment(\.nyx) private var palette
    var body:some View {
        ScrollView { VStack(alignment:.leading,spacing:26) { Eyebrow(text:"A little knowledge. A wider sky.");Text("Learn to look up").font(.system(.largeTitle,design:.serif));ForEach(Essay.allCases) { essay in NavigationLink { EssayView(essay:essay) } label:{ Panel { VStack(alignment:.leading,spacing:22) { Image(systemName:essay.symbol).font(.system(size:28,weight:.ultraLight)).foregroundStyle(palette.accent);Text(essay.title).font(.system(.title2,design:.serif));Text(essay.subtitle).font(.subheadline).foregroundStyle(palette.muted);HStack { Text("\(essay.minutes) minute read").font(.caption);Spacer();Image(systemName:"arrow.up.right") }.foregroundStyle(palette.muted) } } }.buttonStyle(.plain) };NavigationLink("About the data") { AboutDataView() } }.padding(24) }.background(NightBackground()).navigationTitle("Learn").navigationBarTitleDisplayMode(.inline)
    }
}
struct EssayView:View {
    @Environment(\.nyx) private var palette
    let essay:Essay
    var body:some View {
        ScrollView { VStack(alignment:.leading,spacing:28) { Image(systemName:essay.symbol).font(.system(size:48,weight:.ultraLight)).foregroundStyle(palette.accent);Text(essay.title).font(.system(.largeTitle,design:.serif));ForEach(Array(essay.content.components(separatedBy:"\n\n").dropFirst().enumerated()),id:\.offset) { _,paragraph in Text(paragraph).font(.system(.body,design:.serif)).lineSpacing(7).foregroundStyle(palette.ink).textSelection(.enabled) };if OnDeviceGuide.available { NavigationLink("Explain this another way") { GuideView(mode:.learn(essay)) }.buttonStyle(.bordered) } }.padding(26) }.background(NightBackground()).navigationTitle("Learn").navigationBarTitleDisplayMode(.inline)
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
            HStack { Text("NYX").font(.caption).tracking(8).accessibilityHidden(true);Spacer();Button("Skip") { finish() } }.padding(.horizontal,28).padding(.top,28)
            TabView(selection:$page) {
                ForEach(0..<3,id:\.self) { index in
                    ScrollView {
                        VStack(spacing:28) {
                            art(index)
                            Text(titles[index]).font(.system(.largeTitle,design:.serif)).multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true)
                            Text(messages[index]).font(.body).foregroundStyle(palette.muted).multilineTextAlignment(.center).lineSpacing(4).fixedSize(horizontal:false,vertical:true)
                        }.padding(28).frame(maxWidth:.infinity)
                    }.scrollBounceBehavior(.basedOnSize).tag(index)
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
        case 0: MoonDisc(illumination:0.18,waxing:true).frame(width:170,height:170).padding(.vertical,24)
        case 1: ScoreAnatomy(active:page==1)
        default: MoonDisc(illumination:0,waxing:true).frame(width:170,height:170).padding(.vertical,24)
        }
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
        VStack(spacing:18) {
            CelestialGauge(score:94).id(active).frame(height:typeSize.isAccessibilitySize ? nil : 210) // fresh count-up each time the page arrives
            VStack(spacing:10) {
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
#Preview("Onboarding") { OnboardingView {}.preferredColorScheme(.dark) }
#Preview("Privacy AX5") { NavigationStack { PrivacyView() }.environment(PlanModel()).dynamicTypeSize(.accessibility5).preferredColorScheme(.dark) }
