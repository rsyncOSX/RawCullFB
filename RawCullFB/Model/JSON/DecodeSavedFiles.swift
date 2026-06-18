//
//  DecodeSavedFiles.swift
//  RawCull
//
//  Created by Thomas Evensen on 27/01/2026.
//

import Foundation
import RawCullCore

struct DecodeSavedFiles: Codable {
    let catalog: URL?
    let dateStart: String?
    var filerecords: [DecodeFileRecord]?

    enum CodingKeys: String, CodingKey {
        case catalog
        case dateStart
        case filerecords
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        catalog = try values.decodeIfPresent(URL.self, forKey: .catalog)
        dateStart = try values.decodeIfPresent(String.self, forKey: .dateStart)
        filerecords = try values.decodeIfPresent([DecodeFileRecord].self, forKey: .filerecords)
    }
}

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
