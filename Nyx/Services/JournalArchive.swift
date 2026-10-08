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
/// present (same id, or the same park on the same night) is never duplicated.
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
            if let first=item.photos.lazy.compactMap({ photos[$0.file] }).first, let thumbnail=PhotoScaling.jpeg(first, maxPixels: 900) { thumbnails[item.id]=thumbnail }
        }
        return thumbnails
    }
    /// Adds the entries the journal does not have yet and returns how many were added and how many
    /// were already there. Nothing existing is changed. Thumbnails not supplied are drawn here.
    @MainActor func merge(into context: ModelContext, parks: [Park], thumbnails: [UUID: Data]?=nil) throws -> (added: Int, skipped: Int) {
        let existing=try context.fetch(FetchDescriptor<JournalEntry>())
        func night(_ parkID: String, _ date: Date) -> String {
            let park=parks.first { $0.id == parkID }
            return parkID+"|"+(park?.isoDay(date) ?? TripDay(date).iso)
        }
        var ids=Set(existing.map(\.id)), nights=Set(existing.map { night($0.parkID, $0.date) })
        var added=0, skipped=0
        for item in manifest.entries {
            let key=night(item.parkID, item.date)
            guard !ids.contains(item.id), !nights.contains(key) else { skipped+=1; continue }
            let entry=JournalEntry(date: item.date, parkID: item.parkID, observedBortle: min(9, max(1, item.observedBortle)), notes: item.notes)
            entry.id=item.id
            context.insert(entry)
            let kept=item.photos.compactMap { photo in photos[photo.file].map { (photo, $0) } }
            for (index, (photo, data)) in kept.enumerated() {
                let record=JournalPhoto(index: index, data: data, altText: photo.altText)
                context.insert(record)
                record.entry=entry
            }
            entry.thumbnail=thumbnails.map { $0[item.id] } ?? kept.first.flatMap { PhotoScaling.jpeg($0.1, maxPixels: 900) }
            ids.insert(item.id); nights.insert(key); added+=1
        }
        try context.save()
        return (added, skipped)
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
