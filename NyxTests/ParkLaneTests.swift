import Foundation
import Testing
import SwiftUI
@testable import Nyx

/// The park page's wave-2 pieces: the gauge's count-up and sizes, the field countdown, keeping a
/// night, the Moon hero, the sky renderer and Bortle model, viewing spots, programs, What's up's
/// order, chapters and sharing.
@MainActor @Suite struct ParkLaneTests {
    let engine=AstronomyEngine()
    func park(_ id:String) throws -> Park { try #require(try ParkData.load().first { $0.id==id }) }
    func date(_ text:String) throws -> Date { try #require(try? Date(text,strategy:.iso8601)) }
    func night(_ park:Park,_ day:String,score:Int=80) throws -> Night {
        let sky=engine.conditions(for:park,on:park.evening(try date(day+"T20:00:00Z")))
        return Night(park:park,sky:sky,score:DarknessScore(value:score,moonPoints:30,cloudPoints:24,bortlePoints:16,lengthPoints:10),cloudCover:5,forecastUpdated:.now)
    }

    // MARK: Gauge

    @Test func countUpIsFastFirstAndLandsOnTheScore() {
        let early=CelestialGauge.progress(0.1)-CelestialGauge.progress(0), late=CelestialGauge.progress(1.1)-CelestialGauge.progress(1.0)
        #expect(early>5*late)
        for score in [1,23,64,94,100] {
            #expect(CelestialGauge.countValue(score:score,at:0)==0)
            #expect(CelestialGauge.countValue(score:score,at:CelestialGauge.duration(score:score))==score)
            // Never past the score on the way up.
            #expect(stride(from:0.0,through:3,by:0.05).allSatisfy { CelestialGauge.countValue(score:score,at:$0)<=score })
        }
        // The arc leads the numeral.
        #expect(CelestialGauge.countValue(score:90,at:0.05)==0)
    }
    @Test func milestonesTickOnceEach() {
        #expect(CelestialGauge.milestones(from:60,to:75)==[70])
        #expect(CelestialGauge.milestones(from:65,to:95)==[70,90])
        #expect(CelestialGauge.milestones(from:70,to:89).isEmpty)
    }
    /// AX-05/DX-10: at accessibility sizes the numeral stays well above the band label, within the width.
    @Test func accessibleNumeralOutranksTheBand() {
        for band in [20.0,28,38,47,53] {
            let side=CelestialGauge.accessibleSide(band:band,width:345)
            let numeral=CelestialGauge.accessibleNumeral(band:band,side:side)
            #expect(side<=345)
            #expect(numeral>=1.6*band)
        }
    }

    // MARK: Field countdown (DX-02)

    @Test func countdownRoundsUpToWholeMinutes() {
        #expect(FieldCountdown.parts(22*60+39)==(0,23))
        #expect(FieldCountdown.parts(90*60+10)==(1,31))
        #expect(FieldCountdown.parts(3600)==(1,0))
        #expect(FieldCountdown.parts(-5)==(0,0))
    }
    @Test func countdownTicksOnMinuteBoundariesThenSeconds() {
        let start=Date(timeIntervalSince1970:1_000_000)
        let target=start.addingTimeInterval(5*60+20)
        let ticks=Array(FieldCountdownSchedule(target:target).entries(from:start,mode:.normal).prefix(5))
        #expect(ticks.map { target.timeIntervalSince($0).rounded() }==[320,300,240,180,120])
        let late=Array(FieldCountdownSchedule(target:target).entries(from:target.addingTimeInterval(-90),mode:.normal).prefix(3))
        #expect(late.map { target.timeIntervalSince($0).rounded() }==[90,89,88])
    }

    // MARK: Keep this night (PC-1)

    @Test func morningAfterOfferIsForTheLastNightOnly() throws {
        let jotr=try park("jotr")
        let night=jotr.evening(try date("2026-10-07T20:00:00Z"))
        let cal=jotr.calendar
        #expect(KeepThisNight.offersMorningAfter(fieldNight:night,lastNightBegun:night,nightIsOver:true,journaled:false,calendar:cal))
        #expect(!KeepThisNight.offersMorningAfter(fieldNight:night,lastNightBegun:night,nightIsOver:false,journaled:false,calendar:cal))
        #expect(!KeepThisNight.offersMorningAfter(fieldNight:night,lastNightBegun:night,nightIsOver:true,journaled:true,calendar:cal))
        #expect(!KeepThisNight.offersMorningAfter(fieldNight:night,lastNightBegun:jotr.date(night,addingDays:1),nightIsOver:true,journaled:false,calendar:cal))
        #expect(!KeepThisNight.offersMorningAfter(fieldNight:nil,lastNightBegun:night,nightIsOver:true,journaled:false,calendar:cal))
    }
    @Test func fieldNightsAreRememberedPerPark() throws {
        let defaults=try #require(UserDefaults(suiteName:"nyx-tests-keep-night"))
        defaults.removePersistentDomain(forName:"nyx-tests-keep-night")
        let jotr=try park("jotr"), deva=try park("deva")
        let night=try date("2026-10-07T23:00:00Z")
        KeepThisNight.record(park:jotr,night:night,defaults:defaults)
        #expect(KeepThisNight.fieldNight(park:jotr,defaults:defaults)==jotr.evening(night))
        #expect(KeepThisNight.fieldNight(park:deva,defaults:defaults)==nil)
    }
    @Test func prefillCarriesParkDateScoreMoonAndBortle() throws {
        let jotr=try park("jotr")
        let night=try night(jotr,"2026-10-07",score:94)
        let prefill=JournalPrefill(night:night)
        #expect(prefill.parkID=="jotr" && prefill.observedBortle==jotr.bortleEstimate)
        #expect(prefill.date==jotr.evening(night.id))
        #expect(prefill.notes.contains("94") && prefill.notes.contains(night.sky.moon.name))
    }

    // MARK: Moon hero (DX-05)

    @Test func moonTurnsTheShortWayRound() {
        let a=MoonHero.nearest(0.1,to:2*Double.pi-0.1)
        #expect(abs(a-(2*Double.pi+0.1))<1e-9)
        #expect(abs(MoonHero.nearest(3,to:3.2)-3)<1e-9)
    }
    @Test func moonHeroSpeaksPhaseLightAndTimes() throws {
        let jotr=try park("jotr")
        let night=try night(jotr,"2026-10-14")
        let spoken=MoonHero.spoken(night:night,geometry:engine.moon(for:night).geometry)
        #expect(spoken.hasPrefix(night.sky.moon.name))
        #expect(spoken.contains("percent lit, lit from the"))
        let events=MoonHero.events(night)
        #expect(events.map(\.date)==events.map(\.date).sorted())
        for event in events { #expect(spoken.contains(event.time)) }
    }

    // MARK: The sky as a view (DX-06)

    @Test func projectionPutsTheHorizonLowAndHidesTheSkyBehind() {
        let frame=SkyFrame(options:PanoramaOptions(facing:180),size:CGSize(width:390,height:800))
        let horizon=frame.point(0,180)
        #expect(horizon.map { $0.y>600 && $0.y<680 && abs($0.x-195)<0.5 } == true)
        #expect((frame.point(10,0)?.y ?? -1)<0 && frame.point(-60,0)==nil)
        // East of south lies to the left when facing south.
        #expect((frame.point(20,150)?.x ?? 999)<195)
    }
    @Test func horizonSkyIsCachedAndHasTheCatalogue() throws {
        let jotr=try park("jotr")
        let night=jotr.evening(try date("2026-07-15T20:00:00Z"))
        let moment=try date("2026-07-16T07:30:00Z")
        let sky=HorizonSkies.shared.sky(park:jotr,night:night,at:moment)
        #expect(sky.stars.count>300 && sky.dust.count>800)
        #expect(sky.stars.allSatisfy { $0.altitude > -2 })
        #expect(sky.dark)
        #expect(HorizonSkies.shared.sky(park:jotr,night:night,at:moment.addingTimeInterval(60)).id==sky.id)
        let summary=PanoramaCanvas.summary(sky:sky,facing:180,park:jotr,bortle:2)
        #expect(summary.hasPrefix("Facing south"))
    }
    @Test func bortleModelDarkensMonotonically() {
        let classes=(1...9).map(Double.init)
        let limits=classes.map(BortleScale.limitingMagnitude), ways=classes.map(BortleScale.milkyWay), glows=classes.map(BortleScale.glowStrength), heights=classes.map(BortleScale.glowHeight)
        #expect(zip(limits,limits.dropFirst()).allSatisfy { $0>$1 })
        #expect(zip(ways,ways.dropFirst()).allSatisfy { $0>=$1 } && ways[0]==1 && ways[8]==0)
        #expect(zip(glows,glows.dropFirst()).allSatisfy { $0<=$1 } && glows[0]==0)
        #expect(zip(heights,heights.dropFirst()).allSatisfy { $0<=$1 })
        #expect(Set((1...9).map(BortleScale.name)).count==9 && Set((1...9).map(BortleScale.cue)).count==9)
        #expect(EssayFigure(.bortle) != nil && EssayFigure(.meteors) == nil)
    }
    @Test func skyOpensAtTheMiddleOfTrueDarkness() throws {
        let jotr=try park("jotr")
        let sky=engine.conditions(for:jotr,on:jotr.evening(try date("2026-10-07T20:00:00Z")))
        let window=SkyAlmanac.nightWindow(sky)
        let opened=window.start.addingTimeInterval(TonightSkyView.defaultMinutes(sky)*60)
        let start=try #require(sky.darkStart), end=try #require(sky.darkEnd)
        let middle=start.addingTimeInterval(end.timeIntervalSince(start)/2)
        #expect(abs(opened.timeIntervalSince(middle))<=150)
    }

    // MARK: Viewing spots (DX-12, PC-1)

    @Test func spotGlowComparesWithinThePark() {
        #expect(SpotGlow.comparison(10,others:[4,5],parkCentre:nil)=="Brighter than this park's other spots")
        #expect(SpotGlow.comparison(2,others:[5],parkCentre:nil)=="Darker than this park's other spot")
        #expect(SpotGlow.comparison(5,others:[5,5.2],parkCentre:nil)=="About as dark as this park's other spots")
        #expect(SpotGlow.comparison(5,others:[],parkCentre:nil)==nil)
        #expect(SpotGlow.comparison(10,others:[],parkCentre:5)=="Brighter than the park's center")
    }
    @Test func spotsLoseTheRepeatedCaveatAndHandOffToMaps() throws {
        let jotr=try park("jotr")
        let spot=try #require(jotr.viewingSpots.first)
        #expect(SpotGlow.lead(spot)?.contains("not a navigation guide") != true)
        let url=try #require(SpotGlow.directions(spot))
        #expect(url.scheme=="maps" && url.absoluteString.contains("daddr=") && url.absoluteString.contains("dirflg=d"))
    }

    // MARK: Ranger programs

    @Test func programTimesAndPlaces() throws {
        #expect(RangerProgram.timeRange(start:"7:00 PM",end:"8:30 PM")=="7:00 PM – 8:30 PM")
        #expect(RangerProgram.timeRange(start:"7:00 PM",end:" ")=="7:00 PM")
        #expect(RangerProgram.timeRange(start:nil,end:nil)==nil)
        #expect(RangerProgram.place("  ")==nil && RangerProgram.place(" Keys View ")=="Keys View")
        // A cache written before times existed still reads.
        let old=Data(#"{"id":"a","title":"Night sky","date":"2026-10-09","description":"Look up."}"#.utf8)
        let program=try JSONDecoder().decode(RangerProgram.self,from:old)
        #expect(program.time==nil && program.location==nil)
    }

    // MARK: What's up order (DX-18)

    @Test func weakShowersBecomeAMentionStrongOnesARow() throws {
        let jotr=try park("jotr")
        for day in ["2026-10-08","2026-12-13","2026-08-12","2026-11-17","2027-01-03"] {
            let sky=engine.conditions(for:jotr,on:jotr.evening(try date(day+"T20:00:00Z")))
            let up=WhatsUp(park:jotr,sky:sky,isTonight:false)
            let layout=WhatsUpPanel.layout(up)
            #expect(layout.first.contains(up.core))
            if let shower=up.shower, let rate=up.events.shower?.hourlyRate {
                #expect(rate>=WhatsUpPanel.showerRow ? layout.after.contains(shower) : layout.mentions.contains(shower))
            }
        }
    }

    // MARK: Chapters and sharing

    @Test func chapterFollowsTheReadingLine() {
        #expect(ParkChapter.current(tops:[.tonight:-900,.sky:300,.place:2400],line:140) == .tonight)
        #expect(ParkChapter.current(tops:[.tonight:-2000,.sky:100,.place:1800],line:140) == .sky)
        #expect(ParkChapter.current(tops:[.tonight:-4000,.sky:-2000,.place:-10],line:140) == .place)
        #expect(ParkChapter.current(tops:[:],line:140) == .tonight)
    }
    @Test func shareCarriesWordsAndOneReason() throws {
        let jotr=try park("jotr")
        let night=try night(jotr,"2026-10-10",score:94)
        let card=ShareCard(night:night,why:ShareCard.why(night:night,core:nil))
        #expect(card.message.hasSuffix("Planned with Nyx."))
        #expect(card.message.contains("94 out of 100"))
        if night.sky.moonBelowFraction>=0.99 { #expect(ShareCard.why(night:night,core:nil)=="Moon-free through all of true darkness") }
        #expect(abs(ShareCard.Format.story.size.height/ShareCard.Format.story.size.width-16.0/9)<0.001)
    }
}
