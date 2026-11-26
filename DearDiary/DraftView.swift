import SwiftUI
import Photos

private struct ExportJob {
    let data: Data
    let caption: String
    let position: TextPosition
    let focus: CGPoint
    let seed: Int
    let adjust: PhotoAdjust
}

/// The drafted entry as a carousel: the centre card is larger, its neighbours peek in.
/// Everything below the carousel edits the centre card.
struct DraftView: View {
    @Environment(AppState.self) private var state
    @State private var currentID: UUID?
    @State private var exporting = false
    @State private var message: String?
    @State private var shareImages: [UIImage] = []
    @State private var showShare = false
    @State private var showLeftOut = false
    @State private var refreshing: UUID?
    /// Cards whose spare captions are being topped up in the background.
    @State private var toppingUp: Set<UUID> = []
    @State private var riffing = false
    @State private var riffTask: Task<Void, Never>?
    @State private var showArrange = false
    @State private var editing: EditTarget?
    @State private var grammarFix: [UUID: CaptionCheck] = [:]
    @State private var checkingGrammar: UUID?
    @FocusState private var editingLine: Bool

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {
                    if state.entry.isEmpty {
                        emptyState
                    } else {
                        carousel(width: geo.size.width)
                        if let index = currentIndex {
                            controls(for: index)
                                .padding(.horizontal, 24)
                                .padding(.top, 20)
                        }
                    }
                }
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollEdgeEffectStyle(.soft, for: .all)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Draft")
        .navigationBarTitleDisplayMode(.inline)
        .backButtonOnly()
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { showArrange = true } label: {
                    Image(systemName: "arrow.up.arrow.down").foregroundStyle(Theme.ink)
                }
                .disabled(state.entry.count < 2)
                Button { showLeftOut = true } label: {
                    Image(systemName: "plus.rectangle.on.rectangle").foregroundStyle(Theme.ink)
                }
                .disabled(state.leftOut.isEmpty)
            }
        }
        .safeAreaBar(edge: .bottom) {
            if !editingLine { bottomBar }
        }
        .sheet(isPresented: $showShare) { ActivityView(items: shareImages) }
        .sheet(isPresented: $showArrange) { ArrangeSheet() }
        .sheet(item: $editing) { target in PhotoEditorSheet(itemID: target.id) }
        .sheet(isPresented: $showLeftOut) {
            LeftOutSheet(insertAt: (currentIndex ?? -1) + 1) { newID in
                withAnimation { currentID = newID }
            }
        }
        .sensoryFeedback(.selection, trigger: currentID)
        .onAppear {
            if currentID == nil { currentID = state.entry.first?.id }
        }
        .onChange(of: editingLine) { _, focused in
            // Finished typing your own caption: check its grammar.
            guard !focused, let index = currentIndex else { return }
            let item = state.entry[index]
            if isCustom(item) {
                Task { await checkGrammar(for: item.id) }
            }
        }
    }

    private var currentIndex: Int? {
        guard let id = currentID ?? state.entry.first?.id else { return nil }
        return state.entry.firstIndex { $0.id == id }
    }

    // MARK: - Carousel

    private func carousel(width: CGFloat) -> some View {
        let cardWidth = (width * 0.72).rounded()
        let cardHeight = (cardWidth * CaptionSpec.aspect).rounded()
        return ScrollView(.horizontal) {
            LazyHStack(spacing: 12) {
                ForEach(Array(state.entry.enumerated()), id: \.element.id) { position, item in
                    card(item, position: position, width: cardWidth)
                        .frame(width: cardWidth, height: cardHeight)
                        .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                            content
                                .scaleEffect(phase.isIdentity ? 1 : 0.84)
                                .opacity(phase.isIdentity ? 1 : 0.45)
                        }
                        .onTapGesture {
                            withAnimation(.snappy) { currentID = item.id }
                        }
                }
            }
            .scrollTargetLayout()
        }
        .contentMargins(.horizontal, (width - cardWidth) / 2, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $currentID, anchor: .center)
        .scrollIndicators(.hidden)
        .frame(height: cardHeight + 8)
        .padding(.top, 12)
    }

    @ViewBuilder
    private func card(_ item: EntryItem, position: Int, width: CGFloat) -> some View {
        if let photo = state.photo(item.photoIndex) {
            RenderedCard(source: photo.preview,
                         caption: state.caption(at: position),
                         position: item.textPosition,
                         focus: item.focus,
                         look: state.look,
                         width: width * 3,
                         seed: item.photoIndex,
                         adjust: item.adjust)
                .clipShape(Rectangle()) // square, exactly like the saved image
                .shadow(color: .black.opacity(0.5), radius: 18, y: 10)
                .overlay(alignment: .bottomTrailing) {
                    if item.id == (currentID ?? state.entry.first?.id) {
                        Button { editing = EditTarget(id: item.id) } label: {
                            Image(systemName: "slider.horizontal.3")
                        }
                        .buttonStyle(CircleButtonStyle())
                        .padding(10)
                        .transition(.opacity)
                    }
                }
        }
    }

    // MARK: - Controls for the centre card

    private func controls(for i: Int) -> some View {
        @Bindable var state = state
        let item = state.entry[i]
        return VStack(alignment: .leading, spacing: 24) {
            // Position in the entry + move / remove
            HStack(spacing: 10) {
                Text("\(i + 1) / \(state.entry.count)")
                    .font(Theme.font(13))
                    .foregroundStyle(Theme.muted)
                    .monospacedDigit()
                if item.isWildcard {
                    Text("✦ You might have missed this")
                        .font(Theme.font(12))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .glassEffect(.regular, in: Capsule())
                }
                Spacer()
                Button { move(item.id, by: -1) } label: { Image(systemName: "arrow.left") }
                    .buttonStyle(CircleButtonStyle())
                    .disabled(i == 0)
                Button { move(item.id, by: 1) } label: { Image(systemName: "arrow.right") }
                    .buttonStyle(CircleButtonStyle())
                    .disabled(i == state.entry.count - 1)
                Button { remove(item.id, at: i) } label: { Image(systemName: "trash") }
                    .buttonStyle(CircleButtonStyle())
            }

            if !item.whatISaw.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel("Image description")
                    Text(item.whatISaw.sentenceCased)
                        .font(Theme.font(15, .regular))
                        .foregroundStyle(Theme.ink.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Caption options
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionLabel(item.options.isEmpty ? "Caption" : "Pick a caption")
                    Spacer()
                    Button {
                        let custom = isCustom(item) ? item.line : nil
                        Task { await refreshOptions(for: item.id, hint: custom) }
                    } label: {
                        HStack(spacing: 6) {
                            if refreshing == item.id {
                                ProgressView().controlSize(.mini).tint(Theme.ink)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                            Text(isCustom(item) ? "Rephrase mine" : (item.options.isEmpty ? "Suggest" : "New options"))
                        }
                        .font(Theme.font(12))
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .glassEffect(.regular.interactive(), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(refreshing != nil || item.isWriting)
                }
                if item.isWriting {
                    // Captions for this photo are still on their way.
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small).tint(Theme.ink)
                        Text("Writing captions…")
                            .font(Theme.font(14))
                            .foregroundStyle(Theme.muted)
                    }
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
                }
                ForEach(Array(item.options.enumerated()), id: \.offset) { _, option in
                    CaptionOption(text: option, selected: item.line == option) {
                        Haptics.tap()
                        state.entry[i].line = option
                        editingLine = false
                    }
                }
                TextField("Or write your own", text: $state.entry[i].line, axis: .vertical)
                    .font(Theme.font(15, .regular))
                    .textInputAutocapitalization(.never)
                    .lineLimit(1...4)
                    .focused($editingLine)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(item.options.contains(item.line) ? Theme.hairline : Color.white.opacity(0.7), lineWidth: 1)
                    )
                    .onChange(of: item.line) { _, newValue in
                        if editingLine { grammarFix[item.id] = nil }
                        scheduleRiff(for: item.id, text: newValue)
                    }
                if let check = grammarFix[item.id] {
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: "text.badge.checkmark")
                            .foregroundStyle(Theme.muted)
                        VStack(alignment: .leading, spacing: 3) {
                            if let fix = check.fix {
                                Text("Suggested fix")
                                    .font(Theme.font(12))
                                    .foregroundStyle(Theme.muted)
                                Text(fix)
                                    .font(Theme.font(15))
                                    .foregroundStyle(Theme.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if let note = check.note {
                                Text(note.sentenceCased)
                                    .font(Theme.font(13, .regular))
                                    .foregroundStyle(check.fix == nil ? Theme.ink : Theme.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: 0)
                        if let fix = check.fix {
                            Button("Use") {
                                Haptics.tap()
                                state.entry[i].line = fix
                                grammarFix[item.id] = nil
                            }
                            .font(Theme.font(13))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .glassEffect(.regular.tint(.white).interactive(), in: Capsule())
                            .buttonStyle(.plain)
                        }
                        Button { grammarFix[item.id] = nil } label: {
                            Image(systemName: "xmark")
                                .font(Theme.font(12))
                                .foregroundStyle(Theme.muted)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(14)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
                } else if checkingGrammar == item.id {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.mini).tint(Theme.ink)
                        Text("Checking grammar…")
                            .font(Theme.font(12))
                            .foregroundStyle(Theme.muted)
                    }
                }
                if refreshing == item.id && riffing {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.mini).tint(Theme.ink)
                        Text("Building on your line…")
                            .font(Theme.font(12))
                            .foregroundStyle(Theme.muted)
                    }
                }
            }

            // Text position
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Text position")
                HStack(spacing: 8) {
                    ForEach(TextPosition.allCases) { option in
                        PositionButton(position: option, selected: item.textPosition == option) {
                            Haptics.tap()
                            withAnimation(.snappy) { state.entry[i].textPosition = option }
                        }
                    }
                }
            }

        }
    }

    /// Asks the current drafting engine for three fresh options for one photo.
    @MainActor
    private func refreshOptions(for id: UUID, hint: String? = nil) async {
        // Instant: show the good lines already written for this photo, then quietly write more.
        if hint == nil, let j = state.entry.firstIndex(where: { $0.id == id }), !state.entry[j].spare.isEmpty {
            let next = Array(state.entry[j].spare.prefix(3))
            let keepCurrent = !state.entry[j].options.contains(state.entry[j].line) && !state.entry[j].line.isEmpty
            Haptics.bump(.soft)
            withAnimation(.snappy) {
                state.entry[j].options = next
                state.entry[j].spare.removeFirst(next.count)
                if !keepCurrent { state.entry[j].line = next[0] }
            }
            if state.entry[j].spare.count < 3 { topUpSpares(for: id) }
            return
        }
        guard refreshing == nil,
              let item = state.entry.first(where: { $0.id == id }),
              let photo = state.photo(item.photoIndex) else { return }
        refreshing = id
        riffing = hint != nil
        defer { refreshing = nil; riffing = false }
        message = nil
        do {
            var lines: [String] = []
            switch state.engine {
            case .apple:
                if let problem = AppleDrafter.availabilityProblem() {
                    message = problem
                    return
                }
                guard #available(iOS 27.0, *) else { return }
                lines = try await AppleDrafter.moreLines(for: photo, city: state.city, avoid: item.options, hint: hint,
                                                         known: item.whatISaw)
            case .claude:
                guard let key = Keychain.read(), !key.isEmpty else {
                    message = "Add your Anthropic API key in Settings."
                    return
                }
                lines = try await ClaudeClient(apiKey: key, model: state.model)
                    .moreLines(for: photo, city: state.city, avoid: item.options, hint: hint)
            }
            let cleaned = Caption.distinct(lines.map(Caption.cleanLine).filter { !$0.isEmpty })
            guard !cleaned.isEmpty, let j = state.entry.firstIndex(where: { $0.id == id }) else { return }
            let keepCurrent = !state.entry[j].options.contains(state.entry[j].line) && !state.entry[j].line.isEmpty
            Haptics.bump(.soft)
            withAnimation(.snappy) {
                state.entry[j].options = Array(cleaned.prefix(3))
                if hint == nil { state.entry[j].spare = Array(cleaned.dropFirst(3)) }
                if !keepCurrent { state.entry[j].line = cleaned[0] }
            }
            if hint == nil, state.entry[j].spare.count < 3 { topUpSpares(for: id) }
        } catch {
            message = error.localizedDescription
        }
    }

    /// Writes more spare captions for a card in the background, so the next "New options" is instant.
    private func topUpSpares(for id: UUID) {
        guard !toppingUp.contains(id), state.engine == .apple, AppleDrafter.availabilityProblem() == nil,
              let item = state.entry.first(where: { $0.id == id }),
              let photo = state.photo(item.photoIndex) else { return }
        toppingUp.insert(id)
        let seen = item.options + item.spare
        let city = state.city
        Task { @MainActor in
            defer { toppingUp.remove(id) }
            guard #available(iOS 27.0, *) else { return }
            let lines = (try? await AppleDrafter.moreLines(for: photo, city: city, avoid: seen,
                                                           known: item.whatISaw)) ?? []
            guard let j = state.entry.firstIndex(where: { $0.id == id }) else { return }
            let existing = Set(state.entry[j].options + state.entry[j].spare)
            state.entry[j].spare += Caption.distinct(lines.map(Caption.cleanLine))
                .filter { !$0.isEmpty && !existing.contains($0) }
        }
    }

    /// Lowercase, trimmed, no end punctuation: for comparing a line with its proofread version.
    private func normalized(_ text: String) -> String {
        text.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!,;:\"'“” "))
    }

    /// Proofreads a caption you wrote yourself; shows a fix or a note only if something is actually off.
    @MainActor
    private func checkGrammar(for id: UUID) async {
        guard let item = state.entry.first(where: { $0.id == id }) else { return }
        let line = normalized(item.line)
        guard line.split(separator: " ").count >= 2 else { return }
        checkingGrammar = id
        defer { checkingGrammar = nil }
        do {
            let result: (corrected: String, note: String)
            switch state.engine {
            case .apple:
                guard AppleDrafter.availabilityProblem() == nil else { return }
                result = try await AppleDrafter.checkGrammar(line)
            case .claude:
                guard let key = Keychain.read(), !key.isEmpty else { return }
                result = try await ClaudeClient(apiKey: key, model: state.model).checkGrammar(line)
            }
            let fixed = normalized(result.corrected)
            let note = result.note.trimmingCharacters(in: .whitespacesAndNewlines)
            let check = CaptionCheck(fix: (fixed.isEmpty || fixed == line) ? nil : fixed,
                                     note: note.isEmpty ? nil : note)
            // Only if the line hasn't changed meanwhile and there's something to say.
            guard let current = state.entry.first(where: { $0.id == id }),
                  normalized(current.line) == line,
                  check.fix != nil || check.note != nil else { return }
            Haptics.bump(.soft)
            withAnimation(.snappy) { grammarFix[id] = check }
        } catch {
            // A failed check just shows nothing.
        }
    }

    private func isCustom(_ item: EntryItem) -> Bool {
        let line = item.line.trimmingCharacters(in: .whitespacesAndNewlines)
        return !line.isEmpty && !item.options.contains(line)
    }

    /// After you pause typing your own line (at least four words, so there is an idea to keep),
    /// ask the AI to rephrase it.
    private func scheduleRiff(for id: UUID, text: String) {
        riffTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard editingLine,
              trimmed.split(separator: " ").count >= 4,
              let item = state.entry.first(where: { $0.id == id }),
              !item.options.contains(trimmed) else { return }
        riffTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            while refreshing != nil {
                if Task.isCancelled { return }
                try? await Task.sleep(for: .milliseconds(300))
            }
            guard !Task.isCancelled else { return }
            await refreshOptions(for: id, hint: trimmed)
        }
    }

    private func moveTo(_ id: UUID, index: Int) {
        Haptics.bump()
        withAnimation(.snappy) { state.move(id: id, to: index) }
        currentID = id
    }

    private func move(_ id: UUID, by offset: Int) {
        Haptics.bump()
        withAnimation(.snappy) { state.move(id: id, by: offset) }
        currentID = id
    }

    private func remove(_ id: UUID, at index: Int) {
        let next = state.entry.indices.contains(index + 1) ? state.entry[index + 1].id
            : (index > 0 ? state.entry[index - 1].id : nil)
        Haptics.bump(.medium)
        withAnimation(.snappy) { state.remove(id: id) }
        currentID = next
    }

    // MARK: - Empty + bottom bar

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("Nothing in this entry yet")
                .font(Theme.font(17))
                .foregroundStyle(Theme.ink)
            Button("Show left-out photos") { showLeftOut = true }
                .buttonStyle(PillButtonStyle(prominent: false))
                .frame(width: 240)
                .disabled(state.leftOut.isEmpty)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 120)
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            if let message {
                Text(message)
                    .font(Theme.font(12))
                    .foregroundStyle(Theme.muted)
            }
            Button {
                Task { await export(saveToPhotos: true) }
            } label: {
                Text(exporting ? "Rendering…" : "Save \(state.entry.count) to camera roll")
            }
            .buttonStyle(PillButtonStyle())
            .disabled(state.entry.isEmpty || exporting)
        }
        .padding(.horizontal, 24)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    // MARK: - Export

    @MainActor
    private func export(saveToPhotos: Bool) async {
        exporting = true
        defer { exporting = false }
        message = nil

        let jobs: [ExportJob] = state.entry.enumerated().compactMap { (position, item) -> ExportJob? in
            guard let photo = state.photo(item.photoIndex) else { return nil }
            return ExportJob(data: photo.sourceData,
                             caption: state.caption(at: position),
                             position: item.textPosition,
                             focus: item.focus,
                             seed: item.photoIndex,
                             adjust: item.adjust)
        }
        let look = state.look

        let images: [UIImage] = await Task.detached(priority: .userInitiated) {
            jobs.compactMap { (job) -> UIImage? in
                guard let full = ImageLoader.downsample(job.data, maxPixel: 3000) else { return nil }
                return ImageStyler.render(source: full, caption: job.caption, position: job.position,
                                          focus: job.focus, look: look, width: 2160, seed: job.seed,
                                          adjust: job.adjust)
            }
        }.value

        guard saveToPhotos else {
            shareImages = images
            showShare = true
            return
        }

        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            message = "Photos access is off. Turn it on in Settings › Dear Diary."
            return
        }
        do {
            // One at a time, so they land in Photos in posting order.
            for image in images {
                try await PHPhotoLibrary.shared().performChanges {
                    _ = PHAssetChangeRequest.creationRequestForAsset(from: image)
                }
            }
            // Small copies for the "saved" screen, then go there.
            state.savedImages = images.map { $0.preparingThumbnail(of: CGSize(width: 540, height: 720)) ?? $0 }
            // Remember what you kept, as examples for next time.
            LearnedStore.add(state.entry.compactMap { (item) -> LearnedExample? in
                let line = item.line.trimmingCharacters(in: .whitespacesAndNewlines)
                let seen = item.whatISaw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty, !seen.isEmpty else { return nil }
                return LearnedExample(seen: seen, line: line)
            })
            Haptics.success()
            state.markExported()
            state.path.append(.saved)
        } catch {
            Haptics.error()
            message = error.localizedDescription
        }
    }
}

// MARK: - Small components

private struct CaptionOption: View {
    let text: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(Theme.font(16))
                    .foregroundStyle(selected ? Theme.ink : Theme.faint)
                Text(text)
                    .font(Theme.font(15))
                    .foregroundStyle(selected ? Theme.ink : Theme.ink.opacity(0.75))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(14)
            .contentShape(RoundedRectangle(cornerRadius: 16))
            .glassEffect(selected ? .regular.tint(.white.opacity(0.25)).interactive() : .regular.interactive(),
                         in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: selected)
    }
}

private struct PositionButton: View {
    let position: TextPosition
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                // A tiny 3:4 frame showing where the text sits.
                ZStack(alignment: alignment) {
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(selected ? Color.black.opacity(0.5) : Theme.faint, lineWidth: 1)
                    VStack(alignment: .leading, spacing: 2) {
                        Capsule().frame(width: 12, height: 2)
                        Capsule().frame(width: 8, height: 2)
                    }
                    .padding(4)
                }
                .frame(width: 24, height: 32)
                Text(position.rawValue.capitalized)
                    .font(Theme.font(12))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(selected ? Color.black : Theme.ink)
            .contentShape(RoundedRectangle(cornerRadius: 16))
            .glassEffect(selected ? .regular.tint(.white).interactive() : .regular.interactive(),
                         in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private var alignment: Alignment {
        switch position {
        case .top: return .topLeading
        case .middle: return .leading
        case .bottom: return .bottomLeading
        }
    }
}

/// Result of proofreading a caption you wrote: a corrected version and/or a note on what's unclear.
struct CaptionCheck {
    var fix: String?
    var note: String?
}

struct EditTarget: Identifiable {
    let id: UUID
}

/// One editor for everything visual: big live preview on top, then controls for this photo
/// and for the look of all photos (saved for next time).
private struct PhotoEditorSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    let itemID: UUID

    var body: some View {
        @Bindable var state = state
        NavigationStack {
            GeometryReader { geo in
                if let i = state.entry.firstIndex(where: { $0.id == itemID }),
                   let photo = state.photo(state.entry[i].photoIndex) {
                    let item = state.entry[i]
                    let ratio = photo.preview.size.width / max(photo.preview.size.height, 1)
                    VStack(spacing: 14) {
                        RenderedCard(source: photo.preview,
                                     caption: state.caption(at: i),
                                     position: item.textPosition,
                                     focus: item.focus,
                                     look: state.look,
                                     width: 1080,
                                     seed: item.photoIndex,
                                     adjust: item.adjust)
                            .clipShape(Rectangle()) // square, exactly like the saved image
                            .shadow(color: .black.opacity(0.5), radius: 16, y: 8)
                            .frame(maxWidth: .infinity)
                            .frame(height: geo.size.height * 0.52)
                            .padding(.top, 6)

                        ScrollView {
                            VStack(alignment: .leading, spacing: 14) {
                                // This photo
                                HStack {
                                    SectionLabel("This photo")
                                    Spacer()
                                    if item.adjust.isEdited {
                                        Button("Reset") {
                                            Haptics.bump()
                                            withAnimation(.snappy) { state.entry[i].adjust = PhotoAdjust() }
                                        }
                                        .font(Theme.font(12))
                                        .foregroundStyle(Theme.muted)
                                    }
                                }
                                HStack(spacing: 8) {
                                    ForEach(TextPosition.allCases) { option in
                                        PositionButton(position: option, selected: item.textPosition == option) {
                                            Haptics.tap()
                                            withAnimation(.snappy) { state.entry[i].textPosition = option }
                                        }
                                    }
                                }
                                LookSlider("Exposure", value: $state.entry[i].adjust.exposure, range: -1...1)
                                LookSlider("Shadows", value: $state.entry[i].adjust.shadows, range: -1...1)
                                LookSlider("Saturation", value: $state.entry[i].adjust.saturation, range: -1...1)
                                LookSlider("Warmth", value: $state.entry[i].adjust.warmth, range: -1...1)
                                LookSlider("Darken behind text", value: $state.entry[i].adjust.shade, range: 0...1)
                                if abs(ratio - 0.75) > 0.02 {
                                    if ratio > 0.75 {
                                        LookSlider("Framing", value: Binding(
                                            get: { Double(state.entry[i].focus.x) },
                                            set: { state.entry[i].focus.x = CGFloat($0) }), range: 0...1)
                                    } else {
                                        LookSlider("Framing", value: Binding(
                                            get: { Double(state.entry[i].focus.y) },
                                            set: { state.entry[i].focus.y = CGFloat($0) }), range: 0...1)
                                    }
                                }

                                // All photos
                                SectionLabel("All photos")
                                    .padding(.top, 12)
                                LookSlider("Grain", value: $state.look.grain, range: 0...1)
                            }
                            .padding(.bottom, 24)
                        }
                        .scrollEdgeEffectStyle(.soft, for: .top)
                    }
                    .padding(.horizontal, 24)
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }
}

/// Drag to reorder; the first photo opens with "dear … diary,", the last closes with "until next time".
private struct ArrangeSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var state = state
        NavigationStack {
            List {
                Section {
                    Toggle("Start with “dear \(state.city) diary,”", isOn: $state.greetingOn)
                    Toggle("End with “until next time”", isOn: $state.signoffOn)
                }
                Section {
                    ForEach(Array(state.entry.enumerated()), id: \.element.id) { position, item in
                        HStack(spacing: 12) {
                            if let photo = state.photo(item.photoIndex) {
                                Image(uiImage: photo.preview)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 42, height: 56)
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.line.isEmpty ? "—" : item.line)
                                    .font(Theme.font(14))
                                    .lineLimit(2)
                                if position == 0 && state.greetingOn {
                                    Text("Dear diary")
                                        .font(Theme.font(11))
                                        .foregroundStyle(Theme.muted)
                                } else if position == state.entry.count - 1 && state.signoffOn {
                                    Text("Until next time")
                                        .font(Theme.font(11))
                                        .foregroundStyle(Theme.muted)
                                }
                            }
                        }
                    }
                    .onMove { state.entry.move(fromOffsets: $0, toOffset: $1) }
                } header: {
                    Text("Drag to reorder")
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Order")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// Photos that didn't make the entry; tap one to add it after the current card.
private struct LeftOutSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    let insertAt: Int
    let onAdd: (UUID) -> Void
    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 4)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(state.leftOut) { item in
                        Button {
                            Haptics.bump()
                            let added = state.add(item, at: insertAt)
                            onAdd(added.id)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                if let photo = state.photo(item.photoIndex) {
                                    // Same 3:4 shape as the posts.
                                    Color.clear
                                        .aspectRatio(1 / CaptionSpec.aspect, contentMode: .fit)
                                        .overlay {
                                            Image(uiImage: photo.preview)
                                                .resizable()
                                                .scaledToFill()
                                        }
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                                Text(item.reason.isEmpty ? "—" : item.reason.sentenceCased)
                                    .font(Theme.font(11, .regular))
                                    .foregroundStyle(Theme.muted)
                                    .lineLimit(3)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .background(Theme.background)
            .navigationTitle("Left out")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// Renders a styled card off the main thread and re-renders when anything changes.
struct RenderedCard: View {
    let source: UIImage
    let caption: String
    let position: TextPosition
    let focus: CGPoint
    let look: Look
    let width: CGFloat
    var seed: Int = 0
    var adjust = PhotoAdjust()
    @State private var image: UIImage?

    var body: some View {
        Color.white.opacity(0.06)
            .aspectRatio(1 / CaptionSpec.aspect, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFit()
                }
            }
            .task(id: renderKey) {
                let src = source, cap = caption, pos = position, foc = focus, lk = look, w = width, sd = seed, adj = adjust
                let rendered = await Task.detached(priority: .userInitiated) {
                    ImageStyler.render(source: src, caption: cap, position: pos, focus: foc, look: lk, width: w,
                                       seed: sd, adjust: adj)
                }.value
                if !Task.isCancelled { image = rendered }
            }
    }

    private var renderKey: String {
        "\(ObjectIdentifier(source).hashValue)|\(caption)|\(position.rawValue)|\(focus.x)|\(focus.y)|\(look.hashValue)|\(width)|\(seed)|\(adjust.hashValue)"
    }
}

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
