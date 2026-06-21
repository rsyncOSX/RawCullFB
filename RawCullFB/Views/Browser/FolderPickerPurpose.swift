import Foundation

enum FolderPickerPurpose: Equatable {
    case addRootFolder
    case copyRated(RatedCopyFilter)
}
