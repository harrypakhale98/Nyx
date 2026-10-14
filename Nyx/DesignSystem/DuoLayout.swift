import SwiftUI

/// iPhone Duo (iOS 27.1). Its outer display is wider and shorter than other iPhones', so the system
/// stands the toolbar and tab bar on the side, and its inner display can fold through the middle. These
/// helpers adopt the 27.1 SDK's APIs behind a compile-time check, so the same source still builds with
/// the iOS 27.0 SDK, and behind `#available`, so iOS 26 and 27.0 keep their own complete layout.
///
/// Nothing here asks which device it is: the bars follow the system, and the fold is read as a
/// reserved region of the view's own geometry, which is empty on every other iPhone and iPad.

extension View {
    /// A sheet whose only bar item is its close button keeps a horizontal bar on the outer display
    /// (Apple's guidance), so its single glyph does not take a whole column from the content.
    func singleControlBar() -> some View {
        modifier(SingleControlBar())
    }
}

private struct SingleControlBar: ViewModifier {
    func body(content: Content) -> some View {
        #if canImport(SwiftUI, _version: 8.0.85)
        if #available(iOS 27.1, *) {
            content.toolbarVerticalBehavior(.disabled)
        } else {
            content
        }
        #else
        content
        #endif
    }
}

/// The fold of iPhone Duo's inner display, in a view's own coordinates, half open or open flat. Pure numbers, so they are
/// tested; `readingFold` fills them from the view's geometry.
///
/// Only what layout reads is kept: whether the fold runs top to bottom, and then its left and right
/// edges in whole points. Its vertical extent is dropped, so a page that scrolls past the fold (whose
/// region moves in the page's coordinates with every frame) does not change its fold, re-lay its
/// columns and start an animation on each frame of the scroll.
nonisolated struct Fold: Equatable, Sendable {
    /// A fold that runs top to bottom divides the width (a Duo held open like a book); one that runs
    /// side to side divides the height (a Duo standing like a laptop).
    let dividesWidth: Bool
    /// The fold's left and right edges (mirrored for right-to-left layouts by SwiftUI); zero for a
    /// side-to-side fold, whose place no layout reads.
    let minX: Double
    let maxX: Double
    var width: Double { maxX-minX }

    /// From the reserved region's frame in the view's coordinates.
    init(frame: CGRect) {
        dividesWidth=frame.height >= frame.width
        minX=dividesWidth ? frame.minX.rounded(.down) : 0
        maxX=dividesWidth ? frame.maxX.rounded(.up) : 0
    }
    private init(dividesWidth: Bool, minX: Double, maxX: Double) {
        self.dividesWidth=dividesWidth
        self.minX=minX
        self.maxX=maxX
    }

    /// The same fold seen from a view whose leading edge is `x` points from this fold's view (whole
    /// points in, whole points out). A side-to-side fold has no place to move.
    func seen(fromX x: Double) -> Fold {
        dividesWidth ? Fold(dividesWidth: true, minX: minX-x, maxX: maxX-x) : self
    }

    #if DEBUG
    /// The DEBUG stand-in: `band` (the fold in the simulated window) as a view at `viewFrame` (in the
    /// window) reads it. Clipped to the part of the view inside the window, as hardware may clip it too,
    /// so a view scrolled most of the way off screen reads a sliver, or nothing (why scrolling pages read
    /// their fold on the scroll view's own frame, `foldSource`).
    static func standIn(band: CGRect, viewFrame: CGRect, window: CGSize) -> Fold? {
        let onScreen=viewFrame.intersection(CGRect(origin: .zero, size: window))
        guard !onScreen.isNull else { return nil }
        let local=band.intersection(onScreen).offsetBy(dx: -viewFrame.minX, dy: -viewFrame.minY)
        return local.isNull || local.isEmpty ? nil : Fold(frame: local)
    }
    #endif

    /// Where a two-column page should end its leading column so the fold falls in the gap between
    /// the columns: nil when the fold does not run top to bottom through this width, or would leave a
    /// column narrower than `minimum`.
    func leadingWidth(in width: Double, minimum: Double = 300) -> Double? {
        guard dividesWidth, minX >= minimum, width - maxX >= minimum else { return nil }
        return minX
    }
}

extension View {
    /// Reports the fold crossing this view, in its own coordinates, whether iPhone Duo is half open or
    /// open flat: the crease shows either way, so columns meet at it in both. Nil on every other device,
    /// on iPhone Duo when it is closed, and before iOS 27.1.
    func readingFold(_ fold: Binding<Fold?>) -> some View {
        modifier(FoldReader(fold: fold))
    }
}

private struct FoldReader: ViewModifier {
    @Binding var fold: Fold?
    #if DEBUG
    @Environment(\.debugWindowOrigin) private var windowOrigin
    #endif
    func body(content: Content) -> some View {
        #if DEBUG
        if let kind=DebugScenario.fold, let window=DebugScenario.window {
            // DEBUG captures: a fold through the middle of the simulated window (`-nyx-window`). Read in
            // screen coordinates less the window's own origin: a named coordinate space does not reach
            // through the tab view's and split view's hosted columns. The origin is captured, so the
            // reading is redone when it changes, and reported only when it changes.
            let origin=windowOrigin, w=DebugScenario.foldWidth
            let band=kind == "table" ? CGRect(x: 0, y: (window.height-w)/2, width: window.width, height: w) : CGRect(x: (window.width-w)/2, y: 0, width: w, height: window.height)
            content.onGeometryChange(for: Fold?.self) { proxy in
                guard let origin else { return nil }
                return Fold.standIn(band: band, viewFrame: proxy.frame(in: .global).offsetBy(dx: -origin.x, dy: -origin.y), window: window)
            } action: { fold=$0 }
        } else {
            hardware(content)
        }
        #else
        hardware(content)
        #endif
    }
    @ViewBuilder private func hardware(_ content: Content) -> some View {
        #if canImport(SwiftUI, _version: 8.0.85)
        if #available(iOS 27.1, *) {
            content.onGeometryChange(for: Fold?.self) { proxy in
                // `Fold` keeps whole points of the side-to-side extent only, so a layout placed by the
                // fold never chases its own rounding, and scrolling never changes it. Open flat, the
                // fold is reserved but inactive (`.includeInactive`); its crease still shows, so the
                // columns stay on it, and opening or half closing the Duo moves nothing.
                let regions=proxy.reservedRegions(kind: .division, options: .includeInactive)
                return (regions.first(where: \.isActive) ?? regions.first).map { Fold(frame: $0.frame) }
            } action: { fold=$0 }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

extension View {
    /// Whether iPhone Duo's hinge is part way open (book, tent or laptop), for behaviour only: layout
    /// follows size classes and the fold's reserved region, never the angle. False everywhere else.
    func readingHalfOpen(_ halfOpen: Binding<Bool>) -> some View {
        modifier(HalfOpenReader(halfOpen: halfOpen))
    }
}

private struct HalfOpenReader: ViewModifier {
    @Binding var halfOpen: Bool
    func body(content: Content) -> some View {
        #if canImport(SwiftUI, _version: 8.0.85)
        if #available(iOS 27.1, *) {
            content.onHingeChange { _, context in halfOpen=context.hinge?.status == .partiallyOpen }
        } else {
            content
        }
        #else
        content
        #endif
    }
}

extension EnvironmentValues {
    /// The DEBUG simulated window's origin on screen (`-nyx-window`), so a stand-in fold sits where the
    /// hardware's would; nil everywhere else.
    @Entry var debugWindowOrigin: CGPoint?=nil
}

/// Two top-aligned columns, the narrower one at most `narrowMax` wide, `spacing` apart. On iPhone Duo's
/// inner display (half open like a book, or open flat), the gap moves onto the fold and widens by it, so
/// neither column runs across the crease (the outer margins stay as they were; Apple's Fitness grid does the same).
nonisolated struct ColumnSplit: Layout {
    enum Narrow: Sendable { case leading, trailing }
    var narrow: Narrow
    var narrowMax: Double
    var spacing: Double
    var fold: Fold?

    /// The two columns' widths and the gap between them across `total` points.
    static func widths(total: Double, narrow: Narrow, narrowMax: Double, spacing: Double, fold: Fold?) -> (leading: Double, gap: Double, trailing: Double) {
        if let fold, let edge=fold.leadingWidth(in: total, minimum: 260+spacing/2) {
            let leading=(edge-spacing/2).rounded(.down)
            let trailing=(total-fold.maxX-spacing/2).rounded(.down)
            return (leading, max(0, total-leading-trailing), trailing)
        }
        let narrowWidth=min(narrowMax, max(0, (total-spacing)/2)).rounded(.down)
        let wideWidth=max(0, total-spacing-narrowWidth)
        return narrow == .leading ? (narrowWidth, spacing, wideWidth) : (wideWidth, spacing, narrowWidth)
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        let total=proposal.width ?? (subviews[0].sizeThatFits(.unspecified).width+spacing+subviews[1].sizeThatFits(.unspecified).width)
        let w=Self.widths(total: total, narrow: narrow, narrowMax: narrowMax, spacing: spacing, fold: fold)
        let height=max(subviews[0].sizeThatFits(ProposedViewSize(width: w.leading, height: nil)).height, subviews[1].sizeThatFits(ProposedViewSize(width: w.trailing, height: nil)).height)
        return CGSize(width: total, height: height)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let w=Self.widths(total: bounds.width, narrow: narrow, narrowMax: narrowMax, spacing: spacing, fold: fold)
        subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.minY), anchor: .topLeading, proposal: ProposedViewSize(width: w.leading, height: nil))
        subviews[1].place(at: CGPoint(x: bounds.minX+w.leading+w.gap, y: bounds.minY), anchor: .topLeading, proposal: ProposedViewSize(width: w.trailing, height: nil))
    }
}

extension EnvironmentValues {
    /// The fold as a scrolling page reads it on its scroll view's own frame (`foldSource`), in that
    /// frame's coordinates (`FoldSource.space`); nil outside such a page and wherever there is no fold.
    @Entry var pageFold: Fold?=nil
}

extension View {
    /// Reads the fold on this scroll view's own frame, which stays on screen however far the page
    /// scrolls, and hands it to the `FoldColumns` inside. A fold read inside the scrolling content could
    /// be clipped to the sliver still on screen (the DEBUG stand-in does this, and hardware may), so
    /// columns scrolled nearly or wholly out of view would lose it and spring back mid-scroll.
    func foldSource() -> some View {
        modifier(FoldSource())
    }
}

struct FoldSource: ViewModifier {
    nonisolated static let space="nyx.foldSource"
    @State private var fold: Fold?
    func body(content: Content) -> some View {
        content.coordinateSpace(.named(Self.space)).environment(\.pageFold, fold).readingFold($fold)
    }
}

/// `ColumnSplit` fed by its page's `foldSource`: two columns (the content's two views) that meet at the
/// fold. The page's fold is moved into the columns' own coordinates by their leading edge in the page,
/// in whole points, which a vertical scroll never changes.
struct FoldColumns<Content: View>: View {
    var narrow: ColumnSplit.Narrow
    var narrowMax: Double
    var spacing: Double
    @ViewBuilder var content: Content
    @Environment(\.pageFold) private var pageFold
    @State private var leadingEdge=0.0
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.nyxReduceMotion) private var forcedReduceMotion
    private var fold: Fold? { pageFold?.seen(fromX: leadingEdge) }
    var body: some View {
        ColumnSplit(narrow: narrow, narrowMax: narrowMax, spacing: spacing, fold: fold) { content }
            .onGeometryChange(for: Double.self) { $0.frame(in: .named(FoldSource.space)).minX.rounded() } action: { leadingEdge=$0 }
            // The columns ease to the fold as the hinge turns (small moves, on the shared spring).
            .animation(systemReduceMotion || forcedReduceMotion ? nil : NyxMotion.spring, value: fold)
    }
}
