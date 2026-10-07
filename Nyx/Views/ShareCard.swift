import SwiftUI

struct ShareCard:View {
    @Environment(\.nyx) private var palette
    let night:Night
    var body:some View {
        ZStack {
            NightBackground(seed:night.park.id,score:night.score.value,park:night.park,night:night.id)
            VStack(spacing:18) {
                Text("NYX").font(.caption).tracking(7).foregroundStyle(palette.muted)
                // ImageRenderer proposes no size; an unsized gauge collapses and truncates the score.
                CelestialGauge(score:night.score.value,hasForecast:night.score.hasForecast).frame(width:300,height:300)
                Text(night.park.shortName).font(.system(.title,design:.serif)).multilineTextAlignment(.center).foregroundStyle(palette.ink)
                HStack(spacing:10) {
                    MoonView(geometry:AstronomyEngine().moon(for:night).geometry).frame(width:26,height:26)
                    Text(night.park.dayLabel(night.id)).font(.subheadline).foregroundStyle(palette.ink)
                }
                Text(basis).font(.caption).multilineTextAlignment(.center).foregroundStyle(palette.muted)
            }.padding(40)
        }.frame(width:420,height:580)
            // ImageRenderer does not inherit the window's dark scheme; every color here is explicit.
            .environment(\.colorScheme,.dark)
            // This is fixed-size exported artwork, with a complete spoken alternative.
            .dynamicTypeSize(.large).accessibilityElement(children:.ignore).accessibilityLabel(summary)
    }
    var summary:String { String(localized:"\(night.park.shortName), \(night.park.dayLabel(night.id)), darkness score \(night.score.value) out of 100. \(night.score.band.label). \(basis)") }
    private var basis:String {
        switch night.basis {
        case .forecast: String(localized:"Forecast included · conditions may change")
        case .blended: String(localized:"Early look · forecast eased toward usual clouds")
        case .usual: String(localized:"No cloud forecast yet · usual clouds for the month")
        }
    }
}
struct ShareCardButton:View {
    @Environment(\.nyx) private var palette
    let night:Night
    @Environment(\.displayScale) private var displayScale
    @State private var rendered:(key:String,image:Image)?
    private var key:String { night.id.description+String(night.score.value)+String(palette.nightVision) }
    var body:some View {
        Group {
            // While a new night settles, the last card stays in place but cannot be shared, so the
            // button never jumps between two labels as the river is scrubbed.
            if let rendered { ShareLink(item:rendered.image,preview:SharePreview(String(localized:"\(night.score.value)/100 at \(night.park.shortName)"),image:rendered.image)) { Label("Share this night",systemImage:"square.and.arrow.up") }.disabled(rendered.key != key) }
            else { Button("Prepare share card") { render() } }
        }.buttonStyle(.bordered).accessibilityValue(ShareCard(night:night).summary).task(id:key) {
            // Never offer the previous night's card. Settle first: scrubbing the river changes the night many times a second.
            try? await Task.sleep(for:.milliseconds(450)); if !Task.isCancelled { render() }
        }
    }
    private func render() {
        let card=ShareCard(night:night).environment(\.nyx,palette).environment(\.nyxReduceMotion,true).preferredColorScheme(.dark)
        let renderer=ImageRenderer(content:card.modifier(NightVisionFilter(enabled:palette.nightVision)));renderer.scale=max(2,displayScale)
        if let image=renderer.uiImage { rendered=(key,Image(uiImage:image)) }
    }
}
#Preview("Share") { let m=PlanModel();if let p=m.home { ShareCard(night:m.night(p)).environment(\.nyxReduceMotion,true) } }
