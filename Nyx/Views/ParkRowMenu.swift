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
    /// A save that could not be stored: the screen says "Saved places unavailable" (`parkSaveAlert`).
    let failed: ()->Void
    /// Offered only where the list can ask before deleting a spot.
    var deleteSpot: ((Park)->Void)?=nil
    /// "Show in Plan", left out where Plan could not come forward: Ask Nyx is pushed on Plan's own
    /// stack, so the request would change nothing on screen.
    var showsPlan=true
    var body: some View {
        let isSaved=saved.contains { $0.parkID==park.id }
        Button(SaveWords.title(saved:isSaved,spot:park.isSavedSpot,place:park.isCatalogPlace),systemImage:isSaved ? "bookmark.slash" : "bookmark") { toggle(isSaved) }
        if showsPlan { Button("Show in Plan",systemImage:"calendar") { commands?.calendarRequest=CalendarRequest(parkID:park.id,year:nil,month:nil); commands?.tab = .plan } }
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
    /// `showsPlan` false leaves out "Show in Plan" (`ParkRowMenu.showsPlan`); `deleteSpot` offers deleting a
    /// saved spot where the list confirms it (`ParkRowMenu.deleteSpot`).
    func parkRowActions(_ park:Park,showsPlan:Bool=true,deleteSpot:((Park)->Void)?=nil,failed:@escaping ()->Void)->some View {
        contextMenu { ParkRowMenu(park:park,failed:failed,deleteSpot:deleteSpot,showsPlan:showsPlan) }.hoverEffect(.highlight).draggable(park)
    }
    /// "Saved places unavailable", after saving or removing a park, place or spot could not be stored.
    func parkSaveAlert(isPresented:Binding<Bool>,journalUnavailable:Bool)->some View {
        alert("Saved places unavailable",isPresented:isPresented) { Button("OK",role:.cancel) {} } message:{
            Text(journalUnavailable ? "Your saved places are stored with your journal on this iPhone, and that storage could not be opened. Nothing was changed. The Journal tab says more." : "The change could not be stored. Nothing was changed. If this iPhone is nearly full, free some space and try again.")
        }
    }
}
