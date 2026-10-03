import SwiftUI

struct TonightView: View {
    @Environment(PlanModel.self) private var model
    @Environment(\.nyx) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.nyxReduceMotion) private var forcedReduceMotion
    @State private var shooting=0.0
    @State private var refreshed=0
    @Environment(\.openURL) private var openURL
    private var location:LocationService { model.location }
    @State private var explainLocation=false
    @State private var chooseHome=false
    @Namespace private var zoom
    private var candidates:[Park] { model.nearby(latitude:location.latitude,longitude:location.longitude) }
    private var best:[Park] { Array(model.ranked(candidates).prefix(5)) }
    var body: some View {
        @Bindable var model=model
        ScrollView {
            VStack(alignment:.leading,spacing:22) {
                // Decorative at accessibility sizes, where it would push the answer below the fold.
                if !typeSize.isAccessibilitySize { HStack(alignment:.top) {
                    VStack(alignment:.leading,spacing:10) { Eyebrow(text:"The night is waiting");Text("Where the sky\nis darkest").font(.system(.title,design:.serif)).fixedSize(horizontal:false,vertical:true) }
                    Spacer(minLength:8)
                    if let home=model.home { MoonView(geometry:AstronomyEngine().moon(for:model.night(home)).geometry).frame(width:40,height:40).padding(.top,8) }
                } }
                if DebugScenario.state=="loading" { ConstellationLoader().frame(maxWidth:.infinity) }
                else if best.isEmpty || DebugScenario.state=="empty" { CalmState(symbol:"moon.stars",title:"A little farther from here",message:"No national parks fall inside this radius. Widen it or choose a different starting park.");startingPoint }
                else if let park=best.first {
                    let night=model.night(park)
                    VStack(spacing:10) {
                        Eyebrow(text:"Your darkest nearby sky")
                        NavigationLink(value:park) { HStack { Text(park.shortName).font(.system(.title2,design:.serif));Image(systemName:"arrow.up.right").font(.subheadline) }.padding(.vertical,14).padding(.horizontal,22).modifier(ParkPill()) }.buttonStyle(.plain).matchedTransitionSource(id:park.id,in:zoom)
                        CelestialGauge(score:night.score.value,hasForecast:night.score.hasForecast).frame(height:typeSize.isAccessibilitySize ? nil : 240)
                        Text(night.score.hasForecast ? String(localized:"\(park.dayLabel(night.id)) · forecast included") : String(localized:"Moon and darkness only. Clouds are unknown.")).font(.caption).foregroundStyle(palette.muted).multilineTextAlignment(.center)
                        if let closure=model.closure(park) { Label(closure,systemImage:"exclamationmark.triangle").font(.subheadline).foregroundStyle(palette.accent).multilineTextAlignment(.center).padding(.horizontal,12) }
                        else { Text(model.alertSummary(park)).font(.caption).foregroundStyle(palette.muted).multilineTextAlignment(.center).padding(.horizontal,12) }
                    }.frame(maxWidth:.infinity)
                    startingPoint
                    if best.count>1 {
                        Eyebrow(text:"More skies within reach")
                        ForEach(Array(best.dropFirst())) { park in NavigationLink(value:park) { ParkRow(night:model.night(park),closure:model.closure(park)) }.buttonStyle(.plain).matchedTransitionSource(id:park.id,in:zoom);Divider().overlay(palette.line) }
                    }
                    Text("Each park uses its own local date. Estimates can change when cloud forecasts arrive.").font(.caption).foregroundStyle(palette.muted)
                }
                if DebugScenario.state=="error" || DebugScenario.state=="offline" || (model.weatherEnabled && candidates.contains { model.staleForecasts.contains($0.id) }) { Panel { Label("Offline calculations are ready. Refresh when a connection returns.",systemImage:"wifi.slash").font(.subheadline).foregroundStyle(palette.muted) } }
                if OnDeviceGuide.available { NavigationLink { GuideView(mode:.planning) } label:{ Label("Ask Nyx",systemImage:"sparkles") }.buttonStyle(.bordered) }
            }.padding(24)
        }.background(NightBackground(seed:model.homeID,score:best.first.map { model.night($0).score.value })).navigationTitle("Tonight").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement:.topBarTrailing) { NavigationLink { SettingsView() } label:{ Image(systemName:"slider.horizontal.3") }.accessibilityLabel("Settings") } }
            .navigationDestination(for:Park.self) { park in ParkDetailView(park:park).navigationTransition(.zoom(sourceID:park.id,in:zoom)) }
            .sheet(isPresented:$chooseHome) { NavigationStack { ParkPickerView(selection:Binding(get:{model.homeID},set:{ model.homeID=$0;location.clear() })) }.nyxPresentation().presentationDetents([.large]) }
            .sheet(isPresented:$explainLocation) { PermissionExplainer(symbol:"location",title:"Find a sky nearby",message:"Nyx uses your location once to find parks within a straight-line radius. It stays on this iPhone. You can also choose a starting park.",action:"Use my location") { explainLocation=false;location.request() }.nyxPresentation() }
            .task(id:model.homeID+String(model.radiusMiles)+(location.latitude?.description ?? "manual")) { await model.refresh(candidates) }
            .overlay(alignment:.top) { ShootingStar(progress:shooting).frame(height:170) }
            .sensoryFeedback(.selection,trigger:refreshed)
            .refreshable {
                if !systemReduceMotion && !forcedReduceMotion && shooting==0 {
                    withAnimation(.spring(response:0.9,dampingFraction:1)) { shooting=1 } completion:{ shooting=0 }
                }
                await model.refresh(candidates,force:true);refreshed+=1
            }
    }
    /// The starting point is either a chosen park or the device location, never both.
    private var startingPoint:some View {
        Panel { VStack(alignment:.leading,spacing:12) {
            HStack(alignment:.center) {
                Button { chooseHome=true } label:{
                    if location.latitude==nil { Label(String(localized:"From \(model.home?.shortName ?? "")"),systemImage:"mappin.and.ellipse") }
                    else { Label("From your location",systemImage:"location.fill") }
                }.font(.subheadline).frame(minHeight:44).contentShape(Rectangle()).accessibilityHint("Choose a starting park")
                Spacer(minLength:8)
                if location.locating { ProgressView() }
                else if location.denied { Button { if let url=URL(string:UIApplication.openSettingsURLString) { openURL(url) } } label:{ Label("Settings",systemImage:"location.slash").font(.subheadline) }.buttonStyle(.bordered).accessibilityLabel("Turn on location in Settings") }
                else if location.latitude==nil { Button { explainLocation=true } label:{ Label("Near me",systemImage:"location").font(.subheadline) }.buttonStyle(.bordered).accessibilityLabel("Use my location") }
            }
            ViewThatFits(in:.horizontal) {
                HStack { radiusPicker;Text("as the crow flies").font(.caption).foregroundStyle(palette.muted) }
                VStack(alignment:.leading,spacing:8) { radiusPicker;Text("as the crow flies").font(.caption).foregroundStyle(palette.muted) }
            }
            if location.denied || DebugScenario.state=="no-location" { Text("Location is off. A starting park works just as well.").font(.caption).foregroundStyle(palette.muted) }
            if let message=location.message { Text(message).font(.caption).foregroundStyle(palette.muted) }
        } }
    }
    private var radiusPicker:some View {
        @Bindable var model=model
        return Picker("Radius",selection:$model.radiusMiles) {
            ForEach([100.0,200,500,1000],id:\.self) { miles in Text(Measurement(value:miles,unit:UnitLength.miles),format:.measurement(width:.abbreviated,usage:.road)).fixedSize().tag(miles) }
        }.pickerStyle(.menu).fixedSize(horizontal:true,vertical:false)
    }
}
/// Liquid Glass normally; a solid dark capsule in night vision, where the red filter
/// flattens glass toward the text colour and costs contrast.
private struct ParkPill:ViewModifier {
    @Environment(\.nyx) private var palette
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder func body(content:Content)->some View {
        if palette.nightVision || reduceTransparency {
            content.background(Color.black,in:Capsule()).overlay(Capsule().stroke(palette.line,lineWidth:0.8))
        } else { content.glassEffect() }
    }
}
struct ParkPickerView: View {
    @Environment(PlanModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Binding var selection:String
    @State private var search=""
    var body: some View {
        List(model.parks.filter { search.isEmpty || $0.matches(search) }) { park in
            Button { selection=park.id;dismiss() } label:{ HStack { VStack(alignment:.leading) { Text(park.shortName);Text(park.state).font(.caption).foregroundStyle(.secondary) };Spacer();if selection==park.id { Image(systemName:"checkmark") } } }.tint(.primary)
        }.searchable(text:$search,prompt:"Park or state").navigationTitle("Starting park")
            .toolbar { ToolbarItem(placement:.cancellationAction) { Button("Cancel") { dismiss() } } }
    }
}
struct PermissionExplainer: View {
    @Environment(\.dismiss) private var dismiss
    let symbol:String
    let title:LocalizedStringKey
    let message:LocalizedStringKey
    let action:LocalizedStringKey
    let proceed:()->Void
    var body: some View {
        NavigationStack { ScrollView { VStack(spacing:24) { CalmState(symbol:symbol,title:title,message:message);Button(action,action:proceed).buttonStyle(.borderedProminent).foregroundStyle(Color.black);Button("Continue without it") { dismiss() } }.padding(24) }.background(Color.black).toolbar { ToolbarItem(placement:.cancellationAction) { Button("Close") { dismiss() } } } }.presentationDetents([.medium,.large])
    }
}
#Preview("Tonight") { NavigationStack { TonightView() }.environment(PlanModel()).preferredColorScheme(.dark) }
