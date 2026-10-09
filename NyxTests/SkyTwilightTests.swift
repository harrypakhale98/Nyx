import Testing
import Foundation
@testable import Nyx

/// The sky behind every screen shows what the Sun leaves: a white night in Denali has only its
/// brightest stars over a faint lift, the Arctic winter has all of them, and Samoa is unchanged.
@MainActor struct SkyTwilightTests {
    func park(_ id:String) throws -> Park { try #require(try ParkData.load().first { $0.id==id }) }
    func date(_ string:String,park:Park) throws -> Date {
        let f=DateFormatter(); f.dateFormat="yyyy-MM-dd HH:mm"; f.timeZone=park.timeZone
        return try #require(f.date(from:string))
    }
    func visibility(_ id:String,_ stamp:String,highContrast:Bool=false) throws -> (sky:SkyProjection.Sky,seen:RealSky.Visibility) {
        let park=try park(id)
        let sky=SkyProjection.shared.sky(for:park,night:try date(stamp,park:park))
        return (sky,RealSky.Visibility(sunAltitude:sky.sunAltitude,highContrast:highContrast))
    }

    @Test func denaliInJuneShowsOnlyItsBrightestStars() throws {
        let (sky,seen)=try visibility("dena","2026-06-21 12:00")
        // At its lowest, near 2 AM, the Sun is only about 3° down: civil twilight all night.
        #expect(sky.sunAltitude > -6 && sky.sunAltitude < -1)
        #expect(!sky.dark)
        #expect(seen.faint==0 && seen.middle==0)
        #expect(seen.bright==0.5)
        #expect(seen.lift==1)
        #expect(!sky.bright.isEmpty)
    }

    @Test func gatesOfTheArcticInDecemberShowsEveryStar() throws {
        let (sky,seen)=try visibility("gaar","2026-12-21 12:00")
        #expect(sky.sunAltitude < -18)
        #expect(sky.dark)
        #expect(seen.faint==1 && seen.middle==1 && seen.bright==1)
        #expect(seen.lift==0)
    }

    @Test func americanSamoaIsUnchanged() throws {
        for stamp in ["2026-01-15 12:00","2026-06-21 12:00","2026-10-14 12:00"] {
            let (sky,seen)=try visibility("npsa",stamp)
            #expect(sky.sunAltitude < -18, "\(stamp)")
            #expect(seen==RealSky.Visibility(sunAltitude:-40), "\(stamp)")
            #expect(seen.faint==1 && seen.middle==1 && seen.bright==1 && seen.lift==0, "\(stamp)")
        }
    }

    @Test func twilightBandsAndTheLift() {
        // Nautical twilight: the bright and middle stars; astronomical: all of them.
        let nautical=RealSky.Visibility(sunAltitude:-9)
        #expect(nautical.faint==0 && nautical.middle==1 && nautical.bright==1)
        #expect(abs(nautical.lift-0.75)<1e-9)
        let astronomical=RealSky.Visibility(sunAltitude:-15)
        #expect(astronomical.faint==1 && astronomical.middle==1)
        #expect(abs(astronomical.lift-0.25)<1e-9)
        // Off under Reduce Transparency and Increase Contrast.
        #expect(RealSky.Visibility(sunAltitude:-3,liftAllowed:false).lift==0)
    }

    @Test func increaseContrastCalmsTheField() {
        let calm=RealSky.Visibility(sunAltitude:-40,highContrast:true)
        #expect(calm.faint==0)
        #expect(calm.middle>0 && calm.middle<0.5)
        #expect(calm.bright==1)
        // A white night stays a white night.
        let white=RealSky.Visibility(sunAltitude:-3,highContrast:true)
        #expect(white.faint==0 && white.middle==0 && white.bright==0.5)
    }
}
