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
/// Format 2 adds the saved spots, so a journal moved to a new device keeps the places its
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

    /// Reads every photo's data into memory, so it suits a small journal (the tests); the Journal
    /// tab writes its export straight to disk (`write`). `spots` nil reads the saved spots from the
    /// entries' own context.
    static func make(from entries: [JournalEntry], spots: [Spot]?=nil, now: Date = .now) -> JournalArchive {
        var photos: [String: Data]=[:]
        let manifest=layout(entries, spots: spots ?? entries.first?.modelContext.map(Self.spots(in:)) ?? [], now: now) { file, photo in photos[file]=photo.data }
        return JournalArchive(manifest: manifest, photos: photos)
    }
    /// The manifest for `entries`, oldest first, its dates to the whole second; `named` is told each
    /// photo file the manifest names, with its photo.
    private static func layout(_ entries: [JournalEntry], spots: [Spot], now: Date, named: (String, JournalPhoto) -> Void = { _, _ in }) -> Manifest {
        // Whole seconds, as the ISO 8601 dates in entries.json keep them.
        func second(_ date: Date) -> Date { Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down)) }
        let items=entries.sorted { $0.date<$1.date }.map { entry in
            Entry(id: entry.id, date: second(entry.date), parkID: entry.parkID, observedBortle: entry.observedBortle, notes: entry.notes,
                  photos: entry.orderedPhotos.enumerated().map { index, photo in
                      let file=photoFile(entry.id, index)
                      named(file, photo)
                      return Photo(file: file, altText: photo.altText)
                  })
        }
        let places=spots.sorted { ($0.created,$0.id)<($1.created,$1.id) }
        // Without spots, exactly what format 1 wrote.
        return places.isEmpty ? Manifest(format: 1, exported: second(now), entries: items)
            : Manifest(format: format, exported: second(now), entries: items, spots: places.map { $0.wholeSeconds })
    }
    /// A photo's file in the package: its entry's id and its place in the entry.
    private static func photoFile(_ entry: UUID, _ index: Int) -> String { "\(entry.uuidString)-\(index).jpg" }
    /// Nights whose photos are read together while an export is written: only these nights' photos
    /// are ever in memory at once.
    static let exportBatch=8
    /// Writes the journal in `container` as a `.nyxjournal` package at `url`: the same files, byte for
    /// byte, that `make` and `fileWrapper` give. entries.json is written first, then the photos a few
    /// nights at a time (`batch`), each batch read in a context of its own that is let go once its
    /// photos are on disk, so a long journal's photos are never all in memory. A photo added after
    /// the manifest was written is left out; one removed since is simply missing, as an import
    /// allows. Call it off the main thread.
    static func write(_ container: ModelContainer, to url: URL, now: Date = .now, batch: Int=exportBatch) throws {
        let context=ModelContext(container)
        let manifest=layout(try context.fetch(FetchDescriptor<JournalEntry>()), spots: spots(in: context), now: now)
        let folder=url.appendingPathComponent("Photos", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try json(manifest).write(to: url.appendingPathComponent("entries.json", isDirectory: false))
        let named=Set(manifest.entries.flatMap { $0.photos.map(\.file) })
        let withPhotos=manifest.entries.filter { !$0.photos.isEmpty }.map(\.id)
        for start in stride(from: 0, to: withPhotos.count, by: max(1, batch)) {
            let ids=Array(withPhotos[start..<min(withPhotos.count, start+max(1, batch))])
            try autoreleasepool {
                let reader=ModelContext(container)
                for entry in try reader.fetch(FetchDescriptor<JournalEntry>(predicate: #Predicate { ids.contains($0.id) })) {
                    for (index, photo) in entry.orderedPhotos.enumerated() where named.contains(photoFile(entry.id, index)) {
                        try autoreleasepool { try photo.data.write(to: folder.appendingPathComponent(photoFile(entry.id, index), isDirectory: false)) }
                    }
                }
            }
        }
    }
    /// entries.json as Nyx writes it.
    private static func json(_ manifest: Manifest) throws -> Data {
        let encoder=JSONEncoder()
        encoder.outputFormatting=[.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(manifest)
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
        let folder=FileWrapper(directoryWithFileWrappers: [:])
        folder.addRegularFile(withContents: try Self.json(manifest), preferredFilename: "entries.json")
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
    /// Merges the archive as an import would (`JournalImport`): limits checked, photos re-encoded.
    @MainActor func merge(into context: ModelContext) throws -> (added: Int, skipped: Int) {
        try JournalImport(self).merge(into: context)
    }
}

/// A journal made ready to merge, off the main thread, without reading a single photo: its counts
/// and every photo file's size checked from the manifest and the files' attributes, and its words
/// cut to length. The photos are read only when the merge reaches them, a few nights at a time, and
/// only for nights not already in the journal: each is re-encoded once through `PhotoScaling` (a
/// JPEG, an HEIC or a PNG only, drawn again as the editor's JPEG, so no location or camera metadata
/// in the file ever reaches the journal). Nyx itself never writes a journal past these limits (an
/// entry holds at most `PhotoScaling.perEntry` photos, each a 2,400-pixel JPEG), so an archive
/// beyond any of them is refused whole and nothing changes. There is no limit on the package as a
/// whole: it follows from these (`maxEntries` × `PhotoScaling.perEntry` × `PhotoScaling.maxSourceBytes`),
/// and a file in the package that no entry names is never read. Over-long words are cut instead:
/// a long note never costs the whole journal.
nonisolated struct JournalImport: Sendable {
    static let maxEntries=5_000
    static let maxSpots=500
    static let manifestBytes=100_000_000
    /// Notes, a spot's note and a photo's description.
    static let maxText=20_000
    /// A spot's name, region and country code.
    static let maxSpotText=100

    /// Each entry's photos as named in the file, kept only where the file is there (within the size
    /// limit) and named for the first time; nothing has been read from them yet.
    let manifest: JournalArchive.Manifest
    private let source: Source
    /// Where the photos are read from at merge time: an archive already in memory, or the package's
    /// own Photos folder, by the names its listing gave (never a path an entry spells).
    private enum Source: Sendable { case memory([String: Data]), package(URL, [String: URL]) }

    /// From an archive in memory (the tests, the exporter's document).
    init(_ archive: JournalArchive) throws {
        guard archive.manifest.entries.count<=Self.maxEntries, (archive.manifest.spots?.count ?? 0)<=Self.maxSpots,
              archive.manifest.entries.allSatisfy({ $0.photos.count<=PhotoScaling.perEntry }),
              archive.photos.values.allSatisfy({ $0.count<=PhotoScaling.maxSourceBytes }) else { throw JournalArchive.ArchiveError.tooLarge }
        self.init(manifest: archive.manifest, available: Set(archive.photos.keys), source: .memory(archive.photos))
    }
    /// From a `.nyxjournal` package on disk. Sizes come from the files' attributes: an entries.json
    /// past `manifestBytes` or a photo past `PhotoScaling.maxSourceBytes` is refused before it is
    /// read. Only files inside the package's own Photos folder are ever opened, by the names its
    /// listing gives, never a path an entry spells, and a symbolic link is never followed. No photo
    /// is opened here at all; the merge reads them.
    static func read(_ url: URL) throws -> JournalImport {
        let scoped=url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let keys: Set<URLResourceKey>=[.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]
        guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { throw JournalArchive.ArchiveError.unreadable }
        let json=url.appendingPathComponent("entries.json", isDirectory: false)
        let jsonValues=try? json.resourceValues(forKeys: keys)
        guard jsonValues?.isRegularFile == true, jsonValues?.isSymbolicLink != true else { throw JournalArchive.ArchiveError.unreadable }
        guard (jsonValues?.fileSize ?? 0)<=manifestBytes else { throw JournalArchive.ArchiveError.tooLarge }
        let manifest=try JournalArchive.manifest(Data(contentsOf: json))
        // The Photos folder's own listing: a name an entry gives is looked up here, never joined to a path.
        var files: [String: (url: URL, size: Int)]=[:]
        let folder=url.appendingPathComponent("Photos", isDirectory: true)
        for file in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(keys))) ?? [] {
            guard let values=try? file.resourceValues(forKeys: keys), values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            files[file.lastPathComponent]=(file, values.fileSize ?? 0)
        }
        for entry in manifest.entries {
            for photo in entry.photos where (files[photo.file]?.size ?? 0)>PhotoScaling.maxSourceBytes { throw JournalArchive.ArchiveError.tooLarge }
        }
        return JournalImport(manifest: manifest, available: Set(files.keys), source: .package(url, files.mapValues(\.url)))
    }
    /// `available`: the photo files there are. A photo is kept at its first use only, and only when its file is there.
    private init(manifest: JournalArchive.Manifest, available: Set<String>, source: Source) {
        var used=Set<String>()
        func clip(_ text: String, _ limit: Int) -> String { text.count>limit ? String(text.prefix(limit)) : text }
        let entries=manifest.entries.map { item in
            let kept=item.photos.filter { available.contains($0.file) && used.insert($0.file).inserted }.map { photo in
                JournalArchive.Photo(file: photo.file, altText: photo.altText.map { clip($0, Self.maxText) })
            }
            return JournalArchive.Entry(id: item.id, date: item.date, parkID: item.parkID, observedBortle: item.observedBortle,
                                        notes: clip(item.notes, Self.maxText), photos: kept)
        }
        let spots=manifest.spots.map { spots in spots.map { spot in
            JournalArchive.Spot(id: spot.id, name: clip(spot.name, Self.maxSpotText), latitude: spot.latitude, longitude: spot.longitude,
                                timeZoneID: clip(spot.timeZoneID, Self.maxSpotText), countryCode: clip(spot.countryCode, Self.maxSpotText),
                                region: clip(spot.region, Self.maxSpotText), created: spot.created, note: spot.note.map { clip($0, Self.maxText) }, saved: spot.saved)
        } }
        self.manifest=JournalArchive.Manifest(format: manifest.format, exported: manifest.exported, entries: entries, spots: spots)
        self.source=source
    }

    /// What the confirmation names before anything is merged, from the manifest and the files'
    /// sizes alone (no photo is opened): the nights and photos in the file, how many of those nights
    /// are already in this journal, and the spots that would be added.
    struct Summary: Equatable, Sendable { let nights: Int; let photos: Int; let alreadyHere: Int; let spots: Int }
    @MainActor func summary(in context: ModelContext) throws -> Summary {
        let merger=try Merger(self, context: context)
        return Summary(nights: manifest.entries.count, photos: manifest.entries.reduce(0) { $0+$1.photos.count },
                       alreadyHere: manifest.entries.filter { merger.isHere($0) }.count, spots: merger.newSpots.count)
    }
    /// Nights whose photos are read and re-encoded together during a merge: only these nights'
    /// photos are ever decoded at once.
    static let mergeBatch=8
    /// Adds the entries the journal does not have yet and returns how many were added and how many
    /// were already there. Only entries already on the device count: two different entries from the
    /// same night in one archive are both added. Nothing existing is changed. The merge works in a
    /// context of its own with autosave off, saved once at the end, so nothing reaches the store
    /// (or the journal on screen) before that save, and a failed save leaves nothing behind, whatever
    /// else saves `context` meanwhile. Saved spots (format 2) arrive first: one not on the device yet is
    /// added to Your spots, unfollowed, so an archive never sets up reminders, widgets or
    /// forecast requests on its own; one already here (the same id) is left as it is. Spots are not counted.
    @MainActor func merge(into context: ModelContext) throws -> (added: Int, skipped: Int) {
        let folder=try Self.stagingFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        var merger=try Merger(self, context: Self.workspace(context))
        merger.insertSpots()
        for start in stride(from: 0, to: manifest.entries.count, by: Self.mergeBatch) {
            let adding=merger.admit(manifest.entries[start..<min(manifest.entries.count, start+Self.mergeBatch)])
            merger.insert(adding, staged: try stage(adding, in: folder))
        }
        return try merger.save { try $0.save() }
    }
    /// The same, `batch` nights at a time, their photos read and re-encoded off the main thread, so a
    /// long journal never holds the main thread or more than one batch of decoded photos. One save at
    /// the end (`save`, which tests replace): still all or nothing.
    @MainActor func merge(into context: ModelContext, batch: Int, save: @MainActor (ModelContext) throws -> Void = { try $0.save() }) async throws -> (added: Int, skipped: Int) {
        let folder=try Self.stagingFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        var merger=try Merger(self, context: Self.workspace(context))
        merger.insertSpots()
        let size=max(1, batch)
        for start in stride(from: 0, to: manifest.entries.count, by: size) {
            let adding=merger.admit(manifest.entries[start..<min(manifest.entries.count, start+size)])
            let staged=try await Task.detached(priority: .userInitiated) { [self] in try self.stage(adding, in: folder) }.value
            merger.insert(adding, staged: staged)
        }
        return try merger.save(save)
    }
    /// A context of the store's own for one merge, never saved on its own.
    @MainActor private static func workspace(_ context: ModelContext) -> ModelContext {
        let work=ModelContext(context.container)
        work.autosaveEnabled=false
        return work
    }
    /// Where re-encoded photos wait for the merge's save, removed once it is over.
    private static func stagingFolder() throws -> URL {
        let folder=FileManager.default.temporaryDirectory.appendingPathComponent("nyx-import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
    /// A night's photos as the journal keeps them, and its card's thumbnail.
    struct Staged: Sendable { var photos: [(altText: String?, data: Data)]=[]; var thumbnail: Data? }
    /// Reads and re-encodes the photos of `items`, one at a time, each written to `folder` and read
    /// back mapped from there: the merge's single save finds a long journal's photos on disk rather
    /// than in memory. A photo that is gone, has grown past the limit, or is not a JPEG, HEIC or PNG is
    /// left out. A photo that cannot be written (no space) fails the merge, which then changes nothing.
    func stage(_ items: [JournalArchive.Entry], in folder: URL) throws -> [UUID: Staged] {
        var scoped: URL?
        if case .package(let root, _)=source, root.startAccessingSecurityScopedResource() { scoped=root }
        defer { scoped?.stopAccessingSecurityScopedResource() }
        var staged: [UUID: Staged]=[:]
        for item in items {
            var night=Staged()
            for photo in item.photos {
                let file=folder.appendingPathComponent(UUID().uuidString+".jpg", isDirectory: false)
                let written=try autoreleasepool { () throws -> Bool in
                    guard let original=data(photo.file), let keepsake=PhotoScaling.keepsake(original) else { return false }
                    if night.thumbnail == nil { night.thumbnail=PhotoScaling.jpeg(keepsake, maxPixels: 900) }
                    try keepsake.write(to: file)
                    return true
                }
                if written { night.photos.append((photo.altText, try Data(contentsOf: file, options: .alwaysMapped))) }
            }
            staged[item.id]=night
        }
        return staged
    }
    /// One photo file's data as it is now (mapped from disk, not copied), or nil when it is gone, is
    /// no longer a plain file, or has grown past the limit since the file was read.
    private func data(_ file: String) -> Data? {
        switch source {
        case .memory(let photos):
            return photos[file].flatMap { $0.count<=PhotoScaling.maxSourceBytes ? $0 : nil }
        case .package(_, let files):
            guard var url=files[file] else { return nil }
            url.removeAllCachedResourceValues()
            guard let values=try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]), values.isRegularFile == true,
                  values.isSymbolicLink != true, (values.fileSize ?? 0)<=PhotoScaling.maxSourceBytes,
                  let data=try? Data(contentsOf: url, options: .mappedIfSafe), data.count<=PhotoScaling.maxSourceBytes else { return nil }
            return data
        }
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
                PlaceIDText.validated(spot.id) == spot.id && spot.id.hasPrefix(SavedSpots.prefix) && !spotIDs.contains(spot.id)
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
        /// The nights among `items` to add, before any photo is read: those not on the device and
        /// not earlier in the archive. `ids` grows as they are admitted, so an id repeated within
        /// the archive arrives once; the rest count as skipped.
        mutating func admit(_ items: ArraySlice<JournalArchive.Entry>) -> [JournalArchive.Entry] {
            var adding: [JournalArchive.Entry]=[]
            for item in items {
                if isHere(item) { skipped+=1 } else { ids.insert(item.id); adding.append(item) }
            }
            return adding
        }
        mutating func insert(_ items: [JournalArchive.Entry], staged: [UUID: Staged]) {
            for item in items {
                // A park id that names no place in any form Nyx writes is kept as a night outside, never stored as given.
                let parkID=PlaceIDText.validated(item.parkID) == nil ? "" : item.parkID
                let entry=JournalEntry(date: item.date, parkID: parkID, observedBortle: min(9, max(1, item.observedBortle)), notes: item.notes)
                entry.id=item.id
                context.insert(entry)
                let night=staged[item.id] ?? Staged()
                for (index, photo) in night.photos.enumerated() {
                    let record=JournalPhoto(index: index, data: photo.data, altText: photo.altText)
                    context.insert(record)
                    record.entry=entry
                }
                entry.thumbnail=night.thumbnail
                added+=1
            }
        }
        func save(_ save: @MainActor (ModelContext) throws -> Void) throws -> (added: Int, skipped: Int) {
            do { try save(context) } catch { context.rollback(); throw error }
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
/// Where an export is gathered on disk before the person chooses where it goes. One at a time: a
/// new export clears the last, and the Journal tab clears it once the exporter closes.
nonisolated enum JournalExport {
    static var folder: URL { FileManager.default.temporaryDirectory.appendingPathComponent("nyx-export", isDirectory: true) }
    /// Writes the journal in `container` to a new package in `folder` and returns it; nothing is
    /// left behind when it fails.
    static func stage(_ container: ModelContainer, now: Date = .now) throws -> URL {
        clear()
        let package=folder.appendingPathComponent("\(UUID().uuidString).\(JournalArchive.fileExtension)", isDirectory: true)
        do { try JournalArchive.write(container, to: package, now: now) } catch { clear(); throw error }
        return package
    }
    static func clear() { try? FileManager.default.removeItem(at: folder) }
}
/// A package gathered on disk (`JournalExport`) as a document for `fileExporter`. Its files are
/// read only as the exporter copies them, so the photos never gather in memory.
nonisolated struct JournalDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.nyxJournal] }
    let package: URL
    init(package: URL) { self.package=package }
    /// Nyx never opens a journal as a document: an import reads it through `JournalImport`.
    init(configuration: ReadConfiguration) throws { throw CocoaError(.featureUnsupported) }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { try FileWrapper(url: package, options: []) }
}
