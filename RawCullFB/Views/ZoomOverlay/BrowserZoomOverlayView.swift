import SwiftUI

struct BrowserZoomOverlayView: View {
    @Bindable var viewModel: FileBrowserViewModel

    @State private var lastScale: CGFloat = 1.0
    @State private var lastOffset: CGSize = .zero
    @State private var lastMetadataOffset: CGSize = .zero
    @FocusState private var isFocused: Bool

    @State private var keyMonitor: Any?
    @State private var pendingInitialZoomMode: BrowserZoomInitialMode?
    @State private var viewportSize: CGSize = .zero

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

                        if viewModel.settings.enableRatingPins,
                           let rating = viewModel.rating(for: viewModel.selectedFile) {
                            ZoomImageRatingBadge(
                                rating: rating,
                                imageSize: CGSize(width: image.width, height: image.height),
                                containerSize: geometry.size,
                            )
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .scaleEffect(viewModel.zoomScale)
                    .offset(viewModel.zoomOffset)
                    .gesture(zoomPanGesture)
                    .onAppear {
                        viewportSize = geometry.size
                        applyPendingInitialZoomIfNeeded(
                            imageSize: CGSize(width: image.width, height: image.height),
                            viewportSize: geometry.size,
                        )
                    }
                    .onChange(of: geometry.size) { _, size in
                        viewportSize = size
                        applyPendingInitialZoomIfNeeded(
                            imageSize: CGSize(width: image.width, height: image.height),
                            viewportSize: size,
                        )
                    }
                    .onChange(of: viewModel.zoomImage?.hashValue) { _, _ in
                        applyPendingInitialZoomIfNeeded(
                            imageSize: CGSize(width: image.width, height: image.height),
                            viewportSize: geometry.size,
                        )
                    }
                    .onChange(of: viewModel.zoomExifInfo?.focusPoint) { _, _ in
                        applyPendingInitialZoomIfNeeded(
                            imageSize: CGSize(width: image.width, height: image.height),
                            viewportSize: geometry.size,
                        )
                    }
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
                ZStack(alignment: .top) {
                    ZoomMetadataPanel(
                        fileName: viewModel.selectedFile?.name,
                        exifInfo: viewModel.zoomExifInfo,
                        image: viewModel.zoomImage,
                        isCollapsed: $viewModel.isZoomMetadataCollapsed,
                    )
                    .offset(viewModel.zoomMetadataOffset)
                    .gesture(metadataDragGesture)
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                    HStack(spacing: 12) {
                        Button {
                            viewModel.navigateSelection(by: -1)
                        } label: {
                            Image(systemName: "chevron.left.circle")
                        }
                        .help("Previous image")

                        Button {
                            viewModel.navigateSelection(by: 1)
                        } label: {
                            Image(systemName: "chevron.right.circle")
                        }
                        .help("Next image")

                        Button {
                            close()
                        } label: {
                            Image(systemName: "xmark.circle")
                        }
                        .help("Close")
                    }
                    .font(.title2)
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .topTrailing)
                }
                .padding()

                Spacer()

                HStack(spacing: 48) {
                    zoomControlRow
                    if viewModel.settings.enableRatingPins {
                        ZoomRatingBadgeRow(
                            selectedRating: viewModel.rating(for: viewModel.selectedFile),
                            applyRating: { rating in
                                _ = viewModel.updateSelectedFilesRatingAndAdvance(rating)
                            },
                        )
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 18)
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
        .onKeyPress(.leftArrow) {
            handleKeyAction(ZoomOverlayKeyAction.resolve(
                characters: nil,
                keyCode: 123,
                navigationAxis: viewModel.zoomOverlayNavigationAxis,
            ))
        }
        .onKeyPress(.rightArrow) {
            handleKeyAction(ZoomOverlayKeyAction.resolve(
                characters: nil,
                keyCode: 124,
                navigationAxis: viewModel.zoomOverlayNavigationAxis,
            ))
        }
        .onKeyPress(.upArrow) {
            handleKeyAction(ZoomOverlayKeyAction.resolve(
                characters: nil,
                keyCode: 126,
                navigationAxis: viewModel.zoomOverlayNavigationAxis,
            ))
        }
        .onKeyPress(.downArrow) {
            handleKeyAction(ZoomOverlayKeyAction.resolve(
                characters: nil,
                keyCode: 125,
                navigationAxis: viewModel.zoomOverlayNavigationAxis,
            ))
        }
        .onKeyPress(.escape) {
            dismiss()
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "+-jJrRfFaAzZxXpP012345tT")) { press in
            handleKeyAction(ZoomOverlayKeyAction.resolve(
                characters: press.characters,
                keyCode: 0,
                navigationAxis: viewModel.zoomOverlayNavigationAxis,
            ))
        }
        .onAppear {
            pendingInitialZoomMode = viewModel.zoomLaunchContext.initialZoomMode
            installKeyMonitor()
        }
        .onDisappear {
            removeKeyMonitor()
        }
    }

    private var zoomControlRow: some View {
        HStack(spacing: 12) {
            Button { decreaseZoom() } label: {
                ZoomControlBadge {
                    Image(systemName: "minus.magnifyingglass")
                }
            }
            Button { withAnimation(.spring()) { resetToFit() } } label: {
                ZoomControlBadge {
                    Image(systemName: "1.magnifyingglass")
                }
            }
            Button { increaseZoom() } label: {
                ZoomControlBadge {
                    Image(systemName: "plus.magnifyingglass")
                }
            }
            Toggle(isOn: $viewModel.isZoomFocusPointVisible) {
                ZoomControlBadge(width: 62) {
                    HStack(spacing: 6) {
                        Image(systemName: viewModel.isZoomFocusPointVisible ? "dot.circle.viewfinder" : "dot.viewfinder")
                            .foregroundStyle(viewModel.isZoomFocusPointVisible ? .yellow : .primary)
                            .symbolEffect(.bounce, value: viewModel.isZoomFocusPointVisible)

                        Text("A")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                }
            }
            .toggleStyle(.button)
            .disabled(viewModel.zoomExifInfo?.focusPoint == nil)
            .accessibilityLabel("Focus Point")
            .help(viewModel.zoomExifInfo?.focusPoint == nil ? "No focus point found in EXIF data" : "Show focus point")
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

    private func toggleFocusPoint() {
        guard viewModel.zoomExifInfo?.focusPoint != nil else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            viewModel.isZoomFocusPointVisible.toggle()
        }
    }

    private func toggleExifData() {
        withAnimation(.snappy) {
            viewModel.isZoomMetadataCollapsed.toggle()
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

    private func inspectActualPixels() {
        viewModel.zoomLaunchContext = BrowserZoomLaunchContext(
            initialZoomMode: .actualPixels,
            showFocusPointOnOpen: true,
        )
        pendingInitialZoomMode = .actualPixels

        guard let image = viewModel.zoomImage,
              viewportSize.width > 0,
              viewportSize.height > 0
        else { return }
        applyActualPixelsZoom(
            imageSize: CGSize(width: image.width, height: image.height),
            viewportSize: viewportSize,
        )
        pendingInitialZoomMode = nil
    }

    private func applyPendingInitialZoomIfNeeded(imageSize: CGSize, viewportSize: CGSize) {
        guard pendingInitialZoomMode == .actualPixels,
              viewportSize.width > 0,
              viewportSize.height > 0
        else { return }
        if viewModel.zoomLaunchContext.showFocusPointOnOpen,
           !viewModel.isZoomExifInfoLoaded {
            return
        }
        applyActualPixelsZoom(imageSize: imageSize, viewportSize: viewportSize)
        pendingInitialZoomMode = nil
    }

    private func applyActualPixelsZoom(imageSize: CGSize, viewportSize: CGSize) {
        let transform = BrowserZoomViewportMath.actualPixelsTransform(
            imageSize: imageSize,
            viewportSize: viewportSize,
            normalizedFocusPoint: normalizedFocusPoint,
        )
        viewModel.zoomScale = transform.scale
        lastScale = transform.scale
        viewModel.zoomOffset = transform.offset
        lastOffset = transform.offset
        viewModel.isZoomFocusPointVisible = viewModel.zoomExifInfo?.focusPoint != nil
    }

    private var normalizedFocusPoint: CGPoint? {
        guard let focusPoint = viewModel.zoomExifInfo?.focusPoint else { return nil }
        return CGPoint(x: CGFloat(focusPoint.normalizedX), y: CGFloat(focusPoint.normalizedY))
    }

    private func close() {
        viewModel.closeZoom()
    }

    private func handleKeyAction(_ action: ZoomOverlayKeyAction?) -> KeyPress.Result {
        guard let action else { return .ignored }

        switch action {
        case .navigatePrevious:
            viewModel.navigateSelection(by: -1)
            return .handled

        case .navigateNext:
            viewModel.navigateSelection(by: 1)
            return .handled

        case .escape:
            dismiss()
            return .handled

        case .zoomIn:
            increaseZoom()
            return .handled

        case .zoomOut:
            decreaseZoom()
            return .handled

        case .toggleFocusPoints:
            toggleFocusPoint()
            return .handled

        case .inspectActualPixels:
            inspectActualPixels()
            return .handled

        case let .rating(rating):
            return applyRating(rating)
        }
    }

    private func applyRating(_ rating: Int) -> KeyPress.Result {
        guard viewModel.settings.enableRatingPins else { return .ignored }
        return viewModel.updateSelectedFilesRatingAndAdvance(rating) ? .handled : .ignored
    }

    private func dismiss() {
        viewModel.closeZoom()
        resetToFit()
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard viewModel.zoomOverlayVisible,
                  event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                  !(NSApp.keyWindow?.firstResponder is NSText) else { return event }

            return handleKeyEvent(event) == .handled ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func handleKeyEvent(_ event: NSEvent) -> KeyPress.Result {
        handleKeyAction(ZoomOverlayKeyAction.resolve(
            characters: event.characters,
            keyCode: event.keyCode,
            navigationAxis: viewModel.zoomOverlayNavigationAxis,
        ))
    }
}
