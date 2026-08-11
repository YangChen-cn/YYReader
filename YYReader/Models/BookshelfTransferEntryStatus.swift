enum BookshelfTransferEntryStatus: Equatable, Sendable {
    case new
    case existing
    case duplicateInFile
    case invalid
}
