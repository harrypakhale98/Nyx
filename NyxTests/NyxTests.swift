import AppIntents
import Foundation
import Testing
import UIKit
import SwiftData
@testable import Nyx

struct NyxTests {
    func park(_ id:String) throws -> Park { try #require(try ParkData.load().first { $0.id==id }) }
    func date(_ string:String,park:Park) throws -> Date {
        let f=DateFormatter(); f.dateFormat="yyyy-MM-dd HH:mm"; f.timeZone=park.timeZone
        return try #require(f.date(from:string))
    }
    @Test func inventory() throws {
        let parks=try ParkData.load()
        #expect(parks.count==63); #expect(Set(parks.map(\.id)).count==63)
        #expect(parks.filter { $0.latitude<0 }.count==1)
        #expect(parks.filter { $0.state.contains("AK") }.count==8)
        for p in parks {
            #expect((-90...90).contains(p.latitude)); #expect((-180...180).contains(p.longitude))
            #expect(TimeZone(identifier:p.timeZoneID) != nil); #expect(!p.description.isEmpty)
            #expect((1...9).contains(p.bortleEstimate)); #expect(p.sourceURL.hasPrefix("https://www.nps.gov/"))
        }
    }
    @Test func nightInProgressRunsUntilSunrise() throws {
        let tree=try park("jotr")
        let small=try date("2026-10-03 01:30",park:tree), noon=try date("2026-10-03 12:00",park:tree)
        let lastNight=tree.evening(try date("2026-10-02 18:00",park:tree))
        #expect(tree.currentNight(at:small)==lastNight)
        #expect(tree.currentNight(at:try date("2026-10-03 05:30",park:tree))==lastNight)
        // Sunrise at Joshua Tree is about 06:35 in early October; a morning planner sees the coming night.
        #expect(tree.currentNight(at:try date("2026-10-03 08:00",park:tree))==noon)
        #expect(tree.currentNight(at:noon)==noon)
        // Polar night has no sunrise: the switch waits for local noon.
        let arctic=try park("gaar")
        let winter=try date("2026-12-21 10:00",park:arctic)
        #expect(arctic.currentNight(at:winter)==arctic.evening(try date("2026-12-20 18:00",park:arctic)))
    }
    @Test func searchForgivesSpelling() throws {
        #expect(try park("havo").matches("Hawaii Volcanoes"))
        #expect(try park("wrst").matches("Wrangell St Elias"))
        #expect(try park("grsm").matches("smokies"))
        #expect(try !park("jotr").matches("Yellowstone"))
    }
    @Test func midnightSunStillUsesItsForecast() throws {
        let denali=try park("dena")
        let sky=AstronomyEngine().conditions(for:denali,on:try date("2026-06-21 12:00",park:denali))
        #expect(sky.darkStart==nil)
        let window=sky.cloudWindow
        #expect(window.end>window.start)
        let hours=stride(from:sky.evening.timeIntervalSince1970,to:sky.end.timeIntervalSince1970,by:3600).map { $0 }
        let forecast=Forecast(updated:sky.evening,times:hours,clouds:hours.map { _ in 30 })
        #expect(forecast.mean(from:window.start,to:window.end,now:sky.evening)==30)
    }
    /// A few minutes of true darkness must not score like a full night (Wrangell–St. Elias, mid-April).
    @Test func briefDarknessIsCapped() throws {
        let wrangell=try park("wrst")
        let sky=AstronomyEngine().conditions(for:wrangell,on:try date("2026-04-16 12:00",park:wrangell))
        #expect(sky.darkHours>0 && sky.darkHours<1)
        #expect(ScoreEngine().score(sky:sky,bortle:1,cloudCover:0).value<60)
        #expect(ScoreEngine.cap(darkHours:0)==39)
        #expect(ScoreEngine.cap(darkHours:1.5)>ScoreEngine.cap(darkHours:0.5))
        #expect(ScoreEngine.cap(darkHours:3)==100)
    }
    /// The drawn bright limb must point at the Sun as the observer sees it: compare it with the
    /// great-circle bearing from the Moon to the Sun in that park's sky (zenith up, clockwise
    /// toward increasing azimuth, so the drawn counterclockwise angle is its negative).
    @Test func moonBrightLimbFacesTheSun() throws {
        let engine=AstronomyEngine()
        for (id,stamp) in [("jotr","2026-10-12 19:30"),("jotr","2026-10-22 22:00"),("acad","2026-03-24 20:00"),("dena","2026-01-27 18:00"),("npsa","2026-10-14 20:00"),("ever","2026-11-01 05:30")] {
            let p=try park(id), at=try date(stamp,park:p)
            let sun=engine.equatorial(of:.sun,at:at), moon=engine.equatorial(of:.moon,at:at)
            let s=engine.horizontal(date:at,park:p,ra:sun.ra,dec:sun.dec), m=engine.horizontal(date:at,park:p,ra:moon.ra,dec:moon.dec)
            let r=Double.pi/180, dAz=(s.azimuth-m.azimuth)*r
            let bearing=atan2(sin(dAz)*cos(s.altitude*r),cos(m.altitude*r)*sin(s.altitude*r)-sin(m.altitude*r)*cos(s.altitude*r)*cos(dAz))
            let drawn=engine.moonGeometry(for:p,at:at).brightLimb
            let difference=abs(atan2(sin(drawn+bearing),cos(drawn+bearing)))/r
            #expect(difference<3,"\(id) \(stamp): drawn \(drawn/r)°, sun bearing \(bearing/r)°")
        }
    }
    @Test func moonGeometryMatchesPhase() throws {
        let engine=AstronomyEngine(), p=try park("jotr")
        let full=engine.moonGeometry(for:p,at:try date("2026-10-26 12:00",park:p))
        let new=engine.moonGeometry(for:p,at:try date("2026-10-10 00:00",park:p))
        #expect(full.illumination>0.97); #expect(new.illumination<0.03)
        #expect(abs(full.librationLongitude)<8*Double.pi/180); #expect(abs(full.librationLatitude)<7*Double.pi/180)
    }
    @Test func polarAndTropical() throws {
        let engine=AstronomyEngine(), denali=try park("dena"), gates=try park("gaar"), samoa=try park("npsa")
        let summer=engine.conditions(for:denali,on:try date("2026-06-21 12:00",park:denali))
        #expect(summer.darkHours==0); #expect(summer.moonBelowFraction==0)
        #expect(ScoreEngine().score(sky:summer,bortle:1,cloudCover:0).value<40)
        let winter=engine.conditions(for:gates,on:try date("2026-12-21 12:00",park:gates))
        #expect(winter.state == .polarNight); #expect(winter.darkHours>10)
        for month in ["01","07"] {
            let night=engine.conditions(for:samoa,on:try date("2026-\(month)-15 12:00",park:samoa))
            #expect((8...12).contains(night.darkHours)); #expect(night.state == .normal)
        }
    }
    @Test func timeZones() throws {
        let p=try park("grca"), jt=try park("jotr")
        #expect(p.timeZone.secondsFromGMT(for:try date("2026-03-08 12:00",park:p)) == -7*3600)
        #expect(p.timeZone.secondsFromGMT(for:try date("2026-11-01 12:00",park:p)) == -7*3600)
        let engine=AstronomyEngine()
        for day in ["2026-03-07","2026-10-31"] {
            let sky=engine.conditions(for:jt,on:try date(day+" 12:00",park:jt))
            #expect(sky.end.timeIntervalSince(sky.evening) == (day.contains("03") ? 23 : 25)*3600)
        }
    }
    @Test func formula() throws {
        let p=try park("jotr"), sky=AstronomyEngine().conditions(for:p,on:try date("2026-10-10 12:00",park:p))
        let engine=ScoreEngine(), full=engine.score(sky:sky,bortle:2,cloudCover:0), absent=engine.score(sky:sky,bortle:2,cloudCover:nil)
        #expect(full.cloudPoints==25); #expect(absent.cloudPoints==nil)
        #expect(abs(absent.moonPoints-full.moonPoints/0.75)<0.0001)
        #expect(engine.score(sky:sky,bortle:2,cloudCover:.nan).cloudPoints==nil)
        #expect(engine.score(sky:sky,bortle:2,cloudCover:100).value<=full.value)
        for (s,b) in [(0,ScoreBand.poor),(39,.poor),(40,.fair),(59,.fair),(60,.good),(74,.good),(75,.excellent),(89,.excellent),(90,.pristine),(100,.pristine)] { #expect(ScoreBand.band(s)==b) }
    }
    @Test func publishedMoonPhases() throws {
        let dates=[("2026-01-18T19:52:00Z",0.0),("2026-03-03T11:38:00Z",0.5),("2026-10-10T15:50:00Z",0.0)]
        for (text,expected) in dates {
            let date=try #require(ISO8601DateFormatter().date(from:text))
            let actual=AstronomyEngine().moonPhase(at:date).fraction
            let delta=min(abs(actual-expected),1-abs(actual-expected))
            #expect(delta*AstronomyEngine.synodicDays*24<12)
        }
    }
    @Test func forecastCoverage() {
        let now=Date.now
        let forecast=Forecast(updated:now,times:[now.timeIntervalSince1970,now.timeIntervalSince1970+3600],clouds:[20,80])
        #expect(forecast.mean(from:now.addingTimeInterval(1800),to:now.addingTimeInterval(5400))==50)
        #expect(forecast.mean(from:now,to:now.addingTimeInterval(8000))==nil)
        #expect(forecast.mean(from:now,to:now.addingTimeInterval(3600),now:now.addingTimeInterval(40*3600))==nil)
    }
    @Test func malformedForecastCannotFillGaps() {
        let now=Date.now, t=now.timeIntervalSince1970
        let duplicated=Forecast(updated:now,times:[t,t],clouds:[0,0])
        #expect(duplicated.mean(from:now,to:now.addingTimeInterval(7200))==nil)
        let reordered=Forecast(updated:now,times:[t+3600,t],clouds:[0,0])
        #expect(reordered.mean(from:now,to:now.addingTimeInterval(7200))==nil)
    }
    @Test func parkLocalDateBoundary() throws {
        let samoa=try park("npsa"), canyon=try park("grca")
        let instant=try #require(ISO8601DateFormatter().date(from:"2026-10-02T05:00:00Z"))
        #expect(samoa.isoDay(instant)=="2026-10-01")
        #expect(canyon.isoDay(instant)=="2026-10-01")
        let midnight=try date("2026-10-01 00:00",park:samoa)
        #expect(samoa.isoDay(midnight)=="2026-10-01")
    }
    @MainActor @Test func journalPersistsSelectedPhotoAndEdits() throws {
        let config=ModelConfiguration(isStoredInMemoryOnly:true)
        let container=try ModelContainer(for:SavedPark.self,JournalEntry.self,configurations:config)
        let context=ModelContext(container)
        let entry=JournalEntry(date:.now,parkID:"jotr",notes:"A quiet sky.")
        entry.photos=[Data([0,1,2,3])]
        context.insert(entry);context.insert(SavedPark(parkID:"jotr"));try context.save()
        let stored=try #require(try context.fetch(FetchDescriptor<JournalEntry>()).first)
        #expect(stored.photos==[Data([0,1,2,3])]);#expect(stored.notes=="A quiet sky.")
        stored.notes="The Moon rose late.";try context.save()
        #expect(try context.fetch(FetchDescriptor<JournalEntry>()).count==1)
        #expect(try context.fetch(FetchDescriptor<SavedPark>()).first?.parkID=="jotr")
    }
    /// Photos are decoded straight to their stored size; the journal keeps a small list thumbnail.
    @MainActor @Test func journalPhotosAreDownscaled() throws {
        let size=CGSize(width:4000,height:3000)
        let format=UIGraphicsImageRendererFormat(); format.scale=1
        let big=try #require(UIGraphicsImageRenderer(size:size,format:format).image { context in
            UIColor.systemIndigo.setFill(); context.fill(CGRect(origin:.zero,size:size))
        }.jpegData(compressionQuality:0.9))
        let stored=try #require(PhotoScaling.jpeg(big,maxPixels:2400))
        let image=try #require(UIImage(data:stored))
        #expect(max(image.size.width,image.size.height)<=2400)
        #expect(abs(image.size.width/image.size.height-4.0/3.0)<0.01)
        let container=try ModelContainer(for:SavedPark.self,JournalEntry.self,configurations:ModelConfiguration(isStoredInMemoryOnly:true))
        let editor=JournalEditorModel()
        editor.photos=[stored]
        #expect(editor.save(context:ModelContext(container),existing:nil))
        let entry=try #require(try ModelContext(container).fetch(FetchDescriptor<JournalEntry>()).first)
        let thumbnail=try #require(entry.thumbnail.flatMap { UIImage(data:$0) })
        #expect(max(thumbnail.size.width,thumbnail.size.height)<=900)
    }
    @Test func publishedRiseSet() throws {
        struct Reference:Decodable { let park:String; let date:String; let tz:Int; let reference:Response }
        struct Response:Decodable { struct Properties:Decodable { struct Info:Decodable {
            struct Event:Decodable { let phen:String; let time:String }
            let sundata:[Event]; let moondata:[Event]
        }; let data:Info }; let properties:Properties }
        let bundle=Bundle(for:BundleAnchor.self)
        let url=try #require(bundle.url(forResource:"usno-reference",withExtension:"json"))
        let cases=try JSONDecoder().decode([Reference].self,from:Data(contentsOf:url))
        let engine=AstronomyEngine()
        for ref in cases {
            let p=try park(ref.park), day=try date(ref.date+" 12:00",park:p)
            let sky=engine.conditions(for:p,on:day), previous=engine.conditions(for:p,on:p.date(day,addingDays:-1))
            for event in ref.reference.properties.data.sundata {
                let predicted:Date?
                switch event.phen { case "Rise": predicted=previous.sunrise; case "Set": predicted=sky.sunset; case "End Civil Twilight": predicted=sky.civilDusk; default: continue }
                let actual=try date(ref.date+" "+event.time,park:p)
                #expect(abs(try #require(predicted).timeIntervalSince(actual))<120,"\(p.id) \(ref.date) \(event.phen)")
            }
            for event in ref.reference.properties.data.moondata where ["Rise","Set"].contains(event.phen) {
                let actual=try date(ref.date+" "+event.time,park:p)
                let predictions=(event.phen=="Rise" ? [previous.moonrise,sky.moonrise] : [previous.moonset,sky.moonset]).compactMap{$0}
                #expect(predictions.contains { abs($0.timeIntervalSince(actual))<900 },"Moon \(p.id) \(ref.date) \(event.phen)")
            }
        }
    }
}
final class BundleAnchor: NSObject {}
