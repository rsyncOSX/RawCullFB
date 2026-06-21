import Foundation

struct CreateFileHandlers {
    func createFileHandlers(
        memorypressurewarning: @escaping @MainActor @Sendable (Bool) -> Void,
    ) -> FileHandlers {
        FileHandlers(
            memorypressurewarning: memorypressurewarning,
        )
    }
}
