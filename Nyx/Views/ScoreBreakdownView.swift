import SwiftUI

struct ScoreBreakdownView: View {
    @Environment(\.nyx) private var palette
    @Environment(PlanModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @MotionReduced private var reduceMotion: Bool
    let night:Night
    var isTonight=true
    /// Beside the month on a wide iPad: the breakdown without its own page, background or Done.
    var inline=false
    /// What the screen that opened it offers next for the night (Plan: I'm going, its page), above
    /// Share, so the breakdown leads somewhere rather than ending at the score.
    var actions:AnyView?=nil
    @ScaledMetric(relativeTo:.largeTitle) private var numeralSize=72.0
    /// The context lines' symbol column, as wide as the widest symbol at the reader's text size.
    @ScaledMetric(relativeTo:.callout) private var contextIcon=24.0
    /// The Little Dipper beside its sentence in Sky glow.
    @ScaledMetric(relativeTo:.callout) private var dipperWidth=56.0
    var body: some View {
        if inline { content }
        else {
            ScrollView { content.padding(24).readableColumn() }
                // `-nyx-bottom` (DEBUG) opens at the end, for review captures of the actions.
                .defaultScrollAnchor(DebugScenario.isEnabled("bottom") ? .bottom : .top)
                .background(NightBackground(score:night.score.value,park:night.park,night:night.id)).foregroundStyle(palette.ink).navigationTitle("Score breakdown").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.cancellationAction) { Button(role:.close) { dismiss() } } }.singleControlBar()
        }
    }
    private var scoreNumeral: some View {
        Text("\(night.score.value)").scoreNumeral(size:numeralSize,accent:palette.accent).contentTransition(reduceMotion ? .opacity : .numericText(value:Double(night.score.value)))
    }
    private var scoreBand: some View {
        VStack(alignment:.leading,spacing:2) { Text(night.score.band.label).font(.system(.title2,design:.serif)).fixedSize(horizontal:false,vertical:true); Text("out of 100").font(.caption).foregroundStyle(palette.muted) }
    }
    private var content: some View {
        VStack(alignment:.leading,spacing:26) {
            // The eyebrow, then the numeral: the navigation bar already says "Score breakdown".
            Eyebrow(text:"\(night.park.shortName) · \(night.park.dayLabel(night.id))",meta:true)
            // The band keeps its whole width beside the numeral (a one-word band cannot wrap, so a squeezed
            // frame clips it); when both do not fit, as at accessibility sizes, the band goes underneath.
            ViewThatFits(in:.horizontal) {
                HStack(alignment:.firstTextBaseline,spacing:12) { scoreNumeral; scoreBand.fixedSize() }
                VStack(alignment:.leading,spacing:4) { scoreNumeral; scoreBand }
            }
            .accessibilityElement(children:.combine)
            // The weakest link, said beside the number it sets, before the parts that add up to more.
            if let limit=night.score.limit, limit.cap<partsSum {
                if case .darkness = limit {} else {
                    figures(Sentences.join([limit.sentence(tonight:isTonight),String(localized:"The four parts alone would give \(partsSum).")]))
                }
            }
            row("Moonlight",points:Double(shown.moon),of:40,fact:moonFact,detail:String(localized:"How bright the Moon is by phase and how high it stands, through true darkness. A low Moon counts for less than a high one."))
            row("Clouds",points:shown.cloud.map(Double.init),of:25,fact:Self.cloudFact(night),
                context:cloudContext,detail:Self.cloudDetail(usualClouds:night.usualCloud != nil,context:!cloudContext.isEmpty))
            row("Sky glow",points:Double(shown.glow),of:20,fact:String(localized:"Bortle class \(night.park.bortleEstimate) of 9, estimated."),context:lightContext,dipper:LittleDipper.reading(night),detail:String(localized:"Artificial light in the sky, as a conservative Bortle estimate. It is not a measurement."))
            row("True darkness",points:Double(shown.length),of:15,fact:night.sky.darkHours>0 ? String(localized:"\(darkness) of true darkness.") : String(localized:"No true darkness."),detail:String(localized:"True darkness: the Sun more than 18° below the horizon. Ten hours earn full credit."))
            if let caption=night.basisCaption(typical:true) { Text(Sentences.join([caption,String(localized:"The score will change as a forecast arrives.")])).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true) }
            // What the score leaves out, said once and quietly: smoke switched off, or no smoke forecast reaching the night.
            if let smoke=model.smokeNote(night) { Text(smoke).font(.footnote).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true) }
            if night.sky.darkHours==0 { figures(isTonight ? String(localized:"No true darkness tonight at this latitude. The score is capped below 40.") : String(localized:"No true darkness on this night at this latitude. The score is capped below 40.")) }
            else if ScoreEngine.cap(darkHours:night.sky.darkHours)<100 { figures(isTonight ? String(localized:"True darkness lasts only \(darkness) tonight, so the score is held to \(ScoreEngine.cap(darkHours:night.sky.darkHours)) or less.") : String(localized:"True darkness lasts only \(darkness) on this night, so the score is held to \(ScoreEngine.cap(darkHours:night.sky.darkHours)) or less.")) }
            if let event=model.events(night).item(park:night.park,sky:night.sky,isTonight:isTonight) {
                // An eclipse or a shower peak is a reason to go, said beside the score, never in it.
                HStack(alignment:.top,spacing:14) {
                    SkyGlyph(item:event.kind,color:palette.accent).frame(width:22,height:22).padding(.top,2)
                    VStack(alignment:.leading,spacing:6) {
                        Text([event.title,event.note].compactMap { $0 }.joined(separator:", ")).font(.headline)
                        if let value=event.value { Text(value).font(.system(.title3,design:.serif)).foregroundStyle(palette.ink) }
                        Text(event.detail).font(.callout).fixedSize(horizontal:false,vertical:true)
                        Text("Also in the sky this night. Not part of the score.").font(.footnote).foregroundStyle(palette.muted)
                    }
                }
                .accessibilityElement(children:.ignore).accessibilityLabel(event.spoken+" "+String(localized:"Also in the sky this night. Not part of the score."))
            }
            // Dates and the night's hours here are the park's own, wherever this phone is.
            Text(Sentences.join([String(localized:"Each park uses its own local date."),String(localized:"The score is a planning guide, not a guarantee of visibility or safe access.")])).font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
            VStack(alignment:.leading,spacing:12) {
                if let actions { actions }
                ShareCardButton(night:night)
            }
        }
    }
    /// A sentence about what holds the score down, in starlight with only its figures in amber: the
    /// numbers are the score's, so they take its colour, and the words around them stay calm.
    /// Through night vision both are the one red, which loses nothing: the words say it all.
    private func figures(_ sentence:String)->some View {
        Text(Self.figuresLit(sentence,accent:palette.accent)).foregroundStyle(palette.ink).fixedSize(horizontal:false,vertical:true)
    }
    /// `sentence` with each run of digits coloured `accent`, as one attributed string so it wraps,
    /// scales and reads to VoiceOver as the plain sentence does.
    nonisolated static func figuresLit(_ sentence:String,accent:Color)->AttributedString {
        var lit=AttributedString()
        var rest=Substring(sentence)
        while let first=rest.first {
            let figure=first.isWholeNumber
            let run=rest.prefix { $0.isWholeNumber==figure }
            var part=AttributedString(run)
            if figure { part.swiftUI.foregroundColor=accent }
            lit+=part
            rest=rest.dropFirst(run.count)
        }
        return lit
    }
    /// The four parts' sum before any cap, as the readout shows them.
    private var partsSum:Int { night.score.partsSum }
    /// Whole points that add up to `partsSum`, so the rows make the sum the caption names.
    private var shown:(moon:Int,cloud:Int?,glow:Int,length:Int) { night.score.displayedParts }
    /// How the clouds are scored. Where the place has no usual clouds for the month there is nothing
    /// to ease toward: an early look counts its forecast as it stands (`NightPlanner.night`).
    nonisolated static func cloudDetail(usualClouds:Bool,context:Bool)->String {
        switch (usualClouds,context) {
        case (true,false): String(localized:"The hourly forecast averaged over true darkness. Beyond about three days it is eased toward the park's usual clouds for the month; with no forecast, the usual clouds count alone.")
        case (true,true): String(localized:"The hourly forecast averaged over true darkness, eased toward the park's usual clouds beyond about three days. Model agreement and cloud layers are context; smoke or haze can cap the score.")
        case (false,false): String(localized:"The hourly forecast averaged over true darkness, counted as it stands: there are no usual clouds for this place. With no forecast, the score counts the Moon and darkness only.")
        case (false,true): String(localized:"The hourly forecast averaged over true darkness, counted as it stands: there are no usual clouds for this place. Model agreement and cloud layers are context; smoke or haze can cap the score.")
        }
    }
    /// The fact the clouds were scored from, in the words every surface uses for the night's basis.
    nonisolated static func cloudFact(_ night:Night)->String {
        switch night.basis {
        case .forecast: return night.cloudCover.map { String(localized:"\(Int($0.rounded()))% average cover through true darkness.") } ?? String(localized:"No cloud forecast yet.")
        case .blended(_, let lead):
            guard let forecast=night.cloudCover, let counted=night.score.cloudUsed else { return String(localized:"An early look at the clouds.") }
            let days=max(1,Int(lead.rounded()))
            // Nothing to ease toward: the forecast is what counts, said once.
            guard night.usualCloud != nil else { return String(localized:"Early look: a forecast of \(Int(forecast.rounded()))% from \(days) days out, counted as it stands.") }
            return String(localized:"Early look: a forecast of \(Int(forecast.rounded()))% from \(days) days out, eased toward the usual clouds. Counted as \(Int(counted.rounded()))%.")
        case .usual:
            // "No cloud forecast yet." or "Cloud forecast unavailable.", as every surface says it.
            guard let usual=night.usualCloud else { return Sentences.join([night.noForecastSentence ?? "",String(localized:"This score counts the Moon and darkness only.")]) }
            return Sentences.join([night.noForecastSentence ?? "",String(localized:"Usual clouds here at this time of year: \(Int(usual.rounded()))%.")])
        }
    }
    private var moonFact:String {
        let lit=String(localized:"\(night.sky.moon.name), \(Int((night.sky.moon.illumination*100).rounded()))% lit.")
        guard let line=night.sky.moonBelowLine else { return lit }
        return Sentences.join([lit,line])
    }
    /// Model agreement, the cloud layer and the air, each one sentence with a quiet symbol, so the
    /// context reads as a step below the fact the score was computed from.
    private var cloudContext:[(symbol:String,text:String)] {
        guard let outlook=model.outlook(night) else { return [] }
        let lines:[(String,String?)]=[("rectangle.split.3x1",outlook.agreement?.sentence(tonight:isTonight)),("cloud",outlook.layers?.note),
                                      // Very dry, clean air says "Clear air." and more, so it stands in for it.
                                      (outlook.clarity.map(Self.airSymbol) ?? "aqi.low",outlook.crispText == nil ? outlook.airSentence : nil),("sun.haze",outlook.clarity == nil ? outlook.hazeText : nil),
                                      ("sparkles",outlook.crispText)]
        return lines.compactMap { symbol,text in text.map { (symbol,$0) } }
    }
    /// The air's symbol: clean air is not drawn as smoke.
    private static func airSymbol(_ clarity:AirClarity)->String {
        switch clarity { case .clear: "aqi.low"; case .lightHaze: "aqi.medium"; case .haze,.heavy: "smoke" }
    }
    /// NASA's night lights, as context beside the estimate the score uses.
    private var lightContext:[(symbol:String,text:String)] {
        guard let site=SkyGlow.shared.park(night.park.id) else { return [] }
        let lights=String(localized:"Satellite night lights: \(SkyGlow.levelLabel(SkyGlow.shared.level(site.glow))). Context only; not part of the score.")
        // The Park Service's darkest measured site, with its year: also context only.
        guard let darkest=MeasuredSky.shared.sites(night.park.id).first, let measured=darkest.latest, let year=measured.year else { return [("globe.americas",lights)] }
        return [("globe.americas",lights),
                ("camera.aperture",String(localized:"Measured by the Park Service at its darkest site here, \(darkest.name): \(MeasuredSky.reading(measured.sqm)) in \(MeasuredSky.span(year...year)) (higher is darker). Context only; not part of the score."))]
    }
    private var darkness:String { Duration.seconds(night.sky.darkHours*3600).formatted(.units(allowed:[.hours,.minutes],width:.wide)) }
    /// `weight` is the component's share of 100; with no cloud figure at all the others are scaled up to fill it.
    /// Each part states the fact it was scored from, then how it is scored.
    /// `dipper`: the Sky glow part's illustration, what that glow and the night's Moon leave of the Little Dipper.
    private func row(_ title:LocalizedStringKey,points:Double?,of weight:Double,fact:String,context:[(symbol:String,text:String)]=[],dipper:LittleDipper.Reading?=nil,detail:String)->some View {
        let maximum=night.score.cloudPoints != nil || points==nil ? weight : weight/0.75
        return VStack(alignment:.leading,spacing:9) {
            ViewThatFits(in:.horizontal) {
                HStack(alignment:.firstTextBaseline) { Text(title).font(.headline);Spacer();amount(points,of:maximum) }
                VStack(alignment:.leading,spacing:4) { Text(title).font(.headline);amount(points,of:maximum) }
            }
            GeometryReader { proxy in
                ZStack(alignment:.leading) {
                    if let points {
                        Capsule().fill(palette.line)
                        Capsule().fill(palette.accent).frame(width:points>0 ? max(4,proxy.size.width*min(1,points/maximum)) : 0)
                    } else { Capsule().stroke(palette.line,style:StrokeStyle(lineWidth:1,dash:[2,3])) }
                }
            }.frame(height:4).accessibilityHidden(true)
            // Sans for what a part was scored from; serif is kept for the figures and the night's name.
            Text(fact).font(.body).fixedSize(horizontal:false,vertical:true)
            if !context.isEmpty {
                VStack(alignment:.leading,spacing:6) {
                    ForEach(context,id:\.text) { line in
                        // One icon column, so lines with narrower or wider symbols start their words together.
                        Label { Text(line.text).fixedSize(horizontal:false,vertical:true) } icon:{ Image(systemName:line.symbol).foregroundStyle(palette.muted).frame(width:contextIcon).accessibilityHidden(true) }
                    }
                }.font(.callout).foregroundStyle(palette.ink.opacity(palette.nightVision ? 1 : 0.88)).padding(.top,2)
            }
            if let dipper {
                // The drawing beside its sentence; at accessibility sizes it sits above, so the words keep the width.
                let glyph=LittleDipperGlyph(reading:dipper).frame(width:min(dipperWidth,112))
                let sentence=Text(dipper.sentence).font(.callout).foregroundStyle(palette.ink.opacity(palette.nightVision ? 1 : 0.88)).fixedSize(horizontal:false,vertical:true)
                Group {
                    if typeSize.isAccessibilitySize { VStack(alignment:.leading,spacing:6) { glyph; sentence } }
                    else { HStack(alignment:.center,spacing:12) { glyph; sentence } }
                }.padding(.top,2)
            }
            Text(detail).font(.footnote).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
        }
        .padding(.vertical,2)
        .accessibilityElement(children:.combine)
    }
    @ViewBuilder private func amount(_ points:Double?,of maximum:Double)->some View {
        if let points { Text("\(Int(points.rounded())) of \(Int(maximum.rounded()))").font(.system(.title3,design:.serif)).foregroundStyle(palette.accent) }
        else { Text("Unknown").font(.system(.title3,design:.serif)).foregroundStyle(palette.muted) }
    }
}
