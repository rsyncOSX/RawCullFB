// Copyright 2026 Apple Inc.
//
// Derived from apple/coreai-models, licensed under the BSD 3-Clause License.

import Foundation

public struct CoreAIClipTokenizer: Sendable {
    public let encoder: [String: Int32]
    private let decoder: [Int32: String]
    private struct MergePair: Hashable {
        let left: String
        let right: String
    }

    private let bpeRanks: [MergePair: Int]

    public static let sotTokenId: Int32 = 49406
    public static let eotTokenId: Int32 = 49407

    static let byteEncoder: [Int: String] = {
        var bytes =
            Array(Int(("!").utf8.first!)...Int(("~").utf8.first!))
            + Array(0xA1...0xAC)
            + Array(0xAE...0xFF)
        var scalars = bytes
        var nextScalar = 0
        for byte in 0..<256 where !bytes.contains(byte) {
            bytes.append(byte)
            scalars.append(256 + nextScalar)
            nextScalar += 1
        }

        return Dictionary(uniqueKeysWithValues: zip(bytes, scalars).compactMap { byte, scalar in
            Unicode.Scalar(scalar).map { (byte, String($0)) }
        })
    }()

    private struct TokenizerJSON: Decodable {
        let model: Model

        struct Model: Decodable {
            let vocab: [String: Int32]
            let merges: [[String]]
        }
    }

    public init(folder: URL) throws {
        let data = try Data(contentsOf: folder.appendingPathComponent("tokenizer.json"))
        let parsed = try JSONDecoder().decode(TokenizerJSON.self, from: data)
        try self.init(
            vocab: parsed.model.vocab,
            merges: parsed.model.merges.compactMap { pair in
                guard pair.count == 2 else { return nil }
                return (pair[0], pair[1])
            }
        )
    }

    public init(vocab: [String: Int32], merges: [(String, String)]) throws {
        encoder = vocab
        decoder = Dictionary(uniqueKeysWithValues: vocab.map { ($1, $0) })

        var ranks: [MergePair: Int] = [:]
        ranks.reserveCapacity(merges.count)
        for (index, merge) in merges.enumerated() {
            ranks[MergePair(left: merge.0, right: merge.1)] = index
        }
        bpeRanks = ranks
    }

    public func encode(_ text: String, contextLength: Int = 77) -> [Int32] {
        let cleaned = whitespaceClean(text).lowercased()
        let wordTokens = tokenize(cleaned)

        var ids: [Int32] = [Self.sotTokenId]
        ids += wordTokens.compactMap { encoder[$0] }
        ids.append(Self.eotTokenId)

        if ids.count > contextLength {
            ids = Array(ids.prefix(contextLength))
            ids[contextLength - 1] = Self.eotTokenId
        }
        while ids.count < contextLength {
            ids.append(Self.eotTokenId)
        }
        return ids
    }

    private func tokenize(_ text: String) -> [String] {
        splitTokens(text).flatMap { token in
            let byteEncoded = token.utf8.compactMap { Self.byteEncoder[Int($0)] }.joined()
            return bpe(byteEncoded).components(separatedBy: " ")
        }
    }

    private func splitTokens(_ text: String) -> [String] {
        let contractionSuffixes = ["'s", "'t", "'re", "'ve", "'m", "'ll", "'d"]
        var tokens: [String] = []
        var current = text.startIndex
        while current < text.endIndex {
            if let suffix = contractionSuffixes.first(where: { text[current...].hasPrefix($0) }) {
                tokens.append(suffix)
                current = text.index(current, offsetBy: suffix.count)
                continue
            }

            let character = text[current]
            if character.isLetter {
                var end = text.index(after: current)
                while end < text.endIndex && text[end].isLetter {
                    end = text.index(after: end)
                }
                tokens.append(String(text[current..<end]))
                current = end
            } else if character.isNumber {
                tokens.append(String(character))
                current = text.index(after: current)
            } else if character.isWhitespace {
                current = text.index(after: current)
            } else {
                var end = text.index(after: current)
                while end < text.endIndex && !text[end].isWhitespace && !text[end].isLetter
                    && !text[end].isNumber
                {
                    end = text.index(after: end)
                }
                tokens.append(String(text[current..<end]))
                current = end
            }
        }
        return tokens
    }

    private func bpe(_ token: String) -> String {
        var characters = token.map(String.init)
        guard !characters.isEmpty else { return token }
        characters[characters.count - 1] += "</w>"
        guard characters.count > 1 else { return characters[0] }

        var word = characters
        while word.count > 1 {
            var bestRank = Int.max
            var bestIndex = -1
            for index in 0..<(word.count - 1) {
                if let rank = bpeRanks[MergePair(left: word[index], right: word[index + 1])],
                   rank < bestRank
                {
                    bestRank = rank
                    bestIndex = index
                }
            }
            guard bestIndex >= 0 else { break }

            let left = word[bestIndex]
            let right = word[bestIndex + 1]
            var merged: [String] = []
            var index = 0
            while index < word.count {
                if index < word.count - 1 && word[index] == left && word[index + 1] == right {
                    merged.append(left + right)
                    index += 2
                } else {
                    merged.append(word[index])
                    index += 1
                }
            }
            word = merged
        }
        return word.joined(separator: " ")
    }

    private func whitespaceClean(_ text: String) -> String {
        text.components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}

/// Compatibility spelling for CoreAI's tokenizer type before it became internal.
public typealias CLIPTokenizer = CoreAIClipTokenizer
