import SwiftUI

struct QwenResponseSheetView: View {
    let prompt: String
    let results: [QwenPhotoAnalysisResult]
    let onClose: () -> Void

    @State private var selectedResultID: UUID?

    private var selectedResult: QwenPhotoAnalysisResult? {
        selectedResultID.flatMap { id in results.first { $0.id == id } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Qwen Selection Analysis")
                    .font(.title2.weight(.semibold))
                Spacer()
                Text("\(results.filter { $0.assessment != nil }.count) of \(results.count) analyzed")
                    .foregroundStyle(.secondary)
            }

            Text(prompt)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HSplitView {
                Table(results, selection: $selectedResultID) {
                    TableColumn("File") { result in
                        Text(result.fileName).lineLimit(1)
                    }
                    TableColumn("Overall") { result in
                        Text(score(result.assessment?.overallScore)).monospacedDigit()
                    }
                    TableColumn("Composition") { result in
                        Text(rating(result.assessment?.compositionScore))
                    }
                    TableColumn("Exposure") { result in
                        Text(rating(result.assessment?.exposureScore))
                    }
                    TableColumn("Visibility") { result in
                        Text(rating(result.assessment?.subjectVisibilityScore))
                    }
                    TableColumn("Status") { result in
                        Text(result.failure == nil ? "Complete" : "Failed")
                            .foregroundStyle(result.failure == nil ? Color.green : Color.orange)
                    }
                }
                .frame(minWidth: 700)

                QwenAssessmentDetail(result: selectedResult)
                    .frame(minWidth: 300, idealWidth: 380)
            }

            HStack {
                Spacer()
                Button("Done", action: onClose)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 1080, idealWidth: 1200, minHeight: 520, idealHeight: 640)
        .task(id: results.map(\.id)) {
            if selectedResultID.map({ id in results.contains { $0.id == id } }) != true {
                selectedResultID = results.first?.id
            }
        }
    }

    private func score(_ value: Double?) -> String {
        value?.formatted(.number.precision(.fractionLength(2))) ?? "—"
    }

    private func rating(_ value: Int?) -> String {
        value.map { "\($0)/5" } ?? "—"
    }
}

private struct QwenAssessmentDetail: View {
    let result: QwenPhotoAnalysisResult?

    var body: some View {
        ScrollView {
            if let result, let assessment = result.assessment {
                VStack(alignment: .leading, spacing: 12) {
                    Text(result.fileName).font(.headline)
                    LabeledContent("Subject", value: assessment.subject)
                    LabeledContent(
                        "Confidence",
                        value: assessment.confidence.formatted(.percent.precision(.fractionLength(0))),
                    )
                    if let eyesOpen = assessment.eyesOpen {
                        LabeledContent("Eyes", value: eyesOpen ? "Open" : "Closed")
                    }
                    Divider()
                    detailSection("Strengths", values: assessment.strengths)
                    detailSection("Problems", values: assessment.problems)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            } else if let failure = result?.failure {
                ContentUnavailableView(
                    "Analysis Failed",
                    systemImage: "exclamationmark.triangle",
                    description: Text(failure),
                )
            } else {
                ContentUnavailableView("Select a Photo", systemImage: "photo")
            }
        }
    }

    @ViewBuilder
    private func detailSection(_ title: LocalizedStringKey, values: [String]) -> some View {
        Text(title).font(.headline)
        if values.isEmpty {
            Text("None reported").foregroundStyle(.secondary)
        } else {
            ForEach(values, id: \.self) { Text("• \($0)") }
        }
    }
}
