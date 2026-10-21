import SwiftUI

/// Where every distance in reach is measured from, one for Tonight and Plan: a chosen park, a city or
/// town, or the device location, one at a time, and the one radius (`PlanModel.radiusMeters`).
/// "From Joshua Tree · 200 mi ⌃" on the first line; how the distance is measured under it, with Near
/// me trailing that line in full words. Below other content it carries its own heading, so the
/// headings rotor finds it. The screen showing it presents the picker and the location explainer
/// (`StartingPointSheets`).
struct StartingPointPanel: View {
    @Environment(PlanModel.self) private var model
    @Environment(\.nyx) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.openURL) private var openURL
    @ScaledMetric(relativeTo:.subheadline) private var dotSize=3.0
    var heading=false
    /// Opens the starting-point picker.
    let choose:()->Void
    /// Near me: the explainer first, or the location itself (`StartingPointSheets.nearMe`).
    let nearMe:()->Void
    private var location:LocationService { model.location }
    var body: some View {
        if heading { Eyebrow(text:"Starting point") }
        Panel { VStack(alignment:.leading,spacing:0) {
            ViewThatFits(in:.horizontal) {
                HStack(spacing:6) { origin(wraps:false); dot; radiusMenu }
                // A long name, or accessibility sizes: the name wraps and the radius goes underneath.
                VStack(alignment:.leading,spacing:4) { origin(wraps:true); radiusMenu }
            }
            ViewThatFits(in:.horizontal) {
                HStack(spacing:8) { crowFlies; Spacer(minLength:8); locationControl }
                VStack(alignment:.leading,spacing:8) { crowFlies; locationControl }
            }
            if location.denied || DebugScenario.state=="no-location" { Text("Location is off. Choose your city or the park closest to you.").font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true).padding(.top,8) }
            if let message=location.message { Text(message).font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true).padding(.top,8) }
        }
        // The layouts settle on their first pass; a surrounding animation must not morph one into another.
        .transaction { $0.animation=nil }
        // One container, so the accessibility audit can find the row (`startingPoint`).
        .accessibilityElement(children:.contain).accessibilityIdentifier("startingPoint") }
    }
    /// Read on its own after the radius ("Radius, 200 mi", then "as the crow flies"): visible text
    /// is never hidden from VoiceOver, which the accessibility audit checks wherever the panel shows. It keeps the starting point's icon column (the same symbol, hidden, at the same size), so its
    /// words start under "From", not under the pin; at accessibility sizes, where the radius sits at
    /// the leading edge under a wrapped name, it aligns with the radius instead.
    private var crowFlies: some View {
        Label {
            Text("as the crow flies").font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
        } icon:{ if !typeSize.isAccessibilitySize { Image(systemName:originSymbol).hidden().accessibilityHidden(true) } }
        .font(.subheadline)
    }
    /// The starting point's symbol: a pin for a park, a building for a city or town, the arrow for the device.
    private var originSymbol:String { location.latitude != nil ? "location.fill" : model.homePlace == nil ? "mappin.and.ellipse" : "building.2" }
    /// The separator between the starting point and its radius, drawn as a shape rather than a "·"
    /// glyph: a four-point character is mostly anti-aliasing, which the contrast audit measures as text.
    private var dot: some View { Circle().fill(palette.muted).frame(width:dotSize,height:dotSize).accessibilityHidden(true) }
    private func origin(wraps:Bool)->some View {
        Button { choose() } label:{
            Group {
                if location.latitude==nil { Label(String(localized:"From \(model.homePlace?.label ?? model.originName)"),systemImage:originSymbol) }
                else { Label("From your location",systemImage:originSymbol) }
            }.multilineTextAlignment(.leading).fixedSize(horizontal:!wraps,vertical:true)
        }.font(.subheadline).frame(minHeight:44).contentShape(Rectangle()).accessibilityHint("Choose a city, town or park to start from")
    }
    /// Near me (or Settings when location is off), always in words: it is the main way into location.
    @ViewBuilder private var locationControl:some View {
        if location.locating { ProgressView().accessibilityLabel("Finding your location") }
        else if location.denied { Button { if let url=URL(string:UIApplication.openSettingsURLString) { openURL(url) } } label:{ Label("Settings",systemImage:"location.slash").font(.subheadline).frame(minHeight:30) }.buttonStyle(.bordered).fixedSize(horizontal:!typeSize.isAccessibilitySize,vertical:true).accessibilityLabel("Turn on location in Settings").accessibilityInputLabels([Text("Settings"),Text("Turn on location")]) }
        else if location.latitude==nil { Button { nearMe() } label:{ Label("Near me",systemImage:"location").font(.subheadline).frame(minHeight:30) }.buttonStyle(.bordered).fixedSize(horizontal:!typeSize.isAccessibilitySize,vertical:true).accessibilityLabel("Use my location").accessibilityInputLabels([Text("Near me"),Text("Use my location")]) }
    }
    /// The radius as the distance itself in amber with the system's up-down chevrons; a menu of four
    /// distances in the locale's unit (`SearchRadius`), and the current one too when it was set in the
    /// other unit. A plain label, so "200 mi" sits on the row's text with no control inset of its own.
    private var radiusMenu:some View {
        @Bindable var model=model
        let distance=SearchRadius.label(model.radiusMeters)
        return Menu {
            Picker("Radius",selection:$model.radiusMeters) {
                ForEach(SearchRadius.choices(SearchRadius.steps(),keeping:model.radiusMeters),id:\.self) { meters in Text(SearchRadius.label(meters)).tag(meters) }
            }.pickerStyle(.inline)
        } label:{
            HStack(spacing:4) {
                Text(distance)
                Image(systemName:"chevron.up.chevron.down").font(.caption.weight(.semibold)).accessibilityHidden(true)
            }
            .font(.subheadline).foregroundStyle(palette.accent).frame(minWidth:44,minHeight:44).contentShape(Rectangle())
        }
        .buttonStyle(.plain).fixedSize(horizontal:!typeSize.isAccessibilitySize,vertical:true)
        .accessibilityLabel("Radius").accessibilityValue(distance).accessibilityInputLabels([Text("Radius"),Text("Distance")])
    }
}

/// The starting-point picker and the location explainer, for a screen that shows `StartingPointPanel`.
/// "Near me" chosen in the picker brings the explainer (or the location) once the picker has closed.
struct StartingPointSheets: ViewModifier {
    @Environment(PlanModel.self) private var model
    @Binding var choosing:Bool
    @Binding var explaining:Bool
    @State private var nearMeAfterPicker=false
    func body(content:Content)->some View {
        content
        .sheet(isPresented:$choosing,onDismiss:{ if nearMeAfterPicker { nearMeAfterPicker=false; Self.nearMe(model) { explaining=true } } }) {
            NavigationStack { StartingPointPicker(nearMe:{ nearMeAfterPicker=true },selectedParkID:model.homeID,selectedPlace:model.homePlace,locationOff:model.location.denied || DebugScenario.state=="no-location") { choice in
                switch choice {
                case .park(let id): model.choose(parkID:id)
                case .place(let place): model.choose(place)
                }
                model.location.clear()
            } }.nyxPresentation().presentationDetents([.large])
        }
        .sheet(isPresented:$explaining) { PermissionExplainer(symbol:"location",title:"Find a sky nearby",message:"Nyx uses your location once to find parks within a straight-line radius. It stays on this iPhone. You can also choose a city or a park.",action:"Use my location") { explaining=false;model.location.request() }.nyxPresentation() }    }
    /// The explainer only before iOS's first prompt; once answered, Near me just finds you.
    static func nearMe(_ model:PlanModel,explain:()->Void) { if model.location.needsPermission { explain() } else { model.location.request() } }
}
