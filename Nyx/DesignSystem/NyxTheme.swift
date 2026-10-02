import SwiftUI

struct NyxPalette {
    let nightVision: Bool
    let highContrast: Bool
    var ink: Color { nightVision ? .white : Color(red:0.961,green:0.945,blue:0.902) }
    var accent: Color { nightVision ? ink : Color(red:1,green:0.706,blue:0.329) }
    // Filled tracks must remain distinct from the white system thumb after the red filter.
    var controlTint:Color { nightVision ? Color(white:0.22) : Color(red:0.65,green:0.35,blue:0.10) }
    var muted: Color { ink.opacity(nightVision ? 0.96 : highContrast ? 0.9 : 0.72) }
    var panel: Color { nightVision ? Color(red:0.07,green:0.008,blue:0.005) : Color(red:0.043,green:0.063,blue:0.149) }
    var line: Color { ink.opacity(highContrast ? 0.6 : 0.22) }
}
private struct MotionOverrideKey: EnvironmentKey { static let defaultValue=false }
private struct PaletteKey: EnvironmentKey { static let defaultValue=NyxPalette(nightVision:false,highContrast:false) }
extension EnvironmentValues {
    var nyxReduceMotion: Bool { get { self[MotionOverrideKey.self] } set { self[MotionOverrideKey.self]=newValue } }
    var nyx: NyxPalette { get { self[PaletteKey.self] } set { self[PaletteKey.self]=newValue } }
}
enum NyxMotion {
    static let spring=Animation.spring(response:0.65,dampingFraction:0.82)
}
struct Panel<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.nyx) private var palette
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(20).frame(maxWidth:.infinity,alignment:.leading)
            .background(palette.panel.opacity(reduceTransparency || palette.highContrast ? 1 : 0.85),in:RoundedRectangle(cornerRadius:24))
            .overlay(RoundedRectangle(cornerRadius:24).stroke(palette.line,lineWidth:0.5))
    }
}
struct Eyebrow: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.nyx) private var palette
    let text: LocalizedStringKey
    var body: some View { Text(text).font(.caption.weight(.medium)).tracking(typeSize.isAccessibilitySize ? 0 : 2.4).textCase(typeSize.isAccessibilitySize ? nil : .uppercase).fixedSize(horizontal:false,vertical:true).foregroundStyle(palette.muted).accessibilityAddTraits(.isHeader) }
}
struct NightBackground: View {
    var seed: String="nyx"
    var body: some View { ZStack { Color.black; Starfield(seed:seed) }.ignoresSafeArea().accessibilityHidden(true) }
}
struct CalmState: View {
    @Environment(\.nyx) private var palette
    let symbol: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    var body: some View {
        VStack(spacing:20) {
            Image(systemName:symbol).font(.system(size:36,weight:.ultraLight)).foregroundStyle(palette.accent).padding(26)
                .background(Circle().stroke(palette.line,lineWidth:0.5))
            Text(title).font(.system(.title2,design:.serif)).multilineTextAlignment(.center)
            Text(message).font(.body).foregroundStyle(palette.muted).multilineTextAlignment(.center)
        }.frame(maxWidth:.infinity).padding(.vertical,38).padding(.horizontal,24)
    }
}
#Preview("Empty") { CalmState(symbol:"sparkles",title:"A night to remember",message:"Your observations will live here.").background(.black).preferredColorScheme(.dark) }
#Preview("Error • AX5") { CalmState(symbol:"cloud",title:"The forecast is resting",message:"Moon and darkness calculations still work offline.").dynamicTypeSize(.accessibility5).background(.black).preferredColorScheme(.dark) }

struct NightVisionFilter: ViewModifier {
    let enabled:Bool
    @ViewBuilder func body(content:Content)->some View {
        content.saturation(enabled ? 0 : 1).colorMultiply(enabled ? Color(red:1,green:0.27,blue:0.23) : .white)
    }
}

private struct PresentationStyle:ViewModifier {
    @Environment(\.nyx) private var palette
    func body(content:Content)->some View {
        content.foregroundStyle(palette.ink).tint(palette.accent)
            .modifier(NightVisionFilter(enabled:palette.nightVision)).preferredColorScheme(.dark)
    }
}
extension View {
    func nyxPresentation()->some View { modifier(PresentationStyle()) }
}
