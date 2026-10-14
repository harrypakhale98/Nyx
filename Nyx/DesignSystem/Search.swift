import SwiftUI

/// The system search field in the navigation bar, except at accessibility text sizes, where the
/// screen shows `InlineSearchField` instead: on iOS 27 the bar's field keeps its height while its
/// text grows, so at AX5 it draws neither placeholder nor text and does not take a tap.
/// A sheet asked for from the keyboard (⌘N, ⌘,) ends Find a Park's search first: left presented under the
/// sheet after ⌘F, the search took the sheet's first Cancel (seen on iPad). Inside the searchable content,
/// where `dismissSearch` reaches it.
struct SearchEnder: View {
    @Environment(\.dismissSearch) private var dismissSearch
    @Environment(\.isSearching) private var isSearching
    let request: Int?
    var body: some View { Color.clear.accessibilityHidden(true).onChange(of:request) { if isSearching { dismissSearch() } } }
}
struct SystemSearch: ViewModifier {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    let prompt: LocalizedStringKey
    let enabled: Bool
    func body(content:Content)->some View {
        // Always shown: a field that tucks away under the bar moved the whole list 52 pt while the accessibility
        // tree kept the old positions, so the system audit measured every row against the wrong pixels.
        if enabled { content.searchable(text:$text,placement:.navigationBarDrawer(displayMode:.always),prompt:prompt).searchFocused(focused) } else { content }
    }
}
/// A one-line field that wraps (`axis: .vertical`) takes Return as a newline, which the field strips,
/// so its Done or Search key would otherwise leave the keyboard up: over half the screen on an iPhone
/// in landscape. Return is one new "\n" typed; a pasted line break is only stripped.
enum ReturnKey {
    nonisolated static func pressed(old:String,new:String)->Bool {
        new.count == old.count+1 && new.filter { $0 == "\n" }.count == old.filter { $0 == "\n" }.count+1
    }
}
extension View {
    /// Keeps a wrapping field to one line: line breaks are stripped, and Return (`ReturnKey`) runs `done`.
    func strippingReturn(_ text:Binding<String>,done:@escaping ()->Void)->some View {
        onChange(of:text.wrappedValue) { old,new in if new.contains("\n") { text.wrappedValue=new.replacingOccurrences(of:"\n",with:""); if ReturnKey.pressed(old:old,new:new) { done() } } }
    }
}
/// A search field in the page itself, for accessibility text sizes: it grows and wraps with the text.
struct InlineSearchField: View {
    @Environment(\.nyx) private var palette
    @Binding var text: String
    let prompt: LocalizedStringKey
    var focus: FocusState<Bool>.Binding
    var label: LocalizedStringKey = "Search parks"
    var body: some View {
        HStack(alignment:.center,spacing:10) {
            Image(systemName:"magnifyingglass").foregroundStyle(palette.muted).accessibilityHidden(true)
            TextField(prompt,text:$text,axis:.vertical).lineLimit(1...3).submitLabel(.search).focused(focus)
                .autocorrectionDisabled().textInputAutocapitalization(.words)
                .strippingReturn($text) { focus.wrappedValue=false }
                .accessibilityLabel(label)
            if !text.isEmpty {
                Button { text="" } label:{ Image(systemName:"xmark.circle.fill").foregroundStyle(palette.muted).frame(minWidth:44,minHeight:44) }
                    .buttonStyle(.plain).accessibilityLabel("Clear search")
            }
        }
        // Capped at AX3 (still very large) so the whole prompt fits beside the glass on a phone.
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
        .padding(.horizontal,16).padding(.vertical,10).frame(minHeight:44)
        // The whole capsule takes the tap, not only the line of text.
        .contentShape(Rectangle()).onTapGesture { focus.wrappedValue=true }
        .background(RoundedRectangle(cornerRadius:22,style:.continuous).fill(palette.panel))
        .overlay(RoundedRectangle(cornerRadius:22,style:.continuous).stroke(palette.line,lineWidth:0.5))
    }
}
