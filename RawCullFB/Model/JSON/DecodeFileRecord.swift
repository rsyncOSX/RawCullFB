import Foundation

struct DecodeFileRecord: Codable {
    var fileName: String?
    var dateTagged: String?
    var rating: Int?

    enum CodingKeys: String, CodingKey {
        case fileName
        case dateTagged
        case rating
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        fileName = try values.decodeIfPresent(String.self, forKey: .fileName)
        dateTagged = try values.decodeIfPresent(String.self, forKey: .dateTagged)
        rating = try values.decodeIfPresent(Int.self, forKey: .rating)
    }

    init() {
        fileName = nil
        dateTagged = nil
        rating = nil
    }
}
