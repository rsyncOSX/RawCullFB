import RawParserKit
import SwiftUI

struct ZoomMetadataPanel: View {
    let fileName: String?
    let exifInfo: BrowserExifInfo?
    let image: CGImage?
    @Binding var isCollapsed: Bool

    private let columns = [
        GridItem(.fixed(86), alignment: .trailing),
        GridItem(.flexible(minimum: 120), alignment: .leading)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if let fileName {
                    Text(fileName)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 8)

                Button {
                    withAnimation(.snappy) {
                        isCollapsed.toggle()
                    }
                } label: {
                    Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                }
                .buttonStyle(.plain)
                .help(isCollapsed ? "Expand EXIF data" : "Collapse EXIF data")
            }

            if !isCollapsed {
                if let image {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Histogram")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        BrowserHistogramView(image: image)
                    }
                }

                if let exifInfo, !exifInfo.isEmpty {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 5) {
                        ForEach(exifInfo.rows, id: \.0) { label, value in
                            Text(label)
                                .foregroundStyle(.secondary)
                            Text(value)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .font(.caption)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: 320, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }
}
