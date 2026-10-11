import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Nyx's journal export: a package (a folder that reads as one file) declared in the app's Info.plist.
    nonisolated static let nyxJournal=UTType(exportedAs: "com.harrypakhale.nyx.journal", conformingTo: .package)
}
/// A journal as one `.nyxjournal` package: `entries.json` and the photos as JPEG files beside it.
/// Private to Nyx but plain inside (JSON and JPEG), made and read entirely on the device, so moving
/// a journal to a new phone or an iPad never involves a server. Importing merges: an entry already
/// on the device (the same id, or the same park, moment and words) is never duplicated, and two
/// different entries from one night are both kept.
///
/// Format 2 adds the saved spots (G3), so a journal moved to a new device keeps the places its
/// entries were written at. A journal with no spots is still written as format 1, byte for byte as
/// before, so a version without spots can open it; every format-1 archive still imports.
nonisolated struct JournalArchive: Sendable, Equatable {
    static let fileExtension="nyxjournal"
    /// The newest format this version reads and writes.
    static let format=2
    nonisolated struct Photo: Codable, Sendable, Equatable { let file: String; let altText: String? }
    nonisolated struct Entry: Codable, Sendable, Equatable {
        let id: UUID
        let date: Date
        let parkID: String
        let observedBortle: Int
        let notes: String
        let photos: [Photo]
    }
    /// A saved spot: where it is, as the person saved it, and whether it was followed (bookmarked).
    nonisolated struct Spot: Codable, Sendable, Equatable {
        let id: String
        let name: String
        let latitude: Double
        let longitude: Double
        let timeZoneID: String
        let countryCode: String
        let region: String
        let created: Date
        let note: String?
        let saved: Bool
    }
    nonisolated struct Manifest: Codable, Sendable, Equatable {
        let format: Int
        let exported: Date
        let entries: [Entry]
        /// Format 2 on; absent (nil) in format 1.
        var spots: [Spot]?=nil
    }
    nonisolated enum ArchiveError: Error { case unreadable, newerFormat }
    var manifest: Manifest
    /// Photo data by file name.
    var photos: [String: Data]

    /// Reads every photo's data, so the journal view calls it from a background `ModelContext`.
    /// `spots` nil reads the saved spots from the entries' own context.
    static func make(from entries: [JournalEntry], spots: [Spot]?=nil, now: Date = .now) -> JournalArchive {
        var photos: [String: Data]=[:]
        // Whole seconds, as the ISO 8601 dates in entries.json keep them.
        func second(_ date: Date) -> Date { Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down)) }
        let items=entries.sorted { $0.date<$1.date }.map { entry in
            Entry(id: entry.id, date: second(entry.date), parkID: entry.parkID, observedBortle: entry.observedBortle, notes: entry.notes,
                  photos: entry.orderedPhotos.enumerated().map { index, photo in
                      let file="\(entry.id.uuidString)-\(index).jpg"
                      photos[file]=photo.data
                      return Photo(file: file, altText: photo.altText)
                  })
        }
        let places=(spots ?? entries.first?.modelContext.map(Self.spots(in:)) ?? []).sorted { ($0.created,$0.id)<($1.created,$1.id) }
        // Without spots, exactly what format 1 wrote.
        let manifest=places.isEmpty ? Manifest(format: 1, exported: second(now), entries: items)
            : Manifest(format: format, exported: second(now), entries: items, spots: places.map { $0.wholeSeconds })
        return JournalArchive(manifest: manifest, photos: photos)
    }
    /// Every saved spot in a store, with whether it is followed.
    static func spots(in context: ModelContext) -> [Spot] {
        let followed=Set(((try? context.fetch(FetchDescriptor<SavedPark>())) ?? []).map(\.parkID))
        return ((try? context.fetch(FetchDescriptor<SavedSpot>())) ?? []).map { spot in
            Spot(id: spot.id, name: spot.name, latitude: spot.latitude, longitude: spot.longitude, timeZoneID: spot.timeZoneID,
                 countryCode: spot.countryCode, region: spot.region, created: spot.createdAt, note: spot.note, saved: followed.contains(spot.id))
        }
    }
    func fileWrapper() throws -> FileWrapper {
        let encoder=JSONEncoder()
        encoder.outputFormatting=[.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let folder=FileWrapper(directoryWithFileWrappers: [:])
        folder.addRegularFile(withContents: try encoder.encode(manifest), preferredFilename: "entries.json")
        let pictures=FileWrapper(directoryWithFileWrappers: photos.mapValues { FileWrapper(regularFileWithContents: $0) })
        pictures.preferredFilename="Photos"
        folder.addFileWrapper(pictures)
        return folder
    }
    init(manifest: Manifest, photos: [String: Data]) { self.manifest=manifest; self.photos=photos }
    init(wrapper: FileWrapper) throws {
        guard wrapper.isDirectory, let json=wrapper.fileWrappers?["entries.json"]?.regularFileContents else { throw ArchiveError.unreadable }
        let decoder=JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest=try decoder.decode(Manifest.self, from: json)
        guard manifest.format>=1 else { throw ArchiveError.unreadable }
        guard manifest.format<=Self.format else { throw ArchiveError.newerFormat }
        var photos: [String: Data]=[:]
        for (name, file) in wrapper.fileWrappers?["Photos"]?.fileWrappers ?? [:] { photos[name]=file.regularFileContents }
        self.init(manifest: manifest, photos: photos)
    }
    init(url: URL) throws {
        let scoped=url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        try self.init(wrapper: FileWrapper(url: url, options: .immediate))
    }
    /// Each entry's card thumbnail, from its first photo. JPEG scaling is slow, so the journal view
    /// draws these off the main thread before `merge`.
    func thumbnails() -> [UUID: Data] {
        var thumbnails: [UUID: Data]=[:]
        for item in manifest.entries {
            if let thumbnail=item.photos.lazy.compactMap({ self.photos[$0.file] }).compactMap({ PhotoScaling.jpeg($0, maxPixels: 900) }).first { thumbnails[item.id]=thumbnail }
        }
        return thumbnails
    }
    /// What makes two entries the same entry when their ids differ: the park, the moment to the
    /// second (as entries.json keeps it) and the words.
    private struct Sameness: Hashable {
        let parkID: String, second: Int64, notes: String
        init(_ parkID: String, _ date: Date, _ notes: String) {
            self.parkID=parkID; second=Int64(date.timeIntervalSince1970.rounded(.down)); self.notes=notes
        }
    }
    /// Adds the entries the journal does not have yet and returns how many were added and how many
    /// were already there. Only entries already on the device count: two different entries from the
    /// same night in one archive are both added. Nothing existing is changed, and a failed save
    /// leaves nothing behind. A photo whose file is missing or is not an image is left out.
    /// Thumbnails not supplied are drawn here. Saved spots (format 2) arrive first: one not on the
    /// device yet is added, and followed if it was; one already here (the same id) is left as it
    /// is. Spots are not counted.
    @MainActor func merge(into context: ModelContext, thumbnails: [UUID: Data]?=nil) throws -> (added: Int, skipped: Int) {
        let existing=try context.fetch(FetchDescriptor<JournalEntry>())
        var ids=Set(existing.map(\.id))
        let same=Set(existing.map { Sameness($0.parkID, $0.date, $0.notes) })
        var added=0, skipped=0
        let spotIDs=Set(try context.fetch(FetchDescriptor<SavedSpot>()).map(\.id))
        let followed=Set(try context.fetch(FetchDescriptor<SavedPark>()).map(\.parkID))
        var seenSpots=Set<String>()
        for spot in manifest.spots ?? [] {
            // Only a well-formed spot id (`pin:<uuid>`), once, with real coordinates.
            guard DeepLink.placeID(spot.id) == spot.id, spot.id.hasPrefix(SavedSpots.prefix), seenSpots.insert(spot.id).inserted, !spotIDs.contains(spot.id),
                  (-90...90).contains(spot.latitude), (-180...180).contains(spot.longitude) else { continue }
            let zone=TimeZone(identifier: spot.timeZoneID) != nil ? spot.timeZoneID : SavedSpots.solarZone(longitude: spot.longitude)
            context.insert(SavedSpot(id: spot.id, name: spot.name, latitude: spot.latitude, longitude: spot.longitude, timeZoneID: zone,
                                     countryCode: spot.countryCode, region: spot.region, createdAt: spot.created, note: spot.note))
            if spot.saved, !followed.contains(spot.id) { context.insert(SavedPark(parkID: spot.id)) }
        }
        for item in manifest.entries {
            // `ids` grows as entries are added, so an id repeated within the archive arrives once.
            guard !ids.contains(item.id), !same.contains(Sameness(item.parkID, item.date, item.notes)) else { skipped+=1; continue }
            let entry=JournalEntry(date: item.date, parkID: item.parkID, observedBortle: min(9, max(1, item.observedBortle)), notes: item.notes)
            entry.id=item.id
            context.insert(entry)
            let kept=item.photos.compactMap { photo in photos[photo.file].flatMap { PhotoScaling.isImage($0) ? (photo, $0) : nil } }
            for (index, (photo, data)) in kept.enumerated() {
                let record=JournalPhoto(index: index, data: data, altText: photo.altText)
                context.insert(record)
                record.entry=entry
            }
            entry.thumbnail=thumbnails.map { $0[item.id] } ?? kept.lazy.compactMap { PhotoScaling.jpeg($0.1, maxPixels: 900) }.first
            ids.insert(item.id); added+=1
        }
        do { try context.save() } catch { context.rollback(); throw error }
        return (added, skipped)
    }
}
nonisolated extension JournalArchive.Spot {
    /// The creation moment to the whole second, as entries.json keeps dates.
    var wholeSeconds: JournalArchive.Spot {
        JournalArchive.Spot(id: id, name: name, latitude: latitude, longitude: longitude, timeZoneID: timeZoneID, countryCode: countryCode,
                            region: region, created: Date(timeIntervalSince1970: created.timeIntervalSince1970.rounded(.down)), note: note, saved: saved)
    }
}
/// Journals opened from another app arrive as copies in Documents/Inbox (Nyx does not open them in
/// place, `LSSupportsOpeningDocumentsInPlace`). Each copy is removed once it has been imported or
/// could not be; copies left by an import cut short are cleared when Nyx leaves the screen. A journal picked in the
/// app's own file browser is never in the Inbox and is never removed.
nonisolated enum JournalInbox {
    static var folder: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("Inbox", isDirectory: true)
    }
    /// True for a file inside `folder`.
    static func contains(_ url: URL, folder: URL?=folder) -> Bool {
        guard let folder, url.isFileURL else { return false }
        let inbox=folder.standardizedFileURL.resolvingSymlinksInPath().path+"/"
        return url.standardizedFileURL.resolvingSymlinksInPath().path.hasPrefix(inbox)
    }
    static func remove(_ url: URL, folder: URL?=folder) {
        guard contains(url, folder: folder) else { return }
        try? FileManager.default.removeItem(at: url)
    }
    /// Removes every journal in the Inbox except those in `keeping` (one still waiting for the
    /// Journal tab, one being read right now). Runs when Nyx leaves the screen, after any opened
    /// file has been handed to the app, so it needs no file dates (no required-reason file
    /// timestamp API).
    static func sweep(folder: URL?=folder, keeping: [URL]=[]) {
        guard let folder, let items=try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return }
        let kept=Set(keeping.map { $0.standardizedFileURL.resolvingSymlinksInPath().path })
        for item in items where item.pathExtension.lowercased() == JournalArchive.fileExtension {
            guard !kept.contains(item.standardizedFileURL.resolvingSymlinksInPath().path) else { continue }
            try? FileManager.default.removeItem(at: item)
        }
    }
}
/// The archive as a document for `fileExporter`.
nonisolated struct JournalDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.nyxJournal] }
    let archive: JournalArchive
    init(archive: JournalArchive) { self.archive=archive }
    init(configuration: ReadConfiguration) throws { archive=try JournalArchive(wrapper: configuration.file) }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { try archive.fileWrapper() }
}
