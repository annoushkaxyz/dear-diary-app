import SwiftUI
import PhotosUI

/// One page of the cover stack on the home screen.
private struct CoverCard: View {
    let image: UIImage?
    let caption: String?

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .overlay(Color.black.opacity(0.15))
            } else {
                LinearGradient(colors: [Color(white: 0.2), Color(white: 0.09)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            if let caption {
                // Same proportions as the real posts, scaled to the card.
                GeometryReader { geo in
                    Text(caption)
                        .font(.system(size: geo.size.width * 0.052, weight: .medium))
                        .lineSpacing(geo.size.width * 0.012)
                        .foregroundStyle(.white)
                        .padding(.leading, geo.size.width * CaptionSpec.marginLeft)
                        .padding(.top, geo.size.width * 0.15)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
            .strokeBorder(.white.opacity(0.08), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.5), radius: 16, y: 10)
    }
}

/// The fanned stack on the start page. Swipe or tap it to shuffle the pages.
private struct CoverStack: View {
    let images: [UIImage?]
    let caption: String
    let cardWidth: CGFloat

    /// order[0] is the page in front.
    @State private var order = [0, 1, 2]
    @State private var drag: CGSize = .zero
    @State private var pressed = false

    var body: some View {
        ZStack {
            ForEach(order, id: \.self) { card in
                let depth = order.firstIndex(of: card) ?? 0
                CoverCard(image: images.indices.contains(card) ? images[card] : nil,
                          caption: card == 0 ? caption : nil)
                    .frame(width: cardWidth, height: cardWidth * CaptionSpec.aspect)
                    .scaleEffect(scale(depth))
                    .rotation3DEffect(.degrees(depth == 0 ? Double(-drag.height) / 12 : 0), axis: (1, 0, 0))
                    .rotationEffect(.degrees(rotation(depth)))
                    .offset(offset(depth))
                    .zIndex(Double(3 - depth))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: cardWidth * CaptionSpec.aspect + cardWidth * 0.1)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.8)) {
                        pressed = true
                        drag = value.translation
                    }
                }
                .onEnded { value in
                    let moved = abs(value.translation.width) + abs(value.translation.height)
                    let flung = abs(value.predictedEndTranslation.width) > cardWidth * 0.5
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) {
                        // A tap, or a swipe far enough: the front page goes to the back.
                        if moved < 6 || flung {
                            order.append(order.removeFirst())
                        }
                        drag = .zero
                        pressed = false
                    }
                }
        )
        .sensoryFeedback(.impact(weight: .light), trigger: order)
    }

    private func scale(_ depth: Int) -> CGFloat {
        if depth == 0 { return pressed ? 1.03 : 1 }
        return pressed ? 0.88 : 0.9
    }

    private func rotation(_ depth: Int) -> Double {
        switch depth {
        case 0: return Double(drag.width) / 18
        case 1: return pressed ? -9 : -6
        default: return pressed ? 9 : 6
        }
    }

    private func offset(_ depth: Int) -> CGSize {
        // The side pages spread out a little while you hold the stack.
        let side = cardWidth * (pressed ? 0.24 : 0.2)
        switch depth {
        case 0: return drag
        case 1: return CGSize(width: -side, height: cardWidth * 0.06)
        default: return CGSize(width: side, height: cardWidth * 0.06)
        }
    }
}

struct HomeView: View {
    @Environment(AppState.self) private var state
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showSettings = false
    @State private var showPicker = false
    @State private var showDrafts = false
    /// How far back "Scan" looks; changed from the menu on the main button.
    @State private var range: ScanRange = .week

    var body: some View {
        GeometryReader { geo in
            // Hero cards sized to the screen: as big as fits between the title and the controls.
            let cardWidth = min(geo.size.width * 0.62, max(geo.size.height - 150, 200) * 0.75)
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, 24)
                Spacer(minLength: 12)
                if !state.candidates.isEmpty {
                    keptPhotos(cardWidth: cardWidth, screenWidth: geo.size.width)
                } else {
                    // The fanned pages stay inside the side margins.
                    CoverStack(images: Array(state.photos.prefix(3)).map { Optional($0.preview) },
                               caption: "dear \(state.city) diary,\n\ntoday i…",
                               cardWidth: min((geo.size.width - 48) / 1.45, cardWidth * 0.9))
                }
                Spacer(minLength: 12)
                statusArea
                    .padding(.horizontal, 24)
                    .frame(height: 36, alignment: .top)
            }
            .padding(.top, 8)
        }
        .background(Theme.background.ignoresSafeArea())
        .safeAreaBar(edge: .bottom) { bottomBar }
        .toolbar {
            if !state.drafts.isEmpty {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showDrafts = true } label: {
                        Image(systemName: "rectangle.stack").foregroundStyle(Theme.ink)
                    }
                    .accessibilityLabel("Drafts")
                    .disabled(state.isWorking)
                }
            }
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                await loadPicked(items)
                if !state.candidates.isEmpty { state.path.append(.selection) }
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showDrafts) {
            DraftsSheet { id in
                showDrafts = false
                Task {
                    if await state.openDraft(id) { state.path = [.draft] }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: range)
        .photosPicker(isPresented: $showPicker,
                      selection: $pickerItems,
                      maxSelectionCount: 40,
                      selectionBehavior: .ordered,
                      matching: .all(of: [.images, .not(.screenshots)]))
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(Theme.font(13))
                .foregroundStyle(Theme.muted)
            // "dear [lisbon ⌄] diary," — the city is a glass toggle that opens the city sheet.
            let size: CGFloat = state.city.count > 9 ? 28 : 34
            HStack(alignment: .center, spacing: 8) {
                Text("dear")
                Button { showSettings = true } label: {
                    HStack(spacing: 6) {
                        Text(state.city)
                        Image(systemName: "chevron.down")
                            .font(Theme.font(size * 0.45, .semibold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 4)
                    .glassEffect(.regular.interactive(), in: Capsule())
                }
                .buttonStyle(.plain)
                Text("diary,")
            }
            .font(Theme.font(size))
            .foregroundStyle(Theme.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
        .padding(.top, 12)
    }

    /// The kept photos, or, if everything was skipped, all of them (dimmed) so you can add some back.
    private var shownCandidates: [Candidate] {
        let kept = state.candidates.filter(\.included)
        return kept.isEmpty ? state.candidates : kept
    }

    /// The photos that will go into the draft, big and centred. Tap to review.
    private func keptPhotos(cardWidth: CGFloat, screenWidth: CGFloat) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                ForEach(shownCandidates) { candidate in
                    Button { state.path.append(.selection) } label: {
                        Image(uiImage: candidate.thumb)
                            .resizable()
                            .scaledToFill()
                            .frame(width: cardWidth, height: cardWidth * CaptionSpec.aspect)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                            .opacity(candidate.included ? 1 : 0.4)
                            .shadow(color: .black.opacity(0.45), radius: 16, y: 10)
                    }
                    .buttonStyle(.plain)
                    .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                        content
                            .scaleEffect(phase.isIdentity ? 1 : 0.88)
                            .rotationEffect(.degrees(phase.value * 3))
                    }
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, (screenWidth - cardWidth) / 2, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollClipDisabled()
        .frame(height: cardWidth * CaptionSpec.aspect)
    }

    @ViewBuilder
    private var statusArea: some View {
        if let error = state.errorMessage, !state.isWorking {
            Text(error)
                .font(Theme.font(13))
                .foregroundStyle(Color(red: 1, green: 0.55, blue: 0.5))
        }
    }

    /// The one main action. Its label says how far back it looks; the menu on its right
    /// switches the range or lets you pick photos yourself.
    private var bottomBar: some View {
        mainButton
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 8)
    }

    private var mainButton: some View {
        HStack(spacing: 0) {
            Button {
                Haptics.bump(.medium)
                Task {
                    await scan(range)
                    if !state.candidates.isEmpty {
                        Haptics.success()
                        state.path.append(.selection)
                    } else {
                        Haptics.error()
                    }
                }
            } label: {
                Group {
                    if state.isWorking {
                        HStack(spacing: 10) {
                            ProgressView().tint(.black)
                            Text(state.status)
                                .lineLimit(1)
                                .contentTransition(.numericText())
                        }
                    } else {
                        Label("Scan \(range.rawValue)", systemImage: "sparkles")
                            .contentTransition(.numericText())
                    }
                }
                // Balances the menu on the right, so the label sits in the middle of the whole button.
                .padding(.leading, state.isWorking ? 0 : menuWidth)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !state.isWorking {
                Rectangle()
                    .fill(.black.opacity(0.15))
                    .frame(width: 1, height: 24)
                Menu {
                    Picker("Scan", selection: $range.animation()) {
                        ForEach(ScanRange.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    Divider()
                    Button("Select yourself", systemImage: "photo.on.rectangle.angled") { showPicker = true }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(Theme.font(15, .semibold))
                        .frame(width: menuWidth - 1)
                        .frame(maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .menuOrder(.fixed)
                .accessibilityLabel("Scan options")
            }
        }
        .font(Theme.font(16))
        .foregroundStyle(.black)
        .frame(maxWidth: .infinity)
        .frame(height: Theme.buttonHeight)
        .glassEffect(.regular.tint(.white), in: Capsule())
        .allowsHitTesting(!state.isWorking)
    }

    private let menuWidth: CGFloat = 58

    // MARK: - Finding photos

    @MainActor
    private func scan(_ range: ScanRange) async {
        state.errorMessage = nil
        state.detachDraft()
        guard await LibraryScanner.requestAccess() else {
            state.errorMessage = "Photos access is off. Turn it on in Settings › Dear Diary › Photos."
            return
        }
        state.isWorking = true
        defer { state.isWorking = false }
        state.status = "Looking through your photos…"

        let result = await LibraryScanner.scan(range, city: state.currentCity) { message in
            state.status = message
        }
        state.candidates = result.candidates
        state.screenshotsIgnored = result.screenshots
        if result.candidates.isEmpty {
            state.errorMessage = "No photos found in the \(range.rawValue)."
        }
    }

    @MainActor
    private func loadPicked(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        state.errorMessage = nil
        state.detachDraft()
        state.isWorking = true
        defer { state.isWorking = false }

        var result: [Candidate] = []
        for (i, item) in items.enumerated() {
            state.status = "Checking \(i + 1) of \(items.count)…"
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let thumb = ImageLoader.downsample(data, maxPixel: 512) else { continue }
            let reason = PhotoFilter.check(lens: PhotoFilter.lensModel(of: data), thumb: thumb, requireCamera: false)
            result.append(Candidate(assetID: nil, data: data, thumb: thumb,
                                    skipReason: reason, included: reason == nil))
        }
        state.status = "Comparing similar photos…"
        SimilarityFilter.keepBestOfSimilar(&result)
        state.candidates = result
        state.screenshotsIgnored = 0
        pickerItems = []
    }
}
