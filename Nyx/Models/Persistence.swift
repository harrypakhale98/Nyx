import Foundation
import SwiftData

@Model final class SavedPark {
    @Attribute(.unique) var parkID: String
    var savedAt: Date
    init(parkID: String) { self.parkID=parkID; savedAt = .now }
}
@Model final class JournalEntry {
    var id: UUID
    var date: Date
    var parkID: String
    var observedBortle: Int
    var notes: String
    @Attribute(.externalStorage) var photos: [Data]
    init(date: Date, parkID: String, observedBortle: Int = 3, notes: String = "", photos: [Data] = []) {
        id=UUID(); self.date=date; self.parkID=parkID; self.observedBortle=observedBortle; self.notes=notes; self.photos=photos
    }
}
