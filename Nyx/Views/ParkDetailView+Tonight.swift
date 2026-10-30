import SwiftUI
import TipKit

extension ParkDetailView {
    // MARK: Tonight

    @ViewBuilder func tonightChapter(_ proxy:ScrollViewProxy)->some View {
        hero(proxy)
        river
        alerts
    }
    /// The park's state and Dark Sky status: the eyebrow carries data, not a slogan. A saved spot:
    /// "Your spot · California". A place abroad: what it is and where, "International Dark Sky Park · Catalonia, Spain".
    var eyebrow:String { park.isCatalogPlace ? park.worldEyebrow : park.placeEyebrow }
    /// The name and its night's date are one block at every size (a night opened from the calendar
    /// always says which night it is). The closure sits right under the score at every size, as on
    /// Tonight, and the rest follows in Tonight's order (`NightNotes`), so a closed road is read with
    /// the number. At accessibility sizes the words run long, so the whole header reads from the
    /// leading edge (the gauge stays centred): the score comes straight after the date, the closure
    /// right under it and the designation last, so the answer is on the first screen.
    private func hero(_ proxy:ScrollViewProxy)->some View {
        let large=typeSize.isAccessibilitySize, align:TextAlignment=large ? .leading : .center
        let range=CelestialGauge.modelRange(outlook,basis:night.basis)
        return VStack(alignment:large ? .leading : .center,spacing:12) {
            VStack(alignment:large ? .leading : .center,spacing:4) {
                if !large { Eyebrow(text:"\(eyebrow)",meta:true).multilineTextAlignment(align).padding(.bottom,2) }
                title(align:align)
                Text(park.dayLabel(night.id)).font(.subheadline).foregroundStyle(palette.muted)
            }
            gauge(range:range)
            if let closure=model.closure(park) { closureLine(closure,proxy) }
            NightNotes(night:night,isTonight:isTonight,range:range,align:align,typicalClouds:true,partialWindowsOnly:false) { alertsLine(proxy) }
            if large { Eyebrow(text:"\(eyebrow)",meta:true).multilineTextAlignment(align) }
            darkerCapsule
            commit.padding(.top,4)
            ScoreReadout(score:night.score,agreement:outlook?.agreement,isTonight:isTonight) { showBreakdown() }.padding(.top,typeSize.isAccessibilitySize ? 8 : 18)
                // Held with the dial (the zoom in, a forecast still loading), so its parts fill as it counts.
                .environment(\.nyxRevealHeld,heroHeld)
                // Offered once the readout itself is on screen, so the tip points at it, not past the fold.
                .onScrollVisibilityChange(threshold:0.9) { if $0 { readoutSeen=true } }
                // One tip at a time: the river's own tip, further down, goes first.
                .popoverTip(DebugScenario.screen == nil && !palette.nightVision && readoutSeen && !RiverTip().shouldDisplay ? ScoreTip() : nil)
            if isTonight { FieldEntry(park:park,night:night).padding(.top,typeSize.isAccessibilitySize ? 4 : 10) }
            KeepThisNightOffer(park:park).padding(.top,4)
        }
    }
    private func title(align:TextAlignment)->some View {
        Text(park.shortName).font(.system(.largeTitle,design:.serif)).multilineTextAlignment(align).accessibilityAddTraits(.isHeader)
            .onGeometryChange(for:Bool.self) { $0.frame(in:.scrollView).maxY<0 } action:{ titleGone=$0 }
    }
    /// One way to commit to a night, right under the answer it commits to: "I'm going". Nyx keeps
    /// watch on it and Tonight leads with it (`GoingPanel`); the calendar and the Lock Screen follow
    /// from it, offered once it is kept, each asking its own permission when tapped, never all at once.
    @ViewBuilder private var commit: some View {
        let large=typeSize.isAccessibilitySize
        VStack(alignment:large ? .leading : .center,spacing:4) {
            GoingButton(night:night,alignment:large ? .leading : .center)
            if GoingNights.shared.isGoing(park:park,night:night.id) {
                VStack(alignment:.leading,spacing:0) {
                    AddNightToCalendar(night:night)
                    // Tonight is followed from the hero, beside "I'm here tonight".
                    if !isTonight { FollowNightButton(night:night) }
                }
                .frame(maxWidth:large ? .infinity : 300)
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : NyxMotion.spring,value:GoingNights.shared.isGoing(park:park,night:night.id))
    }
    /// The dial, square to its drawing: the lines below start just under the times at its open ends.
    private func gauge(range:ClosedRange<Int>?)->some View {
        CelestialGauge(score:night.score.value,hasForecast:night.score.hasForecast,spokenBasis:night.basisCaption(),
                       revealKey:ScoreReveals.key(parkID:park.id,night:park.isoDay(night.id),score:night.score.value),
                       range:range,night:model.ring(night))
            .frame(maxWidth:.infinity)
            .scrollTransition { [motionReduced = reduceMotion] view,phase in view.scaleEffect(motionReduced || phase.isIdentity ? 1 : 0.95).opacity(motionReduced || phase.isIdentity ? 1 : 0.8) }
            .modifier(DepthParallax(depth:0.1))
            .environment(\.nyxRevealHeld,heroHeld)
    }
    /// The closure beside the score (`ClosureLabel`): the one line that must never be lost in the sky,
    /// and itself the way to the rest of the park's alerts.
    private func closureLine(_ closure:String,_ proxy:ScrollViewProxy)->some View {
        Button { toAlerts(proxy) } label:{ ClosureLabel(closure,prominence:.hero,opens:true).contentShape(Rectangle()) }
            .buttonStyle(.plain)
            .accessibilityHint(otherAlerts>0 ? "Shows the park's other alerts." : "Shows the park's alerts.")
    }
    /// The alerts' place among the night's lines (`NightNotes`): without a closure, a quiet "Before you
    /// go" leads to them when anything is listed. A place abroad says here that Nyx cannot see its
    /// closures, with its site.
    @ViewBuilder private func alertsLine(_ proxy:ScrollViewProxy)->some View {
        let large=typeSize.isAccessibilitySize
        if park.isCatalogPlace { UnknownClosuresNote(park:park,alignment:large ? .leading : .center).frame(maxWidth:420).padding(.horizontal,large ? 0 : 12).id("alerts") }
        else if model.closure(park) == nil, otherAlerts>0 {
            Button { toAlerts(proxy) } label:{
                Label("Before you go (\(otherAlerts))",systemImage:"exclamationmark.shield").font(.footnote.weight(.medium)).frame(minHeight:44).contentShape(Rectangle())
            }.buttonStyle(.plain).foregroundStyle(palette.ink)
            .accessibilityHint("Shows the park's other alerts.")
        }
    }
    private func toAlerts(_ proxy:ScrollViewProxy) { withAnimation(reduceMotion ? nil : NyxMotion.spring) { proxy.scrollTo("alerts",anchor:.top) } }
    /// This park's best night when it is clearly darker and still ahead (`NightVerdict.darker`): the
    /// night Best nights, Tonight and the river name too, in Tonight's capsule and words. A tap turns
    /// this page to that night, as choosing it on the river would; the dial and its words follow.
    @ViewBuilder private var darkerCapsule:some View {
        let ahead=model.nights(park,from:model.tonight(park),count:NightPlanner.horizon)
        if let darker=NightVerdict.darker(than:night,among:ahead) {
            Button { withAnimation(reduceMotion ? nil : NyxMotion.spring) { selected=darker.id } } label:{
                HStack(spacing:8) {
                    Image(systemName:"moon.stars").imageScale(.small).accessibilityHidden(true)
                    Text(NightVerdict.capsule(darker,here:true)).multilineTextAlignment(.leading)
                    Image(systemName:"chevron.forward").imageScale(.small).font(.caption.weight(.semibold)).accessibilityHidden(true)
                }
            }.buttonStyle(.capsuleAction)
            .accessibilityHint("Opens that night at the park.")
        }
    }
    /// Alerts other than the closure shown beside the score.
    private var otherAlerts:Int {
        let alerts=model.enrichments[park.id]?.alerts ?? []
        return alerts.count-(model.closure(park) == nil ? 0 : 1)
    }
    private var river: some View {
        Panel {
            let river=model.nights(park,from:riverStart,count:NightPlanner.horizon)
            TimeRiver(nights:river,selected:Binding(get:{selected ?? initialDate ?? model.tonight(park)},set:{selected=$0}),startsTonight:riverStart==model.tonight(park),outlooks:model.outlooks(river),markers:model.markers(river),open:{ _ in showBreakdown() },hold:$heldNight)
            if model.detailPausedForLowData { Label("Forecast detail paused in Low Data Mode.",systemImage:"antenna.radiowaves.left.and.right.slash").font(.caption).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true).padding(.top,8) }
            Divider().overlay(palette.line).padding(.top,10)
            // Where the night is decided, the way there: a quiet row, or the access note for a roadless park.
            // Committing to the night ("I'm going") sits up with the score it commits to (`commit`).
            NightDirections(park:park)
        }.id("river")
    }
    @ViewBuilder private var alerts: some View {
        // A place abroad says it under the score (`UnknownClosuresNote`), with its site: not again here.
        if park.isCatalogPlace { EmptyView() }
        // A place the Park Service does not run (a saved spot) has no alerts to show: said plainly, once.
        else if park.nps == nil {
            Panel { VStack(alignment:.leading,spacing:8) {
                Label("Before you go",systemImage:"exclamationmark.shield").font(.subheadline.weight(.medium)).accessibilityAddTraits(.isHeader)
                Text("Nyx has no alerts for this place. Check access, local rules and closures before you go.").font(.subheadline).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
            } }.id("alerts")
        } else { parkAlerts }
    }
    private var parkAlerts: some View {
        Panel { VStack(alignment:.leading,spacing:8) {
            // One count on the card, the one beside "All park alerts", so two numbers never seem to disagree.
            Label("Before you go",systemImage:"exclamationmark.shield").font(.subheadline.weight(.medium)).accessibilityAddTraits(.isHeader)
            Text(model.alertSummary(park)).font(.subheadline).foregroundStyle(palette.muted).fixedSize(horizontal:false,vertical:true)
            if model.alertsBusy { AlertsBusyNote(park:park,summarySaysBusy:model.enrichments[park.id] == nil) }
            if let data=model.enrichments[park.id],!data.alerts.isEmpty {
                DisclosureGroup {
                    ForEach(AlertRanking.ranked(data.alerts)) { alert in VStack(alignment:.leading,spacing:8) { Text(alert.displayTitle(park:park)).font(.headline).accessibilityAddTraits(.isHeader);Text(alert.description).font(.subheadline).foregroundStyle(palette.muted) }.padding(.vertical,8) }
                } label:{ Text("All park alerts (\(data.alerts.count))").frame(maxWidth:.infinity,minHeight:44,alignment:.leading) }
                // The Park Service writes in English: every alert, translated by iOS on this device.
                TranslateButton(text:AlertRanking.ranked(data.alerts).map { "\($0.title)\n\($0.description)" }.joined(separator:"\n\n"))
            }
            if let data=model.enrichments[park.id] { Text("Park update: \(park.timestamp(data.updated))").font(.caption).foregroundStyle(palette.muted) }
        } }.id("alerts")
    }
}
