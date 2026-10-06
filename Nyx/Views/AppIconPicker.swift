import SwiftUI

/// The Moon on the Home Screen, in four phases. Each is an Icon Composer document with the same
/// dial, star and glass; only the Moon changes. Icons are static, so this is a choice, not a clock.
enum NyxIcon: String, CaseIterable, Identifiable {
    case crescent, new, quarter, full
    var id: String { rawValue }
    /// The alternate icon's asset name; nil for the primary icon.
    var assetName: String? {
        switch self { case .crescent: nil; case .new: "AppIconNew"; case .quarter: "AppIconQuarter"; case .full: "AppIconFull" }
    }
    var preview: String { "IconPreview"+rawValue.prefix(1).uppercased()+rawValue.dropFirst() }
    var title: String {
        switch self {
        case .crescent: String(localized:"Crescent")
        case .new: String(localized:"New moon")
        case .quarter: String(localized:"First quarter")
        case .full: String(localized:"Full moon")
        }
    }
    var caption: String {
        switch self {
        case .crescent: String(localized:"The original. A waxing Moon over the score's dial.")
        case .new: String(localized:"The darkest nights. Only earthshine on the Moon's face.")
        case .quarter: String(localized:"Half lit, half dark: the balance point.")
        case .full: String(localized:"The bright Moon, for nights you spend with it.")
        }
    }
    init(assetName: String?) { self=Self.allCases.first { $0.assetName==assetName } ?? .crescent }
}
struct AppIconPicker: View {
    @Environment(\.nyx) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var current=NyxIcon(assetName:UIApplication.shared.alternateIconName)
    @State private var failed=false
    @State private var changed=0
    var body: some View {
        Form {
            Section { ForEach(NyxIcon.allCases) { icon in row(icon) } } footer:{
                Text("The icon stays in the phase you choose; it does not follow the Moon.").foregroundStyle(palette.muted)
            }
            if failed { Section { Text("The icon could not be changed right now. Try again in a moment.").foregroundStyle(palette.accent) } }
        }
        .navigationTitle("App icon").navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection,trigger:changed)
    }
    private func row(_ icon:NyxIcon)->some View {
        Button { choose(icon) } label:{
            // At accessibility sizes the icon sits above its words, so names never break mid-word.
            let layout=typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment:.leading,spacing:12)) : AnyLayout(HStackLayout(spacing:16))
            layout {
                HStack {
                    Image(icon.preview).resizable().interpolation(.high).frame(width:60,height:60)
                        .clipShape(RoundedRectangle(cornerRadius:14,style:.continuous))
                        .accessibilityIgnoresInvertColors().accessibilityHidden(true)
                    if typeSize.isAccessibilitySize { Spacer(minLength:8); check(icon) }
                }
                VStack(alignment:.leading,spacing:4) {
                    Text(icon.title).font(.system(.body,design:.serif)).foregroundStyle(palette.ink).fixedSize(horizontal:false,vertical:true)
                    Text(icon.caption).font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
                }
                if !typeSize.isAccessibilitySize { Spacer(minLength:8); check(icon) }
            }.padding(.vertical,4).contentShape(Rectangle())
        }.buttonStyle(.plain)
        .accessibilityElement(children:.combine)
        .accessibilityAddTraits(current == icon ? [.isSelected,.isButton] : .isButton)
    }
    @ViewBuilder private func check(_ icon:NyxIcon)->some View {
        if current == icon { Image(systemName:"checkmark").foregroundStyle(palette.accent).accessibilityHidden(true) }
    }
    private func choose(_ icon:NyxIcon) {
        guard icon != current, UIApplication.shared.supportsAlternateIcons else { return }
        failed=false
        Task {
            do { try await UIApplication.shared.setAlternateIconName(icon.assetName); current=icon; changed+=1 }
            catch { failed=true }
        }
    }
}
#Preview("App icon") { NavigationStack { AppIconPicker() }.preferredColorScheme(.dark) }
