import CoreTransferable
import Foundation
import UniformTypeIdentifiers

extension UTType {
    /// One national park, dragged between Nyx's screens and windows (declared in the app's Info.plist).
    nonisolated static let nyxPark=UTType(exportedAs:"com.harrypakhale.nyx.park",conformingTo:.data)
}
/// The bundled parks, read once, for what arrives from outside a screen: a drop, a restored window.
/// Park ids are the only thing that travels; the park itself always comes from the bundle.
nonisolated enum ParkCatalog {
    static let parks:[Park]=(try? ParkData.load()) ?? []
    static func park(_ id:String)->Park? { parks.first { $0.id==id } }
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
    static func transferred(id:String,catalog:[Park]=ParkCatalog.parks) throws -> Park {
        let id=id.trimmingCharacters(in:.whitespacesAndNewlines).lowercased()
        guard let park=catalog.first(where:{ $0.id==id }) else { throw ParkTransferError.unknownPark }
        return park
    }
    static func transferred(url:URL,catalog:[Park]=ParkCatalog.parks) throws -> Park {
        guard case .park(let id)?=DeepLink(url) else { throw ParkTransferError.unknownPark }
        return try transferred(id:id,catalog:catalog)
    }
}
