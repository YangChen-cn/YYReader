import Foundation

struct ContinuousReaderVisibilityGate {
    private(set) var hasCommittedInCurrentTransaction = false

    mutating func beginTransaction() {
        hasCommittedInCurrentTransaction = false
    }

    func accepts(
        candidateID: UUID,
        currentID: UUID?,
        orderedChapterIDs: [UUID]
    ) -> Bool {
        guard !hasCommittedInCurrentTransaction,
              let currentID,
              candidateID != currentID,
              let currentIndex = orderedChapterIDs.firstIndex(of: currentID),
              let candidateIndex = orderedChapterIDs.firstIndex(of: candidateID) else {
            return false
        }
        return abs(candidateIndex - currentIndex) == 1
    }

    mutating func recordCommit() {
        hasCommittedInCurrentTransaction = true
    }
}
