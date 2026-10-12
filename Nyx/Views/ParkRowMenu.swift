import SwiftUI
import SwiftData

/// A park row's menu wherever a park stands as a row (the Parks list, Tonight's other parks, a trip's
/// stops, Ask Nyx's records): save or follow it, its month in Plan, a window of its own on iPad, and,
/// where the list can confirm it, deleting a saved spot. Long press, or a secondary click with a pointer.
struct ParkRowMenu: View {
    @Environment(PlanModel.self) private var model
    @Environment(SceneCommands.self) private var commands: SceneCommands?
    @Environment(\.modelContext) private var context
    @Query(sort:\SavedPark.savedAt) private var saved: [SavedPark]
    let park: Park
    /// A save that could not be stored: the screen says "Unable to save" (`parkSaveAlert`).
    let failed: ()->Void
    /// Offered only where the list can ask before deleting a spot.
    var deleteSpot: ((Park)->Void)?=nil
    /// "Show in Plan", left out where Plan could not come forward: Ask Nyx is pushed on Plan's own
    /// stack, so the request would change nothing on screen.
    var showsPlan=true
    var body: some View {
        let isSaved=saved.contains { $0.parkID==park.id }
        Button(SaveWords.title(saved:isSaved,spot:park.isSavedSpot,place:park.isCatalogPlace),systemImage:isSaved ? "bookmark.slash" : "bookmark") { toggle(isSaved) }
        if showsPlan { Button("Show in Plan",systemImage:"calendar") { commands?.calendarRequest=CalendarRequest(parkID:park.id,year:nil,month:nil); commands?.tab=2 } }
        OpenParkWindowButton(park:park)
        if park.isSavedSpot, let deleteSpot { Button("Delete spot",systemImage:"trash",role:.destructive) { deleteSpot(park) } }
    }
    private func toggle(_ isSaved:Bool) {
        // Saved parks share the journal's store; a save into its stand-in would not last.
        guard !model.journalUnavailable else { failed(); return }
        if let item=saved.first(where:{ $0.parkID==park.id }) { context.delete(item) } else { context.insert(SavedPark(parkID:park.id)) }
        do {
            try context.save()
            // A followed place abroad joins Spotlight (`SpotlightIndexer.remember`).
            if !isSaved, park.isCatalogPlace { let followed=Set(saved.map(\.parkID)).union([park.id]); Task { await SpotlightIndexer.remember(park,followed:followed) } }
        } catch { context.rollback(); failed() }
    }
}

extension View {
    /// A park row outside the Parks list behaves as one inside it: the same menu, the highlight
    /// under a pointer, and the park dragged onto Plan (its month), Journal (a new entry) or another window.
    /// `showsPlan` false leaves out "Show in Plan" (`ParkRowMenu.showsPlan`).
    func parkRowActions(_ park:Park,showsPlan:Bool=true,failed:@escaping ()->Void)->some View {
        contextMenu { ParkRowMenu(park:park,failed:failed,showsPlan:showsPlan) }.hoverEffect(.highlight).draggable(park)
    }
    /// "Unable to save", after a save from a park row's menu could not be stored.
    func parkSaveAlert(isPresented:Binding<Bool>,journalUnavailable:Bool)->some View {
        alert("Unable to save",isPresented:isPresented) { Button("OK",role:.cancel) {} } message:{
            Text(journalUnavailable ? "Saved parks are kept with your journal, which could not be opened. Nothing was changed." : "Your changes could not be stored. Try again when space is available.")
        }
    }
}
