import Foundation
import Testing
@testable import Nyx

/// Trip planning, your constellation, the year's recap, first light and links.
struct DelightTests {
    let parks=(try? ParkData.load()) ?? []
    func park(_ id:String) throws -> Park { try #require(parks.first { $0.id==id }) }
    /// A night with a chosen score, for exercising the assignment alone.
    func night(_ park:Park,_ score:Int,day:TripDay,clouds:Double?=10)->Night {
        let evening=day.evening(in:park)
        let sky=SkyConditions(evening:evening,end:evening+86400,sunset:evening+6*3600,sunrise:evening+18*3600,civilDusk:nil,nauticalDusk:nil,
                              darkStart:evening+8*3600,darkEnd:evening+16*3600,state:.normal,moon:MoonPhase(fraction:0),moonrise:nil,moonset:nil,moonBelowFraction:1,darkHours:8)
        return Night(park:park,sky:sky,score:DarknessScore(value:score,moonPoints:40,cloudPoints:clouds.map { _ in 25 },bortlePoints:20,lengthPoints:15),cloudCover:clouds,forecastUpdated:clouds == nil ? nil : evening)
    }
    let friday=TripDay(year:2026,month:10,day:9)

    // MARK: Days

    @Test func tripDays() throws {
        #expect(friday.weekday==6 && friday.adding(1).weekday==7 && friday.isWeekendNight && !friday.adding(2).isWeekendNight)
        #expect(TripDay(iso:"2026-10-31")?.adding(1)==TripDay(year:2026,month:11,day:1))
        #expect(TripDay(iso:"2026-02-30")==nil && TripDay(iso:"2026-1-05")==nil && TripDay(iso:"tomorrow")==nil)
        #expect(TripDay(iso:"2028-02-29") != nil)
        #expect(friday.days(to:friday.adding(14))==14)
        // A week: two weekend nights. Never more than 14 nights, even weekends across months.
        #expect(TripPlanner.days(first:friday.adding(-4),last:friday.adding(2),weekendsOnly:true)==[friday,friday.adding(1)])
        #expect(TripPlanner.days(first:friday,last:friday.adding(40),weekendsOnly:false).count==14)
        let weekends=TripPlanner.days(first:friday,last:friday.adding(120),weekendsOnly:true)
        #expect(weekends.count==14 && weekends.allSatisfy(\.isWeekendNight))
        #expect(TripPlanner.days(first:friday,last:friday.adding(-1),weekendsOnly:false).isEmpty)
        // A day is the same evening in each park's own zone.
        let samoa=try park("npsa"), acadia=try park("acad")
        #expect(samoa.isoDay(friday.evening(in:samoa))=="2026-10-09" && acadia.isoDay(friday.evening(in:acadia))=="2026-10-09")
    }

    // MARK: Assignment

    @Test func hopsNeverExceedTheLimit() throws {
        let jotr=try park("jotr"), acad=try park("acad")
        let days=[friday,friday.adding(1)]
        // Joshua Tree then Acadia would score most, but that is a 2,300-mile hop overnight.
        let grid=[[night(acad,60,day:days[0]),night(jotr,95,day:days[0])],[night(acad,99,day:days[1]),night(jotr,60,day:days[1])]]
        let plan=TripPlanner.plan(days:days,grid:grid,closures:[:],maxHopMeters:300*1609.344)
        #expect(plan.stops.map(\.night.park.id)==["acad","acad"])
        #expect(plan.stops[1].hopMeters==0)
        let free=TripPlanner.plan(days:days,grid:grid,closures:[:],maxHopMeters:.infinity)
        #expect(free.stops.map(\.night.park.id)==["jotr","acad"])
        #expect((free.stops[1].hopMeters ?? 0)>3_000_000)
    }
    @Test func weekendsAreIndependentTrips() throws {
        let jotr=try park("jotr"), acad=try park("acad")
        let days=TripPlanner.days(first:friday,last:friday.adding(7),weekendsOnly:true)
        #expect(days==[friday,friday.adding(1),friday.adding(7)])
        let grid=days.enumerated().map { i,day in i<2 ? [night(acad,60,day:day),night(jotr,95,day:day)] : [night(acad,99,day:day),night(jotr,60,day:day)] }
        let plan=TripPlanner.plan(days:days,grid:grid,closures:[:],maxHopMeters:300*1609.344)
        // Home in between: the next Friday may be anywhere in reach.
        #expect(plan.stops.map(\.night.park.id)==["jotr","jotr","acad"])
        #expect(plan.stops[2].hopMeters==nil && plan.stops[1].hopMeters==0)
    }
    @Test func tiesStayPutAndBestNightIsEarliest() throws {
        let deva=try park("deva"), jotr=try park("jotr"), grba=try park("grba")
        let days=[friday,friday.adding(1),friday.adding(2)]
        // Equal scores everywhere: no reason to drive, and the darkest measured sky (Great Basin,
        // NASA Black Marble) wins the tie rather than the first park by id.
        let grid=days.map { day in [night(deva,80,day:day),night(grba,80,day:day),night(jotr,80,day:day)] }
        let plan=TripPlanner.plan(days:days,grid:grid,closures:[:],maxHopMeters:.infinity)
        #expect(Set(plan.stops.map(\.night.park.id)).count==1 && plan.stops[0].night.park.id=="grba")
        #expect(plan.best?.day==friday && plan.stops.filter(\.isBest).count==1)
        // The same inputs give the same plan.
        #expect(TripPlanner.plan(days:days,grid:grid,closures:[:],maxHopMeters:.infinity).stops.map(\.night.park.id)==plan.stops.map(\.night.park.id))
        // A clearly darker night elsewhere is worth the drive.
        var moved=grid; moved[1][2]=night(jotr,95,day:days[1])
        let better=TripPlanner.plan(days:days,grid:moved,closures:[:],maxHopMeters:.infinity)
        #expect(better.stops[1].night.park.id=="jotr" && better.best?.day==days[1])
    }
    @Test func closuresAreFlaggedAndCostTheAssignment() throws {
        let deva=try park("deva"), jotr=try park("jotr")
        let days=[friday]
        let close=[[night(deva,85,day:friday),night(jotr,80,day:friday)]]
        let flagged=TripPlanner.plan(days:days,grid:close,closures:["deva":"Badwater Road closed"],maxHopMeters:.infinity)
        #expect(flagged.stops.first?.night.park.id=="jotr" && flagged.stops.first?.closure==nil)
        let far=[[night(deva,95,day:friday),night(jotr,80,day:friday)]]
        let still=TripPlanner.plan(days:days,grid:far,closures:["deva":"Badwater Road closed"],maxHopMeters:.infinity)
        // Much darker despite the alert: chosen, flagged, and its score shown unchanged.
        #expect(still.stops.first?.closure=="Badwater Road closed" && still.stops.first?.night.score.value==95)
        #expect(TripPlanner.shareText(still) { _ in "" }.contains("Closure alert: Badwater Road closed"))
    }
    @Test func emptyPlans() {
        #expect(TripPlanner.plan(days:[friday],grid:[[]],closures:[:],maxHopMeters:1).stops.isEmpty)
        #expect(TripPlanner.plan(days:[],grid:[],closures:[:],maxHopMeters:1).stops.isEmpty)
        #expect(TripPlanner.candidates(parks,latitude:0,longitude:-140,radiusMiles:300).isEmpty)
        // Joshua Tree's 200-mile circle holds Joshua Tree itself and is sorted by id.
        let near=TripPlanner.candidates(parks,latitude:33.87,longitude:-115.9,radiusMiles:200).map(\.id)
        #expect(near.contains("jotr") && near==near.sorted())
    }

    // MARK: Real nights

    @Test func polarNightsAreHonest() throws {
        let denali=try park("dena")
        let days=TripPlanner.days(first:TripDay(year:2026,month:6,day:19),last:TripDay(year:2026,month:6,day:21),weekendsOnly:false)
        let grid=TripPlanner.nights(parks:[denali],days:days,forecasts:[:])
        let plan=TripPlanner.plan(days:days,grid:grid,closures:[:],maxHopMeters:.infinity)
        #expect(plan.stops.count==3)
        for stop in plan.stops {
            #expect(stop.night.score.value<=39 && !stop.night.score.hasForecast)
            #expect(stop.reason.hasPrefix(String(localized:"No true darkness at this latitude")))
            #expect(stop.reason.contains(String(localized:"no cloud forecast yet")))
        }
        let draft=CalendarDraft(stop:try #require(plan.stops.first))
        #expect(draft.notes.contains(SkyConditions.noDarknessMessage(tonight:false)))
    }
    /// Since score v2 every night counts clouds (forecast, early look or usual), so a park with a
    /// forecast and one without compare directly; nothing falls back to Moon and darkness only.
    @Test func mixedForecastsCompareDirectly() throws {
        let deva=try park("deva"), jotr=try park("jotr")
        let now=try #require(TripDay(iso:"2026-10-06")?.evening(in:jotr))
        let hours=(0..<(20*24)).map { now.timeIntervalSince1970-86400+Double($0)*3600 }
        let clear=Forecast(updated:now,times:hours,clouds:hours.map { _ in 5 })
        let days=[TripDay(year:2026,month:10,day:7)]
        let both=TripPlanner.nights(parks:[deva,jotr],days:days,forecasts:["deva":clear,"jotr":clear],now:now)
        #expect(both[0].allSatisfy { $0.score.hasForecast && $0.cloudCover==5 })
        #expect(TripPlanner.reason(both[0][0]).contains(String(localized:"5% cloud forecast")))
        // One park without a forecast: it is scored with its usual clouds and says so; the other keeps its forecast.
        let mixed=TripPlanner.nights(parks:[deva,jotr],days:days,forecasts:["jotr":clear],now:now)
        #expect(mixed[0][0].basis == .usual && mixed[0][0].cloudCover==nil && mixed[0][0].usualCloud != nil)
        #expect(mixed[0][1].score.hasForecast)
        let plan=TripPlanner.plan(days:days,grid:mixed,closures:[:],maxHopMeters:.infinity)
        #expect(plan.unforecastNights==(plan.stops[0].night.park.id=="deva" ? 1 : 0))
        // A forecast is never dropped for its age: 40 hours later the same nights keep it.
        let later=TripPlanner.nights(parks:[deva,jotr],days:days,forecasts:["deva":clear,"jotr":clear],now:now+40*3600)
        #expect(later[0].map(\.score.value)==both[0].map(\.score.value))
        // Ten days on, the same forecast for a night ten days after it was made counts not at all.
        let far=TripPlanner.nights(parks:[deva],days:[TripDay(year:2026,month:10,day:17)],forecasts:["deva":clear],now:now)
        #expect(far[0][0].basis == .usual && far[0][0].cloudCover==nil)
        #expect(TripPlanner.shareText(TripPlanner.plan(days:[TripDay(year:2026,month:10,day:17)],grid:far,closures:[:],maxHopMeters:.infinity)) { _ in "" }.contains(String(localized:"usual clouds")))
    }
    @Test func calendarDraftIsHonest() throws {
        let grba=try park("grba")
        let day=TripDay(year:2026,month:10,day:10)
        let real=TripPlanner.nights(parks:[grba],days:[day],forecasts:[:])[0][0]
        let draft=CalendarDraft(night:real,closure:"Wheeler Peak Scenic Drive closed")
        #expect(draft.start==real.sky.darkStart && draft.end==real.sky.darkEnd && draft.timeZone==grba.timeZone)
        #expect(draft.title==String(localized:"Stargazing at Great Basin"))
        #expect(draft.notes.contains("Wheeler Peak Scenic Drive closed") && draft.notes.contains(String(localized:"Check closures and the forecast before you go.")))
        #expect(draft.notes.contains(String(localized:"No cloud forecast yet.")) && draft.notes.contains(String(localized:"This score uses the usual October clouds at Great Basin.")))
        #expect(draft.url?.absoluteString=="nyx://whatsup?date=2026-10-10&park=grba")
    }

    // MARK: Your constellation

    @Test func everyParkHasAPlaceOnTheSkyMap() throws {
        #expect(parks.count==63)
        var points:[(String,CGPoint)]=[]
        for park in parks {
            let point=SkyMap.position(park), inset=SkyMap.inset(SkyMap.region(park))
            #expect((0...1).contains(point.x) && (0...SkyMap.aspect).contains(point.y),"\(park.id)")
            #expect(inset.frame.insetBy(dx:-0.001,dy:-0.001).contains(point),"\(park.id)")
            // Lower-48 parks stay clear of the insets drawn in the sea.
            if SkyMap.region(park) == .lower48 { for other in SkyMap.insets.dropFirst() { #expect(!other.frame.contains(point),"\(park.id) in \(other.region)") } }
            points.append((park.id,point))
        }
        let gaar=try park("gaar"), havo=try park("havo"), npsa=try park("npsa"), viis=try park("viis")
        #expect(SkyMap.region(gaar) == .alaska && SkyMap.region(havo) == .hawaii && SkyMap.region(npsa) == .samoa && SkyMap.region(viis) == .virginIslands)
        // North is up and east is right inside the lower 48.
        let acad=try park("acad"), olym=try park("olym"), glac=try park("glac"), bibe=try park("bibe")
        #expect(SkyMap.position(acad).x>SkyMap.position(olym).x)
        #expect(SkyMap.position(glac).y<SkyMap.position(bibe).y)
        // No two parks share a point (Sequoia and Kings Canyon are the closest pair).
        for i in points.indices { for j in points.indices where j>i {
            #expect(hypot(points[i].1.x-points[j].1.x,points[i].1.y-points[j].1.y)>0.0015,"\(points[i].0) \(points[j].0)")
        } }
    }
    @Test func constellationIsDeterministic() throws {
        var calendar=Calendar(identifier:.gregorian); calendar.timeZone=TimeZone(identifier:"America/Denver") ?? .gmt
        func date(_ iso:String) throws -> Date { try #require(TripDay(iso:iso)?.evening(in:try park("grba"))) }
        let ids=(0..<6).map { UUID(uuidString:String(format:"00000000-0000-0000-0000-%012d",$0)) ?? UUID() }
        let nights=[
            LoggedNight(id:ids[0],date:try date("2025-12-20"),parkID:"grba",observedBortle:1,score:90),
            LoggedNight(id:ids[1],date:try date("2026-01-15"),parkID:"grba",observedBortle:2,score:70),
            LoggedNight(id:ids[2],date:try date("2026-02-10"),parkID:"deva",observedBortle:2,score:80),
            LoggedNight(id:ids[3],date:try date("2026-07-24"),parkID:"grba",observedBortle:1,score:95),
            LoggedNight(id:ids[4],date:try date("2026-08-12"),parkID:"brca",observedBortle:2,score:88),
            LoggedNight(id:ids[5],date:try date("2026-08-14"),parkID:"zzzz",observedBortle:2,score:88),
        ]
        let layout=ConstellationLayout(nights:nights,parks:parks,calendar:calendar)
        let again=ConstellationLayout(nights:nights.reversed(),parks:parks,calendar:calendar)
        #expect(layout.stars.count==5)  // an unknown park is left out, never placed at 0,0
        #expect(layout.stars.map(\.point)==again.stars.map(\.point) && layout.lines==again.lines)
        // December belongs to the winter of the January that follows it.
        #expect(layout.seasons==[Season(year:2026,kind:.winter),Season(year:2026,kind:.summer)])
        #expect(layout.lines.filter { $0.season.kind == .winter }.count==2 && layout.lines.filter { $0.season.kind == .summer }.count==1)
        // Three nights at Great Basin: a small cluster, the first exactly on the park.
        let basin=layout.stars.filter { $0.night.parkID=="grba" }.map(\.point)
        let grba=try park("grba")
        #expect(basin.count==3 && basin[0]==SkyMap.position(grba) && Set(basin.map { "\($0.x),\($0.y)" }).count==3)
        #expect(basin.allSatisfy { hypot($0.x-basin[0].x,$0.y-basin[0].y)<0.02 })
        // Darker skies shine brighter.
        #expect(ConstellationLayout.brightness(bortle:1,score:90)>ConstellationLayout.brightness(bortle:5,score:90))
        #expect((0.3...1).contains(ConstellationLayout.brightness(bortle:9,score:0)) && ConstellationLayout.brightness(bortle:1,score:100)==1)
        #expect(ConstellationLayout(nights:[],parks:parks).stars.isEmpty)
        // Minimum spanning tree: n − 1 edges, never a longer edge than needed.
        let square=[CGPoint(x:0,y:0),CGPoint(x:1,y:0),CGPoint(x:0,y:1),CGPoint(x:1,y:1)]
        #expect(ConstellationLayout.figure(square).count==3 && ConstellationLayout.figure(square).allSatisfy { hypot($0.0.x-$0.1.x,$0.0.y-$0.1.y)<=1 })
    }
    @Test func skiesSeen() {
        let id={ UUID() }
        let nights=[LoggedNight(id:id(),date:.now,parkID:"grba",observedBortle:2),LoggedNight(id:id(),date:.now,parkID:"grba",observedBortle:1),
                    LoggedNight(id:id(),date:.now,parkID:"jotr",observedBortle:4)]
        let seen=SkiesSeen(nights:nights,parks:parks)
        #expect(seen.parks.count==2 && seen.total==63 && seen.line==String(localized:"2 of 63 national park skies"))
        #expect(seen.parks.first?.id=="grba" && seen.parks.first?.darkestBortle==1 && seen.parks.first?.nights==2)
    }

    // MARK: Year under the stars

    @Test func recapTemplate() throws {
        var calendar=Calendar(identifier:.gregorian); calendar.timeZone=TimeZone(identifier:"America/Los_Angeles") ?? .gmt
        let grba=try park("grba"), deva=try park("deva"), jotr=try park("jotr")
        func at(_ park:Park,_ iso:String) throws -> Date { try #require(TripDay(iso:iso)?.evening(in:park)) }
        let nights=[
            LoggedNight(id:UUID(),date:try at(jotr,"2025-11-20"),parkID:"jotr",observedBortle:4),
            LoggedNight(id:UUID(),date:try at(jotr,"2026-03-18"),parkID:"jotr",observedBortle:3),
            LoggedNight(id:UUID(),date:try at(grba,"2026-08-12"),parkID:"grba",observedBortle:1,score:80),
            LoggedNight(id:UUID(),date:try at(deva,"2026-10-10"),parkID:"deva",observedBortle:2),
        ]
        let recap=YearRecap(year:2026,nights:nights,parks:parks,calendar:calendar)
        #expect(recap.nights==3 && recap.parkNames==["Death Valley","Great Basin","Joshua Tree"])
        #expect(recap.newParkNames==["Death Valley","Great Basin"])
        #expect(recap.darkest?.parkID=="grba" && recap.darkest?.bortle==1)
        #expect((1...3).contains(recap.phases.count))
        // The Perseids peak on the night of August 12, 2026, with the Moon nearly new.
        #expect(recap.event?.contains("Perseids") == true)
        let text=recap.template
        #expect(text.contains("3 nights") && text.contains("2 of them new to you") && text.contains("Great Basin") && text.contains("Bortle 1"))
        #expect(!text.contains("!"))
        #expect(recap.facts.contains(String(localized:"Nights recorded: 3")))
        let empty=YearRecap(year:2024,nights:nights,parks:parks,calendar:calendar)
        #expect(empty.nights==0 && empty.template.contains("No nights recorded in 2024"))
        let first=YearRecap(year:2025,nights:nights,parks:parks,calendar:calendar)
        #expect(first.template.contains("one night") && first.template.contains("each one new to you"))
        for fraction in stride(from:0.0,to:1,by:0.01) { #expect(MoonPhase(fraction:fraction).name==MoonPhase(fraction:YearRecap.phaseFraction(YearRecap.phaseIndex(fraction))).name) }
    }

    @Test func reflectionMayNotInventNumbers() {
        let facts=["Year: 2026","Nights recorded: 3","Darkest observed sky: Great Basin, August 12, 2026, Bortle 1"]
        #expect(OnDeviceGuide.grounded("Three quiet nights in 2026, the darkest at Great Basin under a Bortle 1 sky.",facts:facts))
        #expect(!OnDeviceGuide.grounded("You saw 40 meteors at Great Basin.",facts:facts))
        #expect(!OnDeviceGuide.grounded("What a year!",facts:facts) && !OnDeviceGuide.grounded("",facts:facts))
    }

    // MARK: First light

    @Test func firstLightOnlyInTrueDarkness() throws {
        let jotr=try park("jotr")
        let sky=AstronomyEngine().conditions(for:jotr,on:friday.evening(in:jotr))
        let dark=try #require(sky.darkStart), end=try #require(sky.darkEnd)
        #expect(!FirstLight.shouldShow(sky:sky,now:dark-60,alreadySeen:false))
        #expect(FirstLight.shouldShow(sky:sky,now:dark+60,alreadySeen:false))
        #expect(!FirstLight.shouldShow(sky:sky,now:dark+60,alreadySeen:true))
        #expect(!FirstLight.shouldShow(sky:sky,now:end+60,alreadySeen:false))
        let denali=try park("dena")
        let summer=AstronomyEngine().conditions(for:denali,on:TripDay(year:2026,month:6,day:21).evening(in:denali))
        #expect(!FirstLight.shouldShow(sky:summer,now:summer.evening+12*3600,alreadySeen:false))
        #expect(FirstLight.key("grba")=="firstLight.grba")
    }

    // MARK: Links

    @Test func deepLinks() throws {
        func link(_ s:String)->DeepLink? { URL(string:s).flatMap(DeepLink.init) }
        #expect(link("nyx://whatsup?date=2026-12-13&park=grba") == .whatsUp(park:"grba",day:TripDay(year:2026,month:12,day:13)))
        #expect(link("nyx://whatsup?park=GRBA&date=2026-12-13") == .whatsUp(park:"grba",day:TripDay(year:2026,month:12,day:13)))
        #expect(link("nyx://whatsup?date=2026-13-01&park=grba")==nil && link("nyx://whatsup?park=grba")==nil && link("nyx://whatsup?date=2026-12-13")==nil)
        #expect(link("nyx://calendar/grba?month=2026-12") == .calendar(park:"grba",year:2026,month:12))
        #expect(link("nyx://calendar/grba") == .calendar(park:"grba",year:nil,month:nil))
        #expect(link("nyx://calendar/grba?month=2026-13")==nil && link("nyx://calendar?month=2026-12")==nil && link("nyx://calendar/grba?month=december")==nil)
        #expect(link("nyx://park/jotr") == .park("jotr") && link("nyx://tonight") == .tonight && link("nyx://field/dena") == .field("dena"))
        #expect(link("https://whatsup?date=2026-12-13&park=grba")==nil && link("nyx://park/../../etc")==nil && link("nyx://elsewhere")==nil)
        for value in [DeepLink.whatsUp(park:"grba",day:TripDay(year:2027,month:1,day:3)),.calendar(park:"deva",year:2027,month:5),.calendar(park:"deva",year:nil,month:nil),.park("jotr"),.tonight,.field("gaar")] {
            #expect(value.url.flatMap(DeepLink.init)==value)
        }
        // Every bundled park id is a valid link.
        for park in parks { #expect(link("nyx://park/\(park.id)") == .park(park.id)) }
    }
}
