import SwiftUI

/// A screen that accepts a dragged park (iPad, or iPhone with a long-press drag): Plan opens that
/// park's month, Journal starts an entry for it. While a park hovers over the screen, a quiet amber
/// frame and one line say what letting go will do. VoiceOver users reach the same actions from
/// each park's own menu ("Show in Plan") and the journal's "Record a night".
struct ParkDropTarget: ViewModifier {
    @Environment(\.nyx) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let prompt: LocalizedStringKey
    let symbol: String
    let drop: (Park)->Void
    @State private var targeted=false
    func body(content:Content)->some View {
        content
            // The iOS 16 form, which reports hovering on iOS 26 as well; the iOS 26 session form
            // only reports it from iOS 27 (`onDropSessionUpdated`).
            .dropDestination(for:Park.self) { parks,_ in
                guard let park=parks.first else { return false }
                drop(park)
                return true
            } isTargeted:{ targeted=$0 }
            .overlay {
                if targeted {
                    ZStack(alignment:.top) {
                        RoundedRectangle(cornerRadius:28).strokeBorder(palette.accent.opacity(0.8),lineWidth:2).padding(6)
                        Label(prompt,systemImage:symbol).font(.headline).foregroundStyle(Color.black)
                            .padding(.horizontal,18).padding(.vertical,10)
                            .background(Capsule().fill(palette.accent))
                            .padding(.top,18)
                    }
                    .ignoresSafeArea(edges:.bottom)
                    .allowsHitTesting(false).accessibilityHidden(true)
                    .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : NyxMotion.spring,value:targeted)
            .sensoryFeedback(.selection,trigger:targeted) { _,now in now }
    }
}
extension View {
    /// Accepts a park dropped onto the screen (`ParkDropTarget`).
    func acceptsPark(_ prompt:LocalizedStringKey,systemImage:String,drop:@escaping (Park)->Void)->some View {
        modifier(ParkDropTarget(prompt:prompt,symbol:systemImage,drop:drop))
    }
}
extension JournalPrefill {
    /// A park dropped onto the Journal: an entry for tonight at that park (or now, before tonight's
    /// evening, since the editor takes no date still ahead), its Bortle estimate, and no notes yet.
    nonisolated static func dropped(park:Park,tonight:Date,now:Date = .now)->JournalPrefill {
        JournalPrefill(parkID:park.id,date:min(park.evening(tonight),now),observedBortle:park.bortleEstimate,notes:"")
    }
}
#Preview("Drop target") {
    Color.black.frame(height:400).acceptsPark("Plan this park",systemImage:"calendar") { _ in }
        .environment(\.nyx,NyxPalette(nightVision:false,highContrast:false)).preferredColorScheme(.dark)
}
