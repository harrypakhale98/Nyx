import SwiftUI

/// The one gate between a slow launch and the scores. While the offline caches are still being
/// read after the first frame (`PlanModel.cachesPending`), a surface that shows a Darkness Score
/// shows the constellation loader instead, never a moon-and-darkness score those reads are about
/// to change. It sits where scores enter the screen, so a new screen cannot forget it: every tab
/// (`TabChrome`, unless the tab is listed in `ungatedTabs`), every park page wherever it opens (a
/// link's sheet, a park's own window, the Parks split view), Assistive Access, and field mode
/// (`FieldPresenter` waits for the same reads). The tab bar, the Journal and anything presented
/// without a score answer at once; the gate lifts on the shared spring the moment the reads land.
struct ScoreGate: ViewModifier {
    @Environment(PlanModel.self) private var model
    @MotionReduced private var reduceMotion: Bool
    /// Off for a surface that carries no score from the caches (`ungatedTabs`).
    var enabled=true
    /// Draw the night behind the loader: off where the page already has its own sky behind it.
    var background=true
    func body(content:Content)->some View {
        let waits=Self.waits(enabled:enabled,cachesPending:model.cachesPending)
        Group {
            if waits {
                ConstellationLoader().frame(maxWidth:.infinity,maxHeight:.infinity)
                    .background { if background { NightBackground() } }
                    .transition(.opacity)
            } else { content }
        }
        .animation(NyxMotion.spring(reduced:reduceMotion),value:waits)
    }
    /// Whether a surface waits: only while the launch's cache reads are still out.
    nonisolated static func waits(enabled:Bool,cachesPending:Bool)->Bool { enabled && cachesPending }
    /// The tabs that never wait: the Journal's nights are scored with each month's usual clouds
    /// (`PlanModel.loggedNights`), never from the forecast caches. Every other tab, and any tab
    /// added later, waits.
    nonisolated static let ungatedTabs: Set<Int>=[3]
    nonisolated static func gates(tab:Int)->Bool { !ungatedTabs.contains(tab) }
}
extension View {
    /// Waits with the constellation loader while the launch's cache reads are out (`ScoreGate`).
    func scoreGate(_ enabled:Bool=true,background:Bool=true)->some View { modifier(ScoreGate(enabled:enabled,background:background)) }
}
