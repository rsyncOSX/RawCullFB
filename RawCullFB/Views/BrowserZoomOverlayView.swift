import SwiftUI

enum ZoomOverlayNavigationAxis: Equatable {
    case vertical
    case horizontal
}

nonisolated enum ZoomOverlayKeyAction: Equatable {
    case navigatePrevious
    case navigateNext
    case escape
    case zoomIn
    case zoomOut
    case toggleFocusPoints
    case inspectActualPixels
    case rating(Int)

    nonisolated static func resolve(
        characters: String?,
        keyCode: UInt16,
        navigationAxis: ZoomOverlayNavigationAxis,
    ) -> ZoomOverlayKeyAction? {
        if let action = action(for: characters) {
            return action
        }

        return switch (navigationAxis, keyCode) {
        case (.horizontal, 123), (.vertical, 126):
            .navigatePrevious

        case (.horizontal, 124), (.vertical, 125):
            .navigateNext

        case (_, 53):
            .escape

        default:
            nil
        }
    }

    private nonisolated static func action(for characters: String?) -> ZoomOverlayKeyAction? {
        switch characters {
        case "+":
            .zoomIn

        case "-":
            .zoomOut

        case "a", "A":
            .toggleFocusPoints

        case "z", "Z":
            .inspectActualPixels

        default:
            BrowserRatingShortcut.rating(for: characters).map(ZoomOverlayKeyAction.rating)
        }
    }
}

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

    // ADDED

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

private struct BrowserZoomViewportTransform: Equatable {
    var scale: CGFloat
    var offset: CGSize
}

private enum BrowserZoomViewportMath {
    static func actualPixelsTransform(
        imageSize: CGSize,
        viewportSize: CGSize,
        normalizedFocusPoint: CGPoint?,
    ) -> BrowserZoomViewportTransform {
        let scale = actualPixelsScale(imageSize: imageSize, viewportSize: viewportSize)
        guard let normalizedFocusPoint else {
            return BrowserZoomViewportTransform(scale: scale, offset: .zero)
        }

        let fitRect = fittedImageRect(imageSize: imageSize, containerSize: viewportSize)
        guard fitRect.width > 0, fitRect.height > 0 else {
            return BrowserZoomViewportTransform(scale: scale, offset: .zero)
        }

        let point = CGPoint(
            x: fitRect.minX + normalizedFocusPoint.x * fitRect.width,
            y: fitRect.minY + normalizedFocusPoint.y * fitRect.height,
        )
        let viewportCenter = CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
        let desiredOffset = CGSize(
            width: (viewportCenter.x - point.x) * scale,
            height: (viewportCenter.y - point.y) * scale,
        )
        let scaledImageSize = CGSize(width: fitRect.width * scale, height: fitRect.height * scale)

        return BrowserZoomViewportTransform(
            scale: scale,
            offset: clampedOffset(
                desiredOffset,
                scaledImageSize: scaledImageSize,
                viewportSize: viewportSize,
            ),
        )
    }

    private static func actualPixelsScale(imageSize: CGSize, viewportSize: CGSize) -> CGFloat {
        let fitRect = fittedImageRect(imageSize: imageSize, containerSize: viewportSize)
        guard fitRect.width > 0, fitRect.height > 0 else { return 1.0 }
        let fitScale = min(fitRect.width / imageSize.width, fitRect.height / imageSize.height)
        guard fitScale > 0, fitScale.isFinite else { return 1.0 }
        return 0.6 / fitScale
    }

    private static func clampedOffset(
        _ offset: CGSize,
        scaledImageSize: CGSize,
        viewportSize: CGSize,
    ) -> CGSize {
        let maxX = max(0, (scaledImageSize.width - viewportSize.width) / 2)
        let maxY = max(0, (scaledImageSize.height - viewportSize.height) / 2)
        return CGSize(
            width: min(max(offset.width, -maxX), maxX),
            height: min(max(offset.height, -maxY), maxY),
        )
    }
}

private enum ZoomBadgeStyle {
    static let fill = Color(nsColor: .systemGray).opacity(0.78)
}

private struct ZoomRatingBadgeRow: View {
    let selectedRating: Int?
    let applyRating: (Int) -> Void

    private let badges = [
        RatingBadgeOption(label: "X", rating: -1),
        RatingBadgeOption(label: "P", rating: 0),
        RatingBadgeOption(label: "2", rating: 2),
        RatingBadgeOption(label: "3", rating: 3),
        RatingBadgeOption(label: "4", rating: 4),
        RatingBadgeOption(label: "5", rating: 5)
    ]

    var body: some View {
        HStack(spacing: 12) {
            ForEach(badges) { badge in
                Button {
                    applyRating(badge.rating)
                } label: {
                    BrowserRatingBadge(rating: badge.rating, size: 25)
                        .overlay {
                            if selectedRating == badge.rating {
                                Circle()
                                    .strokeBorder(.white.opacity(0.9), lineWidth: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
                .help("Rate \(badge.label)")
                .accessibilityLabel("Rate \(badge.label)")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

struct BrowserRatingBadge: View {
    let rating: Int
    var size: CGFloat = 32

    var body: some View {
        Text(Self.label(for: rating))
            .font(.system(size: size * 0.46, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Self.textColor(for: rating))
            .frame(width: size, height: size)
            .background(
                Circle()
                    .fill(ZoomBadgeStyle.fill),
            )
            .shadow(color: .black.opacity(0.55), radius: 3, x: 0, y: 1)
            .accessibilityLabel("Rating \(Self.label(for: rating))")
    }

    private static func label(for rating: Int) -> String {
        switch rating {
        case -1:
            "X"

        case 0:
            "P"

        default:
            "\(rating)"
        }
    }

    private static func textColor(for rating: Int) -> Color {
        switch rating {
        case -1:
            .red

        case 0:
            .blue

        case 2:
            .yellow

        case 3:
            .green

        case 4:
            .cyan

        case 5:
            .pink

        default:
            .primary
        }
    }
}

private struct ZoomControlBadge<Content: View>: View {
    var width: CGFloat = 48
    var height: CGFloat = 28
    let content: Content

    init(
        width: CGFloat = 48,
        height: CGFloat = 28,
        @ViewBuilder content: () -> Content,
    ) {
        self.width = width
        self.height = height
        self.content = content()
    }

    var body: some View {
        content
            .font(.system(size: 17, weight: .semibold))
            .frame(width: width, height: height)
            .background(
                RoundedRectangle(cornerRadius: height / 2, style: .continuous)
                    .fill(ZoomBadgeStyle.fill),
            )
            .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
            .contentShape(RoundedRectangle(cornerRadius: height / 2, style: .continuous))
    }
}

private struct RatingBadgeOption: Identifiable {
    var id: Int {
        rating
    }

    let label: String
    let rating: Int
}

private struct ZoomImageRatingBadge: View {
    let rating: Int
    let imageSize: CGSize
    let containerSize: CGSize

    var body: some View {
        let drawRect = fittedImageRect(imageSize: imageSize, containerSize: containerSize)
        BrowserRatingBadge(rating: rating, size: 44)
            .position(
                x: drawRect.maxX - 30,
                y: drawRect.maxY - 30,
            )
            .frame(width: containerSize.width, height: containerSize.height)
    }
}

private struct ZoomMetadataPanel: View {
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

private struct FocusPointMarker: View {
    let focusPoint: BrowserFocusPoint
    let imageSize: CGSize
    let containerSize: CGSize

    var body: some View {
        FocusPointBracketMarker(
            normalizedX: CGFloat(focusPoint.normalizedX),
            normalizedY: CGFloat(focusPoint.normalizedY),
            boxSize: 16,
            imageSize: imageSize,
        )
        .stroke(.red, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 0)
        .frame(width: containerSize.width, height: containerSize.height)
        .accessibilityLabel("Focus point")
    }
}

private struct FocusPointBracketMarker: Shape {
    let normalizedX: CGFloat
    let normalizedY: CGFloat
    let boxSize: CGFloat
    let imageSize: CGSize

    nonisolated func path(in rect: CGRect) -> Path {
        let drawRect = fittedImageRect(imageSize: imageSize, containerSize: rect.size)
        let cx = drawRect.minX + normalizedX * drawRect.width
        let cy = drawRect.minY + normalizedY * drawRect.height
        let half = boxSize / 2
        let bracket = boxSize * 0.28

        var path = Path()
        let corners: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (-1, -1, 1, 0), (-1, -1, 0, 1),
            (1, -1, -1, 0), (1, -1, 0, 1),
            (-1, 1, 1, 0), (-1, 1, 0, -1),
            (1, 1, -1, 0), (1, 1, 0, -1)
        ]

        for (sx, sy, dx, dy) in corners {
            path.move(to: CGPoint(x: cx + sx * half, y: cy + sy * half))
            path.addLine(
                to: CGPoint(
                    x: cx + sx * half + dx * bracket,
                    y: cy + sy * half + dy * bracket,
                ),
            )
        }

        return path
    }
}

private nonisolated func fittedImageRect(imageSize: CGSize, containerSize: CGSize) -> CGRect {
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
