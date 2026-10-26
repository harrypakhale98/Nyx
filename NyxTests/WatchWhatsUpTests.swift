import Foundation
import Testing
@testable import Nyx

/// Apple Watch in 1.4: "What's up tonight" on the wrist and "Update from iPhone". The watch's own
/// views build only in the watch targets; what is checked here is what they rest on: the message
/// the iPhone answers (`WatchRequest`), and the `WhatsUp` items and layout rule the wrist page reads.
@MainActor struct WatchWhatsUpTests {
    let engine = AstronomyEngine()
    func sky(_ park: Park, _ day: String) throws -> SkyConditions {
        engine.conditions(for: park, on: park.evening(try #require(try? Date(day+"T20:00:00Z", strategy: .iso8601))))
    }

    // MARK: Update from iPhone

    /// The wire: the watch spells these strings itself (`IPhoneAsk`), so they never change quietly.
    @Test func theRequestIsSpelledAsTheWatchSpellsIt() {
        #expect(WatchRequest.key == "request" && WatchRequest.context == "context" && WatchRequest.replyKey == "reply")
        #expect(WatchRequest.Reply.refreshing.rawValue == "refreshing" && WatchRequest.Reply.resending.rawValue == "resending")
    }
    /// Asked for its context, the iPhone says at once whether it will ask for fresh clouds; with
    /// cloud forecasts switched off it only hands over what it has, and the watch says so.
    @Test func theIPhoneAnswersWhatItWillDo() {
        let ask: [String: Any] = ["request": "context"]
        #expect(WatchRequest.reply(to: ask, forecastsOn: true) == .refreshing)
        #expect(WatchRequest.reply(to: ask, forecastsOn: false) == .resending)
    }
    /// Anything else is not a request this iPhone knows: answered empty, and nothing runs.
    @Test func otherMessagesAreNotRequests() {
        #expect(WatchRequest.reply(to: [:], forecastsOn: true) == nil)
        #expect(WatchRequest.reply(to: ["request": "forecast"], forecastsOn: true) == nil)
        #expect(WatchRequest.reply(to: ["request": 1], forecastsOn: true) == nil)
        #expect(WatchRequest.reply(to: ["context": "request"], forecastsOn: true) == nil)
    }

    // MARK: What's up on the wrist

    /// The wrist row is the title (with its word), the figure and the sentence; VoiceOver reads the
    /// spoken form, which must name the thing first, as the row does.
    @Test func everyItemNamesItselfFirstWhenSpoken() throws {
        for (id, day) in [("jotr", "2026-12-13"), ("jotr", "2027-07-10"), ("jotr", "2026-08-27"), ("dena", "2026-06-21"), ("npsa", "2026-10-10")] {
            let up = WhatsUp(park: try park(id), sky: try sky(try park(id), day), isTonight: true)
            for item in up.items {
                #expect(item.spoken.hasPrefix(item.title), "\(id) \(day) \(item.id)")
                #expect(!item.detail.isEmpty, "\(id) \(day) \(item.id)")
                // A timed item is a time the thing is up, so it always has a figure to show.
                #expect(!item.timed || item.value != nil, "\(id) \(day) \(item.id)")
            }
        }
    }
    /// The Geminids' peak at Joshua Tree: a row right after the core, above the planets (ten or more
    /// an hour, a rare thing before the ones up most nights), timed, with "peak tonight" beside the
    /// name, the wrist's own words for that night. Siri says it in the same place (`items`).
    @Test func aShowerPeakIsARowAboveThePlanets() throws {
        let jotr = try park("jotr")
        let up = WhatsUp(park: jotr, sky: try sky(jotr, "2026-12-13"), isTonight: true)
        let layout = WhatsUpPanel.layout(up)
        #expect(layout.first.last?.kind == .meteors && layout.mentions.isEmpty)
        #expect(up.items.map(\.id) == (layout.first + up.planets + layout.after + layout.mentions).map(\.id))
        #expect(up.shower?.note == "peak tonight" && up.shower?.timed == true)
        // The wrist copies the iPhone card's threshold (`WristWhatsUp.showerRow` in NyxWatch).
        #expect(WhatsUpPanel.showerRow == 10)
    }
    /// The partial eclipse of August 2026 is seen from Joshua Tree: a timed row above the planets.
    @Test func aVisiblePartialEclipseIsATimedRow() throws {
        let jotr = try park("jotr")
        let up = WhatsUp(park: jotr, sky: try sky(jotr, "2026-08-27"), isTonight: true)
        let eclipse = try #require(up.eclipse)
        #expect(up.events.eclipse?.visible != nil && up.events.eclipse?.eclipse.type == "partial")
        #expect(eclipse.timed && eclipse.value != nil)
        #expect(WhatsUpPanel.layout(up).first.contains { $0.kind == .eclipse })
    }
    /// Denali at midsummer is the wrist's quiet sky: the core cannot be timed and says why in the
    /// seasonal guidance's words; there is no shower or eclipse to lead with.
    @Test func midsummerAtDenaliIsAQuietSky() throws {
        let dena = try park("dena"), sky = try sky(dena, "2026-06-21")
        let up = WhatsUp(park: dena, sky: sky, isTonight: true)
        #expect(sky.darkHours == 0)
        #expect(!up.core.timed && up.core.value == "Below the horizon")
        #expect(up.eclipse == nil && WhatsUpPanel.layout(up).after.isEmpty)
    }
}
