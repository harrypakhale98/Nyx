import SwiftUI

/// iPad: a screen's width decides its composition, never the device. The same rules serve a
/// 13-inch iPad in landscape, a narrow window beside another app and an iPhone, so every width
/// gets the layout that fits it. Pure numbers, so they are tested.
nonisolated enum WideLayout {
    /// Two columns from this width up: a full-screen iPad in either orientation (11-inch portrait
    /// is 834 pt and stays single), iPhone Duo's inner display in landscape (951 pt less its side bar,
    /// about 880), or a large window. Narrower windows keep the phone's column, and so does a large
    /// iPhone in landscape (956 pt less both sides' safe areas, about 832).
    static let twoColumnWidth=860.0
    /// At accessibility text sizes a column needs about twice the room, so the split waits longer.
    static let twoColumnWidthLargeText=1180.0
    /// A comfortable line: about 70 characters of body text with the page's own padding.
    static let readableWidth=700.0
    /// Essays and forms read best a little narrower.
    static let proseWidth=680.0
    /// A two-column page's widest: both columns and the gap between them, centred beyond it, so on a
    /// 13-inch iPad in landscape the eye never travels a whole window between a score and its reasons.
    static let twoColumnMaximum=1240.0
    /// The page's measure at this width: two columns up to `twoColumnMaximum`, one at `readableWidth`.
    static func pageWidth(width:Double,largeText:Bool)->Double {
        columns(width:width,largeText:largeText)==2 ? twoColumnMaximum : readableWidth
    }
    static func columns(width:Double,largeText:Bool)->Int {
        width>=(largeText ? twoColumnWidthLargeText : twoColumnWidth) ? 2 : 1
    }
    /// The hero column of a two-column page: wide enough for the gauge and the time river, never
    /// more than half the page. Whole points: a fractional column nudges the page's own width by a fraction of a point,
    /// which would be measured again, and the layout would never settle.
    static func leadingWidth(_ width:Double)->Double { min(520,max(400,width*0.42)).rounded() }
    /// A trailing inspector (the night's breakdown beside the page) opens only in a regular-width
    /// window at least this wide, so the page beside it keeps about 640 points.
    static let inspectorWindow=1000.0
    /// Once open, the inspector stays while the page beside it keeps this much; narrower, it closes
    /// and the breakdown returns to a sheet. The gap between the two numbers keeps a resize from
    /// opening and closing it in turn (the page's width shrinks by the inspector's own width).
    static let inspectorPageMinimum=560.0
    /// Whether the inspector has room: `width` is the page's own width, which already excludes an open inspector.
    static func inspector(width:Double,open:Bool,regular:Bool,largeText:Bool)->Bool {
        guard regular, !largeText else { return false }
        return width>=(open ? inspectorPageMinimum : inspectorWindow)
    }
    /// Field mode in a wide landscape window: the night and "Where to look" side by side, each about
    /// the width of a phone's column or more. An iPhone in landscape (compact height) does the same
    /// from 600 points, since one page at a time would leave it a strip between header and footer.
    /// Portrait and narrow windows keep one page at a time, and so do accessibility text sizes.
    static let compactHeightSideBySide=600.0
    static func sideBySide(width:Double,height:Double,largeText:Bool,compactHeight:Bool=false)->Bool {
        guard width>height else { return false }
        return columns(width:width,largeText:largeText)==2 || (compactHeight && !largeText && width>=compactHeightSideBySide)
    }
    /// The side margin that centres a column of at most `measure` points in `width`.
    static func margin(width:Double,measure:Double)->Double { max(0,(width-measure)/2) }
    /// Each side's room beyond a two-column page's `twoColumnMaximum`, in whole points: kept as
    /// the outer scroll view's content margin, never by narrowing the scroll views, so a column
    /// still scrolls (and shows its indicator) at the window's edge.
    static func twoColumnSide(_ width:Double)->Double { margin(width:width,measure:twoColumnMaximum).rounded(.down) }
    /// How far a centred column of at most `measure` points moves so it centres on iPhone Duo's fold
    /// instead of on `width` (whose trailing side bar puts the middle of the space left of the
    /// crease). Whole points; zero without a fold that runs top to bottom near the middle, which on
    /// every other device and on the Duo's outer display means always.
    static func foldShift(width:Double,measure:Double,fold:Fold?)->Double {
        guard let fold, fold.dividesWidth, width>0 else { return 0 }
        let shift=((fold.minX+fold.maxX)/2-width/2).rounded()
        // A fold far from the middle (a narrow sheet it happens to cross) leaves the column centred.
        guard abs(shift)<=width/8 else { return 0 }
        return shift
    }
}

extension View {
    /// Content no wider than `measure`, centred: a readable column on a wide iPad, unchanged on iPhone.
    /// On iPhone Duo's inner display it centres on the fold, so a page sits square on the crease.
    func readableColumn(_ measure:Double=WideLayout.readableWidth)->some View {
        modifier(ReadableColumn(measure:measure))
    }
    /// A `Form` or `List` whose rows keep a readable width on a wide iPad. The scroll view still
    /// spans the window, so its indicator stays at the edge.
    func readableForm(_ measure:Double=WideLayout.proseWidth)->some View { modifier(ReadableForm(measure:measure)) }
    /// Reports this view's width in whole points, for pages that choose between one and two columns.
    /// Sub-point changes are ignored, so a layout can never chase its own rounding.
    func measuringWidth(_ width:Binding<Double>)->some View {
        onGeometryChange(for:Double.self) { $0.size.width.rounded() } action:{ if abs($0-width.wrappedValue)>=1 { width.wrappedValue=$0 } }
    }
}
private struct ReadableColumn: ViewModifier {
    let measure:Double
    @State private var width=0.0
    @State private var fold:Fold?
    func body(content:Content)->some View {
        // The shift is twice the padding on one side: the column is centred in what remains, so its
        // middle lands on the fold. The outer frame keeps the full width, which alone is measured.
        let shift=WideLayout.foldShift(width:width,measure:measure,fold:fold)
        return content.frame(maxWidth:measure)
            .padding(.leading,max(0,shift*2)).padding(.trailing,max(0,-shift*2))
            .frame(maxWidth:.infinity)
            .measuringWidth($width).readingFold($fold)
    }
}
private struct ReadableForm: ViewModifier {
    let measure:Double
    @State private var width=0.0
    func body(content:Content)->some View {
        let margin=WideLayout.margin(width:width,measure:measure)
        // Only where the window is wider than the measure: below it the list keeps its own inset.
        // One branch, so a window resized across the threshold keeps the form (its scroll position
        // and focus): the narrow case sets a zero margin on the indicators, which is their default.
        let wide=margin>20
        return content.contentMargins(.horizontal,wide ? margin : 0,for:wide ? ContentMarginPlacement.scrollContent : .scrollIndicators).measuringWidth($width)
    }
}
