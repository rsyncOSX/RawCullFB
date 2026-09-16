import Foundation
import PhotoAIContracts
@testable import RawCullFB
import Testing

@Suite("Deep Review enhancements")
struct DeepAIReviewEnhancementTests {
    @Test(
        "Scope selects the expected candidates",
        arguments: [
            (DeepAIReviewScope.fast, Array(1 ... 8)),
            (DeepAIReviewScope.automatic, Array(4 ... 15)),
            (DeepAIReviewScope.full, Array(1 ... 15)),
        ],
    )
    func scopeSelection(scope: DeepAIReviewScope, expectedRanks: [Int]) {
        let candidates = (1 ... 15).map { makeCandidate(rank: $0) }

        let selected = RawCullDeepAIReviewPipeline.selectedCandidates(
            from: candidates,
            scope: scope,
        )

        #expect(selected.map(\.burstRank) == expectedRanks)
    }

    @Test(
        "Subject labels choose a specific SAM prompt",
        arguments: [
            ("person", SubjectSegmentationPrompt.face),
            ("bird", SubjectSegmentationPrompt.birdHead),
            ("deer", SubjectSegmentationPrompt.animalHead),
            ("car", SubjectSegmentationPrompt.subject),
        ],
    )
    func subjectPrompt(label: String, expectedPrompt: SubjectSegmentationPrompt) {
        let prompts = RawCullDeepAIReviewPipeline.promptAttempts(
            preset: .auto,
            subjectLabel: label,
        )

        #expect(prompts.first == expectedPrompt)
    }

    private func makeCandidate(rank: Int) -> DeepAIReviewInputCandidate {
        DeepAIReviewInputCandidate(
            fileID: UUID(),
            fileName: "photo-\(rank).jpg",
            url: URL(filePath: "/tmp/photo-\(rank).jpg"),
            burstRank: rank,
            normalSharpnessScore: Float(rank),
            subjectLabel: nil,
            normalizedAFPoint: nil,
        )
    }
}
