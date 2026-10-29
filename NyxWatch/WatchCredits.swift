import SwiftUI

/// The sources Nyx on Apple Watch draws from, credited as their terms ask: the iPhone's own lines
/// (`Credits`), those something on the wrist rests on, so a licence is never shortened away here.
struct WatchCredits: View {
    @Environment(\.nyx) private var palette
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Credits.Section.allCases, id: \.self) { section in
                    ForEach(section.lines(for: .watch), id: \.self) { line in Text(line).font(.footnote) }
                }
                Text(Credits.notAffiliated).font(.caption2).foregroundStyle(palette.muted)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .nyxTitle(String(localized: "Credits"))
    }
}

#Preview("Credits • red") {
    WatchPreviewHost(nightVision: true) { _, _ in NavigationStack { WatchCredits() } }
}
#Preview("Credits • AX5") {
    WatchPreviewHost(nightVision: false) { _, _ in NavigationStack { WatchCredits() } }.dynamicTypeSize(.accessibility5)
}
