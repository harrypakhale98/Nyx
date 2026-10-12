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
    /// `tooLarge`: past one of `JournalImport`'s limits, which a journal Nyx wrote never reaches.
    nonisolated enum ArchiveError: Error { case unreadable, newerFormat, tooLarge }
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
    /// A package already in memory (the exporter's document). The counts are checked here; the
    /// photos' sizes when it is prepared (`JournalImport`).
    init(wrapper: FileWrapper) throws {
        guard wrapper.isDirectory, let json=wrapper.fileWrappers?["entries.json"]?.regularFileContents else { throw ArchiveError.unreadable }
        guard json.count<=JournalImport.manifestBytes else { throw ArchiveError.tooLarge }
        let manifest=try Self.manifest(json)
        var photos: [String: Data]=[:]
        for (name, file) in wrapper.fileWrappers?["Photos"]?.fileWrappers ?? [:] { photos[name]=file.regularFileContents }
        self.init(manifest: manifest, photos: photos)
    }
    /// entries.json, read and checked against the counts an import allows.
    static func manifest(_ json: Data) throws -> Manifest {
        let decoder=JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest=try decoder.decode(Manifest.self, from: json)
        guard manifest.format>=1 else { throw ArchiveError.unreadable }
        guard manifest.format<=Self.format else { throw ArchiveError.newerFormat }
        guard manifest.entries.count<=JournalImport.maxEntries, (manifest.spots?.count ?? 0)<=JournalImport.maxSpots,
              manifest.entries.allSatisfy({ $0.photos.count<=PhotoScaling.perEntry }) else { throw ArchiveError.tooLarge }
        return manifest
    }
    /// Merges the archive as an import would (`JournalImport`): photos re-encoded, limits checked.
    @MainActor func merge(into context: ModelContext) throws -> (added: Int, skipped: Int) {
        try JournalImport(self).merge(into: context)
    }
}

/// A journal made ready to merge, entirely off the main thread: its counts and every file's size
/// checked before anything is read, its words cut to length, and each photo re-encoded once
/// through `PhotoScaling` (a JPEG, an HEIC or a PNG only, drawn again as the editor's JPEG, so no
/// location or camera metadata in the file ever reaches the journal). Nyx itself never writes a
/// journal past these limits (an entry holds at most `PhotoScaling.perEntry` photos, each a
/// 2,400-pixel JPEG), so an archive beyond any of them is refused whole and nothing changes.
/// Over-long words are cut instead: a long note never costs the whole journal.
nonisolated struct JournalImport: Sendable {
    static let maxEntries=5_000
    static let maxSpots=500
    static let maxPackageBytes=500_000_000
    static let manifestBytes=100_000_000
    /// Notes, a spot's note and a photo's description.
    static let maxText=20_000
    /// A spot's name, region and country code.
    static let maxSpotText=100

    let manifest: JournalArchive.Manifest
    /// Each photo file named by an entry, re-encoded; a file named a second time is not used again.
    let photos: [String: Data]
    let thumbnails: [UUID: Data]

    /// From an archive in memory (the tests, the exporter's document).
    init(_ archive: JournalArchive) throws {
        guard archive.manifest.entries.count<=Self.maxEntries, (archive.manifest.spots?.count ?? 0)<=Self.maxSpots,
              archive.manifest.entries.allSatisfy({ $0.photos.count<=PhotoScaling.perEntry }),
              archive.photos.values.allSatisfy({ $0.count<=PhotoScaling.maxSourceBytes }),
              archive.photos.values.reduce(0, { $0+$1.count })<=Self.maxPackageBytes else { throw JournalArchive.ArchiveError.tooLarge }
        try self.init(manifest: archive.manifest) { archive.photos[$0] }
    }
    /// From a `.nyxjournal` package on disk. Sizes come from the files' attributes first: a package
    /// past `maxPackageBytes`, an entries.json past `manifestBytes` or a photo past
    /// `PhotoScaling.maxSourceBytes` is refused before it is read. Only files inside the package's
    /// own Photos folder are opened, by the names its listing gives, never a path an entry spells,
    /// and a symbolic link is never followed.
    static func read(_ url: URL) throws -> JournalImport {
        let scoped=url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let manager=FileManager.default
        let keys: Set<URLResourceKey>=[.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
        guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true,
              let walker=manager.enumerator(at: url, includingPropertiesForKeys: Array(keys)) else { throw JournalArchive.ArchiveError.unreadable }
        var total=0
        for case let file as URL in walker {
            let values=try file.resourceValues(forKeys: keys)
            guard values.isSymbolicLink != true, values.isRegularFile == true else { continue }
            total+=values.fileSize ?? 0
            guard total<=maxPackageBytes else { throw JournalArchive.ArchiveError.tooLarge }
        }
        let json=url.appendingPathComponent("entries.json", isDirectory: false)
        let jsonValues=try? json.resourceValues(forKeys: keys)
        guard jsonValues?.isRegularFile == true, jsonValues?.isSymbolicLink != true else { throw JournalArchive.ArchiveError.unreadable }
        guard (jsonValues?.fileSize ?? 0)<=manifestBytes else { throw JournalArchive.ArchiveError.tooLarge }
        let manifest=try JournalArchive.manifest(Data(contentsOf: json))
        // The Photos folder's own listing: a name an entry gives is looked up here, never joined to a path.
        var files: [String: (url: URL, size: Int)]=[:]
        let folder=url.appendingPathComponent("Photos", isDirectory: true)
        for file in (try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(keys))) ?? [] {
            guard let values=try? file.resourceValues(forKeys: keys), values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            files[file.lastPathComponent]=(file, values.fileSize ?? 0)
        }
        for entry in manifest.entries {
            for photo in entry.photos where (files[photo.file]?.size ?? 0)>PhotoScaling.maxSourceBytes { throw JournalArchive.ArchiveError.tooLarge }
        }
        return try JournalImport(manifest: manifest) { name in
            files[name].flatMap { try? Data(contentsOf: $0.url, options: .mappedIfSafe) }
        }
    }
    /// `read` gives a photo file's data by name (nil when there is none). Each file is read and
    /// re-encoded at its first use only; a photo that is not a JPEG, HEIC or PNG is left out.
    private init(manifest: JournalArchive.Manifest, read: (String) -> Data?) throws {
        var used=Set<String>(), photos: [String: Data]=[:], thumbnails: [UUID: Data]=[:]
        func clip(_ text: String, _ limit: Int) -> String { text.count>limit ? String(text.prefix(limit)) : text }
        let entries=manifest.entries.map { item in
            let kept=item.photos.filter { used.insert($0.file).inserted }.compactMap { photo -> JournalArchive.Photo? in
                guard let data=read(photo.file), data.count<=PhotoScaling.maxSourceBytes, let keepsake=PhotoScaling.keepsake(data) else { return nil }
                photos[photo.file]=keepsake
                return JournalArchive.Photo(file: photo.file, altText: photo.altText.map { clip($0, Self.maxText) })
            }
            if let first=kept.first.flatMap({ photos[$0.file] }), let thumbnail=PhotoScaling.jpeg(first, maxPixels: 900) { thumbnails[item.id]=thumbnail }
            return JournalArchive.Entry(id: item.id, date: item.date, parkID: item.parkID, observedBortle: item.observedBortle,
                                        notes: clip(item.notes, Self.maxText), photos: kept)
        }
        let spots=manifest.spots.map { spots in spots.map { spot in
            JournalArchive.Spot(id: spot.id, name: clip(spot.name, Self.maxSpotText), latitude: spot.latitude, longitude: spot.longitude,
                                timeZoneID: clip(spot.timeZoneID, Self.maxSpotText), countryCode: clip(spot.countryCode, Self.maxSpotText),
                                region: clip(spot.region, Self.maxSpotText), created: spot.created, note: spot.note.map { clip($0, Self.maxText) }, saved: spot.saved)
        } }
        self.manifest=JournalArchive.Manifest(format: manifest.format, exported: manifest.exported, entries: entries, spots: spots)
        self.photos=photos
        self.thumbnails=thumbnails
    }

    /// What the confirmation names before anything is merged: the nights and photos in the file,
    /// how many of those nights are already in this journal, and the spots that would be added.
    struct Summary: Equatable, Sendable { let nights: Int; let photos: Int; let alreadyHere: Int; let spots: Int }
    @MainActor func summary(in context: ModelContext) throws -> Summary {
        let merger=try Merger(self, context: context)
        return Summary(nights: manifest.entries.count, photos: manifest.entries.reduce(0) { $0+$1.photos.count },
                       alreadyHere: manifest.entries.filter { merger.isHere($0) }.count, spots: merger.newSpots.count)
    }
    /// Adds the entries the journal does not have yet and returns how many were added and how many
    /// were already there. Only entries already on the device count: two different entries from the
    /// same night in one archive are both added. Nothing existing is changed, and a failed save
    /// leaves nothing behind. Saved spots (format 2) arrive first: one not on the device yet is
    /// added to Your spots, unfollowed, so an archive never sets up reminders, widgets or
    /// forecast requests on its own; one already here (the same id) is left as it is. Spots are not counted.
    @MainActor func merge(into context: ModelContext) throws -> (added: Int, skipped: Int) {
        var merger=try Merger(self, context: context)
        merger.insertSpots()
        for item in manifest.entries { merger.insert(item) }
        return try merger.save()
    }
    /// The same, `batch` entries at a time with a yield between, so a long journal never holds the
    /// main thread for the whole import. One save at the end: still all or nothing.
    @MainActor func merge(into context: ModelContext, batch: Int) async throws -> (added: Int, skipped: Int) {
        var merger=try Merger(self, context: context)
        merger.insertSpots()
        for (index, item) in manifest.entries.enumerated() {
            if index>0, index.isMultiple(of: max(1, batch)) { await Task.yield() }
            merger.insert(item)
        }
        return try merger.save()
    }

    /// What makes two entries the same entry when their ids differ: the park, the moment to the
    /// second (as entries.json keeps it) and the words.
    private struct Sameness: Hashable {
        let parkID: String, second: Int64, notes: String
        init(_ parkID: String, _ date: Date, _ notes: String) {
            self.parkID=parkID; second=Int64(date.timeIntervalSince1970.rounded(.down)); self.notes=notes
        }
    }
    @MainActor private struct Merger {
        let source: JournalImport
        let context: ModelContext
        var ids: Set<UUID>
        let same: Set<Sameness>
        /// The archive's well-formed spots not on this device yet, once each.
        let newSpots: [JournalArchive.Spot]
        var added=0, skipped=0
        init(_ source: JournalImport, context: ModelContext) throws {
            self.source=source; self.context=context
            let existing=try context.fetch(FetchDescriptor<JournalEntry>())
            ids=Set(existing.map(\.id))
            same=Set(existing.map { Sameness($0.parkID, $0.date, $0.notes) })
            let spotIDs=Set(try context.fetch(FetchDescriptor<SavedSpot>()).map(\.id))
            var seen=Set<String>()
            // Only a well-formed spot id (`pin:<uuid>`), once, with real coordinates.
            newSpots=(source.manifest.spots ?? []).filter { spot in
                DeepLink.placeID(spot.id) == spot.id && spot.id.hasPrefix(SavedSpots.prefix) && !spotIDs.contains(spot.id)
                    && (-90...90).contains(spot.latitude) && (-180...180).contains(spot.longitude) && seen.insert(spot.id).inserted
            }
        }
        func isHere(_ item: JournalArchive.Entry) -> Bool { ids.contains(item.id) || same.contains(Sameness(item.parkID, item.date, item.notes)) }
        func insertSpots() {
            for spot in newSpots {
                let zone=TimeZone(identifier: spot.timeZoneID) != nil ? spot.timeZoneID : SavedSpots.solarZone(longitude: spot.longitude)
                context.insert(SavedSpot(id: spot.id, name: spot.name, latitude: spot.latitude, longitude: spot.longitude, timeZoneID: zone,
                                         countryCode: spot.countryCode, region: spot.region, createdAt: spot.created, note: spot.note))
            }
        }
        mutating func insert(_ item: JournalArchive.Entry) {
            // `ids` grows as entries are added, so an id repeated within the archive arrives once.
            guard !isHere(item) else { skipped+=1; return }
            // A park id that names no place in any form Nyx writes is kept as a night outside, never stored as given.
            let parkID=DeepLink.placeID(item.parkID) == nil ? "" : item.parkID
            let entry=JournalEntry(date: item.date, parkID: parkID, observedBortle: min(9, max(1, item.observedBortle)), notes: item.notes)
            entry.id=item.id
            context.insert(entry)
            let kept=item.photos.compactMap { photo in source.photos[photo.file].map { (photo, $0) } }
            for (index, (photo, data)) in kept.enumerated() {
                let record=JournalPhoto(index: index, data: data, altText: photo.altText)
                context.insert(record)
                record.entry=entry
            }
            entry.thumbnail=source.thumbnails[item.id]
            ids.insert(item.id); added+=1
        }
        func save() throws -> (added: Int, skipped: Int) {
            do { try context.save() } catch { context.rollback(); throw error }
            return (added, skipped)
        }
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
