import SwiftUI

/// Tonight's pointer to the nearest dark sky (`DarkerSky`): a direction, a distance and the
/// satellite map's class, said as a light-map estimate with no name and no score. It can be saved
/// as a spot (which gives it nights, widgets, the watch and reminders) or looked at in Maps as a pin.
struct DarkerSkyPanel: View {
    @Environment(PlanModel.self) private var model
    @Environment(\.nyx) private var palette
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo:.title3) private var arrowSize=22.0
    let offer: DarkerSky.Offer
    @State private var saving=false
    /// Grid centres carry many decimals; three (about 100 m) is finer than a cell.
    private var coordinate:(latitude:Double,longitude:Double) {
        ((offer.area.latitude*1000).rounded()/1000,(offer.area.longitude*1000).rounded()/1000)
    }
    /// A saved spot already on this dark area: within 10 km of it.
    private var savedSpot:Park? {
        model.spots.first { Park.distance($0.latitude,$0.longitude,offer.area.latitude,offer.area.longitude)<=10_000 }
    }
    var body: some View {
        Panel { VStack(alignment:.leading,spacing:14) {
            Eyebrow(text:"A dark area")
            // At accessibility sizes the arrow sits above the sentence, which keeps the full width.
            let layout=typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment:.leading,spacing:8)) : AnyLayout(HStackLayout(alignment:.firstTextBaseline,spacing:12))
            layout {
                // Points the way on the page's own north-up frame: a hint of direction, not a compass.
                Image(systemName:"location.north.fill").font(.system(size:arrowSize*0.8)).foregroundStyle(palette.accent)
                    .rotationEffect(.degrees(offer.bearing)).frame(width:arrowSize,height:arrowSize).accessibilityHidden(true)
                Text(DarkerSky.headline(offer)).font(.system(.title3,design:.serif)).fixedSize(horizontal:false,vertical:true)
            }
            VStack(alignment:.leading,spacing:6) {
                Text(DarkerSky.skyLine(offer))
                if let comparison=DarkerSky.comparison(offer) { Text(comparison) }
            }.font(.subheadline).foregroundStyle(palette.ink).fixedSize(horizontal:false,vertical:true)
            Text(DarkerSky.caution).font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
            ViewThatFits(in:.horizontal) {
                HStack(spacing:18) { actions }
                VStack(alignment:.leading,spacing:4) { actions }
            }
        } }
        .accessibilityElement(children:.contain).accessibilityIdentifier("darkerSky")
        .sheet(isPresented:$saving) { SaveSpotView(coordinate:coordinate).nyxPresentation() }
    }
    @ViewBuilder private var actions: some View {
        if let spot=savedSpot {
            Label { Text("Saved as \(spot.shortName)") } icon:{ Image(systemName:"checkmark.circle") }
                .font(.footnote.weight(.medium)).foregroundStyle(palette.muted).frame(minHeight:44)
        } else if !model.journalUnavailable {
            Button { saving=true } label:{ Label("Save as a spot",systemImage:"mappin.and.ellipse").font(.footnote.weight(.medium)).frame(minHeight:44) }
                .buttonStyle(.borderless).foregroundStyle(palette.accent)
                .accessibilityHint("Gives it nights and a score. You can then add it to your widgets, Apple Watch and reminders.")
        }
        if let url=MapsHandOff.pin(latitude:coordinate.latitude,longitude:coordinate.longitude,label:SkyGrid.DarkArea.title) {
            Button { openURL(url) } label:{ Label("Show in Maps",systemImage:"map").font(.footnote.weight(.medium)).frame(minHeight:44) }
                .buttonStyle(.borderless).foregroundStyle(palette.accent)
                .accessibilityHint("Opens Apple Maps at this point, without directions. Nyx sends nothing.")
        }
    }
}

#Preview("Dark area · bright reach") {
    DarkerSkyPanel(offer:.init(area:.init(latitude:25.42,longitude:47.61,magnitude:21.4,bortle:3,distanceMeters:142_000),bearing:48,darkestInReach:8))
        .padding().environment(PlanModel()).background(.black).preferredColorScheme(.dark)
}
#Preview("Dark area · nothing in reach · AX5") {
    DarkerSkyPanel(offer:.init(area:.init(latitude:25.42,longitude:47.61,magnitude:20.9,bortle:4,distanceMeters:410_000),bearing:200,darkestInReach:nil))
        .padding().environment(PlanModel()).dynamicTypeSize(.accessibility5).background(.black).preferredColorScheme(.dark)
}
