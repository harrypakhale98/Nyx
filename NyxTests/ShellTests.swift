import Foundation
import Testing
@testable import Nyx

/// Starting places, the four tabs, the calendar's stretch, stays in a trip, Ask Nyx's records and
/// the review prompt's rules.
@MainActor struct ShellTests {
    let parks=(try? ParkData.load()) ?? []
    func park(_ id:String) throws -> Park { try #require(parks.first { $0.id==id }) }

    // MARK: Starting places

    @Test func placesAreBundledAndSearchable() throws {
        let places=StartingPlaces.all
        #expect(places.count>=1000)
        // Every state capital, so a person in any state finds a city they know.
        for (state,capital) in [("IL","Springfield"),("SD","Pierre"),("VT","Montpelier"),("AK","Juneau"),("HI","Honolulu"),("MN","Saint Paul")] {
            #expect(places.contains { $0.state==state && $0.name==capital },"missing \(capital), \(state)")
        }
        #expect(StartingPlaces.search("Chicago").first?.label=="Chicago, IL")
        #expect(StartingPlaces.search("chicago il").first?.label=="Chicago, IL")
        #expect(StartingPlaces.search("Springfield, Illinois").first?.label=="Springfield, IL")
        #expect(StartingPlaces.search("St. Paul").first?.label=="Saint Paul, MN")
        // Largest first among equal matches: Columbus, Ohio before Columbus, Georgia.
        #expect(StartingPlaces.search("Columbus").first?.label=="Columbus, OH")
        #expect(StartingPlaces.search("").isEmpty && StartingPlaces.search("zzqx").isEmpty)
        #expect(StartingPlaces.named("Denver")?.label=="Denver, CO")
        #expect(StartingPlaces.named("Denver, CO")?.label=="Denver, CO")
        #expect(StartingPlaces.named("") == nil && StartingPlaces.named("Atlantis") == nil)
    }
    @Test func aPlaceStartsFromItsNearestPark() throws {
        let chicago=try #require(StartingPlaces.named("Chicago, IL"))
        #expect(PlanModel.nearestPark(to:chicago,in:parks)?.id=="indu")
        let near=parks.filter { chicago.distanceMeters(to:$0)<=200*1609.344 }.map(\.id)
        #expect(near.contains("indu") && !near.contains("jotr"))
    }
    @Test func askNyxStartsFromACity() throws {
        let lookup=NightLookup(parks:parks,forecasts:[:],now:Date(timeIntervalSince1970:1791403200))
        let denver=lookup.parksNear(park:"Denver",radiusMiles:100)
        #expect(!denver.isEmpty && denver.allSatisfy { $0.contains("from Denver, CO") })
        #expect(denver.contains { $0.hasPrefix("Rocky Mountain") })
        // A park's own name still wins: Mesa Verde is a park, not Mesa, Arizona.
        #expect(lookup.origin(named:"Mesa Verde")?.label=="Mesa Verde")
        #expect(lookup.parksNear(park:"Atlantis",radiusMiles:300).first?.hasPrefix("No national park or US city") == true)
    }

    // MARK: Tabs and links

    @Test func fourTabsAndTheirRoutes() {
        #expect(SceneCommands.tabs.count==4)
        #expect(SceneCommands.tabIndex("tonight")==0 && SceneCommands.tabIndex("parks")==1 && SceneCommands.tabIndex("journal")==3)
        // The map is a mode of Parks; the accessibility audit opens it by this route.
        #expect(SceneCommands.tabIndex("parks-map")==1)
        // Screenshot scripts still say "calendar"; it is Plan's month.
        #expect(SceneCommands.tabIndex("calendar")==2 && SceneCommands.tabIndex("plan")==2)
        // Learn is no longer a tab: its route opens the index on its own.
        #expect(SceneCommands.tabIndex("learn")==nil)
    }

    // MARK: The calendar's stretch

    func night(_ park:Park,_ day:TripDay,score:Int,illumination:Double,forecast:Bool)->Night {
        let evening=day.evening(in:park)
        let fraction=acos(1-2*illumination)/(2*Double.pi)
        let sky=SkyConditions(evening:evening,end:evening+86400,sunset:evening+6*3600,sunrise:evening+18*3600,civilDusk:nil,nauticalDusk:nil,
                              darkStart:evening+8*3600,darkEnd:evening+16*3600,state:.normal,moon:MoonPhase(fraction:fraction),moonrise:nil,moonset:nil,moonBelowFraction:1,darkHours:8)
        return Night(park:park,sky:sky,score:DarknessScore(value:score,moonPoints:40,cloudPoints:25,bortlePoints:20,lengthPoints:15,basis:forecast ? .forecast : .usual),cloudCover:forecast ? 10 : nil,forecastUpdated:forecast ? evening : nil)
    }
    @Test func theRingFollowsTheScoresWhileForecastsExist() throws {
        let jotr=try park("jotr"), first=TripDay(year:2026,month:10,day:1)
        // Forecast nights 7–20: the moon is darkest on 8–12, but 13–17 score higher.
        let nights=(0..<31).map { i in
            let day=first.adding(i), d=i+1
            let score=(13...17).contains(d) ? 95 : 80
            return night(jotr,day,score:score,illumination:(8...12).contains(d) ? 0.02 : 0.5,forecast:(7...20).contains(d))
        }
        let stretch=CalendarView.stretch(nights,month:nights,after:nights[6].id)
        #expect(stretch.kind == .best && stretch.inMonth)
        #expect(stretch.nights.map { jotr.calendar.component(.day,from:$0.id) }==[13,14,15,16,17])
        // Past nights never carry the ring.
        #expect(stretch.nights.allSatisfy { $0.id>=nights[6].id })
    }
    @Test func beyondTheForecastTheRingMarksTheDarkestMoon() throws {
        let jotr=try park("jotr"), first=TripDay(year:2026,month:11,day:1)
        let nights=(0..<30).map { i in night(jotr,first.adding(i),score:70,illumination:(5...9).contains(i) ? 0.03 : 0.6,forecast:false) }
        let stretch=CalendarView.stretch(nights,month:nights,after:nights[0].id)
        #expect(stretch.kind == .moon && stretch.inMonth)
        #expect(stretch.nights.first?.id==nights[5].id && stretch.nights.count==5)
        #expect(CalendarView.Stretch.Kind.best.title != CalendarView.Stretch.Kind.moon.title)
    }

    // MARK: Trip stays

    @Test func backToBackNightsAtOneParkAreOneStay() throws {
        let deva=try park("deva"), jotr=try park("jotr"), friday=TripDay(year:2026,month:10,day:9)
        func stop(_ park:Park,_ offset:Int,best:Bool=false)->TripStop {
            var s=TripStop(day:friday.adding(offset),night:night(park,friday.adding(offset),score:90+offset,illumination:0.01,forecast:true),closure:nil,hopMeters:nil)
            s.isBest=best; return s
        }
        let stops=[stop(deva,0),stop(deva,1,best:true),stop(deva,2),stop(jotr,3),stop(jotr,5)]
        let stays=TripPlanner.stays(stops)
        #expect(stays.map(\.count)==[3,1,1])
        let draft=try #require(CalendarDraft(stay:stays[0]))
        #expect(draft.title.contains("Death Valley"))
        #expect(draft.start==CalendarDraft(stop:stops[0]).start && draft.end==CalendarDraft(stop:stops[2]).end)
        #expect(draft.notes.components(separatedBy:"\n").filter { $0.contains(" out of 100 ") }.count==3)
        #expect(CalendarDraft(stay:[]) == nil)
        #expect(CalendarDraft(stay:[stops[3]])==CalendarDraft(stop:stops[3]))
        #expect(TripStay(stays[0])?.best?.isBest == true)
    }

    // MARK: Ask Nyx

    @Test func recordsReadBackAsRows() throws {
        let arch=try park("arch")
        let record=GuideRecord("Arches; Fri, Oct 9 (2026-10-09); score 94/100 Pristine; cloud forecast included, 3% cloud; New moon 1% lit; 9.4 hours of true darkness",parks:parks) { _ in .now }
        #expect(record.park?.id=="arch" && record.score==94 && record.band=="Pristine")
        #expect(record.night==TripDay(year:2026,month:10,day:9).evening(in:arch))
        #expect(!record.line.contains("/100") && !record.line.hasPrefix("Arches") && record.line.contains("3% cloud"))
        #expect(record.chip(number:2).hasPrefix("2 · Arches"))
        let near=GuideRecord("Arches, UT; 220 miles straight-line from Denver, CO; tonight 88/100 Excellent",parks:parks) { _ in TripDay(year:2026,month:10,day:7).evening(in:arch) }
        #expect(near.park?.id=="arch" && near.score==88 && near.night != nil && near.line.hasPrefix("220 miles"))
        let start=GuideRecord("Starting point: Chicago, IL. Distances are straight-line estimates.",parks:parks) { _ in .now }
        #expect(start.park==nil && start.score==nil && start.line.hasPrefix("Starting point"))
        // The longest name wins.
        #expect(GuideRecord("Sequoia; tonight",parks:parks) { _ in .now }.park?.id=="sequ")
    }
    @Test func answersMayNotMisquoteTheRecords() {
        let facts=["Arches; Fri, Oct 9 (2026-10-09); score 94/100 Pristine"]
        #expect(OnDeviceGuide.grounded("Arches on Oct 9 scores 94.",facts:facts))
        #expect(!OnDeviceGuide.grounded("Arches on Oct 9 scores 97.",facts:facts))
        #expect(!OnDeviceGuide.grounded("Arches is Pristine!",facts:facts))
    }

    // MARK: Review prompt

    @Test func theReviewPromptAsksOncePerVersionAndNeverInTheDark() {
        #expect(ReviewPrompt.shouldAsk(askedVersion:nil,version:"1.1",nightVision:false,inField:false))
        #expect(!ReviewPrompt.shouldAsk(askedVersion:"1.1",version:"1.1",nightVision:false,inField:false))
        #expect(ReviewPrompt.shouldAsk(askedVersion:"1.0",version:"1.1",nightVision:false,inField:false))
        #expect(!ReviewPrompt.shouldAsk(askedVersion:nil,version:"1.1",nightVision:true,inField:false))
        #expect(!ReviewPrompt.shouldAsk(askedVersion:nil,version:"1.1",nightVision:false,inField:true))
        #expect(!ReviewPrompt.shouldAsk(askedVersion:nil,version:"",nightVision:false,inField:false))
    }
    @Test func greatNightsCountTowardTheThird() throws {
        let defaults=try #require(UserDefaults(suiteName:"nyx-shell-tests"))
        defaults.removePersistentDomain(forName:"nyx-shell-tests")
        let key=ReviewPrompt.greatNightsKey(version:"1.1")
        ReviewPrompt.noteNightViewed(score:60,defaults:defaults,version:"1.1") { _ in }
        #expect(defaults.integer(forKey:key)==0)
        ReviewPrompt.noteNightViewed(score:75,defaults:defaults,version:"1.1") { _ in }; ReviewPrompt.noteNightViewed(score:94,defaults:defaults,version:"1.1") { _ in }
        #expect(defaults.integer(forKey:key)==2)
        defaults.removePersistentDomain(forName:"nyx-shell-tests")
    }
    @Test func supportLinksStayOnTheirHosts() {
        #expect(SupportLink.privacyPolicy?.host()=="get-nyx.com" && SupportLink.privacyPolicy?.path()=="/privacy")
        #expect(SupportLink.support?.host()=="get-nyx.com" && SupportLink.support?.path()=="/support")
        #expect(SupportLink.email?.scheme=="mailto")
        // Live on the App Store: Rate opens the write-review page; share cards carry the product page.
        #expect(AppStoreLink.appID == "6818817800")
        #expect(SupportLink.review?.absoluteString == "https://apps.apple.com/app/id6818817800?action=write-review")
        #expect(SupportLink.storePage?.absoluteString == "https://apps.apple.com/app/id6818817800")
    }
}
