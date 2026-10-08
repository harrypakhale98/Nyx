import SwiftUI

/// "From home tonight", at the foot of Tonight: for anyone who cannot travel to a park tonight
/// (no car, no accessible transport, a long day), the sky over their own starting point. The
/// Moon, true darkness, an eclipse or a shower worth stepping out for, and the planets, worked out
/// on this device. Nothing is fetched for it, so the person's coordinates never leave the phone.
struct FromHomePanel: View {
    @Environment(\.nyx) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo:.headline) private var glyphSize=20.0
    let origin: HomeSky.Origin
    let now: Date
    @State private var sky: HomeSky?
    var body: some View {
        VStack(alignment:.leading,spacing:16) {
            Eyebrow(text:"From \(origin.name) tonight")
            Text("Not heading to a park tonight? This is the sky over your starting point.")
                .font(.subheadline).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
            if let sky {
                rows(sky)
                notes(sky)
            } else {
                ProgressView().frame(maxWidth:.infinity,minHeight:60).accessibilityLabel("Working out tonight's sky")
            }
        }
        .frame(maxWidth:.infinity,alignment:.leading)
        .padding(20)
        .background(RoundedRectangle(cornerRadius:24).fill(palette.panel))
        .overlay(RoundedRectangle(cornerRadius:24).stroke(palette.line,lineWidth:0.5))
        .accessibilityElement(children:.contain)
        // Worked out off the main thread, once per place and night.
        .task(id:key) {
            let origin=origin, now=now
            let computed=await Task.detached(priority:.userInitiated) { HomeSky(origin:origin,now:now) }.value
            if !Task.isCancelled { sky=computed }
        }
    }
    private var key:String { "\(origin.name)|\(origin.latitude)|\(origin.longitude)|\(Int(now.timeIntervalSince1970/3600))" }
    @ViewBuilder private func rows(_ sky:HomeSky)->some View {
        VStack(alignment:.leading,spacing:14) {
            row(title:Text("Moon"),value:sky.moonPhase,detail:sky.moonTimes) {
                // The app's own Moon, lit on the right side for this sky (turned for the southern one).
                MoonDisc(illumination:sky.sky.moon.illumination,waxing:sky.sky.moon.waxing,southern:origin.latitude<0)
                    .accessibilityIgnoresInvertColors()
            }
            Divider().overlay(palette.line)
            row(title:Text("True darkness"),value:sky.hasDarkness ? sky.darkness : String(localized:"None tonight"),detail:sky.hasDarkness ? sky.moonlightLine : sky.darkness) {
                Image(systemName:"moon.stars").resizable().scaledToFit().foregroundStyle(palette.accent)
            }
            ForEach([sky.eclipse,sky.shower].compactMap { $0 }) { item in
                Divider().overlay(palette.line)
                row(title:Text(item.title),value:item.value,detail:item.detail,spoken:item.spoken) {
                    SkyGlyph(SkyGlyph.Kind(item.kind),color:palette.accent)
                }
            }
            Divider().overlay(palette.line)
            if sky.planets.isEmpty {
                row(title:Text("Planets"),value:nil,detail:String(localized:"No bright planets up in the dark hours tonight.")) {
                    SkyGlyph(.planet,color:palette.muted)
                }
            } else {
                ForEach(sky.planets) { planet in
                    row(title:Text([planet.title,planet.note].compactMap { $0 }.joined(separator:" · ")),value:planet.value,detail:planet.detail,spoken:planet.spoken) {
                        SkyGlyph(.planet,color:palette.accent)
                    }
                }
            }
        }
    }
    private func row<Glyph:View>(title:Text,value:String?,detail:String?,spoken:String?=nil,@ViewBuilder glyph:()->Glyph)->some View {
        HStack(alignment:.top,spacing:14) {
            if !typeSize.isAccessibilitySize { glyph().frame(width:glyphSize,height:glyphSize).padding(.top,1).accessibilityHidden(true) }
            VStack(alignment:.leading,spacing:4) {
                ViewThatFits(in:.horizontal) {
                    HStack(alignment:.firstTextBaseline) {
                        title.font(.headline).foregroundStyle(palette.ink)
                        Spacer(minLength:8)
                        if let value { Text(value).font(.subheadline.monospacedDigit()).foregroundStyle(palette.accent).multilineTextAlignment(.trailing) }
                    }
                    VStack(alignment:.leading,spacing:3) {
                        title.font(.headline).foregroundStyle(palette.ink)
                        if let value { Text(value).font(.subheadline.monospacedDigit()).foregroundStyle(palette.accent) }
                    }
                }
                if let detail { Text(detail).font(.subheadline).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true) }
            }
        }
        .accessibilityElement(children:.combine)
        .modifier(SpokenOverride(text:spoken))
    }
    @ViewBuilder private func notes(_ sky:HomeSky)->some View {
        VStack(alignment:.leading,spacing:6) {
            Text("Check your local forecast for clouds. Nyx asks for none here, so your location stays on this device.")
            if origin.source != .park {
                Text("Nyx has no light map for homes. Streetlights hide faint stars; the Moon, the planets and the brightest stars still show.")
            }
            Text("Times are \(sky.place.timeZoneName).")
        }
        .font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
    }
}
/// Gives a combined row the item's own spoken sentence, which reads ranges as "from … to …".
private struct SpokenOverride: ViewModifier {
    let text: String?
    func body(content:Content)->some View {
        if let text { content.accessibilityLabel(Text(text)) } else { content }
    }
}

#Preview("From Chicago") { if let place=StartingPlaces.named("Chicago, IL"), let origin=HomeSky.origin(location:nil,place:place,park:nil) { ScrollView { FromHomePanel(origin:origin,now:.now).padding() }.background(.black).preferredColorScheme(.dark) } }
#Preview("Geminids • AX5") { if let place=StartingPlaces.named("Denver"), let origin=HomeSky.origin(location:nil,place:place,park:nil) { ScrollView { FromHomePanel(origin:origin,now:Date(timeIntervalSince1970:1797195600)).padding() }.background(.black).dynamicTypeSize(.accessibility5).preferredColorScheme(.dark) } }
#Preview("Midnight sun • night vision") { if let park=try? ParkData.load().first(where:{ $0.id=="gaar" }), let origin=HomeSky.origin(location:nil,place:nil,park:park) { ScrollView { FromHomePanel(origin:origin,now:Date(timeIntervalSince1970:1782086400)).padding() }.background(.black).environment(\.nyx,NyxPalette(nightVision:true,highContrast:false)).modifier(NightVisionFilter(enabled:true)).preferredColorScheme(.dark) } }
