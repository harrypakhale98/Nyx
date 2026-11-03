import Foundation
import Testing
@testable import Nyx

/// Tonight's first answer on a cold launch is the one it settles on: near a border it waits for the
/// world catalogue, and the catalogue arrives with the forecasts kept for its places in reach.
@MainActor struct TonightFirstAnswerTests {
    /// Clouds for the world catalogue: one kept forecast for every place asked about, from the files
    /// alone; nothing for the parks.
    actor KeptWeather: WeatherProviding {
        let kept: Forecast
        private(set) var asked: [Bool]=[]
        init(kept: Forecast) { self.kept=kept }
        func forecasts(for parks: [Park], network: Bool, force: Bool) async -> [String: Forecast] { [:] }
        func hydrate(_ parks: [Park]) async -> [String: Forecast] { [:] }
        func seed(_ cached: [String: Forecast], parks: [Park]) async {}
        func catalogForecasts(_ requests: [[Park]], network: Bool, force: Bool) async -> [String: Forecast] {
            asked.append(network)
            return Dictionary(requests.joined().map { ($0.id, kept) }, uniquingKeysWith: { first, _ in first })
        }
    }
    /// The parks' clouds wait at a gate until let go, as a slow network does; the catalogue's kept
    /// clouds are read from the files at once, and nothing is asked of the network for them.
    actor GatedWeather: WeatherProviding {
        let kept: Forecast
        private var gate: CheckedContinuation<Void, Never>?
        private(set) var asking=false
        init(kept: Forecast) { self.kept=kept }
        func forecasts(for parks: [Park], network: Bool, force: Bool) async -> [String: Forecast] {
            guard network else { return [:] }
            await withCheckedContinuation { gate=$0; asking=true }
            return [:]
        }
        func open() { gate?.resume(); gate=nil }
        func hydrate(_ parks: [Park]) async -> [String: Forecast] { [:] }
        func seed(_ cached: [String: Forecast], parks: [Park]) async {}
        func catalogForecasts(_ requests: [[Park]], network: Bool, force: Bool) async -> [String: Forecast] {
            network ? [:] : Dictionary(requests.joined().map { ($0.id, kept) }, uniquingKeysWith: { first, _ in first })
        }
    }
    /// No clouds from anywhere: a test hands the model its own.
    actor NoWeather: WeatherProviding {
        func forecasts(for parks: [Park], network: Bool, force: Bool) async -> [String: Forecast] { [:] }
        func hydrate(_ parks: [Park]) async -> [String: Forecast] { [:] }
        func seed(_ cached: [String: Forecast], parks: [Park]) async {}
    }
    /// No clouds from anywhere, and a note of every catalogue place asked about over the network.
    actor AskedWeather: WeatherProviding {
        private(set) var asked=Set<String>()
        func forecasts(for parks: [Park], network: Bool, force: Bool) async -> [String: Forecast] { [:] }
        func hydrate(_ parks: [Park]) async -> [String: Forecast] { [:] }
        func seed(_ cached: [String: Forecast], parks: [Park]) async {}
        func catalogForecasts(_ requests: [[Park]], network: Bool, force: Bool) async -> [String: Forecast] {
            if network { asked.formUnion(requests.joined().map(\.id)) }
            return [:]
        }
    }
    /// A model that never reaches the network: the services answer from stubs.
    static func quietModel(weather: any WeatherProviding) throws -> PlanModel {
        let defaults=try #require(UserDefaults(suiteName: "nyx-first-answer-\(UUID().uuidString)"))
        defaults.set(true, forKey: "startChosen")
        let model=PlanModel(weather: weather, parkStore: ParkStore(transport: StubHTTP([:]), persist: false),
                            detail: ForecastDetailService(transport: StubHTTP([:]), persist: false),
                            aurora: AuroraService(transport: StubHTTP([:]), persist: false), defaults: defaults)
        model.radiusMeters=321_869
        return model
    }
    static func model(home: String, weather: any WeatherProviding) throws -> PlanModel {
        let defaults=try #require(UserDefaults(suiteName: "nyx-first-answer-\(UUID().uuidString)"))
        defaults.set(home, forKey: "homePark"); defaults.set(true, forKey: "startChosen")
        let model=PlanModel(weather: weather, parkStore: ParkStore(transport: StubHTTP([:]), persist: false),
                            detail: ForecastDetailService(transport: StubHTTP([:]), persist: false), defaults: defaults)
        model.radiusMeters=321_869
        return model
    }
    static func overcast(_ now: Date) -> Forecast {
        let start=now.timeIntervalSince1970-86400
        return Forecast(updated: now, times: (0..<(16*24)).map { start+Double($0)*3600 }, clouds: Array(repeating: 100, count: 16*24))
    }
    static func clear(_ now: Date) -> Forecast {
        let start=now.timeIntervalSince1970-86400
        return Forecast(updated: now, times: (0..<(16*24)).map { start+Double($0)*3600 }, clouds: Array(repeating: 0, count: 16*24))
    }

    @Test func aReachAcrossTheUSEdgeIsKnownWithoutTheCatalogue() throws {
        let parks=try ParkData.load()
        func crosses(_ id: String) throws -> Bool {
            let park=try #require(parks.first { $0.id == id })
            return TonightReach.crossesUSEdge(latitude: park.latitude, longitude: park.longitude, radiusMeters: 321_869)
        }
        // Joshua Tree (Mexico), Big Bend (Mexico), Glacier and Voyageurs (Canada), Acadia (Canada and the sea).
        for id in ["jotr", "bibe", "glac", "voya", "acad"] { #expect(try crosses(id), "\(id)") }
        // Arches and Great Sand Dunes reach no border and no coast.
        for id in ["arch", "grsa"] { #expect(try !crosses(id), "\(id)") }
    }

    /// At Joshua Tree the first answer waits for the catalogue (Constitution 1857 in Mexico is in reach),
    /// and the catalogue arrives with its places' kept forecasts already counted, so the answer Tonight
    /// first shows is the one it keeps once a refresh reads the same files. Arches never waits.
    @Test func aCatalogueLandingAfterTheFirstRankingNamesOneAnswer() async throws {
        let weather=KeptWeather(kept: Self.overcast(.now))
        let model=try Self.model(home: "jotr", weather: weather)
        #expect(!model.catalogIsReady && model.awaitingWorld)
        await model.catalogReady()
        #expect(!model.awaitingWorld)
        let inReach=model.placesInReach().places
        let world=inReach.filter(\.isCatalogPlace)
        #expect(world.contains { $0.id == "wd:Q5164083" })
        // Every catalogue place in reach is already scored on its kept clouds, read without the network.
        #expect(world.allSatisfy { model.forecasts[$0.id] != nil })
        #expect(await weather.asked == [false])
        let first=model.ranked(model.shortlist(inReach)).first?.id
        // What a refresh reads from the same files changes nothing.
        await model.takeKeptForecasts(inReach)
        #expect(model.ranked(model.shortlist(model.placesInReach().places)).first?.id == first)
        // Overcast across the border: the answer is not a place scored on clouds it was about to lose.
        #expect(first.map { !$0.hasPrefix(Park.catalogPrefix) } == true)

        let arches=try Self.model(home: "arch", weather: KeptWeather(kept: Self.overcast(.now)))
        #expect(!arches.catalogIsReady && !arches.awaitingWorld)
    }

    /// A wider radius (or a late Near-me fix) that brings catalogue places into reach: they count the
    /// clouds kept for them before the parks' request comes back, never their usual clouds until then.
    @Test func placesNewlyInReachCountTheirKeptCloudsAtOnce() async throws {
        let weather=GatedWeather(kept: Self.overcast(.now))
        let model=try Self.quietModel(weather: weather)
        model.choose(parkID: "jotr")
        model.radiusMeters=80_000
        await model.catalogReady()
        let near=Set(model.placesInReach().places.map(\.id))
        model.radiusMeters=321_869
        let all=model.placesInReach().places
        let reached=all.filter { $0.isCatalogPlace && !near.contains($0.id) }
        // Constitution 1857, across the border in Mexico, comes into reach with nothing read for it yet.
        #expect(reached.contains { $0.id == "wd:Q5164083" })
        #expect(reached.allSatisfy { model.forecasts[$0.id] == nil })
        let refresh=Task { await model.refresh(all, parkUpdates: false) }
        var spins=0
        while !(await weather.asking), spins<5_000 { spins+=1; try await Task.sleep(for: .milliseconds(2)) }
        try #require(await weather.asking)
        // The parks' request is still out, and the places newly in reach already count what is kept for them.
        #expect(reached.allSatisfy { model.forecasts[$0.id] != nil })
        await weather.open()
        await refresh.value
    }

    /// Abroad, a radius can hold more places than Tonight ranks at once: the shortlist's leader (the
    /// darkest skies nearest, before any forecast) can give way to a place beyond it under clearer sky
    /// once every place is ranked. So the answer waits until tonight at all of them is worked out.
    @Test func abroadTheAnswerWaitsForEveryPlaceInReach() async throws {
        let model=try Self.quietModel(weather: NoWeather())
        let sydney=try #require(StartingPlaces.all.first { $0.name == "Sydney" })
        model.choose(sydney)
        await model.catalogReady()
        let all=model.placesInReach().places, shortlist=model.shortlist(all)
        try #require(all.count>TonightReach.shortlistSize && shortlist.count == TonightReach.shortlistSize)
        // Clouds by region, as the catalogue's tiles bring them: overcast over the shortlist, clear beyond it.
        let listed=Set(shortlist.map(\.id)), now=Date.now
        model.takeForecasts(Dictionary(uniqueKeysWithValues: all.map { ($0.id, listed.contains($0.id) ? Self.overcast(now) : Self.clear(now)) }))
        let first=try #require(model.ranked(shortlist).first), settled=try #require(model.ranked(all).first)
        #expect(first.id != settled.id && !listed.contains(settled.id))
        // Tonight shows no answer from the shortlist alone: only once every place's tonight is prepared.
        #expect(TonightReach.waits(all, prepared: nil) && TonightReach.waits(all, prepared: TonightReach.key(shortlist)))
        #expect(!TonightReach.waits(all, prepared: TonightReach.key(all.reversed())))
        // At home, where the radius holds no more than the shortlist, it never waits.
        #expect(!TonightReach.waits(shortlist, prepared: nil))
    }

    /// Abroad, Assistive Access and Ask Nyx name Tonight's place: nothing from the shortlist alone, then
    /// the leader of every place in reach once their tonight is worked out. Ask Nyx's own search of a
    /// radius too wide to work out says it ranked the darkest skies only.
    @Test func abroadEveryScreenNamesTonightsPlace() async throws {
        let model=try Self.quietModel(weather: NoWeather())
        let sydney=try #require(StartingPlaces.all.first { $0.name == "Sydney" })
        model.choose(sydney)
        await model.catalogReady()
        let all=model.placesInReach().places, shortlist=model.shortlist(all)
        try #require(all.count>TonightReach.shortlistSize)
        let listed=Set(shortlist.map(\.id)), now=Date.now
        model.takeForecasts(Dictionary(uniqueKeysWithValues: all.map { ($0.id, listed.contains($0.id) ? Self.overcast(now) : Self.clear(now)) }))
        let settled=try #require(model.ranked(all).first)
        try #require(!listed.contains(settled.id))
        #expect(model.wholeReach == nil && AssistiveTonight.best(model) == nil)
        await model.prepareReach(all)
        #expect(model.wholeReach?.map(\.id) == all.map(\.id))
        #expect(AssistiveTonight.best(model)?.id == settled.id)
        let partial={ (facts: [GuideFact]) in facts.contains { $0.text.hasPrefix("Ranked from the \(TonightReach.shortlistSize) places with the darkest skies nearest ") } }
        #expect(partial(GuideView.lookup(model).parksNearFacts(park: "Sydney", radius: 322, system: .kilometers)))
        #expect(!partial(GuideView.lookup(model).parksNearFacts(park: "Arches", radius: 150, system: .miles)))
    }

    /// Abroad, a new radius keeps the answer on screen until every place in it is worked out: the last
    /// set ranked whole while the place it named is still in reach, never the new shortlist; the loader
    /// when that place is left behind.
    @Test func abroadANewRadiusKeepsTheAnswerUntilReady() async throws {
        let model=try Self.quietModel(weather: NoWeather())
        let sydney=try #require(StartingPlaces.all.first { $0.name == "Sydney" })
        model.choose(sydney)
        await model.catalogReady()
        let near=model.placesInReach().places
        await model.prepareReach(near)
        #expect(TonightReach.pool(near, prepared: model.preparedReach)?.map(\.id) == near.map(\.id))
        let leader=try #require(model.ranked(near).first).id
        model.radiusMeters=500_000
        let wider=model.placesInReach().places
        try #require(wider.count>near.count && TonightReach.waits(wider, prepared: model.preparedReach))
        let kept=TonightReach.pool(wider, prepared: model.preparedReach, kept: near, leader: leader)
        #expect(kept?.map(\.id) == near.map(\.id) && kept?.map(\.id) != model.shortlist(wider).map(\.id))
        #expect(TonightReach.pool(wider, prepared: model.preparedReach, kept: nil, leader: nil) == nil)
        await model.prepareReach(wider)
        #expect(TonightReach.pool(wider, prepared: model.preparedReach, kept: near, leader: leader)?.map(\.id) == wider.map(\.id))
        // A reach that has left the kept place behind (another starting point): the loader, not the old answer.
        #expect(TonightReach.pool(wider, prepared: nil, kept: near, leader: "elsewhere") == nil)
    }

    /// Abroad, the reach is worked out again once the night turns over: tonight at every place is the next
    /// night's, so nothing ranks them on the main thread until it is ready.
    @Test func abroadANewNightWaitsForTheReachAgain() async throws {
        let model=try Self.quietModel(weather: NoWeather())
        let sydney=try #require(StartingPlaces.all.first { $0.name == "Sydney" })
        model.choose(sydney)
        await model.catalogReady()
        let all=model.placesInReach().places
        try #require(all.count>TonightReach.shortlistSize)
        await model.prepareReach(all)
        #expect(model.wholeReach?.map(\.id) == all.map(\.id))
        model.pinClock(model.today.addingTimeInterval(86_400))
        #expect(model.preparedReach == nil && model.wholeReach == nil && AssistiveTonight.inReach(model) == nil)
        await model.prepareReach(all)
        #expect(model.wholeReach?.map(\.id) == all.map(\.id))
    }

    /// A prepare for a reach that has since moved on (another window's, a moment late) never marks the
    /// current one ready.
    @Test func aLatePrepareForAnEarlierReachIsDropped() async throws {
        let model=try Self.quietModel(weather: NoWeather())
        let sydney=try #require(StartingPlaces.all.first { $0.name == "Sydney" })
        model.choose(sydney)
        await model.catalogReady()
        let near=model.placesInReach().places
        model.radiusMeters=500_000
        let wider=model.placesInReach().places
        try #require(near.count>TonightReach.shortlistSize && wider.count>near.count)
        await model.prepareReach(near)
        #expect(model.preparedReach == nil && model.wholeReach == nil)
        await model.prepareReach(wider)
        #expect(model.preparedReach == TonightReach.key(wider) && model.wholeReach?.map(\.id) == wider.map(\.id))
    }

    /// Abroad, Assistive Access waits as Tonight does: before the world catalogue is read, the reach holds
    /// no place yet, and that is never said as "nothing is close enough".
    @Test func abroadAssistiveTonightWaitsForTheCatalogue() async throws {
        let model=try Self.quietModel(weather: NoWeather())
        let sydney=try #require(StartingPlaces.all.first { $0.name == "Sydney" })
        model.choose(sydney)
        #expect(model.awaitingWorld && AssistiveTonight.inReach(model) == nil && AssistiveTonight.best(model) == nil)
        // Ask Nyx's records wait too: nothing from the starting point alone.
        #expect(model.wholeReach == nil)
        await model.catalogReady()
        await model.prepareReach(model.placesInReach().places)
        #expect(!model.awaitingWorld && AssistiveTonight.inReach(model) != nil)
    }

    /// Assistive Access asks for the clouds of the place it names when that is a catalogue place leading a
    /// reach of a few places, named on a cold launch before the world catalogue is read.
    @Test func assistiveHomeAsksForTheCataloguePlaceItNames() async throws {
        let weather=AskedWeather()
        let model=try Self.quietModel(weather: weather)
        let sydney=try #require(StartingPlaces.all.first { $0.name == "Sydney" })
        model.choose(sydney)
        model.radiusMeters=50_000
        await AssistiveHome.upkeep(model)
        // The reach as it stands once the catalogue is read: what was asked about must already include its leader.
        await model.catalogReady()
        try #require((1...TonightReach.shortlistSize).contains(model.placesInReach().places.count))
        let named=try #require(AssistiveTonight.best(model))
        #expect(named.isCatalogPlace)
        #expect(await weather.asked.contains(named.id))
    }

    /// Abroad, the reach stays worked out while a night turns over elsewhere (Joshua Tree's sunrise, in the
    /// middle of Sydney's night), so Tonight, Ask Nyx and Assistive Access keep their answer; once one of its
    /// own places turns over, it waits to be worked out again.
    @Test func abroadTheReachOutlastsANightTurningOverElsewhere() async throws {
        let model=try Self.quietModel(weather: NoWeather())
        let sydney=try #require(StartingPlaces.all.first { $0.name == "Sydney" })
        model.choose(sydney)
        await model.catalogReady()
        let all=model.placesInReach().places
        try #require(all.count>TonightReach.shortlistSize)
        // Nov 10, 2026: Joshua Tree's sunrise, a minute either side.
        let start=Date(timeIntervalSince1970: 1_794_268_800)
        let sunrise=try #require(model.park("jotr")?.nightTurnovers(from: start, to: start.addingTimeInterval(2*86_400)).first)
        let before=sunrise.addingTimeInterval(-60), after=sunrise.addingTimeInterval(60)
        try #require(!all.contains { $0.currentNight(at: before) != $0.currentNight(at: after) })
        model.pinClock(before)
        await model.prepareReach(all)
        #expect(model.wholeReach?.map(\.id) == all.map(\.id))
        model.tick(after)
        #expect(model.today == after)
        #expect(model.preparedReach == TonightReach.key(all) && model.wholeReach?.map(\.id) == all.map(\.id))
        let own=try #require(all.first?.nightTurnovers(from: after, to: after.addingTimeInterval(2*86_400)).first)
        model.tick(own.addingTimeInterval(60))
        #expect(model.preparedReach == nil && model.wholeReach == nil && AssistiveTonight.inReach(model) == nil)
        await model.prepareReach(all)
        #expect(model.wholeReach?.map(\.id) == all.map(\.id))
    }

    /// iPhone in landscape: the pill goes beside the dial when, stacked, the whole dial that keeps its words
    /// inside would not stand above the tab bar's edge, or with a closure, would not with the closure under it.
    @Test func theLandscapePillGoesBesideTheDialWhenItMust() {
        // iPhone SE: 234 pt of page, the dial 98 pt down when stacked.
        #expect(TonightView.pillBeside(page: 234, stackedTop: 98, inside: 190))
        // Stacked where the whole dial clears the tab bar's edge by 12 pt (an iPhone 18 Pro Max at the default
        // size), unless a closure needs its line on the first screen; beside it where it would not (an 18 Pro).
        #expect(!TonightView.pillBeside(page: 300, stackedTop: 92, inside: 190))
        #expect(!TonightView.pillBeside(page: 298, stackedTop: 96.33, inside: 190))
        #expect(TonightView.pillBeside(page: 264, stackedTop: 92, inside: 190))
        #expect(TonightView.pillBeside(page: 300, stackedTop: 92, inside: 190, closure: 30))
        #expect(!TonightView.pillBeside(page: 400, stackedTop: 92, inside: 190, closure: 30))
        #expect(!TonightView.pillBeside(page: 0, stackedTop: 0, inside: 190))
        // Beside it when the units would show but the times under the ring's ends would not (a Pro Max at XL).
        #expect(TonightView.pillBeside(page: 300, stackedTop: 100, inside: 209))
        #expect(TonightView.pillBeside(page: 293, stackedTop: 92, inside: 190))
        // Larger text never asks for more than the compact cap (220 pt): 228 pt would have put it beside.
        #expect(!TonightView.pillBeside(page: 335, stackedTop: 100, inside: 228))
        #expect(TonightView.pillBeside(page: 330, stackedTop: 100, inside: 228))
        // Beside it on an iPhone SE, the dial has the page's height: its words inside at the default size, and
        // at XXL the capped dial while its units show.
        #expect(TonightView.dialHeight(compact: true, page: 234, top: 8, inside: 190) == 214)
        #expect(TonightView.dialHeight(compact: true, page: 234, top: 8, inside: 228) == 220)
        // Stacked with a closure, the dial leaves the closure's line above the tab bar.
        #expect(TonightView.dialHeight(compact: true, page: 340, top: 92, inside: 190, closure: 30) == 196)
        // Half a point short of the room with a closure: stacked, as the room rounds up, and the dial that keeps
        // its words inside, never a point smaller with its word dropped under the ring.
        #expect(!TonightView.pillBeside(page: 333.5, stackedTop: 92, inside: 190, closure: 30))
        #expect(TonightView.dialHeight(compact: true, page: 333.5, top: 92, inside: 190, closure: 30) == 190)
        // A page shorter than the floor: the dial keeps to the page.
        #expect(TonightView.dialHeight(compact: true, page: 150, top: 8, inside: 190) == 130)
    }

    /// Beside the dial in landscape, the steps and the way back stay above the tab bar's edge: in words with
    /// the whole context, then with its night alone, then as glyphs, and only then without the context.
    @Test func theStepsBesideTheDialStayOnTheFirstScreen() {
        // A pill of 86 pt, a context of 46 pt (its night alone 20 pt); the steps and the way back 120 pt in words, 44 pt as glyphs.
        let ways={ (room: Double) in TonightView.stepsBeside(room: room, column: 86, context: 46, day: 20, apart: 120, glyphs: 44) }
        #expect(ways(400) == (steps: .apart, context: .whole))
        #expect(ways(272) == (steps: .apart, context: .whole))
        #expect(ways(271) == (steps: .apart, context: .day))
        #expect(ways(246) == (steps: .apart, context: .day))
        #expect(ways(245) == (steps: .glyphs, context: .whole))
        #expect(ways(195) == (steps: .glyphs, context: .day))
        // Short even for the glyphs with the night: the context leaves the column.
        #expect(ways(169) == (steps: .glyphs, context: .after))
        #expect(ways(100) == (steps: .glyphs, context: .after))
        // A page not yet measured keeps the column as it is.
        #expect(ways(0) == (steps: .apart, context: .whole))
        // Only the way back (no steps): a row of its own, with the whole context, the night, or neither.
        let back={ (room: Double) in TonightView.stepsBeside(room: room, column: 86, context: 46, day: 20, apart: 45, glyphs: nil) }
        #expect(back(197) == (steps: .apart, context: .whole))
        #expect(back(171) == (steps: .apart, context: .day))
        #expect(back(170) == (steps: .apart, context: .after))
    }

    /// At accessibility sizes in landscape, the dial is held to what the page's height leaves its band word.
    @Test func anAccessibleDialFitsThePageWithItsWord() {
        #expect(CelestialGauge.accessibleSide(fitting: .infinity, band: 70) == .infinity)
        let side=CelestialGauge.accessibleSide(fitting: 214, band: 70)
        let whole={ (side: Double) in side+16+CelestialGauge.accessibleBandGap(side: side)+70 }
        #expect(side>100 && whole(side) <= 214 && whole(side+1)>214)
    }

    /// iPhone in landscape: the dial takes what the first screen leaves under the pill, between 160 and 240 pt,
    /// or, a little short of the dial that holds its word inside, that dial when its units still show.
    @Test func theLandscapeDialFitsTheFirstScreen() {
        #expect(TonightView.dialHeight(compact: false, page: 300, top: 120) == 240)
        #expect(TonightView.dialHeight(compact: true, page: 0, top: 0) == 240)
        #expect(TonightView.dialHeight(compact: true, page: 330, top: 110) == 208)
        #expect(TonightView.dialHeight(compact: true, page: 600, top: 110) == 240)
        #expect(TonightView.dialHeight(compact: true, page: 250, top: 130) == 160)
        // Beside the pill, short of the dial that keeps its word inside (190 pt): that dial while the first screen
        // shows its units...
        #expect(TonightView.dialHeight(compact: true, page: 285, top: 105, inside: 190) == 190)
        #expect(TonightView.dialHeight(compact: true, page: 320, top: 105, inside: 190) == 203)
        // ...and the fitted dial, words below, when even its units would go under the tab bar.
        #expect(TonightView.dialHeight(compact: true, page: 273, top: 115, inside: 209) == 160)
        #expect(TonightView.dialHeight(compact: false, page: 273, top: 105, inside: 190) == 240)
    }
}
