import Foundation

// MARK: - QueueEntry

enum QueueEntrySource: String, Codable, Hashable {
    case current
    case added
    case radio
}

struct QueueEntry: Identifiable, Hashable {
    let id: UUID
    let song: Song
    var source: QueueEntrySource = .added
}

// MARK: - QueueState

struct QueueState {
    let entries: [QueueEntry]
    let currentIndex: Int
}
