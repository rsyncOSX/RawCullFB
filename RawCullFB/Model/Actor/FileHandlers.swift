import Foundation

struct FileHandlers {
    let memorypressurewarning: @MainActor @Sendable (Bool) -> Void
}
