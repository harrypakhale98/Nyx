import SwiftUI

struct SettingsView:View {
    @Environment(\.nyx) private var palette
    @Environment(PlanModel.self) private var model
    @AppStorage("nightVision",store:SharedSettings.defaults) private var nightVision=false
    @AppStorage("notificationsEnabled") private var notifications=false
    @State private var explainNotifications=false
    @State private var permissionMessage:String?
    @State private var replay=false
    var body:some View {
        Form {
            Section("In the dark") { Toggle("Night-vision mode",isOn:$nightVision);Text("A red palette reduces glare. Lower the screen brightness too; Nyx does not change it for you.").font(.caption).foregroundStyle(palette.muted) }
            Section("Saved parks") {
                Toggle("Promising-night reminders",isOn:Binding(get:{notifications},set:{ value in if value { explainNotifications=true } else { notifications=false;Task { await NotificationScheduler().remove() } } }))
                Text("Local reminders for saved parks with scores of 90 or higher. Forecasts may change. Upcoming nights are recalculated whenever Nyx opens.").font(.caption).foregroundStyle(palette.muted)
                if let permissionMessage { Text(permissionMessage).font(.caption) }
            }
            Section("Your iPhone") { NavigationLink("Your privacy") { PrivacyView() };NavigationLink("About the data") { AboutDataView() };LabeledContent("Distance units",value:String(localized:"Device locale"));Text("Distances use your region's units. Radius is always a straight line.").font(.caption).foregroundStyle(palette.muted) }
            Section { Button("Replay the introduction") { replay=true };LabeledContent("Version",value:"1.0") }
        }.navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented:$explainNotifications) { PermissionExplainer(symbol:"bell",title:"A night worth making time for",message:"Nyx can remind you about promising nights at saved parks. These notifications are scheduled on this iPhone. They are estimates, not confirmations of clear skies or access.",action:"Enable reminders") {
                explainNotifications=false
                Task { notifications=await NotificationScheduler().requestAuthorization(); if !notifications { permissionMessage=String(localized:"Reminders are off. You can enable them in iPhone Settings.") } }
            }.nyxPresentation() }
            .sheet(isPresented:$replay) { OnboardingView { replay=false }.nyxPresentation() }
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
                Toggle("Cloud forecasts",isOn:$model.weatherEnabled)
                Text("Requests go to api.open-meteo.com using the park's coordinates, never your device location. The service receives network information such as your IP address.").font(.caption).foregroundStyle(palette.muted)
                Toggle("Park alerts and programs",isOn:$model.npsEnabled)
                Text("With an NPS key, requests go to developer.nps.gov for the selected park. The service receives network information such as your IP address.").font(.caption).foregroundStyle(palette.muted)
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
            block("Forecasts","Open-Meteo forecasts cover up to 16 days. Clouds are averaged over the complete dark window. Forecasts older than 36 hours or with incomplete coverage are treated as unavailable. Smoke, haze, transparency and seeing are not part of this score. Weather data: Open-Meteo, CC BY 4.0.")
            block("Parks and skyglow","The bundled NPS inventory contains 63 national parks. Bortle classes are conservative estimates, not instrument measurements. Designations are checked against the NPS dark-sky list. Viewing coordinates are approximate, not directions. Park data: National Park Service.")
            block("Access comes first","A score never confirms that a road or park is open. Alerts and ranger programs require an NPS key and are cached. Their update time is shown. Check with the park before traveling, especially when Nyx has not checked alerts.")
            block("Park-local time","Each park has an IANA time zone. A night runs from local noon to the following local noon. Times shown on detail belong to that park, including changes for daylight saving time. Milky Way guidance is seasonal, not a precise visibility forecast.")
        }.padding(24) }.background(NightBackground()).navigationTitle("About the data").navigationBarTitleDisplayMode(.inline)
    }
    private func block(_ title:LocalizedStringKey,_ content:LocalizedStringKey)->some View { VStack(alignment:.leading,spacing:10) { Text(title).font(.system(.title2,design:.serif));Text(content).font(.body).lineSpacing(4).foregroundStyle(palette.muted) } }
}
enum Essay: String,CaseIterable,Identifiable {
    case darkness,bortle,etiquette
    var id:String { rawValue }
    var title:String { switch self { case .darkness:String(localized:"A sky worth protecting");case .bortle:String(localized:"Reading the Bortle scale");case .etiquette:String(localized:"Sharing the night") } }
    var subtitle:String { switch self { case .darkness:String(localized:"Why darkness deserves care");case .bortle:String(localized:"Understand artificial sky brightness");case .etiquette:String(localized:"Leave room for everyone to look up") } }
    var symbol:String { switch self { case .darkness:"sparkles";case .bortle:"circle.lefthalf.filled";case .etiquette:"moon.stars" } }
    var content:String { switch self { case .darkness:String(localized:"essay.darkness");case .bortle:String(localized:"essay.bortle");case .etiquette:String(localized:"essay.etiquette") } }
}
struct LearnView:View {
    @Environment(\.nyx) private var palette
    var body:some View {
        ScrollView { VStack(alignment:.leading,spacing:26) { Eyebrow(text:"A little knowledge. A wider sky.");Text("Learn to look up").font(.system(.largeTitle,design:.serif));ForEach(Essay.allCases) { essay in NavigationLink { EssayView(essay:essay) } label:{ Panel { VStack(alignment:.leading,spacing:22) { Image(systemName:essay.symbol).font(.system(size:28,weight:.ultraLight)).foregroundStyle(palette.accent);Text(essay.title).font(.system(.title2,design:.serif));Text(essay.subtitle).font(.subheadline).foregroundStyle(palette.muted);HStack { Text("4 minute read").font(.caption);Spacer();Image(systemName:"arrow.up.right") }.foregroundStyle(palette.muted) } } }.buttonStyle(.plain) };NavigationLink("About the data") { AboutDataView() } }.padding(24) }.background(NightBackground()).navigationTitle("Learn").navigationBarTitleDisplayMode(.inline)
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
    @Environment(\.nyx) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page=0
    let finish:()->Void
    private let titles:[LocalizedStringKey]=["Make room\nfor the night","A darker sky.\nA clearer plan.","The night is yours."]
    private let messages:[LocalizedStringKey]=["Find the national parks and nights that give the stars their best chance.","Moonlight, clouds, artificial light and the length of darkness become one score. Every estimate tells you what is still unknown.","Nyx has no account, no ads, no tracking. Your journal never leaves this phone."]
    var body:some View {
        ScrollView { VStack(spacing:28) {
            HStack { Text("NYX").font(.caption).tracking(8);Spacer();Button("Skip") { finish() } }.padding(.bottom,14)
            if page==1 { CelestialGauge(score:94,hasForecast:false).frame(height:240) }
            else { MoonDisc(illumination:page==0 ? 0.18 : 0.06,waxing:true).frame(width:170,height:170).padding(.vertical,35) }
            Text(titles[page]).font(.system(.largeTitle,design:.serif)).multilineTextAlignment(.center)
            Text(messages[page]).font(.body).foregroundStyle(palette.muted).multilineTextAlignment(.center).lineSpacing(4)
            HStack(spacing:12) { ForEach(0..<3,id:\.self) { i in Circle().fill(i==page ? palette.accent : palette.line).frame(width:5,height:5) } }.accessibilityLabel("Introduction, page \(page+1) of 3")
            Button(page==2 ? "Begin exploring" : "Continue") { if page==2 { finish() } else { withAnimation(reduceMotion ? nil : NyxMotion.spring) { page+=1 } } }.buttonStyle(.borderedProminent).controlSize(.large)
        }.padding(28) }.background(NightBackground()).foregroundStyle(palette.ink)
    }
}
#Preview("Learn") { NavigationStack { LearnView() }.preferredColorScheme(.dark) }
#Preview("Onboarding") { OnboardingView {}.preferredColorScheme(.dark) }
#Preview("Privacy AX5") { NavigationStack { PrivacyView() }.environment(PlanModel()).dynamicTypeSize(.accessibility5).preferredColorScheme(.dark) }
