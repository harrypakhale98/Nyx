import SwiftUI

/// iPad: a screen's width decides its composition, never the device. The same rules serve a
/// 13-inch iPad in landscape, a narrow window beside another app and an iPhone, so every width
/// gets the layout that fits it. Pure numbers, so they are tested.
nonisolated enum WideLayout {
    /// Two columns from this width up: a full-screen iPad in either orientation (11-inch portrait
    /// is 834 pt and stays single), or a large window. Narrower windows keep the phone's column.
    static let twoColumnWidth=900.0
    /// At accessibility text sizes a column needs about twice the room, so the split waits longer.
    static let twoColumnWidthLargeText=1180.0
    /// A comfortable line: about 70 characters of body text with the page's own padding.
    static let readableWidth=700.0
    /// Essays and forms read best a little narrower.
    static let proseWidth=680.0
    static func columns(width:Double,largeText:Bool)->Int {
        width>=(largeText ? twoColumnWidthLargeText : twoColumnWidth) ? 2 : 1
    }
    /// The hero column of a two-column page: wide enough for the gauge and the time river, never
    /// more than half the page. Whole points: a fractional column nudges the page's own width by a fraction of a point,
    /// which would be measured again, and the layout would never settle.
    static func leadingWidth(_ width:Double)->Double { min(520,max(400,width*0.42)).rounded() }
    /// The side margin that centres a column of at most `measure` points in `width`.
    static func margin(width:Double,measure:Double)->Double { max(0,(width-measure)/2) }
}

extension View {
    /// Content no wider than `measure`, centred: a readable column on a wide iPad, unchanged on iPhone.
    func readableColumn(_ measure:Double=WideLayout.readableWidth)->some View {
        frame(maxWidth:measure).frame(maxWidth:.infinity)
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
private struct ReadableForm: ViewModifier {
    let measure:Double
    @State private var width=0.0
    @ViewBuilder func body(content:Content)->some View {
        let margin=WideLayout.margin(width:width,measure:measure)
        // Only where the window is wider than the measure: below it the list keeps its own inset.
        if margin>20 { content.contentMargins(.horizontal,margin,for:.scrollContent).measuringWidth($width) }
        else { content.measuringWidth($width) }
    }
}
