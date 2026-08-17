import CoreAICLIPBackend
import Foundation
import PhotoAIContracts

nonisolated enum CLIPSimilaritySearch {
    static func results(
        in index: CLIPPersistedIndex,
        anchorURL: URL,
        limit: Int,
    ) throws -> [CLIPSearchResult] {
        let decoder = JSONDecoder()
        let indexed = try index.entries.map { entry in
            let embedding = try decoder.decode(ImageEmbedding.self, from: entry.artifact.payload)
            guard EmbeddingArtifact(
                descriptor: entry.artifact.descriptor,
                embedding: embedding,
            ).isInternallyConsistent else {
                throw CLIPSimilarityArtifactError.invalidPayload(
                    "The vector payload does not match its artifact descriptor.",
                )
            }
            return (entry: entry, embedding: embedding)
        }
        let anchorPath = anchorURL.standardizedFileURL.path
        guard let anchor = indexed.first(where: {
            $0.entry.fingerprint.standardizedPath == anchorPath
        }) else {
            throw CLIPFeatureError.imageNotIndexed(anchorURL.lastPathComponent)
        }

        let scored = indexed.compactMap { candidate -> (CLIPIndexEntry, Float)? in
            guard candidate.entry.fingerprint.standardizedPath != anchorPath,
                  let distance = anchor.embedding.cosineDistance(to: candidate.embedding)
            else { return nil }
            return (candidate.entry, 1 - distance)
        }
        .sorted {
            if $0.1 == $1.1 {
                return $0.0.source.url.path < $1.0.source.url.path
            }
            return $0.1 > $1.1
        }

        return scored.prefix(max(0, limit)).enumerated().map { offset, item in
            CLIPSearchResult(
                rank: offset + 1,
                score: item.1,
                fileName: item.0.source.displayName,
                path: item.0.source.url.path,
            )
        }
    }
}
