import Foundation
import Testing
import SwiftUI
@testable import Nyx

/// The caches give exactly what the uncached work gives: a kept night equals the
/// planner's, a change of forecast or detail is seen at once, a kept calendar equals a fresh one,
/// the bundled parks read once equal a fresh read, the journal's kept scores equal a fresh scoring,
/// and the resolved star colours equal the mix they replace.
@MainActor @Suite struct CachingTests {
    let engine=AstronomyEngine()
    func named(_ id:String) throws -> Park { try #require(try ParkData.load().first { $0.id==id }) }
    func offline() -> PlanModel {
        PlanModel(weather:WeatherService(transport:RoutedHTTP(),persist:false),parkStore:ParkStore(transport:RoutedHTTP(),persist:false),detail:ForecastDetailService(transport:RoutedHTTP(),persist:false))
    }
    /// The night as `night(_:on:)` worked it out before it kept anything.
    func uncached(_ model:PlanModel,_ park:Park,_ date:Date) -> Night {
        let evening=park.evening(date)
        return NightPlanner.night(park:park,sky:engine.conditions(for:park,on:evening),forecast:model.forecasts[park.id],detail:model.details[park.id],now:.now,scoring:ScoreEngine())
    }
    func same(_ a:Night,_ b:Night) -> Bool {
        a.id==b.id && a.park==b.park && a.score.value==b.score.value && a.score.moonPoints==b.score.moonPoints && a.score.cloudPoints==b.score.cloudPoints
            && a.score.bortlePoints==b.score.bortlePoints && a.score.lengthPoints==b.score.lengthPoints && a.score.basis==b.score.basis && a.score.cloudUsed==b.score.cloudUsed
            && a.cloudCover==b.cloudCover && a.forecastUpdated==b.forecastUpdated && a.usualCloud==b.usualCloud && a.upperCloudOnly==b.upperCloudOnly
            && a.modelSpread==b.modelSpread && a.aerosol==b.aerosol && a.sky.darkStart==b.sky.darkStart && a.sky.darkEnd==b.sky.darkEnd
    }
    /// Hourly clouds across a night's window, issued now.
    func forecast(_ night:Night,clouds:Double) -> Forecast {
        let window=night.sky.cloudWindow
        let first=(floor(window.start.timeIntervalSince1970/3600)-1)*3600
        let times=(0..<30).map { first+Double($0)*3600 }
        return Forecast(updated:.now,times:times,clouds:times.map { _ in clouds })
    }
    func models(_ night:Night,updated:Date) -> ForecastDetail {
        let times=forecast(night,clouds:0).times
        return ForecastDetail(models:HourlySeries(updated:updated,times:times,values:[
            "cloud_cover_gfs_seamless":times.map { _ in 0 },"cloud_cover_ecmwf_ifs025":times.map { _ in 20 },"cloud_cover_icon_seamless":times.map { _ in 60 }]))
    }

    // MARK: Nights

    @Test func keptNightsEqualThePlanners() throws {
        let model=offline()
        for id in ["jotr","dena","gaar","npsa","hale","acad"] {
            let park=try named(id)
            #expect(model.tonight(park)==park.currentNight(at:model.today))
            for offset in [0,1,3,12,20,40] {
                let date=park.date(model.tonight(park),addingDays:offset)
                let first=model.night(park,on:date), again=model.night(park,on:date)
                #expect(same(first,uncached(model,park,date)))
                #expect(same(again,first))
            }
            // Tonight without a date is the same night as tonight's date.
            #expect(same(model.night(park),model.night(park,on:model.tonight(park))))
        }
    }
    @Test func aChangedForecastOrDetailIsSeenAtOnce() throws {
        let model=offline()
        let park=try named("jotr")
        let date=park.date(model.tonight(park),addingDays:2)
        let before=model.night(park,on:date)
        model.forecasts[park.id]=forecast(before,clouds:0)
        let clear=model.night(park,on:date)
        #expect(same(clear,uncached(model,park,date)))
        #expect(clear.cloudCover==0)
        model.forecasts[park.id]=forecast(before,clouds:100)
        let cloudy=model.night(park,on:date)
        #expect(same(cloudy,uncached(model,park,date)))
        #expect(cloudy.cloudCover==100 && cloudy.score.value<clear.score.value)
        // Recent model spread is described; a spread older than 36 hours is not.
        model.details[park.id]=models(before,updated:.now)
        let spread=model.night(park,on:date)
        #expect(same(spread,uncached(model,park,date)) && spread.modelSpread != nil)
        model.details[park.id]=models(before,updated:Date.now.addingTimeInterval(-40*3600))
        let old=model.night(park,on:date)
        #expect(same(old,uncached(model,park,date)) && old.modelSpread == nil)
        model.details[park.id]=nil
        model.forecasts[park.id]=nil
        #expect(same(model.night(park,on:date),before))
    }
    /// Every new forecast or detail moves the data revision, even for parks that already had one,
    /// so a result kept from them (the trip plan) is worked out again rather than left stale.
    @Test func newForecastsAndDetailMoveTheRevision() throws {
        let model=offline()
        let park=try named("jotr")
        let night=model.night(park,on:park.date(model.tonight(park),addingDays:1))
        model.forecasts[park.id]=forecast(night,clouds:0)
        let first=model.dataRevision
        // Same park, same count of forecasts: still a new revision.
        model.forecasts[park.id]=forecast(night,clouds:80)
        #expect(model.dataRevision>first)
        let second=model.dataRevision
        model.details[park.id]=models(night,updated:.now)
        #expect(model.dataRevision>second)
    }
    /// A park with the same id but a different record is scored as itself, never as the kept one.
    @Test func aDifferentParkRecordIsNotTakenForTheKeptOne() throws {
        let model=offline()
        let park=try named("jotr")
        let date=park.date(model.tonight(park),addingDays:1)
        _=model.night(park,on:date)
        var summit=park; summit.aboveInversion=true
        #expect(model.night(park,on:date).park.aboveInversion == park.aboveInversion)
        #expect(model.night(summit,on:date).park.aboveInversion == true)
    }

    // MARK: Calendar and parks

    @Test func aParksCalendarFollowsItsZoneAndRegion() async throws {
        for park in try ParkData.load() {
            var fresh=Calendar(identifier:.gregorian)
            fresh.timeZone=park.timeZone; fresh.locale = .current; fresh.firstWeekday=Calendar.current.firstWeekday
            let kept=park.calendar  // built per read: a cache cost more than it saved (1.4.1 benchmark)
            #expect(kept==fresh)
            #expect(kept.timeZone==fresh.timeZone && kept.firstWeekday==fresh.firstWeekday && kept.locale==fresh.locale && kept.minimumDaysInFirstWeek==fresh.minimumDaysInFirstWeek)
            #expect(park.calendar==kept)
        }
        // Asked from many threads at once, every answer is the park's own.
        let parks=try ParkData.load()
        let zones=await withTaskGroup(of:[Bool].self) { group in
            for _ in 0..<8 { group.addTask { parks.map { $0.calendar.timeZone.identifier==$0.timeZone.identifier } } }
            var all:[Bool]=[]
            for await answers in group { all+=answers }
            return all
        }
        #expect(zones.allSatisfy { $0 })
    }
    @Test func bundledParksReadOnceEqualAFreshRead() throws {
        let url=try #require(Bundle.main.url(forResource:"parks",withExtension:"json"))
        let fresh=try JSONDecoder().decode([Park].self,from:Data(contentsOf:url))
        let first=try ParkData.load(), second=try ParkData.load()
        #expect(first==fresh && second==fresh && !first.isEmpty)
        // Another bundle is still read from that bundle: this one has no parks file.
        #expect(throws:(any Error).self) { try ParkData.load(bundle:Bundle(for:BundleMarker.self)) }
    }

    // MARK: Journal

    @Test func keptJournalScoresEqualAFreshScoring() throws {
        let model=offline()
        let ids=["nowhere"]+model.parks.map(\.id)
        let entries=(0..<40).map { i in JournalEntry(date:Date.now.addingTimeInterval(-Double(i)*86400*7.3),parkID:ids[i%ids.count]) }
        func fresh(_ entry:JournalEntry) -> Int? { model.parks.first { $0.id==entry.parkID }.map { uncached(model,$0,entry.date).score.value } }
        let first=model.loggedNights(entries), again=model.loggedNights(entries)
        #expect(first==again)
        for (night,entry) in zip(first,entries) {
            #expect(night.id==entry.id && night.date==entry.date && night.parkID==entry.parkID && night.observedBortle==entry.observedBortle && night.notes==entry.notes)
            #expect(night.score==fresh(entry))
        }
        #expect(first.contains { $0.parkID=="nowhere" && $0.score == nil })
        // An edited note or a moved date is read afresh; a new forecast rescores.
        let park=try named("jotr")
        let ahead=JournalEntry(date:park.date(model.tonight(park),addingDays:2),parkID:"jotr")
        let before=try #require(model.loggedNights([ahead]).first?.score)
        ahead.notes="Clear to the south."
        #expect(model.loggedNights([ahead]).first?.notes=="Clear to the south.")
        model.forecasts[park.id]=forecast(model.night(park,on:ahead.date),clouds:100)
        let cloudy=try #require(model.loggedNights([ahead]).first?.score)
        #expect(cloudy==fresh(ahead) && cloudy<before)
        ahead.date=park.date(ahead.date,addingDays:1)
        #expect(model.loggedNights([ahead]).first?.score==fresh(ahead))
    }

    // MARK: Star colours

    /// The tint as RealSky and PanoramaSky each mixed it before (Ballesteros, then 35% starlight).
    func oldTint(_ colorIndex:Double,ink:Color) -> Color {
        let temperature=4600*(1/(0.92*colorIndex+1.7)+1/(0.92*colorIndex+0.62))
        let warmth=max(-1,min(1,(6500-temperature)/3500))
        return warmth>0 ? Color(red:1,green:1-0.18*warmth,blue:1-0.42*warmth).mix(with:ink,by:0.35)
            : Color(red:1+0.25*warmth,green:1+0.1*warmth,blue:1).mix(with:ink,by:0.35)
    }
    func close(_ a:Color,_ b:Color,in environment:EnvironmentValues) -> Bool {
        let x=a.resolve(in:environment), y=b.resolve(in:environment), tolerance:Float=1/255
        return abs(x.red-y.red)<=tolerance && abs(x.green-y.green)<=tolerance && abs(x.blue-y.blue)<=tolerance && abs(x.opacity-y.opacity)<=tolerance
    }
    var inks:[Color] {
        [NyxPalette(nightVision:false,highContrast:false).ink,NyxPalette(nightVision:true,highContrast:false).ink,
         NyxPalette(nightVision:true,highContrast:true).ink,NightTint.standard.color,NyxPalette.starlight]
    }
    var environments:[EnvironmentValues] {
        var dark=EnvironmentValues(); dark.colorScheme = .dark
        return [EnvironmentValues(),dark]
    }
    @Test func resolvedStarTintsEqualTheMix() {
        let indices=stride(from:-0.4,through:2,by:0.15).map { $0 }+[0.6,0.65,1.0]
        for ink in inks {
            let resolved=SkyTint.resolved(indices,ink:ink)
            #expect(resolved.count==indices.count)
            for environment in environments {
                for (index,tint) in zip(indices,resolved) {
                    #expect(close(tint,oldTint(index,ink:ink),in:environment))
                    #expect(close(SkyTint.star(index,ink:ink),oldTint(index,ink:ink),in:environment))
                }
                #expect(close(SkyTint.planet(ink:ink),Color(red:1,green:0.86,blue:0.66).mix(with:ink,by:0.3),in:environment))
            }
        }
    }
    @Test func eachSkysTintsFollowItsStars() throws {
        let park=try named("jotr")
        let night=park.evening(try #require(try? Date("2026-10-09T03:00:00Z",strategy:.iso8601)))
        let sky=SkyProjection.shared.sky(for:park,night:night)
        let environment=EnvironmentValues()
        for ink in inks {
            let tints=SkyProjection.shared.tints(sky,ink:ink)
            #expect(tints.faint.count==sky.faint.count && tints.middle.count==sky.middle.count && tints.bright.count==sky.bright.count)
            for (star,tint) in zip(sky.faint+sky.middle+sky.bright,tints.faint+tints.middle+tints.bright) { #expect(close(tint,oldTint(star.colorIndex,ink:ink),in:environment)) }
        }
        let horizon=HorizonSkies.shared.sky(park:park,night:night,at:night.addingTimeInterval(10*3600))
        for ink in inks {
            let tints=HorizonSkies.shared.tints(horizon,ink:ink)
            #expect(tints.count==horizon.stars.count)
            for (star,tint) in zip(horizon.stars,tints) { #expect(close(tint,oldTint(star.colorIndex,ink:ink),in:environment)) }
        }
    }
}
/// A class in the test bundle, whose bundle has no parks file.
private final class BundleMarker {}

/// A kept forecast belongs to the point it was asked for (`ForecastPoints`).
struct ForecastPointsTests {
    func folder() throws -> URL {
        let url=FileManager.default.temporaryDirectory.appendingPathComponent("nyx-points-\(UUID().uuidString)",isDirectory:true)
        try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true)
        return url
    }
    func keep(_ names:[String],in folder:URL) throws { for name in names { try Data("{}".utf8).write(to:folder.appendingPathComponent("nyx-\(name).json")) } }
    func kept(_ name:String,in folder:URL)->Bool { FileManager.default.fileExists(atPath:folder.appendingPathComponent("nyx-\(name).json").path) }
    /// The park with its first viewing spot moved north by `metres`.
    func moved(_ park:Park,metres:Double) throws -> Park {
        var json=try #require(try JSONSerialization.jsonObject(with:JSONEncoder().encode(park)) as? [String:Any])
        var spots=try #require(json["viewingSpots"] as? [[String:Any]])
        let latitude=try #require(spots[0]["latitude"] as? Double)
        spots[0]["latitude"]=latitude+metres/111_195
        json["viewingSpots"]=spots
        return try JSONDecoder().decode(Park.self,from:JSONSerialization.data(withJSONObject:json))
    }
    @Test func firstRunDropsOnlyTheParksMovedBefore() throws {
        let parks=try ParkData.load(), dir=try folder(), old=try folder()
        try keep(["weather-grba","detail-grba","summit-grba","weather-jotr","detail-jotr","alerts"],in:dir)
        try keep(["weather-grba"],in:old)
        #expect(ForecastPoints.reconcile(parks:parks,folders:[dir,old])==["grba"])
        #expect(!kept("weather-grba",in:dir) && !kept("detail-grba",in:dir) && !kept("summit-grba",in:dir) && !kept("weather-grba",in:old))
        #expect(kept("weather-jotr",in:dir) && kept("detail-jotr",in:dir) && kept("alerts",in:dir))
        #expect(kept("points",in:dir))
        // Kept points now: Great Basin's new forecasts stay.
        try keep(["weather-grba"],in:dir)
        #expect(ForecastPoints.reconcile(parks:parks,folders:[dir]).isEmpty && kept("weather-grba",in:dir))
    }
    @Test func aMovedSpotDropsItsParksForecastsOnly() throws {
        let parks=try ParkData.load(), dir=try folder()
        ForecastPoints.reconcile(parks:parks,folders:[dir])
        try keep(["weather-jotr","detail-jotr","weather-zion"],in:dir)
        // A few metres: the same point, kept.
        let nudged=try parks.map { $0.id=="jotr" ? try moved($0,metres:40) : $0 }
        #expect(ForecastPoints.reconcile(parks:nudged,folders:[dir]).isEmpty && kept("weather-jotr",in:dir))
        // Five kilometres: somewhere else, dropped; Zion untouched.
        let shifted=try parks.map { $0.id=="jotr" ? try moved($0,metres:5000) : $0 }
        #expect(ForecastPoints.reconcile(parks:shifted,folders:[dir])==["jotr"])
        #expect(!kept("weather-jotr",in:dir) && !kept("detail-jotr",in:dir) && kept("weather-zion",in:dir))
    }
}
