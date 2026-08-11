import Foundation

struct ContinuousReaderVisibilityGate {
    private(set) var hasCommittedInCurrentTransaction = false

    mutating func beginTransaction() {
        hasCommittedInCurrentTransaction = false
    }

    func accepts(
        candidateID: UUID,
        currentID: UUID?,
        chapterIndexByID: [UUID: Int]
    ) -> Bool {
        guard !hasCommittedInCurrentTransaction,
              let currentID,
              candidateID != currentID,
              let currentIndex = chapterIndexByID[currentID],
              let candidateIndex = chapterIndexByID[candidateID] else {
            return false
        }
        return abs(candidateIndex - currentIndex) == 1
    }

    mutating func recordCommit() {
        hasCommittedInCurrentTransaction = true
    }
}
