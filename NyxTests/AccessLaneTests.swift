import Foundation
import Testing
import SwiftUI
import SwiftData
import Accessibility
@testable import Nyx

/// Wave 2 accessibility: a red for every eye, a field screen bright enough to read, the river
/// without a drag, shorter park rows, the Moon by name, the night in the hand, a tone toward the
/// sky, journal photo descriptions, the Assistive Access card and the sky map's order.
@MainActor @Suite struct AccessLaneTests {
    let engine=AstronomyEngine()
    func park(_ id:String) throws -> Park { try #require(try ParkData.load().first { $0.id==id }) }
    func date(_ text:String) throws -> Date { try #require(try? Date(text,strategy:.iso8601)) }
    func night(_ park:Park,_ day:String,score:Int=80,forecast:Bool=true) throws -> Night {
        let sky=engine.conditions(for:park,on:park.evening(try date(day+"T20:00:00Z")))
        return Night(park:park,sky:sky,score:ScoreEngine().score(sky:sky,bortle:park.bortleEstimate,cloudCover:forecast ? 5 : nil),cloudCover:forecast ? 5 : nil,forecastUpdated:forecast ? .now : nil)
    }

    // MARK: AX-02 Red for every eye

    /// The brighter red keeps primary and secondary text above 4.5:1 on black and on the night
    /// panel for typical, protan and deutan eyes (Machado 2009); the standard red does not for protans.
    @Test func brighterRedPassesForColourBlindEyes() {
        let black=SIMD3<Double>(0,0,0)
        let grey=0.2126*0.07+0.7152*0.008+0.0722*0.005
        for vision in ColorVision.allCases {
            let red=NightTint.brighter.rgb, panel=red*grey
            #expect(vision.contrast(red,black)>=4.5, "primary on black, \(vision)")
            #expect(vision.contrast(red*0.96,black)>=4.5, "secondary on black, \(vision)")
            #expect(vision.contrast(red,panel)>=4.5, "primary on the panel, \(vision)")
        }
        // Why it exists: the standard red falls short for protans, and matches Research/contrast.json.
        #expect(ColorVision.protan.contrast(NightTint.standard.rgb,black)<4.5)
        #expect(abs(ColorVision.typical.contrast(NightTint.standard.rgb,black)-6.16)<0.02)
        #expect(abs(ColorVision.protan.contrast(NightTint.brighter.rgb,black)-5.11)<0.02)
    }
    @Test func increaseContrastOrTheSwitchBrightensTheRed() {
        #expect(NyxPalette(nightVision:true,highContrast:false).red == .standard)
        #expect(NyxPalette(nightVision:true,highContrast:true).red == .brighter)
        #expect(NyxPalette(nightVision:true,highContrast:false,brighterRed:true).red == .brighter)
    }
    /// Hairlines and tracks reach 3:1 (WCAG 1.4.11) by default, in both palettes.
    @Test func linesReachThreeToOne() {
        let starlight=SIMD3(0.961,0.945,0.902), black=SIMD3<Double>(0,0,0)
        #expect(ColorVision.typical.contrast(starlight*0.4,black)>=3)
        #expect(ColorVision.typical.contrast(NightTint.standard.rgb*0.7,black)>=3)
    }
    /// Field mode never raises the screen, dims to 12%, or 20% for people who need more light, and
    /// "Keep my brightness" leaves it alone.
    @Test func fieldBrightnessFloor() {
        #expect(FieldSession.dimmed(from:0.8,legible:false,keep:false)==0.12)
        #expect(FieldSession.dimmed(from:0.8,legible:true,keep:false)==0.2)
        #expect(FieldSession.dimmed(from:0.05,legible:true,keep:false)==0.05)
        #expect(FieldSession.dimmed(from:nil,legible:false,keep:false)==0.12)
        #expect(FieldSession.dimmed(from:0.8,legible:false,keep:true)==nil)
    }

    // MARK: AX-08 Park rows

    @Test func parkRowSaysNameScoreBandThenClosure() throws {
        let zion=try park("zion"), tonight=try night(zion,"2026-10-10")
        let plain=ParkRow.spokenLabel(night:tonight,closure:nil)
        #expect(plain.hasPrefix(zion.shortName+". Darkness score \(tonight.score.value), \(tonight.score.band.label)."))
        #expect(!plain.contains("Closure") && !plain.contains("  ") && !plain.contains(zion.state))
        let closed=ParkRow.spokenLabel(night:tonight,closure:"Kolob Canyons Road closed")
        #expect(closed.hasSuffix("Closure alert: Kolob Canyons Road closed"))
        let more=ParkRow.moreContent(night:tonight,closure:"Kolob Canyons Road closed",week:[tonight],stepFree:true)
        #expect(more.first == ParkRowContent.Item(label:"Closure alert",value:"Kolob Canyons Road closed",high:true))
        #expect(more.dropFirst().allSatisfy { !$0.high })
        #expect(more.contains { $0.label=="Step-free viewing" } && more.contains { $0.label=="Clouds" })
        #expect(!ParkRow.moreContent(night:tonight,closure:nil,week:[],stepFree:false).contains { $0.high })
    }

    // MARK: AX-13 The Moon by name

    @Test func moonLabelsLeadWithThePhase() throws {
        let jotr=try park("jotr")
        // Oct 2026: new moon Oct 10, full Oct 26. Oct 14: a waxing crescent; Oct 31: waning gibbous.
        let crescent=engine.moonGeometry(for:jotr,at:try date("2026-10-14T03:00:00Z"))
        #expect(crescent.waxing == true && crescent.phase?.name == "Waxing crescent")
        #expect(MoonView.label(crescent).hasPrefix("Waxing crescent, ") && MoonView.label(crescent).contains("percent lit, lit from the"))
        let gibbous=engine.moonGeometry(for:jotr,at:try date("2026-10-31T09:00:00Z"))
        #expect(gibbous.waxing == false && gibbous.phase?.name == "Waning gibbous")
        // A morph between nights knows no direction and says "Moon".
        let morph=MoonGeometry(phaseAngle:1,brightLimb:0,north:0,librationLongitude:0,librationLatitude:0)
        #expect(MoonView.label(morph).hasPrefix("Moon, "))
        #expect(MoonDisc.label(illumination:0.34,waxing:true)=="Waxing crescent, 34 percent lit")
        #expect(MoonDisc.label(illumination:1,waxing:false).hasPrefix("Full moon"))
    }

    // MARK: Award angle 1: Feel tonight

    @Test func feelTonightFollowsTheNight() throws {
        let jotr=try park("jotr"), tonight=try night(jotr,"2026-11-12")
        let sound=NightSonification(park:jotr,sky:tonight.sky)
        let touch=NightTouch(sound)
        #expect(touch.duration==24 && touch.hum.count==48)
        #expect(touch.hum.allSatisfy { $0>=0.12 && $0<=1 })
        // Faint at dusk and dawn, strongest in true darkness.
        let middle=touch.hum[touch.hum.count/2]
        #expect(middle>touch.hum[0]+0.3 && middle>touch.hum[touch.hum.count-1]+0.3)
        // A tap for each moonrise and moonset, at the same moment as the sound's pulse, scaled to 24 s.
        let pulses=sound.cues.filter { $0.sound == .pulseRising || $0.sound == .pulseFalling }
        #expect(touch.taps.count==pulses.count)
        #expect(zip(touch.taps,pulses).allSatisfy { abs($0.time-$1.offset*2)<1e-9 && $0.sharpness==1 })
        #expect(touch.swells.count==sound.cues.filter { $0.sound == .chime }.count)
        #expect(touch.swells.allSatisfy { $0.time>=0 && $0.time+$0.duration<=24 })
        #expect(touch.opening.contains("24 seconds of touch"))
        // Moonlight softens it; a dark sky without the Moon is the strongest.
        #expect(NightTouch.strength(darkness:1,moonlight:0)==1 && NightTouch.strength(darkness:1,moonlight:1)<0.6 && NightTouch.strength(darkness:0,moonlight:0)==0.12)
        // Core Haptics allows 16 points a curve: the hum is split, sharing joins.
        let curves=MoonHaptics.humCurves(touch)
        #expect(curves.allSatisfy { $0.controlPoints.count<=16 } && curves.count==4)
    }

    // MARK: Award angle 1: Where to look by sound

    @Test func beaconSitsWhereTheTargetIs() {
        let ahead=BeaconGeometry.position(targetAltitude:0,targetAzimuth:180,facingAzimuth:180)
        #expect(abs(ahead.x)<1e-9 && abs(ahead.y)<1e-9 && abs(ahead.z+2)<1e-9)
        // Facing north, a target due east is to the right; due south is behind.
        #expect(BeaconGeometry.position(targetAltitude:0,targetAzimuth:90,facingAzimuth:0).x>1.9)
        #expect(BeaconGeometry.position(targetAltitude:0,targetAzimuth:180,facingAzimuth:0).z>1.9)
        // High targets are above; looking up brings them ahead.
        let high=BeaconGeometry.position(targetAltitude:60,targetAzimuth:0,facingAzimuth:0)
        #expect(high.y>1.5)
        #expect(BeaconGeometry.offAxis(targetAltitude:60,targetAzimuth:0,facingAzimuth:0,facingAltitude:60)<1)
        #expect(abs(BeaconGeometry.offAxis(targetAltitude:0,targetAzimuth:90,facingAzimuth:0)-90)<1e-6)
        // The pulse quickens as you turn toward it.
        #expect(BeaconGeometry.rate(offAxis:0)==1.8 && BeaconGeometry.rate(offAxis:180)==1 && BeaconGeometry.rate(offAxis:30)>BeaconGeometry.rate(offAxis:90))
        let samples=BeaconGeometry.pulse(frequency:BeaconGeometry.frequency,sampleRate:8000)
        #expect(samples.count==7200 && samples.allSatisfy { abs($0)<=0.5 })
    }
    @Test func beaconChoosesTheCoreThenPlanetsThenTheMoon() {
        func target(_ id:String,_ kind:FieldSkyTarget.Kind,_ altitude:Double,_ magnitude:Double=0)->FieldSkyTarget {
            FieldSkyTarget(id:id,kind:kind,name:id,altitude:altitude,azimuth:180,magnitude:magnitude)
        }
        #expect(BeaconGeometry.automatic([target("moon",.moon,40),target("core",.core,20),target("jupiter",.planet,50,-2.5)])?.id=="core")
        #expect(BeaconGeometry.automatic([target("moon",.moon,40),target("core",.core,-5),target("mars",.planet,30,0.5),target("jupiter",.planet,50,-2.5)])?.id=="jupiter")
        #expect(BeaconGeometry.automatic([target("moon",.moon,40),target("core",.core,-5)])?.id=="moon")
        #expect(BeaconGeometry.automatic([target("moon",.moon,-3),target("core",.core,-5)]) == nil)
    }

    // MARK: PA-13 Journal photo descriptions

    @Test func photoDescriptionsAreKeptInOrder() throws {
        let opened=JournalStore.open(inMemory:true)
        let container=try #require(opened.container)
        let context=ModelContext(container)
        let editor=JournalEditorModel()
        editor.photos=[Data([1]),Data([2]),Data([3])]
        #expect(editor.descriptions==["","",""])
        editor.descriptions=["A ridge at dusk","","Two people beside a telescope"]
        editor.suggestions[2]="Suggested text"
        editor.removePhoto(at:1)
        #expect(editor.descriptions==["A ridge at dusk","Two people beside a telescope"] && editor.suggestions[1]=="Suggested text")
        // A suggestion is never saved by itself.
        #expect(editor.save(context:context,existing:nil))
        let entry=try #require(try context.fetch(FetchDescriptor<JournalEntry>()).first)
        #expect(entry.orderedPhotos.map(\.altText)==["A ridge at dusk","Two people beside a telescope"])
        editor.useSuggestion(1)
        #expect(editor.descriptions[1]=="Suggested text" && editor.suggestions[1] == nil)
        // Reopened, the descriptions come back beside their photos.
        let reopened=JournalEditorModel(entry:entry)
        #expect(reopened.descriptions==["A ridge at dusk","Two people beside a telescope"])
        #expect(JournalPhotoLabel.text("  ",index:0)=="Journal photo 1" && JournalPhotoLabel.text("A ridge",index:1)=="Photo: A ridge")
    }
    @Test func suggestionsAreOneCalmLine() {
        #expect(PhotoDescriber.clean("\"A ridge under stars!\"\nMore text")=="A ridge under stars.")
        #expect(PhotoDescriber.clean("ok") == nil)
        #expect((PhotoDescriber.clean(String(repeating:"a",count:400))?.count ?? 0)==160)
    }

    // MARK: PA-4 Bortle on iOS 26

    @Test func bortleIsSpelledPhoneticallyBeforeIOS27() {
        let text="Bortle estimate, class 2 of 9. Bortle is a scale."
        let found=NyxSpeech.phoneticAnnotations(in:text)
        #expect(found.count==2 && found.allSatisfy { text[$0.range]=="Bortle" && $0.ipa=="ˈbɔɹtəl" })
        let attributed=SpokenText.phonetic(text)
        let marked=attributed.runs.filter { $0.accessibilitySpeechPhoneticNotation != nil }
        #expect(marked.count==2 && marked.allSatisfy { String(attributed[$0.range].characters)=="Bortle" })
        #expect(NyxSpeech.phoneticAnnotations(in:"Darkness score 94").isEmpty)
        // The SSML path keeps the same IPA.
        #expect(NyxSpeech.pronunciations.first { $0.word=="Bortle" }?.ssml.contains(NyxSpeech.bortleIPA) == true)
    }

    // MARK: AX-07 Assistive Access

    @Test func assistiveCardSaysOneWordAndOneTime() throws {
        let jotr=try park("jotr"), tonight=try night(jotr,"2026-10-10")
        #expect(AssistiveParkCard.word(tonight)=="\(tonight.score.band.label) night")
        let estimate=try night(jotr,"2026-10-10",forecast:false)
        #expect(AssistiveParkCard.word(estimate).hasSuffix(", clouds not known yet"))
        let dark=try #require(tonight.sky.darkStart)
        #expect(AssistiveParkCard.darkLine(tonight)=="Dark from \(jotr.time(dark))")
        // Midsummer in Denali: no true darkness, said plainly.
        let dena=try park("dena"), june=try night(dena,"2026-06-21")
        #expect(AssistiveParkCard.darkLine(june)==SkyConditions.noDarknessMessage(tonight:true))
    }

    // MARK: AX-13 Sky map order

    @Test func skyMapStarsReadWestToEast() {
        let stars=[("c",0.8,0.2),("a",0.1,0.5),("b",0.4,0.9),("b2",0.4005,0.1)].map { SkyMapContent.Star(id:$0.0,point:CGPoint(x:$0.1,y:$0.2),brightness:1,label:$0.0) }
        #expect(SkyMapView.geographic(stars).map(\.id)==["a","b2","b","c"])
    }
}
