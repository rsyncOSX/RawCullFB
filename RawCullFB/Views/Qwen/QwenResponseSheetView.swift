import SwiftUI

struct QwenResponseSheetView: View {
    let prompt: String
    let response: String
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Qwen Response")
                .font(.title2.weight(.semibold))

            QwenResponseContent(prompt: prompt, response: response)

            HStack {
                Spacer()
                Button("Done", action: onClose)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 560, idealWidth: 680, minHeight: 360, idealHeight: 480)
    }
}

private struct QwenResponseContent: View {
    let prompt: String
    let response: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Prompt")
                    .font(.headline)
                Text(prompt)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                Divider()

                Text("Response")
                    .font(.headline)
                Text(response)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
