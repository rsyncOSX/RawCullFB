import SwiftUI

struct BrowserZoomOverlayView: View {
    @Bindable var viewModel: FileBrowserViewModel

    @State private var lastScale: CGFloat = 1.0
    @State private var lastOffset: CGSize = .zero
    @State private var lastMetadataOffset: CGSize = .zero
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.98)
                .ignoresSafeArea()

            GeometryReader { geometry in
                if let image = viewModel.zoomImage {
                    ZStack {
                        Image(decorative: image, scale: 1.0, orientation: .up)
                            .resizable()
                            .scaledToFit()
                            .frame(width: geometry.size.width, height: geometry.size.height)

                        if viewModel.isZoomFocusPointVisible,
                           let focusPoint = viewModel.zoomExifInfo?.focusPoint {
                            FocusPointMarker(
                                focusPoint: focusPoint,
                                imageSize: CGSize(width: image.width, height: image.height),
                                containerSize: geometry.size,
                            )
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .scaleEffect(viewModel.zoomScale)
                    .offset(viewModel.zoomOffset)
                        .gesture(zoomPanGesture)
                        .onTapGesture(count: 2) {
                            withAnimation(.spring()) {
                                viewModel.zoomScale > 1.0 ? resetToFit() : zoomToTwoX()
                            }
                        }
                } else {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.large)
                        Text("Extracting embedded JPG...")
                            .font(.title3)
                    }
                    .padding(18)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            VStack {
                HStack {
                    ZoomMetadataPanel(
                        fileName: viewModel.selectedFile?.name,
                        exifInfo: viewModel.zoomExifInfo,
                        isCollapsed: $viewModel.isZoomMetadataCollapsed,
                    )
                    .offset(viewModel.zoomMetadataOffset)
                    .gesture(metadataDragGesture)

                    Spacer()

                    Button {
                        viewModel.navigateSelection(by: -1)
                    } label: {
                        Image(systemName: "chevron.left.circle")
                    }
                    .font(.title2)
                    .buttonStyle(.plain)
                    .help("Previous image")

                    Button {
                        viewModel.navigateSelection(by: 1)
                    } label: {
                        Image(systemName: "chevron.right.circle")
                    }
                    .font(.title2)
                    .buttonStyle(.plain)
                    .help("Next image")

                    Button {
                        close()
                    } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .font(.title2)
                    .buttonStyle(.plain)
                    .help("Close")
                }
                .padding()

                Spacer()

                HStack(spacing: 12) {
                    Button { decreaseZoom() } label: { Image(systemName: "minus.magnifyingglass") }
                    Button { withAnimation(.spring()) { resetToFit() } } label: { Image(systemName: "1.magnifyingglass") }
                    Button { increaseZoom() } label: { Image(systemName: "plus.magnifyingglass") }
                    Toggle("Focus Point", isOn: $viewModel.isZoomFocusPointVisible)
                        .toggleStyle(.button)
                        .disabled(viewModel.zoomExifInfo?.focusPoint == nil)
                        .help(viewModel.zoomExifInfo?.focusPoint == nil ? "No focus point found in EXIF data" : "Show focus point")
                }
                .buttonStyle(.bordered)
                .padding(.bottom, 18)
            }

            Button("Close") { close() }
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .frame(width: 0, height: 0)
        }
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled(true)
        .onAppear {
            isFocused = true
            lastScale = viewModel.zoomScale
            lastOffset = viewModel.zoomOffset
            lastMetadataOffset = viewModel.zoomMetadataOffset
        }
        .onKeyPress(.leftArrow) {
            viewModel.navigateSelection(by: -1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            viewModel.navigateSelection(by: 1)
            return .handled
        }
        .onKeyPress(.escape) {
            close()
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "+-")) { press in
            switch press.characters {
            case "+": increaseZoom()
            case "-": decreaseZoom()
            default: break
            }
            return .handled
        }
    }

    private var zoomPanGesture: some Gesture {
        SimultaneousGesture(
            MagnifyGesture()
                .onChanged { value in
                    viewModel.zoomScale = min(max(lastScale * value.magnification, 0.5), 5.0)
                }
                .onEnded { _ in
                    lastScale = viewModel.zoomScale
                    if viewModel.zoomScale < 1.0 {
                        withAnimation(.spring()) { resetToFit() }
                    }
                },
            DragGesture()
                .onChanged { value in
                    guard viewModel.zoomScale > 1.0 else { return }
                    viewModel.zoomOffset = CGSize(
                        width: lastOffset.width + value.translation.width,
                        height: lastOffset.height + value.translation.height,
                    )
                }
                .onEnded { _ in
                    lastOffset = viewModel.zoomOffset
                },
        )
    }

    private var metadataDragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                viewModel.zoomMetadataOffset = CGSize(
                    width: lastMetadataOffset.width + value.translation.width,
                    height: lastMetadataOffset.height + value.translation.height,
                )
            }
            .onEnded { _ in
                lastMetadataOffset = viewModel.zoomMetadataOffset
            }
    }

    private func increaseZoom() {
        withAnimation(.spring()) {
            viewModel.zoomScale = min(viewModel.zoomScale + 0.25, 5.0)
            lastScale = viewModel.zoomScale
        }
    }

    private func decreaseZoom() {
        withAnimation(.spring()) {
            viewModel.zoomScale = max(viewModel.zoomScale - 0.25, 0.5)
            lastScale = viewModel.zoomScale
            if viewModel.zoomScale <= 1.0 {
                viewModel.zoomOffset = .zero
                lastOffset = .zero
            }
        }
    }

    private func zoomToTwoX() {
        viewModel.zoomScale = 2.0
        lastScale = 2.0
    }

    private func resetToFit() {
        viewModel.zoomScale = 1.0
        lastScale = 1.0
        viewModel.zoomOffset = .zero
        lastOffset = .zero
    }

    private func close() {
        viewModel.closeZoom()
    }
}

private struct ZoomMetadataPanel: View {
    let fileName: String?
    let exifInfo: BrowserExifInfo?
    @Binding var isCollapsed: Bool

    private let columns = [
        GridItem(.fixed(86), alignment: .trailing),
        GridItem(.flexible(minimum: 120), alignment: .leading),
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

            if !isCollapsed, let exifInfo, !exifInfo.isEmpty {
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
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: 420, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }
}

private struct FocusPointMarker: View {
    let focusPoint: BrowserFocusPoint
    let imageSize: CGSize
    let containerSize: CGSize

    var body: some View {
        let rect = fittedImageRect(imageSize: imageSize, containerSize: containerSize)
        Circle()
            .stroke(.yellow, lineWidth: 2)
            .frame(width: 28, height: 28)
            .overlay {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.yellow)
            }
            .shadow(color: .black.opacity(0.8), radius: 2)
            .position(
                x: rect.minX + rect.width * focusPoint.normalizedX,
                y: rect.minY + rect.height * focusPoint.normalizedY,
            )
            .accessibilityLabel("Focus point")
    }

    private func fittedImageRect(imageSize: CGSize, containerSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              containerSize.width > 0, containerSize.height > 0
        else { return .zero }

        let scale = min(containerSize.width / imageSize.width, containerSize.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (containerSize.width - size.width) / 2,
            y: (containerSize.height - size.height) / 2,
            width: size.width,
            height: size.height,
        )
    }
}
