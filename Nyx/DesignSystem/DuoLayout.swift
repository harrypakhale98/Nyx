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

/// The fold of a partially opened iPhone Duo, in a view's own coordinates. Pure numbers, so they are
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

    /// Where a two-column page should end its leading column so the fold falls in the gap between
    /// the columns: nil when the fold does not run top to bottom through this width, or would leave a
    /// column narrower than `minimum`.
    func leadingWidth(in width: Double, minimum: Double = 300) -> Double? {
        guard dividesWidth, minX >= minimum, width - maxX >= minimum else { return nil }
        return minX
    }
}

extension View {
    /// Reports the active fold crossing this view, in its own coordinates: nil on every other device,
    /// on iPhone Duo when it is closed or open flat, and before iOS 27.1.
    func readingFold(_ fold: Binding<Fold?>) -> some View {
        modifier(FoldReader(fold: fold))
    }
}

private struct FoldReader: ViewModifier {
    @Binding var fold: Fold?
    func body(content: Content) -> some View {
        #if DEBUG
        if let kind=DebugScenario.fold, let window=DebugScenario.window {
            // DEBUG captures: a fold through the middle of the simulated window (`-nyx-window`).
            let space=DebugWindowSpace.name, w=DebugScenario.foldWidth
            content.onGeometryChange(for: Fold?.self) { proxy in
                let frame=proxy.frame(in: .named(space))
                let band=kind == "table" ? CGRect(x: 0, y: (window.height-w)/2, width: window.width, height: w) : CGRect(x: (window.width-w)/2, y: 0, width: w, height: window.height)
                let local=band.offsetBy(dx: -frame.minX, dy: -frame.minY).intersection(CGRect(origin: .zero, size: frame.size))
                return local.isNull || local.isEmpty ? nil : Fold(frame: local)
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
                // fold never chases its own rounding, and scrolling never changes it.
                proxy.reservedRegions(kind: .division).first(where: \.isActive).map { Fold(frame: $0.frame) }
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

/// The DEBUG window's coordinate space, so a simulated fold sits where the hardware's would.
nonisolated enum DebugWindowSpace {
    static let name="nyx.debugWindow"
}

/// Two top-aligned columns, the narrower one at most `narrowMax` wide, `spacing` apart. When iPhone
/// Duo is half open like a book, the gap moves onto the fold and widens by it, so neither column bends
/// through the crease (the outer margins stay as they were; Apple's Fitness grid does the same).
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

/// `ColumnSplit` with its own fold reader: two columns (the content's two views) that meet at the fold.
struct FoldColumns<Content: View>: View {
    var narrow: ColumnSplit.Narrow
    var narrowMax: Double
    var spacing: Double
    @ViewBuilder var content: Content
    @State private var fold: Fold?
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.nyxReduceMotion) private var forcedReduceMotion
    var body: some View {
        ColumnSplit(narrow: narrow, narrowMax: narrowMax, spacing: spacing, fold: fold) { content }
            .readingFold($fold)
            // The columns ease to the fold as the hinge turns (small moves, on the shared spring).
            .animation(systemReduceMotion || forcedReduceMotion ? nil : NyxMotion.spring, value: fold)
    }
}
