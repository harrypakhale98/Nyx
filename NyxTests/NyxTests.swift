import AppIntents
import Foundation
import Testing
import UIKit
import SwiftUI
import SwiftData
@testable import Nyx

struct NyxTests {
    func park(_ id:String) throws -> Park { try #require(try ParkData.load().first { $0.id==id }) }
    func date(_ string:String,park:Park) throws -> Date {
        let f=DateFormatter(); f.dateFormat="yyyy-MM-dd HH:mm"; f.timeZone=park.timeZone
        return try #require(f.date(from:string))
    }
    /// The 18 national parks certified as International Dark Sky Parks by DarkSky International:
    /// the NPS Night Skies list (asterisked, updated July 2025) plus Badlands (July 2026).
    @Test func darkSkyDesignationsMatchTheOfficialList() throws {
        let designated=Set(try ParkData.load().filter(\.darkSkyDesignated).map(\.id))
        #expect(designated==Set("arch badl bibe blca brca cany care deva glac grba grca grsa jotr maca meve pefo voya zion".split(separator:" ").map(String.init)))
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
    /// Kobuk Valley in late December: solar noon is after 13:00, so sunrise (about 13:04 the next
    /// day) falls after the noon-to-noon window. It is still found, after true darkness ends.
    @Test func lateArcticSunriseIsFound() throws {
        let kova=try park("kova")
        let sky=AstronomyEngine().conditions(for:kova,on:try date("2026-12-27 12:00",park:kova))
        let sunset=try #require(sky.sunset), sunrise=try #require(sky.sunrise)
        #expect(sunrise>sky.end && sunrise<sky.end.addingTimeInterval(6*3600))
        #expect(sunrise>sunset && sunrise>(sky.darkEnd ?? sunset))
        #expect(kova.calendar.component(.hour,from:sunrise)==13)
    }
    /// Under the midnight sun the cloud window is centred on the Sun's lowest point, not the clock's midnight.
    @Test func midnightSunCloudWindowFollowsTheSun() throws {
        let kova=try park("kova"), engine=AstronomyEngine()
        let sky=engine.conditions(for:kova,on:try date("2026-06-21 12:00",park:kova))
        #expect(sky.state == .polarDay)
        let low=try #require(sky.lowestSun)
        let window=sky.cloudWindow
        #expect(window.start==low.addingTimeInterval(-7200) && window.end==low.addingTimeInterval(7200))
        // Lower than at either edge of the window, and lower than at 22:00 on the clock.
        #expect(engine.solarAltitude(at:low,park:kova)<engine.solarAltitude(at:window.start,park:kova))
        #expect(engine.solarAltitude(at:low,park:kova)<engine.solarAltitude(at:window.end,park:kova))
        #expect(engine.solarAltitude(at:low,park:kova)<engine.solarAltitude(at:try date("2026-06-21 22:00",park:kova),park:kova)-5)
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
    /// On a July midnight at Joshua Tree the galactic core sits low in the south: the band must
    /// pass near the bottom centre of the southward view, and Antares and the core stay above it.
    @MainActor @Test func milkyWayCoreInTheSouthInSummer() throws {
        let p=try park("jotr")
        let sky=SkyProjection.shared.sky(for:p,night:try date("2026-07-15 12:00",park:p))
        #expect(sky.dark)
        let core=sky.galaxy.flatMap { $0 }.max { $0.brightness<$1.brightness }
        let point=try #require(core).position
        #expect(abs(point.x)<0.6)          // roughly due south
        #expect(point.y < -0.2)            // below the 45° centre of the view, near the horizon
        #expect(sky.faint.count+sky.middle.count+sky.bright.count>300)
    }
    /// Whether ImageRenderer runs the Moon's Metal shader: the lit limb must come out bright.
    @MainActor @Test func moonShaderRendersToImage() throws {
        let engine=AstronomyEngine(), p=try park("jotr")
        let geometry=engine.moonGeometry(for:p,at:try date("2026-10-26 23:00",park:p))
        let renderer=ImageRenderer(content:MoonView(geometry:geometry).frame(width:100,height:100))
        renderer.scale=1
        let image=try #require(renderer.cgImage)
        let context=try #require(CGContext(data:nil,width:100,height:100,bitsPerComponent:8,bytesPerRow:400,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image,in:CGRect(x:0,y:0,width:100,height:100))
        let pixels=try #require(context.data).assumingMemoryBound(to:UInt8.self)
        let centre=pixels[(50*100+50)*4]
        print("MOON-SHADER-CENTRE", centre)
        #expect(centre>60)
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
    /// Exact points, so a swapped weight or a lost moon bonus cannot pass unnoticed.
    @Test func formulaPinnedToSpecWeights() {
        let start=Date(timeIntervalSince1970:1_800_000_000)
        let sky=SkyConditions(evening:start,end:start.addingTimeInterval(86400),sunset:nil,sunrise:nil,civilDusk:nil,nauticalDusk:nil,
                              darkStart:start.addingTimeInterval(8*3600),darkEnd:start.addingTimeInterval(16*3600),state:.normal,
                              moon:MoonPhase(fraction:0.25),moonrise:nil,moonset:nil,moonBelowFraction:0.5,darkHours:8)
        // Moon 40·(0.5 + 0.5·0.5) = 30, clouds 25·0.6 = 15, Bortle 3 → 20·6/8 = 15, darkness 15·0.8 = 12.
        let full=ScoreEngine().score(sky:sky,bortle:3,cloudCover:40)
        #expect(full.value==72); #expect(abs(full.moonPoints-30)<1e-9); #expect(full.cloudPoints.map { abs($0-15)<1e-9 }==true)
        #expect(abs(full.bortlePoints-15)<1e-9); #expect(abs(full.lengthPoints-12)<1e-9)
        // Beyond the forecast: (30 + 15 + 12) / 0.75 = 76.
        #expect(ScoreEngine().score(sky:sky,bortle:3,cloudCover:nil).value==76)
        #expect(ScoreEngine.cap(darkHours:0)==39); #expect(ScoreEngine.cap(darkHours:1)==59); #expect(ScoreEngine.cap(darkHours:3)==100)
    }
    /// Independent reference times (PyEphem; upper limb at -0°34' for rise and set, the Sun's
    /// centre at -18° for true darkness), including Alaska and American Samoa, where shallow
    /// paths magnify any error in the horizon convention. nil means no such event that night.
    @Test func referenceRiseSetAndDarkness() throws {
        let cases:[(String,String,String?,String?,String?,String?,String?)]=[
            ("dena","2026-02-10","2026-02-11T02:27:42Z","2026-02-11T05:07:24Z","2026-02-11T15:28:15Z",nil,nil),
            ("dena","2026-12-21","2026-12-22T00:19:34Z","2026-12-22T03:36:47Z","2026-12-22T16:28:40Z","2026-12-21T21:19:36Z",nil),
            ("wrst","2026-01-15","2026-01-16T00:51:29Z","2026-01-16T03:37:30Z","2026-01-16T15:42:02Z","2026-01-16T19:19:54Z","2026-01-16T20:51:20Z"),
            ("wrst","2026-02-10","2026-02-11T02:03:07Z","2026-02-11T04:32:23Z","2026-02-11T14:55:45Z","2026-02-11T16:11:08Z","2026-02-11T17:51:29Z"),
            ("npsa","2026-06-21","2026-06-22T04:59:52Z","2026-06-22T06:16:20Z","2026-06-22T16:26:31Z","2026-06-21T23:17:03Z","2026-06-22T11:46:21Z"),
            ("npsa","2026-12-21","2026-12-22T05:46:52Z","2026-12-22T07:06:43Z","2026-12-22T15:29:10Z","2026-12-22T03:46:13Z","2026-12-22T15:16:55Z"),
            ("grca","2026-10-10","2026-10-11T00:59:08Z","2026-10-11T02:24:09Z","2026-10-11T12:06:51Z","2026-10-11T14:38:27Z","2026-10-11T00:48:19Z"),
            ("jotr","2026-03-07","2026-03-08T01:44:54Z","2026-03-08T03:07:49Z","2026-03-08T12:40:01Z","2026-03-08T06:15:13Z","2026-03-08T16:32:15Z")
        ]
        let engine=AstronomyEngine(), iso=ISO8601DateFormatter()
        for (id,night,sunset,dusk,dawn,moonrise,moonset) in cases {
            let p=try park(id), sky=engine.conditions(for:p,on:try date(night+" 12:00",park:p))
            for (label,predicted,expected,tolerance) in [("sunset",sky.sunset,sunset,120.0),("dusk",sky.darkStart,dusk,120),("dawn",sky.darkEnd,dawn,120),
                                                          ("moonrise",sky.moonrise,moonrise,300),("moonset",sky.moonset,moonset,300)] {
                guard let expected else { #expect(predicted==nil,"\(id) \(night) \(label) should not occur"); continue }
                let reference=try #require(iso.date(from:expected))
                let actual=try #require(predicted,"\(id) \(night) \(label) missing")
                #expect(abs(actual.timeIntervalSince(reference))<tolerance,"\(id) \(night) \(label)")
            }
        }
    }
    @Test func milkyWayGuidanceFollowsLatitude() throws {
        let engine=AstronomyEngine()
        let arctic=try park("gaar"), samoa=try park("npsa"), tree=try park("jotr"), kenai=try park("kefj")
        #expect(engine.milkyWayGuidance(for:engine.conditions(for:arctic,on:try date("2026-12-15 12:00",park:arctic)),park:arctic).contains("at or below"))
        // Kenai Fjords at midsummer: the core only grazes the horizon and there is no true darkness.
        #expect(!engine.milkyWayGuidance(for:engine.conditions(for:kenai,on:try date("2026-06-21 12:00",park:kenai)),park:kenai).contains("Summer favors"))
        #expect(engine.milkyWayGuidance(for:engine.conditions(for:tree,on:try date("2026-07-15 12:00",park:tree)),park:tree).hasPrefix("Summer"))
        #expect(engine.milkyWayGuidance(for:engine.conditions(for:samoa,on:try date("2026-07-15 12:00",park:samoa)),park:samoa).hasPrefix("Southern winter"))
    }
    /// Short polar-winter days: the Sun can rise after local noon; that is not the night's sunrise.
    @Test func polarWinterSunriseFollowsSunset() throws {
        let kobuk=try park("kova")
        let sky=AstronomyEngine().conditions(for:kobuk,on:try date("2026-12-03 12:00",park:kobuk))
        if let sunset=sky.sunset, let sunrise=sky.sunrise { #expect(sunrise>sunset) }
    }
    @Test func publishedMoonPhases() throws {
        let dates=[("2026-01-18T19:52:00Z",0.0),("2026-03-03T11:38:00Z",0.5),("2026-10-10T15:50:00Z",0.0)]
        for (text,expected) in dates {
            let date=try #require(ISO8601DateFormatter().date(from:text))
            let actual=AstronomyEngine().moonPhase(at:date).fraction
            let delta=min(abs(actual-expected),1-abs(actual-expected))
            #expect(delta*AstronomyEngine.synodicDays*24<1)
        }
    }
    @Test func forecastCoverage() {
        let now=Date.now
        let forecast=Forecast(updated:now,times:[now.timeIntervalSince1970,now.timeIntervalSince1970+3600],clouds:[20,80])
        // Instant values: each stands for the half hour either side of its timestamp.
        #expect(forecast.mean(from:now,to:now.addingTimeInterval(3600))==50)
        #expect(forecast.mean(from:now.addingTimeInterval(1800),to:now.addingTimeInterval(5400))==80)
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
