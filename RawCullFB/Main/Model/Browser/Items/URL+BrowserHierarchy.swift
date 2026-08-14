import Foundation

extension URL {
    func isEqualOrDescendant(of ancestorURL: URL) -> Bool {
        let pathComponents = standardizedFileURL.pathComponents
        let ancestorPathComponents = ancestorURL.standardizedFileURL.pathComponents

        guard pathComponents.count >= ancestorPathComponents.count else { return false }
        return zip(pathComponents, ancestorPathComponents).allSatisfy(==)
    }
}
