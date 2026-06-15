import SwiftUI

struct BrowserZoomOverlayView: View {
    @Bindable var viewModel: FileBrowserViewModel

    @State private var currentScale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.98)
                .ignoresSafeArea()

            GeometryReader { geometry in
                if let image = viewModel.zoomImage {
                    Image(decorative: image, scale: 1.0, orientation: .up)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .scaleEffect(currentScale)
                        .offset(offset)
                        .gesture(zoomPanGesture)
                        .onTapGesture(count: 2) {
                            withAnimation(.spring()) {
                                currentScale > 1.0 ? resetToFit() : zoomToTwoX()
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
                    if let file = viewModel.selectedFile {
                        Text(file.name)
                            .font(.headline)
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.regularMaterial, in: Capsule())
                    }

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
        .onAppear { isFocused = true }
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
        .onChange(of: viewModel.selectedFileID) { _, _ in
            resetToFit()
        }
    }

    private var zoomPanGesture: some Gesture {
        SimultaneousGesture(
            MagnifyGesture()
                .onChanged { value in
                    currentScale = min(max(lastScale * value.magnification, 0.5), 5.0)
                }
                .onEnded { _ in
                    lastScale = currentScale
                    if currentScale < 1.0 {
                        withAnimation(.spring()) { resetToFit() }
                    }
                },
            DragGesture()
                .onChanged { value in
                    guard currentScale > 1.0 else { return }
                    offset = CGSize(
                        width: lastOffset.width + value.translation.width,
                        height: lastOffset.height + value.translation.height,
                    )
                }
                .onEnded { _ in
                    lastOffset = offset
                },
        )
    }

    private func increaseZoom() {
        withAnimation(.spring()) {
            currentScale = min(currentScale + 0.25, 5.0)
            lastScale = currentScale
        }
    }

    private func decreaseZoom() {
        withAnimation(.spring()) {
            currentScale = max(currentScale - 0.25, 0.5)
            lastScale = currentScale
            if currentScale <= 1.0 {
                offset = .zero
                lastOffset = .zero
            }
        }
    }

    private func zoomToTwoX() {
        currentScale = 2.0
        lastScale = 2.0
    }

    private func resetToFit() {
        currentScale = 1.0
        lastScale = 1.0
        offset = .zero
        lastOffset = .zero
    }

    private func close() {
        viewModel.closeZoom()
        resetToFit()
    }
}
