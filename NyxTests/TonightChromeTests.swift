import Foundation
import Testing
@testable import Nyx

/// Tonight's first screen and its chrome: the meteor that fades in and burns out, the night-vision
/// lamp's timing, and the one-line caveat that keeps "check alerts before you go".
@MainActor @Suite struct TonightChromeTests {
    @Test func shootingStarFadesInAndBurnsOut() {
        #expect(ShootingStar.brightness(progress:0)==0)
        #expect(ShootingStar.brightness(progress:1)<1e-9)
        #expect(abs(ShootingStar.brightness(progress:0.5)-1)<1e-9)
        // Never brighter than the middle, and rising then falling.
        #expect(ShootingStar.brightness(progress:0.1)<ShootingStar.brightness(progress:0.3))
        #expect(ShootingStar.brightness(progress:0.9)<ShootingStar.brightness(progress:0.7))
    }

    @Test func shootingStarTrailFollowsTheSpringsSpeed() {
        // A critically damped spring from rest is fastest at 1 − 2/e of the way (about 0.26).
        let peak=1-2/exp(1.0)
        #expect(abs(ShootingStar.speed(progress:peak)-1)<0.01)
        #expect(ShootingStar.speed(progress:0.02)<0.5)
        #expect(ShootingStar.speed(progress:0.98)<0.3)
        #expect(ShootingStar.speed(progress:0.5)<ShootingStar.speed(progress:peak))
        // Out of range is clamped, never NaN.
        #expect(ShootingStar.speed(progress:-1)==ShootingStar.speed(progress:0))
        #expect(!ShootingStar.speed(progress:2).isNaN)
    }

    @Test func lampReversesFromWhereTheCoverIs() {
        // A cover already half down needs half the dimming time; a full cover needs none.
        #expect(NightVisionLamp.dimTime(from:0)==NightVisionLamp.dim)
        #expect(abs(NightVisionLamp.dimTime(from:0.5)-NightVisionLamp.dim/2)<1e-9)
        #expect(NightVisionLamp.dimTime(from:1)==0)
        #expect(NightVisionLamp.dimTime(from:3)==0)
        // Dates near today keep about a microsecond of precision, hence the tolerances.
        let start=Date(timeIntervalSince1970:1_000)
        let down=NightVisionLamp.Cover(from:0,to:1,start:start,duration:0.2)
        #expect(down.value(at:start)==0)
        #expect(abs(down.value(at:start.addingTimeInterval(0.1))-0.5)<1e-5)
        #expect(down.value(at:start.addingTimeInterval(5))==1)
        // A second tap 0.1 s in turns back from 0.5, not from black.
        let back=NightVisionLamp.Cover(from:down.value(at:start.addingTimeInterval(0.1)),to:0,start:start.addingTimeInterval(0.1),duration:NightVisionLamp.reveal)
        #expect(abs(back.value(at:start.addingTimeInterval(0.1))-0.5)<1e-5)
        #expect(NightVisionLamp.Cover().value(at:.now)==0)
    }

    @Test func caveatFactsStartLinesWithACapital() {
        #expect(CaveatLine.sentence("check alerts before you go")=="Check alerts before you go")
        #expect(CaveatLine.sentence("forecast from Oct 8, 1:51 PM")=="Forecast from Oct 8, 1:51 PM")
        #expect(CaveatLine.sentence("No closures listed")=="No closures listed")
        #expect(CaveatLine.sentence("")=="")
    }

    @Test func listedAlertsKeepTheSafetyCue() {
        let model=PlanModel()
        guard let park=model.home else { Issue.record("No starting park"); return }
        model.enrichments[park.id]=ParkEnrichment(updated:.now,alerts:[],programs:[],description:nil,programsUpdated:nil)
        #expect(model.alertFacts(park)==["No alerts listed","confirm access before you go"])
    }
}
