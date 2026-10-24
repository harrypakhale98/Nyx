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
    /// Tonight, before the verdict, so a closed road is read with the number. At accessibility sizes the words
    /// run long, so the whole header reads from the leading edge (the gauge stays centred): the score
    /// comes straight after the date, the closure right under it and the designation last, so the
    /// answer is on the first screen; the date before the dial costs the closure nothing.
    private func hero(_ proxy:ScrollViewProxy)->some View {
        let large=typeSize.isAccessibilitySize, align:TextAlignment=large ? .leading : .center
        let range=CelestialGauge.modelRange(outlook,basis:night.basis)
        return VStack(alignment:large ? .leading : .center,spacing:12) {
            if large {
                VStack(alignment:.leading,spacing:4) {
                    title(align:align)
                    Text(park.dayLabel(night.id)).font(.subheadline).foregroundStyle(palette.muted)
                }
                gauge(range:range)
            } else {
                VStack(spacing:4) {
                    Eyebrow(text:"\(eyebrow)",meta:true).multilineTextAlignment(align).padding(.bottom,2)
                    title(align:align)
                    Text(park.dayLabel(night.id)).font(.subheadline).foregroundStyle(palette.muted)
                }
            }
            if large {
                alertLine(proxy,align:align)
                Eyebrow(text:"\(eyebrow)",meta:true).multilineTextAlignment(align)
            }
            // Only when there is a note, so an empty slot never adds a gap above the dial.
            if park.accessNote != nil { AccessNoteLabel(park:park,alignment:large ? .leading : .center).frame(maxWidth:420).padding(.horizontal,large ? 0 : 12) }
            if !large {
                gauge(range:range)
                alertLine(proxy,align:align)
            }
            if night.sky.state == .polarNight { Text("The Sun stays below the horizon today.").font(.subheadline).foregroundStyle(palette.muted).multilineTextAlignment(align) }
            if night.sky.darkHours==0 { Text(SkyConditions.noDarknessMessage(tonight:isTonight)).font(.body).foregroundStyle(palette.ink).multilineTextAlignment(align) }
            // The night in plain words first: where the Moon is, and whether the Milky Way is worth the drive.
            if let verdict=verdict {
                Text(verdict.text).font(.subheadline).foregroundStyle(palette.ink).multilineTextAlignment(align)
                    .fixedSize(horizontal:false,vertical:true).padding(.horizontal,large ? 0 : 12)
                    .accessibilityLabel(verdict.spoken)
            }
            if let caption=night.basisCaption(typical:true) {
                // The gauge speaks the first sentence; VoiceOver hears only the month's usual clouds here.
                Text(caption).font(.caption).foregroundStyle(palette.muted).multilineTextAlignment(align)
                    .accessibilityLabel(night.typicalClouds ?? caption).accessibilityHidden(night.typicalClouds == nil)
            }
            // How sure the forecast is, in Tonight's words for the same night (`ForecastSpread`).
            if let spread=ForecastSpread.line(agreement:outlook?.agreement,range:range,tonight:isTonight) {
                let disagree=outlook?.agreement?.band == .disagree
                Text(spread).font(.caption).monospacedDigit().foregroundStyle(palette.muted).multilineTextAlignment(align)
                    .fixedSize(horizontal:false,vertical:true).padding(.horizontal,large ? 0 : 12)
                    // The gauge speaks the score range; the models' disagreement is news it does not say.
                    .accessibilityHidden(!disagree)
            }
            // A caveat in words, in ink: amber is the score's and the light's.
            if let smoke=model.smokeCaveat(night) { Label(smoke,systemImage:"smoke").font(.subheadline).foregroundStyle(palette.ink).multilineTextAlignment(align).fixedSize(horizontal:false,vertical:true).padding(.horizontal,large ? 0 : 12) }
            if let window=model.clearWindow(night) {
                // At accessibility sizes the glyph would take a column of its own: the words alone. Under
                // a bright Moon the clear hours are not the night's best, and their glyph says so.
                Label { Text(window.line(park:park)).fixedSize(horizontal:false,vertical:true) } icon:{ if !typeSize.isAccessibilitySize { Image(systemName:window.moonlit ? "moon" : "sparkles").accessibilityHidden(true) } }
                    .font(.subheadline).foregroundStyle(palette.ink).multilineTextAlignment(align).padding(.horizontal,large ? 0 : 12)
                    .accessibilityElement(children:.combine)
            }
            darkerCapsule
            commit.padding(.top,4)
            ScoreReadout(score:night.score,agreement:outlook?.agreement,isTonight:isTonight) { showBreakdown() }.padding(.top,typeSize.isAccessibilitySize ? 8 : 18)
                .popoverTip(DebugScenario.screen == nil && !palette.nightVision ? ScoreTip() : nil)
            // Under the score at a place abroad: Nyx cannot see its closures, so it says so and points to the park's own site.
            if park.isCatalogPlace { UnknownClosuresNote(park:park,alignment:large ? .leading : .center).frame(maxWidth:420).padding(.horizontal,large ? 0 : 12).id("alerts") }
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
    /// The park's alerts in one line beside the score. A closure is the one line that must never be
    /// lost in the sky: on a dark scrim, and itself the way to the rest of the park's alerts. Without
    /// one, a quiet "Before you go" leads there when anything else is listed.
    @ViewBuilder private func alertLine(_ proxy:ScrollViewProxy,align:TextAlignment)->some View {
        let toAlerts={ withAnimation(reduceMotion ? nil : NyxMotion.spring) { proxy.scrollTo("alerts",anchor:.top) } }
        if let closure=model.closure(park) {
            Button(action:toAlerts) {
                HStack(alignment:.firstTextBaseline,spacing:6) {
                    Label(closure,systemImage:"exclamationmark.triangle").labelStyle(.caution).multilineTextAlignment(align).fixedSize(horizontal:false,vertical:true)
                    // At accessibility sizes the words take the whole width ("temporarily" broke mid-word beside it).
                    if !typeSize.isAccessibilitySize { Image(systemName:"chevron.forward").font(.caption.weight(.semibold)).foregroundStyle(palette.muted).accessibilityHidden(true) }
                }
                .font(.subheadline)
                .padding(.horizontal,12).padding(.vertical,6).frame(minHeight:44)
                .background(Color.black.opacity(0.6),in:RoundedRectangle(cornerRadius:12)).contentShape(Rectangle())
            }.buttonStyle(.plain)
            .accessibilityLabel(ClosureLine.spoken(closure))
            .accessibilityHint(otherAlerts>0 ? "Shows the park's other alerts." : "Shows the park's alerts.")
        } else if otherAlerts>0 {
            Button(action:toAlerts) {
                Label("Before you go (\(otherAlerts))",systemImage:"exclamationmark.shield").font(.footnote.weight(.medium)).frame(minHeight:44).contentShape(Rectangle())
            }.buttonStyle(.plain).foregroundStyle(palette.ink)
            .accessibilityHint("Shows the park's other alerts.")
        }
    }
    /// The plain sentence under the dial (`NightVerdict`): the Moon and the Milky Way. A darker night
    /// ahead is not a sentence in it but the capsule below (`darkerCapsule`), as on Tonight.
    private var verdict:NightVerdict.Line? {
        NightVerdict.line(sky:night.sky,core:model.whatsUp(night).coreNight,park:park)
    }
    /// This park's best night when it is clearly darker and still ahead (`NightVerdict.darker`): the
    /// night Best nights, Tonight and the river name too, in Tonight's capsule and words. A tap turns
    /// this page to that night, as choosing it on the river would; the dial and its words follow.
    @ViewBuilder private var darkerCapsule:some View {
        let ahead=model.nights(park,from:model.tonight(park),count:NightVerdict.horizon)
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
            let river=model.nights(park,from:riverStart,count:30)
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
