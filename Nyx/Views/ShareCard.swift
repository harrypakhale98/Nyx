import SwiftUI

struct ShareCard:View {
    @Environment(\.nyx) private var palette
    let night:Night
    var body:some View {
        ZStack {
            NightBackground(seed:night.park.id,score:night.score.value)
            VStack(spacing:18) {
                Text("NYX").font(.caption).tracking(7).foregroundStyle(palette.muted)
                // ImageRenderer proposes no size; an unsized gauge collapses and truncates the score.
                CelestialGauge(score:night.score.value,hasForecast:night.score.hasForecast).frame(width:300,height:300)
                Text(night.park.shortName).font(.system(.title,design:.serif)).multilineTextAlignment(.center).foregroundStyle(palette.ink)
                Text(night.park.dayLabel(night.id)).font(.subheadline).foregroundStyle(palette.ink)
                Text(night.score.hasForecast ? String(localized:"Forecast included · conditions may change") : String(localized:"Moon and darkness only · clouds unknown")).font(.caption).multilineTextAlignment(.center).foregroundStyle(palette.muted)
            }.padding(40)
        }.frame(width:420,height:580)
            // ImageRenderer does not inherit the window's dark scheme; every color here is explicit.
            .environment(\.colorScheme,.dark)
            // This is fixed-size exported artwork, with a complete spoken alternative.
            .dynamicTypeSize(.large).accessibilityElement(children:.ignore).accessibilityLabel(summary)
    }
    var summary:String { String(localized:"\(night.park.shortName), \(night.park.dayLabel(night.id)), darkness score \(night.score.value) out of 100. \(night.score.band.label). \(night.score.hasForecast ? String(localized:"Forecast included · conditions may change") : String(localized:"Moon and darkness only · clouds unknown"))") }
}
struct ShareCardButton:View {
    @Environment(\.nyx) private var palette
    let night:Night
    @State private var rendered:Image?
    var body:some View {
        Group {
            if let rendered { ShareLink(item:rendered,preview:SharePreview(String(localized:"\(night.score.value)/100 at \(night.park.shortName)"),image:rendered)) { Label("Share this night",systemImage:"square.and.arrow.up") } }
            else { Button("Prepare share card") { render() } }
        }.buttonStyle(.bordered).accessibilityValue(ShareCard(night:night).summary).task(id:night.id.description+String(night.score.value)+String(palette.nightVision)) {
            // Settle first: scrubbing the time river changes the night many times a second.
            try? await Task.sleep(for:.milliseconds(450)); if !Task.isCancelled { render() }
        }
    }
    private func render() {
        let card=ShareCard(night:night).environment(\.nyx,palette).environment(\.nyxReduceMotion,true).preferredColorScheme(.dark)
        let renderer=ImageRenderer(content:card.modifier(NightVisionFilter(enabled:palette.nightVision)));renderer.scale=2
        if let image=renderer.uiImage { rendered=Image(uiImage:image) }
    }
}
#Preview("Share") { let m=PlanModel();if let p=m.home { ShareCard(night:m.night(p)).environment(\.nyxReduceMotion,true) } }
