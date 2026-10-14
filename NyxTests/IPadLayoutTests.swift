import Foundation
import Testing
@testable import Nyx

/// iPad windows chosen by width, the keyboard's Refresh in Tonight's words, and the photo
/// description's starting line from Vision's labels.
@Suite struct IPadLayoutTests {
    // MARK: Width, never the device

    @Test func parksSplitsOnlyWhereTwoColumnsFit() {
        // iPhone 18 Pro, iPad mini portrait, a 700-point window, 11-inch portrait: the list, then the park pushed.
        for width in [402.0,700,744,834] { #expect(!ParksTab.split(width:width,largeText:false)) }
        // 13-inch portrait, 11-inch landscape, 13-inch landscape: the list beside the park.
        for width in [1032.0,1194,1376] { #expect(ParksTab.split(width:width,largeText:false)) }
        // The boundary is WideLayout's.
        #expect(!ParksTab.split(width:WideLayout.twoColumnWidth-1,largeText:false))
        #expect(ParksTab.split(width:WideLayout.twoColumnWidth,largeText:false))
        // At accessibility text sizes the split waits for twice the room.
        #expect(!ParksTab.split(width:1032,largeText:true))
        #expect(ParksTab.split(width:1376,largeText:true))
        // Not yet measured: a stack, so the first measurement never pushes the chosen park.
        #expect(!ParksTab.split(width:0,largeText:false))
    }
    @Test func theJournalMentionsOtherDevicesInWideWindows() {
        // The widest iPhone in portrait (440) says nothing; any window wider than a phone does.
        #expect(!JournalView.mentionsOtherDevices(width:402,regular:false))
        #expect(!JournalView.mentionsOtherDevices(width:440,regular:false))
        #expect(JournalView.mentionsOtherDevices(width:480,regular:false))
        #expect(JournalView.mentionsOtherDevices(width:1032,regular:false))
        // A regular-width window says it before it is measured.
        #expect(JournalView.mentionsOtherDevices(width:0,regular:true))
        // The journal's own two columns follow WideLayout.
        #expect(WideLayout.columns(width:834,largeText:false)==1)
        #expect(WideLayout.columns(width:1032,largeText:false)==2)
    }

    // MARK: ⌘R

    @Test func refreshSaysWhatItFound() {
        #expect(RefreshOutcome.of(forecastsOn:true,fetched:true,current:false) == .updated)
        // Minutes-old forecasts are current: nothing new to fetch is still up to date.
        #expect(RefreshOutcome.of(forecastsOn:true,fetched:false,current:true) == .updated)
        // Offline: saved data, and why.
        #expect(RefreshOutcome.of(forecastsOn:true,fetched:false,current:false) == .unreachable)
        // Forecasts switched off in Your privacy: never "Updated", whatever the cache holds.
        #expect(RefreshOutcome.of(forecastsOn:false,fetched:true,current:true) == .forecastsOff)
        #expect(RefreshOutcome.unreachable.line == String(localized:"Could not reach the forecast. Showing saved data."))
    }
    @Test @MainActor func refreshAndNightKeysFollowTheTabOnScreen() {
        let commands=SceneCommands()
        let night=UUID(), list=SceneCommands.Refresher(id:UUID(),speaks:false), tonight=SceneCommands.Refresher(id:UUID(),speaks:true)
        // Nothing reported: the keys rest.
        var menu=commands.menu(journalOpen:true)
        #expect(!menu.nights && !menu.refresh && menu.tabs && menu.record)
        // Tonight's river on tab 0; the list on tab 1.
        commands.nights(night,tab:0,on:true)
        commands.refreshes(tonight,tab:0,on:true)
        commands.refreshes(list,tab:1,on:true)
        menu=commands.menu(journalOpen:true)
        #expect(menu.nights && menu.refresh)
        // Parks has a list to refresh but no night to move.
        commands.tab=1
        menu=commands.menu(journalOpen:true)
        #expect(!menu.nights && menu.refresh)
        // Plan and Journal have neither.
        commands.tab=3
        menu=commands.menu(journalOpen:false)
        #expect(!menu.nights && !menu.refresh && !menu.record)
        // Tonight speaks its own result, so ⌘R there is quiet; the newest screen answers.
        commands.tab=0
        commands.refresh()
        #expect(commands.refreshRequest?.target == tonight.id && commands.refreshRequest?.quiet == true)
        commands.tab=1
        commands.refresh()
        #expect(commands.refreshRequest?.target == list.id && commands.refreshRequest?.quiet == false)
        // Gone from screen, gone from the menu.
        commands.nights(night,tab:0,on:false)
        commands.refreshes(list,tab:1,on:false)
        #expect(!commands.menu(journalOpen:true).refresh)
        commands.tab=0
        #expect(!commands.menu(journalOpen:true).nights)
        // A park's own window has no tabs: no Settings or new entry from it, its night keys on tab 0.
        let window=SceneCommands(parkWindow:true)
        window.nights(night,tab:0,on:true)
        let parkMenu=window.menu(journalOpen:true)
        #expect(!parkMenu.tabs && !parkMenu.record && parkMenu.nights)
    }

    // MARK: A photo's starting line

    @Test func labelsMakeAPlainStartingLine() throws {
        try #require(Bundle.main.preferredLocalizations.first?.hasPrefix("en") == true)
        let line=PhotoLabels.line(from:["tent":0.9,"mountain":0.8,"night_sky":0.95,"outdoor":0.99,"sky":0.97])
        // The sky first, then the land, then what people brought; "sky" is not repeated beside "night sky",
        // and identifiers Nyx has no word for ("outdoor") are left out.
        #expect(line == "Night sky, mountains, tent")
        // Unsure labels are dropped; nothing sure, no line.
        #expect(PhotoLabels.line(from:["night_sky":0.3,"tent":0.2]) == nil)
        #expect(PhotoLabels.line(from:["outdoor":0.99,"structure":0.9]) == nil)
        #expect(PhotoLabels.line(from:[:]) == nil)
        // Two identifiers for one word say it once; at most four words.
        #expect(PhotoLabels.line(from:["people":0.9,"crowd":0.9]) == "People")
        let many=PhotoLabels.line(from:["night_sky":1,"moon":1,"mountain":1,"forest":1,"lake":1,"tent":1])
        #expect(many == "Night sky, Moon, mountains, forest")
        // "sky" alone still names the sky.
        #expect(PhotoLabels.line(from:["sky":0.9,"tree":0.9]) == "Sky, trees")
    }
    @Test func labelsAreOfferedOnlyInThePersonsLanguage() {
        #expect(PhotoLabels.speaks(app:"en",preferred:["en-US","es-MX"]))
        #expect(PhotoLabels.speaks(app:"es",preferred:["es-MX"]))
        // A French iPhone reads Nyx in English: an English list would not be the person's words.
        #expect(!PhotoLabels.speaks(app:"en",preferred:["fr-FR","en-US"]))
        #expect(!PhotoLabels.speaks(app:nil,preferred:["en-US"]))
        #expect(!PhotoLabels.speaks(app:"en",preferred:[]))
    }
}
