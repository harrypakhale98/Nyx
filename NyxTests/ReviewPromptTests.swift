import Testing
import Foundation
import UIKit
@testable import Nyx

/// The rating request's moments: counters that start again in each version, a journal entry in a
/// version not yet asked, and a night from field mode kept the morning after. Never in the dark.
@MainActor struct ReviewPromptTests {
    final class Asks { var count=0 }
    func suite(_ name:String) throws -> UserDefaults {
        let defaults=try #require(UserDefaults(suiteName:name))
        defaults.removePersistentDomain(forName:name)
        return defaults
    }

    @Test func greatNightsCountAgainInEachVersion() throws {
        let defaults=try suite("nyx-review-versions"); defer { defaults.removePersistentDomain(forName:"nyx-review-versions") }
        let asks=Asks()
        for _ in 0..<4 { ReviewPrompt.noteNightViewed(score:90,defaults:defaults,version:"1.2") { _ in asks.count+=1 } }
        // The third great night in 1.2 asks; the fourth does not ask again.
        #expect(asks.count==1)
        #expect(defaults.integer(forKey:ReviewPrompt.greatNightsKey(version:"1.2"))==4)
        // 1.3 starts from nothing and asks on its own third.
        #expect(defaults.integer(forKey:ReviewPrompt.greatNightsKey(version:"1.3"))==0)
        ReviewPrompt.noteNightViewed(score:80,defaults:defaults,version:"1.3") { _ in asks.count+=1 }
        ReviewPrompt.noteNightViewed(score:80,defaults:defaults,version:"1.3") { _ in asks.count+=1 }
        #expect(asks.count==1)
        ReviewPrompt.noteNightViewed(score:80,defaults:defaults,version:"1.3") { _ in asks.count+=1 }
        #expect(asks.count==2)
    }

    @Test func aJournalEntryInANewVersionAsks() throws {
        let defaults=try suite("nyx-review-journal"); defer { defaults.removePersistentDomain(forName:"nyx-review-journal") }
        let asks=Asks()
        // One new entry, whatever was there before (not only the first ever).
        ReviewPrompt.noteJournalEntry(old:12,new:13,defaults:defaults) { _ in asks.count+=1 }
        #expect(asks.count==1)
        // A store loading or an import of many is not a moment; nor is a deletion.
        ReviewPrompt.noteJournalEntry(old:0,new:40,defaults:defaults) { _ in asks.count+=1 }
        ReviewPrompt.noteJournalEntry(old:13,new:12,defaults:defaults) { _ in asks.count+=1 }
        #expect(asks.count==1)
        // Asked in 1.2 already: the claim refuses in 1.2 and allows 1.3, once.
        defaults.set("1.2",forKey:ReviewPrompt.askedKey)
        #expect(!ReviewPrompt.claim(defaults:defaults,version:"1.2",nightVision:false,inField:false))
        #expect(ReviewPrompt.claim(defaults:defaults,version:"1.3",nightVision:false,inField:false))
        #expect(defaults.string(forKey:ReviewPrompt.askedKey)=="1.3")
        #expect(!ReviewPrompt.claim(defaults:defaults,version:"1.3",nightVision:false,inField:false))
    }

    @Test func keepingAFieldNightAsks() throws {
        let defaults=try suite("nyx-review-field"); defer { defaults.removePersistentDomain(forName:"nyx-review-field") }
        let asks=Asks()
        ReviewPrompt.noteFieldNightKept(defaults:defaults) { _ in asks.count+=1 }
        #expect(asks.count==1)
    }

    @Test func fieldModeCountsAnywhereInThePresentationChain() {
        // The dawn editor is a sheet over field mode: the top controller is the sheet, not field mode.
        let field=FieldHostingController(parkID:"gaar")
        #expect(ReviewPrompt.inField([UIViewController(),field,UIViewController()]))
        #expect(ReviewPrompt.inField([UIViewController(),field]))
        #expect(!ReviewPrompt.inField([UIViewController(),UIViewController()]))
        #expect(!ReviewPrompt.inField([]))
    }

    @Test func neverInTheDark() throws {
        let defaults=try suite("nyx-review-dark"); defer { defaults.removePersistentDomain(forName:"nyx-review-dark") }
        #expect(!ReviewPrompt.claim(defaults:defaults,version:"1.3",nightVision:true,inField:false))
        #expect(!ReviewPrompt.claim(defaults:defaults,version:"1.3",nightVision:false,inField:true))
        // Nothing recorded, so the version can still ask once the lights are normal.
        #expect(defaults.string(forKey:ReviewPrompt.askedKey)==nil)
        #expect(ReviewPrompt.claim(defaults:defaults,version:"1.3",nightVision:false,inField:false))
    }
}
