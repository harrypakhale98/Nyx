import AppIntents
import CoreLocation
import Foundation
import GeoToolbox
import SwiftData
import UniformTypeIdentifiers

/// The journal for Siri and Shortcuts: "Add to my Nyx journal" asks what to remember and saves
/// it without lighting the screen, so eyes stay dark-adapted. Entries stay in Nyx's own store on
/// this device; nothing is sent anywhere. Each entry belongs to tonight's park (field mode or a
/// followed night, else the starting park).
///
/// Not the system journal schema (`.journal.entry` / `.journal.createEntry`): it requires a
/// `PlaceDescriptor` location, and that type fails App Shortcuts' Siri phrase training in Release
/// archives with Xcode 27, which stops the archive. Plain App Intents keep the voice path.
struct JournalEntryEntity: AppEntity {
    /// The store does the filtering: only the entries asked for are read, and their photos only
    /// when an entry itself is requested by id, never for a list or a search.
    struct Query: EntityStringQuery {
        func entities(for identifiers: [UUID]) async throws -> [JournalEntryEntity] {
            try await JournalAccess.entities(FetchDescriptor<JournalEntry>(predicate: #Predicate { identifiers.contains($0.id) }), photos: true)
        }
        func entities(matching string: String) async throws -> [JournalEntryEntity] { try await JournalAccess.entities(matching: string) }
        func suggestedEntities() async throws -> [JournalEntryEntity] {
            var recent=FetchDescriptor<JournalEntry>()
            recent.fetchLimit=5
            return try await JournalAccess.entities(recent)
        }
    }
    static let defaultQuery=Query()
    static let typeDisplayRepresentation=TypeDisplayRepresentation(name: "Journal entry")
    let id: UUID
    var title: String?
    var message: AttributedString?
    var mediaItems: [IntentFile]
    var entryDate: Date?
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title ?? String(localized: "Journal entry"))",
                              subtitle: entryDate.map { "\($0.formatted(date: .abbreviated, time: .omitted))" })
    }
}
extension JournalEntryEntity {
    /// `photos` reads every photo's file; lists and searches leave it off.
    @MainActor init(_ entry: JournalEntry, photos: Bool) {
        let park=JournalAccess.park(entry.parkID)
        id=entry.id
        title=park?.shortName
        message=entry.notes.isEmpty ? nil : AttributedString(entry.notes)
        mediaItems=photos ? entry.orderedPhotos.enumerated().map { IntentFile(data: $1.data, filename: "night-\($0+1).jpg", type: .jpeg) } : []
        entryDate=entry.date
    }
}

/// "Add to my Nyx journal": a new entry at the park of tonight's followed night or field mode,
/// else the starting park, with the park's estimated Bortle class as the observed default (the
/// editor's default too). Photos are kept as the editor keeps them: images only, up to four, each
/// within the editor's size limit, as JPEG; anything that cannot be read as a photo is left out.
struct AddJournalEntryIntent: AppIntent {
    static let title: LocalizedStringResource="Add to journal"
    static let description=IntentDescription("Adds a note about tonight to your Nyx journal, at tonight's park.")
    @Parameter(title: "Note", requestValueDialog: "What would you like to remember about tonight?")
    var message: String
    @Parameter(title: "Title")
    var title: String?
    @Parameter(title: "Date")
    var entryDate: Date?
    @Parameter(title: "Photos", supportedContentTypes: [.image])
    var mediaItems: [IntentFile]?
    func perform() async throws -> some ReturnsValue<JournalEntryEntity> {
        let entry=try await JournalAccess.add(title: title, message: message, date: entryDate ?? .now, location: nil, files: mediaItems ?? [])
        return .result(value: entry)
    }
}

/// The journal's store for intents, which may run before any window has opened it.
@MainActor enum JournalAccess {
    /// Set by the app as it opens the store, so intents and windows share one container.
    private(set) static var container: ModelContainer?
    /// The store on disk could not be opened, so `container` is only a stand-in in memory that is
    /// gone on the next launch. Intents then say so plainly instead of seeming to save.
    private(set) static var unavailable=false
    static func configure(container: ModelContainer?, unavailable: Bool) {
        self.container=container; self.unavailable=unavailable
    }
    /// The journal's store on disk, opened here when an intent runs before any window has opened it.
    static func store() throws -> ModelContainer {
        if container == nil, !unavailable {
            let opened=JournalStore.open(inMemory: false)
            configure(container: opened.container, unavailable: opened.failed)
        }
        guard !unavailable, let container else { throw NyxIntentError.journalUnavailable }
        return container
    }
    nonisolated static func park(_ id: String) -> Park? { (try? ParkData.load())?.first { $0.id == id } }
    /// The park's place for the journal schema: its coordinates and name, nothing looked up.
    nonisolated static func place(_ park: Park) -> PlaceDescriptor {
        PlaceDescriptor(representations: [.coordinate(CLLocationCoordinate2D(latitude: park.latitude, longitude: park.longitude))], commonName: park.name)
    }
    /// The park a spoken entry belongs to: tonight's night in progress (field mode or a followed
    /// night), else a place the person named that is within 50 km of a park, else the starting park.
    static func defaultParkID(location: PlaceDescriptor?, inProgress: String?, home: String?) -> String {
        if let inProgress { return inProgress }
        if let coordinate=location?.coordinate, let parks=try? ParkData.load(),
           let near=parks.min(by: { $0.distanceMeters(latitude: coordinate.latitude, longitude: coordinate.longitude) < $1.distanceMeters(latitude: coordinate.latitude, longitude: coordinate.longitude) }),
           near.distanceMeters(latitude: coordinate.latitude, longitude: coordinate.longitude) < 50_000 { return near.id }
        return home ?? "jotr"
    }
    /// Entries newest first, as the descriptor selects and limits them.
    static func entities(_ descriptor: FetchDescriptor<JournalEntry>, photos: Bool = false) async throws -> [JournalEntryEntity] {
        var descriptor=descriptor
        descriptor.sortBy=[SortDescriptor(\.date, order: .reverse)]
        return try store().mainContext.fetch(descriptor).map { JournalEntryEntity($0, photos: photos) }
    }
    /// Up to 20 entries whose words contain the text (ignoring case and accents), or whose park it names.
    static func entities(matching string: String) async throws -> [JournalEntryEntity] {
        let parkIDs=((try? ParkData.load()) ?? []).filter { $0.matches(string) }.map(\.id)
        var descriptor=FetchDescriptor<JournalEntry>(predicate: #Predicate { parkIDs.contains($0.parkID) || $0.notes.localizedStandardContains(string) })
        descriptor.fetchLimit=20
        return try await entities(descriptor)
    }
    /// A photo from Shortcuts, if it is an image within the editor's size limit (the file's size is
    /// read before its contents), as the editor's JPEG; nil for anything else.
    nonisolated static func keepsake(_ file: IntentFile) -> Data? {
        if let type=file.type, !type.conforms(to: .image) { return nil }
        if let size=file.fileURL.flatMap({ try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }), size>PhotoScaling.maxSourceBytes { return nil }
        let data=file.data
        guard data.count<=PhotoScaling.maxSourceBytes else { return nil }
        return PhotoScaling.jpeg(data, maxPixels: 2400)
    }
    static func add(title: String?, message: String, date: Date, location: PlaceDescriptor?, files: [IntentFile]) async throws -> JournalEntryEntity {
        let store=try store()
        let inProgress=FieldActivities.current?.attributes.parkID
        let parkID=defaultParkID(location: location, inProgress: inProgress, home: UserDefaults.standard.string(forKey: "homePark"))
        let notes=[title, message].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: "\n\n")
        // Read and shrunk off the main thread: a photo can be tens of megabytes.
        let scaled=await Task.detached(priority: .userInitiated) { Array(files.lazy.compactMap(keepsake).prefix(4)) }.value
        let entry=JournalEntry(date: date, parkID: parkID, observedBortle: park(parkID)?.bortleEstimate ?? 3, notes: notes, photos: scaled)
        entry.thumbnail=scaled.first.flatMap { PhotoScaling.jpeg($0, maxPixels: 900) }
        let context=store.mainContext
        context.insert(entry)
        do { try context.save() } catch { context.rollback(); throw NyxIntentError.journalUnavailable }
        return JournalEntryEntity(entry, photos: true)
    }
}
