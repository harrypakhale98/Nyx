import Foundation
import Testing
@testable import Nyx

@MainActor
struct EssayLinkTests {
    @Test func everyEssayLinkOpensARealNyxRoute() throws {
        let jotr = try #require(try ParkData.load().first { $0.id == "jotr" })
        for essay in Essay.allCases {
            guard let link = essay.link(home: jotr, tonight: "2026-10-07") else {
                #expect([.bortle, .etiquette, .access].contains(essay), "\(essay) should lead somewhere in Nyx")
                continue
            }
            #expect(DeepLink(link.url) != nil, "\(essay): \(link.url) is not a link Nyx answers")
            #expect(!link.label.isEmpty)
        }
        #expect(Essay.score.link(home: jotr, tonight: "2026-10-07")?.url.absoluteString == "nyx://tonight")
        #expect(Essay.photo.link(home: jotr, tonight: "2026-10-07")?.url.absoluteString == "nyx://whatsup?date=2026-10-07&park=jotr")
        #expect(Essay.forecast.link(home: jotr, tonight: nil)?.url.absoluteString == "nyx://calendar/jotr")
    }
    @Test func withoutAStartingParkOnlyTonightLinks() {
        #expect(Essay.score.link(home: nil, tonight: nil) != nil)
        #expect(Essay.photo.link(home: nil, tonight: nil) == nil && Essay.safety.link(home: nil, tonight: nil) == nil)
    }
}
