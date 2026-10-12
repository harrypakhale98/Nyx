import Foundation
import CoreGraphics
import Testing
@testable import Nyx

/// The Parks map's US areas draw US places only (their boxes reach into Canada, Mexico and the
/// Bahamas), and a map's places split into a pool scored off the main thread, then ranked.
struct MapAreaTests {
    let parks=(try? ParkData.load()) ?? []
    func place(_ id: String, _ latitude: Double, _ longitude: Double, country: String, curated: Bool = false, bortle: Int = 2) -> Park {
        Park(id:id,nps:nil,name:id,countryCode:country,region:"",kind:curated ? .nationalPark : .darkSkyPark,curated:curated,latitude:latitude,longitude:longitude,timeZoneID:"UTC",
             darkSkyDesignated:false,bortleEstimate:bortle,description:"",sourceURL:"",sourceNote:"",viewingSpots:[])
    }

    /// Abaco (the Bahamas), Espíritu Santo (Mexico) and a park in southern Ontario lie inside the lower
    /// 48's box but are not drawn on it; US catalogue places, the curated parks and a spot inside the
    /// states are. The circle around a starting point and the world keep every place.
    @Test func lowerFortyEightDrawsUSPlacesOnly() {
        let abaco=place("wd:Q1",26.4,-77.1,country:"BS"), espiritu=place("wd:Q2",24.5,-110.35,country:"MX")
        let pelee=place("wd:Q3",41.96,-82.52,country:"CA"), cherry=place("wd:Q4",41.66,-77.82,country:"US")
        // A spot in northern Montana whose nearest bundled town is across the border still counts as American.
        let montana=place("\(SavedSpots.prefix)a",48.9,-111.5,country:"CA"), sonora=place("\(SavedSpots.prefix)b",29.1,-110.95,country:"MX")
        let all=parks+[abaco,espiritu,pelee,cherry,montana,sonora]
        let shown=Set(SkyMap.places(all,for:.lower48).map(\.id))
        #expect(!shown.contains(abaco.id) && !shown.contains(espiritu.id) && !shown.contains(pelee.id) && !shown.contains(sonora.id))
        #expect(shown.contains(cherry.id) && shown.contains(montana.id))
        #expect(parks.allSatisfy { shown.contains($0.id) })
        for region in SkyMap.Region.unitedStates { #expect(SkyMap.places(all,for:region).allSatisfy(SkyMap.isAmerican)) }
        #expect(SkyMap.places(all,for:.around).count==all.count)
        #expect(SkyMap.places(all,for:.world).count==all.count)
        // Puerto Rico and the territories count as American.
        #expect(SkyMap.isAmerican(place("wd:Q5",18.3,-65.8,country:"PR")) && SkyMap.isAmerican(place("wd:Q6",-14.3,-170.7,country:"AS")))
        // On the drawn lower 48 the Bahamas place would be in view: the filter, not the frame, leaves it out.
        let frame=SkyMap.lower48
        #expect(frame.point(abaco).map { frame.shows($0,margin:0.01) } == true)
        let picked=SkyMap.shown(SkyMap.places(all,for:.lower48),in:frame) { $0 }
        #expect(!picked.places.contains { $0.id==abaco.id })
    }
    /// The US start is unchanged: every curated park on the lower 48's map is still drawn there.
    @Test func curatedParksStillDrawnOnTheirAreas() {
        for region in SkyMap.Region.unitedStates {
            let frame=SkyMap.frame(region,origin:nil,radiusMeters:0)
            let inArea=parks.filter { SkyMap.region($0)==region }
            let picked=SkyMap.shown(SkyMap.places(parks,for:region),in:frame) { $0 }
            #expect(Set(inArea.map(\.id)).isSubset(of:Set(picked.places.map(\.id))),"\(region)")
        }
    }
    /// `pool` then `shown(pool)` is exactly `shown`, and the pool's `rest` is what `rank` receives, so
    /// a screen that warms `rest` off the main thread warms every night it then ranks.
    @Test func poolIsWhatRankReceives() {
        let frame=MapFrame.around(GeoPoint(latitude:50,longitude:10),radiusMeters:1_500_000,aspect:SkyMap.aspect)
        var places:[Park]=[]
        for i in 0..<30 { for j in 0..<30 { places.append(place("wd:Q\(i*30+j)",44+Double(i)*0.4,1+Double(j)*0.6,country:"DE",bortle:1+(i+j)%8)) } }
        places.append(place("curated",50,10,country:"US",curated:true))
        let rank:([Park])->[Park]={ $0.sorted { ($0.bortleEstimate,$0.id)<($1.bortleEstimate,$1.id) } }
        var received:[String]=[]
        let direct=SkyMap.shown(places,in:frame,limit:120,scoreLimit:300) { received=$0.map(\.id); return rank($0) }
        let pool=SkyMap.pool(places,in:frame,scoreLimit:300)
        let split=SkyMap.shown(pool,limit:120,rank:rank)
        #expect(pool.rest.map(\.id)==received)
        #expect(pool.rest.count<=300 && pool.fixed.map(\.id)==["curated"])
        #expect(direct.places.map(\.id)==split.places.map(\.id) && direct.inView==split.inView && split.inView>pool.rest.count)
    }
    /// The sub-score titles are measured by their longest word, wider in spaced capitals.
    @Test @MainActor func subscoreTitlesMeasureTheLongestWord() {
        let wide=SubscoreTitles.widestWord(["Luz de luna","Resplandor"],typeSize:.large,spaced:true,bold:false)
        let plain=SubscoreTitles.widestWord(["Luz de luna","Resplandor"],typeSize:.large,spaced:false,bold:false)
        let word=SubscoreTitles.widestWord(["Resplandor"],typeSize:.large,spaced:false,bold:false)
        #expect(wide>plain && plain==word && plain>0)
        #expect(SubscoreTitles.pointSize(.xxxLarge)>SubscoreTitles.pointSize(.large))
        // One style for all four: spaced capitals while they fit four across (a little smaller if need be),
        // then plain words, then two by two; never below 70%.
        #expect(SubscoreTitles.style(widestSpaced:70,widestPlain:55,width:346,spacing:14) == .init(spaced:true,scale:1,columns:4))
        let shrunk=SubscoreTitles.style(widestSpaced:85,widestPlain:60,width:346,spacing:14)
        #expect(shrunk.spaced && shrunk.columns==4 && abs(shrunk.scale-76/85.0)<1e-9)
        #expect(SubscoreTitles.style(widestSpaced:100,widestPlain:80,width:346,spacing:14) == .init(spaced:false,scale:76/80.0,columns:4))
        #expect(SubscoreTitles.style(widestSpaced:130,widestPlain:107,width:346,spacing:14) == .init(spaced:true,scale:1,columns:2))
        #expect(SubscoreTitles.style(widestSpaced:nil,widestPlain:40,width:346,spacing:14) == .init(spaced:false,scale:1,columns:4))
        #expect(SubscoreTitles.style(widestSpaced:500,widestPlain:400,width:346,spacing:14).scale==0.7)
    }
}

/// The world map's first open, timed (`TEST_RUNNER_NYX_BENCH=1`): ranking every pooled place on the main
/// thread from cold, against the same ranking once `prepareNights` has worked their astronomy out off it.
/// Prints `BENCH|name|ms` as SpeedBenchmarks does.
@MainActor
@Suite(.enabled(if: ProcessInfo.processInfo.environment["NYX_BENCH"] != nil), .serialized)
struct MapSpeedBenchmarks {
    private func ms(_ duration: Duration) -> Double { Double(duration.components.seconds)*1000+Double(duration.components.attoseconds)/1e15 }
    @Test func worldMapFirstOpen() async {
        let clock=ContinuousClock()
        let cold=PlanModel()
        await cold.catalogReady()
        let frame=SkyMap.frame(.world,origin:nil,radiusMeters:0)
        let pool=SkyMap.pool(cold.mapPlaces,in:frame)
        let before=clock.measure { _=SkyMap.shown(pool) { $0.map { cold.night($0) }.sorted(by:NightPlanner.better).map(\.park) } }
        let warm=PlanModel()
        await warm.catalogReady()
        let warmPool=SkyMap.pool(warm.mapPlaces,in:frame)
        let off=await clock.measure { await warm.prepareNights(warmPool.rest,count:1) }
        let after=clock.measure { _=SkyMap.shown(warmPool) { $0.map { warm.night($0) }.sorted(by:NightPlanner.better).map(\.park) } }
        print("BENCH|world map rank on main, cold (\(pool.rest.count) places)|\(String(format:"%.2f",ms(before)))")
        print("BENCH|world map warm off main|\(String(format:"%.2f",ms(off)))")
        print("BENCH|world map rank on main, after warming|\(String(format:"%.2f",ms(after)))")
        #expect(pool.rest.count>40)
    }
}
