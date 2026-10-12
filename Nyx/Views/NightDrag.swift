import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// One night at one place, dragged from Plan's month onto the Journal (declared in the app's Info.plist).
    nonisolated static let nyxNight=UTType(exportedAs:"com.harrypakhale.nyx.night",conformingTo:.data)
}
/// A night as a drag item (iPad): the place's id and the night's day, written as a Gregorian
/// "2026-10-17" in the place's own time zone, so it names the same night in any window, device
/// calendar or time zone. Nothing about the person travels with it. Only the Journal takes it:
/// Plan, which takes a park, would otherwise offer itself under the finger the moment a night lifts.
nonisolated struct NightTransfer: Codable, Equatable, Sendable, Transferable {
    let place: String
    let night: String
    init(place: String, night: String) { self.place=place; self.night=night }
    init(_ night: Night) { self.init(place:night.park.id,night:night.park.isoDay(night.id)) }
    /// The night's own date at `park` (its noon there, as the app keys nights); nil for another
    /// place, or a day that is not a real Gregorian "YYYY-MM-DD" between 1900 and 2200 (the years
    /// Nyx's links accept).
    func date(at park: Park) -> Date? {
        guard park.id == place, let day=TripDay(iso:night), Self.years.contains(day.year),
              let date=park.calendar.date(from:DateComponents(year:day.year,month:day.month,day:day.day,hour:12)),
              park.isoDay(date) == night else { return nil }
        return date
    }
    static let years=1900...2200
    /// A night as it arrives from a drag, which any app can offer under Nyx's type: small, a place
    /// id in its stored form (`DeepLink.placeID`) and a real day, or nothing.
    static func received(_ data: Data) throws -> NightTransfer {
        guard data.count <= 512 else { throw ParkTransferError.unknownPark }
        let transfer=try JSONDecoder().decode(NightTransfer.self,from:data)
        guard DeepLink.placeID(transfer.place) == transfer.place, let day=TripDay(iso:transfer.night), years.contains(day.year) else {
            throw ParkTransferError.unknownPark
        }
        return transfer
    }
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType:.nyxNight)
    }
}
/// What the Journal takes from a drag: a night from Plan's month, else a park from any list.
nonisolated enum JournalDrop: Transferable, Equatable, Sendable {
    case night(NightTransfer)
    case park(String)
    static var transferRepresentation: some TransferRepresentation {
        // Nyx's night, else a park by any of the ways a park arrives (its id, its nyx:// link).
        DataRepresentation(importedContentType:.nyxNight) { data in JournalDrop.night(try NightTransfer.received(data)) }
        ProxyRepresentation(importing:{ (park:Park) in JournalDrop.park(park.id) })
    }
}
extension JournalDrop {
    /// "Record a night" for what was dropped: the night itself (a night after tonight has not
    /// happened yet, so nothing), or tonight at a park. Nil for a place this device does not know.
    @MainActor func prefill(model: PlanModel, now: Date = .now) -> JournalPrefill? {
        switch self {
        case .park(let id):
            guard let park=model.park(id) else { return nil }
            return .dropped(park:park,tonight:model.tonight(park),now:now)
        case .night(let transfer):
            guard let park=model.park(transfer.place), let date=transfer.date(at:park) else { return nil }
            return .recording(model.night(park,on:date),tonight:model.tonight(park),now:now)
        }
    }
}
extension JournalPrefill {
    /// A night from Plan's month for the journal, as "Keep this night" fills it (the place, the
    /// night, the Bortle estimate, Nyx's score and the Moon as a first line), dated no later than
    /// now since the editor takes no date still ahead. Nil for a night after tonight.
    nonisolated static func recording(_ night: Night, tonight: Date, now: Date = .now) -> JournalPrefill? {
        guard night.id <= tonight else { return nil }
        let kept=JournalPrefill(night:night)
        return JournalPrefill(parkID:kept.parkID,date:min(kept.date,now),observedBortle:kept.observedBortle,notes:kept.notes)
    }
}
/// A calendar night that has begun, offered to the journal: "Record this night" in its menu and
/// as a VoiceOver action on every device, and on iPad a drag onto the Journal (its tab or its
/// screen). Nights still ahead offer neither: a journal keeps nights that happened.
struct RecordableNight: ViewModifier {
    let night: Night
    let enabled: Bool
    let record: () -> Void
    func body(content: Content) -> some View {
        if enabled {
            content
                .accessibilityAction(named:"Record this night",record)
                .modifier(NightDragSource(night:night))
        } else {
            content
        }
    }
}
/// The drag itself, on iPad only: on iPhone a long press stays the night's menu alone.
private struct NightDragSource: ViewModifier {
    let night: Night
    func body(content: Content) -> some View {
        if UIDevice.current.userInterfaceIdiom == .pad { content.draggable(NightTransfer(night)) }
        else { content }
    }
}
