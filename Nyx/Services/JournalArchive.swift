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
nonisolated struct JournalArchive: Sendable, Equatable {
    static let fileExtension="nyxjournal"
    static let format=1
    nonisolated struct Photo: Codable, Sendable, Equatable { let file: String; let altText: String? }
    nonisolated struct Entry: Codable, Sendable, Equatable {
        let id: UUID
        let date: Date
        let parkID: String
        let observedBortle: Int
        let notes: String
        let photos: [Photo]
    }
    nonisolated struct Manifest: Codable, Sendable, Equatable {
        let format: Int
        let exported: Date
        let entries: [Entry]
    }
    nonisolated enum ArchiveError: Error { case unreadable, newerFormat }
    var manifest: Manifest
    /// Photo data by file name.
    var photos: [String: Data]

    /// Reads every photo's data, so the journal view calls it from a background `ModelContext`.
    static func make(from entries: [JournalEntry], now: Date = .now) -> JournalArchive {
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
        return JournalArchive(manifest: Manifest(format: format, exported: second(now), entries: items), photos: photos)
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
    /// Thumbnails not supplied are drawn here.
    @MainActor func merge(into context: ModelContext, thumbnails: [UUID: Data]?=nil) throws -> (added: Int, skipped: Int) {
        let existing=try context.fetch(FetchDescriptor<JournalEntry>())
        var ids=Set(existing.map(\.id))
        let same=Set(existing.map { Sameness($0.parkID, $0.date, $0.notes) })
        var added=0, skipped=0
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
    /// Removes every journal in the Inbox except `keeping` (one still waiting for the Journal tab).
    /// Runs when Nyx leaves the screen, after any opened file has been handed to the app, so it
    /// needs no file dates (no required-reason file timestamp API).
    static func sweep(folder: URL?=folder, keeping: URL?=nil) {
        guard let folder, let items=try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return }
        let kept=keeping.map { $0.standardizedFileURL.resolvingSymlinksInPath().path }
        for item in items where item.pathExtension.lowercased() == JournalArchive.fileExtension {
            guard item.standardizedFileURL.resolvingSymlinksInPath().path != kept else { continue }
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
