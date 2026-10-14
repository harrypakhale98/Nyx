import CoreTransferable
import Foundation
import UniformTypeIdentifiers

extension UTType {
    /// One national park, dragged between Nyx's screens and windows (declared in the app's Info.plist).
    nonisolated static let nyxPark=UTType(exportedAs:"com.harrypakhale.nyx.park",conformingTo:.data)
}
nonisolated enum ParkTransferError: Error { case unknownPark }
/// A park as a drag item: Nyx's own type carries the park id (Plan and Journal accept it), other
/// apps get the park's name as plain text, and a `nyx://park/<id>` link for anything that keeps links.
/// Nothing about the person travels with it.
nonisolated extension Park: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(contentType:.nyxPark) { park in Data(park.id.utf8) } importing:{ data in try Park.transferred(id:String(decoding:data,as:UTF8.self)) }
        ProxyRepresentation(exporting:{ park in park.name })
        ProxyRepresentation(exporting:{ park in try park.link() },importing:{ (url:URL) in try Park.transferred(url:url) })
    }
    /// `nyx://park/<id>`, the same link the widgets and Spotlight use.
    func link() throws -> URL {
        guard let url=DeepLink.park(id).url else { throw ParkTransferError.unknownPark }
        return url
    }
    /// The place an id names. Without a `catalog`, Nyx's own: the curated parks and the world catalogue
    /// (decoded only when a `wd:` id is first asked for). Park ids are the only thing that travels; the
    /// park itself always comes from the bundle, and a spot's `pin:` id, which lives in the person's
    /// store, resolves to nothing here.
    static func transferred(id:String,catalog:[Park]?=nil) throws -> Park {
        // Today's letter ids and the namespaced ones (`wd:Q42`, `pin:<uuid>`) read as a link would read them.
        let trimmed=id.trimmingCharacters(in:.whitespacesAndNewlines), id=DeepLink.placeID(trimmed) ?? trimmed.lowercased()
        let found:Park?=if let catalog { catalog.first { $0.id==id } } else { ParkLibrary.place(id,snapshot:nil) }
        guard let park=found else { throw ParkTransferError.unknownPark }
        return park
    }
    static func transferred(url:URL,catalog:[Park]?=nil) throws -> Park {
        switch DeepLink(url) {
        case .park(let id)?, .parkNight(let id,_)?: return try transferred(id:id,catalog:catalog)
        default: throw ParkTransferError.unknownPark
        }
    }
}
