import SwiftUI

/// A park's closure, said one way on every screen: the filled warning glyph in the caution colour,
/// the words in ink, and VoiceOver's "Closure alert: …" (`ClosureLine.spoken`) whatever is shown.
/// Its lines grow at every text size and never clip. Under a score (`hero`) it sits directly under
/// the dial or numeral on a dark scrim, so no bright stretch of the Milky Way behind it costs it
/// contrast, centred until accessibility sizes read it from the leading edge; in a row it is one line
/// among the others.
struct ClosureLabel: View {
    enum Prominence { case hero, row }
    @Environment(\.nyx) private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    let closure: String
    var prominence: Prominence = .row
    /// Centred, as under a centred answer (every hero, and a row's line under one); leading otherwise.
    var centered: Bool
    /// "Closure alert: …" in words on screen too, where the glyph alone may not be enough (Assistive
    /// Access, a stay in a trip's plan that is not under its score).
    var named=false
    /// A park page's closure is the way to its other alerts: a chevron says so, but not at
    /// accessibility sizes, where the words need the whole width.
    var opens=false
    /// The size where a screen sets all its type larger (Assistive Access); else the prominence's own.
    var font: Font?
    init(_ closure: String, prominence: Prominence = .row, centered: Bool? = nil, named: Bool = false, opens: Bool = false, font: Font? = nil) {
        self.closure=closure; self.prominence=prominence; self.centered=centered ?? (prominence == .hero)
        self.named=named; self.opens=opens; self.font=font
    }
    var body: some View {
        let large=typeSize.isAccessibilitySize
        let label=HStack(alignment:.firstTextBaseline,spacing:6) {
            // The glyph filled, drawn here rather than through `CautionLabelStyle`, whose icon came out as the outline.
            Label { words.foregroundStyle(palette.ink) }
                icon:{ Image(systemName:"exclamationmark.triangle").symbolVariant(.fill).foregroundStyle(palette.caution) }
                .multilineTextAlignment(centered && !large ? .center : .leading)
                .fixedSize(horizontal:false,vertical:true)
            if opens && !large { Image(systemName:"chevron.forward").font(.caption.weight(.semibold)).foregroundStyle(palette.muted) }
        }
        .font(font ?? (prominence == .hero ? .subheadline : .footnote))
        Group {
            if prominence == .hero {
                label.padding(.horizontal,12).padding(.vertical,6).frame(minHeight:opens ? 44 : nil)
                    .background(Color.black.opacity(0.6),in:RoundedRectangle(cornerRadius:NyxMetrics.chipRadius,style:.continuous))
            } else { label }
        }
        // One element in its own words, and text, as a label is: an element without the trait reads as
        // a control, held to a control's tap target.
        .accessibilityElement(children:.ignore)
        .accessibilityLabel(ClosureLine.spoken(closure))
        .accessibilityAddTraits(.isStaticText)
    }
    /// The closure in its own words, or after "Closure alert". Under a score the heading is a line of its
    /// own, held whole, so a narrow column never breaks it inside a word ("Sper-" in German) and leaves only
    /// that on the first screen: on one line at its size or at three quarters of it, else on two lines broken
    /// at a space at three quarters (two lines at full size would leave the second under an iPhone SE's tab
    /// bar at the largest size), and only a single word too long for that is made smaller still.
    @ViewBuilder private var words: some View {
        if named && prominence == .hero {
            let alignment:HorizontalAlignment=centered && !typeSize.isAccessibilitySize ? .center : .leading
            let heading=String(localized:"Closure alert")
            VStack(alignment:alignment,spacing:2) {
                ViewThatFits(in:.horizontal) {
                    Text(heading).lineLimit(1)
                    Text(heading).font(.system(size:headingSize*0.75,weight:.semibold)).lineLimit(1)
                    if let lines=Self.headingLines(heading) {
                        VStack(alignment:alignment,spacing:0) { Text(lines.0).lineLimit(1); Text(lines.1).lineLimit(1) }.font(.system(size:headingSize*0.75,weight:.semibold))
                    }
                    Text(heading).lineLimit(1).minimumScaleFactor(0.5).allowsTightening(true)
                }.fontWeight(.semibold)
                Text(closure)
            }
        } else { Text(named ? ClosureLine.spoken(closure) : closure) }
    }
    /// The hero's text size (the subheadline style's 15 pt, scaled), for a heading set smaller than it.
    @ScaledMetric(relativeTo:.subheadline) private var headingSize=15.0
    /// A heading of more than one word as two lines broken at the space that best balances them, the first
    /// line the longer on a tie; nil for a single word.
    nonisolated static func headingLines(_ heading:String)->(String,String)? {
        let words=heading.split(separator:" ").map(String.init)
        guard words.count>1 else { return nil }
        let splits=(1..<words.count).map { (words[..<$0].joined(separator:" "),words[$0...].joined(separator:" ")) }
        return splits.min { max($0.0.count,$0.1.count)<max($1.0.count,$1.1.count) || max($0.0.count,$0.1.count)==max($1.0.count,$1.1.count) && $0.0.count>$1.0.count }
    }
}

private let previewClosure="Keys View Road closed at night for repairs through the end of the month"
#Preview("Closure • hero") { ClosureLabel(previewClosure,prominence:.hero).padding(24).background(.black).preferredColorScheme(.dark) }
#Preview("Closure • hero, opens the alerts") { ClosureLabel(previewClosure,prominence:.hero,opens:true).padding(24).background(.black).preferredColorScheme(.dark) }
#Preview("Closure • row") { ClosureLabel(previewClosure).padding(24).background(.black).preferredColorScheme(.dark) }
#Preview("Closure • named") { ClosureLabel(previewClosure,named:true,font:.title3.weight(.semibold)).padding(24).background(.black).preferredColorScheme(.dark) }
#Preview("Closure • hero, named, AX5") { ClosureLabel(previewClosure,prominence:.hero,named:true).dynamicTypeSize(.accessibility5).frame(width:300).padding(24).background(.black).preferredColorScheme(.dark) }
#Preview("Closure • hero AX5") { ClosureLabel(previewClosure,prominence:.hero,opens:true).dynamicTypeSize(.accessibility5).padding(24).background(.black).preferredColorScheme(.dark) }
#Preview("Closure • Increase Contrast") { ClosureLabel(previewClosure,prominence:.hero).environment(\.nyx,NyxPalette(nightVision:false,highContrast:true)).padding(24).background(.black).preferredColorScheme(.dark) }
#Preview("Closure • night vision") {
    ClosureLabel(previewClosure,prominence:.hero).environment(\.nyx,NyxPalette(nightVision:true,highContrast:false)).padding(24).background(.black)
        .modifier(NightVisionFilter(enabled:true)).preferredColorScheme(.dark)
}
