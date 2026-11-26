import SwiftUI
import ImageIO
import Security
import CoreLocation

// MARK: - Photos

struct DiaryPhoto: Identifiable {
    let id = UUID()
    /// 1-based number, as Claude sees it ("Photo 3").
    let index: Int
    /// Original file bytes, decoded at full size only when exporting.
    let sourceData: Data
    /// Small version for the UI and for Claude.
    let preview: UIImage
    let modelJPEG: Data

    init?(index: Int, data: Data) {
        guard let preview = ImageLoader.downsample(data, maxPixel: 1024),
              let jpeg = preview.jpegData(compressionQuality: 0.75) else { return nil }
        self.index = index
        self.sourceData = data
        self.preview = preview
        self.modelJPEG = jpeg
    }

    func fullImage() -> UIImage? {
        ImageLoader.downsample(sourceData, maxPixel: 2600)
    }
}

enum TextPosition: String, CaseIterable, Hashable, Identifiable {
    case top, middle, bottom
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .top: return "align.vertical.top"
        case .middle: return "align.vertical.center"
        case .bottom: return "align.vertical.bottom"
        }
    }
}

/// Per-photo edits, on top of your look.
struct PhotoAdjust: Hashable {
    var exposure: Double = 0   // -1…1 stops
    var shadows: Double = 0    // -1 lifts … 1 deepens
    var saturation: Double = 0 // -1…1
    var warmth: Double = 0     // -1 cool … 1 warm
    var shade: Double = 0      // 0…1 darkens the area behind the text
    var isEdited: Bool { exposure != 0 || shadows != 0 || saturation != 0 || warmth != 0 || shade != 0 }
}

struct EntryItem: Identifiable, Hashable {
    let id = UUID()
    var photoIndex: Int
    /// Caption suggestions for this photo, best first.
    var options: [String]
    /// The line actually printed (one of the options, or your own edit).
    var line: String
    var whatISaw: String
    var textPosition: TextPosition
    var focus: CGPoint
    var isWildcard: Bool
    var adjust = PhotoAdjust()
    /// True while its captions are still being written (the draft opens before they're all done).
    var isWriting = false
    /// Good lines that didn't make the first three, shown instantly on "New options".
    var spare: [String] = []

    static func == (a: EntryItem, b: EntryItem) -> Bool {
        a.id == b.id && a.line == b.line && a.textPosition == b.textPosition && a.focus == b.focus
            && a.options == b.options && a.adjust == b.adjust && a.isWriting == b.isWriting
    }
    func hash(into h: inout Hasher) { h.combine(id) }
}

struct LeftOut: Identifiable {
    let id = UUID()
    var photoIndex: Int
    var reason: String
}

// MARK: - The look

/// Your editing recipe. Tune it in Settings → my look.
struct Look: Codable, Hashable {
    var exposure: Double = -0.35   // stops
    var shadows: Double = 0.5      // 0 = flat, 1 = deep
    var contrast: Double = 1.06
    var saturation: Double = 1.08
    var warmth: Double = 0.3       // -1 cool … 1 warm
    var fade: Double = 0.0         // lifts the blacks
    var grain: Double = 0.0        // 0 = none, 1 = heavy

    init() {}

    // Tolerates looks saved by older versions (missing keys keep their defaults).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Look.defaultValues
        exposure = try c.decodeIfPresent(Double.self, forKey: .exposure) ?? d.exposure
        shadows = try c.decodeIfPresent(Double.self, forKey: .shadows) ?? d.shadows
        contrast = try c.decodeIfPresent(Double.self, forKey: .contrast) ?? d.contrast
        saturation = try c.decodeIfPresent(Double.self, forKey: .saturation) ?? d.saturation
        warmth = try c.decodeIfPresent(Double.self, forKey: .warmth) ?? d.warmth
        fade = try c.decodeIfPresent(Double.self, forKey: .fade) ?? d.fade
        grain = try c.decodeIfPresent(Double.self, forKey: .grain) ?? d.grain
    }

    private static let defaultValues = Look()

    static let key = "look"

    static func load() -> Look {
        guard let data = UserDefaults.standard.data(forKey: key),
              let look = try? JSONDecoder().decode(Look.self, from: data) else { return Look() }
        return look
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Look.key)
        }
    }
}

// MARK: - Cities

/// A city the diary can address ("dear paris diary,"), with its centre for the location filter.
struct DiaryCity: Codable, Hashable, Identifiable {
    var name: String
    var latitude: Double
    var longitude: Double
    var id: String { name }
    var location: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }

    static let lisbon = DiaryCity(name: "lisbon", latitude: 38.7223, longitude: -9.1393)
    private static let key = "cities"

    static func loadAll() -> [DiaryCity] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([DiaryCity].self, from: data), !list.isEmpty else { return [.lisbon] }
        return list
    }

    static func saveAll(_ list: [DiaryCity]) {
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

// MARK: - Learning from your choices

/// A caption you kept, with what was in the photo. Used as an extra example next time.
struct LearnedExample: Codable, Hashable {
    let seen: String
    let line: String
}

enum LearnedStore {
    private static let key = "learnedExamples"
    private static let limit = 60

    static func all() -> [LearnedExample] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([LearnedExample].self, from: data) else { return [] }
        return list
    }

    /// Newest first; duplicates are skipped.
    static func add(_ examples: [LearnedExample]) {
        var list = all()
        for example in examples.reversed() where !list.contains(example) {
            list.insert(example, at: 0)
        }
        if let data = try? JSONEncoder().encode(Array(list.prefix(limit))) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

// MARK: - Navigation

/// The screens after the start page: choose photos → draft → saved.
enum Route: Hashable {
    case selection, draft, saved
}

// MARK: - App state

@Observable
final class AppState {
    var candidates: [Candidate] = []
    /// True after you change the selection in Review, so the main button offers to redraft.
    var selectionChanged = false
    /// Where you are: start page → selection → draft → saved.
    var path: [Route] = []
    /// Small copies of the last saved entry, for the "saved" screen.
    var savedImages: [UIImage] = []
    var screenshotsIgnored = 0

    var includedCount: Int { candidates.filter(\.included).count }

    var candidateSummary: String {
        let skipped = candidates.filter { $0.skipReason != nil }.count
        var parts = ["\(includedCount) photos ready"]
        if skipped > 0 { parts.append("\(skipped) skipped") }
        if screenshotsIgnored > 0 { parts.append("\(screenshotsIgnored) screenshots ignored") }
        return parts.joined(separator: " · ")
    }

    var photos: [DiaryPhoto] = [] {
        didSet { photosChanged = true; scheduleSave() }
    }
    var entry: [EntryItem] = [] { didSet { scheduleSave() } }
    var leftOut: [LeftOut] = [] { didSet { scheduleSave() } }

    // MARK: Keeping drafts

    /// Every saved draft, newest first, for the Drafts list.
    var drafts: [DraftStore.Summary] = []
    /// Which saved draft is open (nil after "New entry" or a new scan, until the next draft starts).
    @ObservationIgnored var currentDraftID: UUID?
    @ObservationIgnored private var currentCreated = Date()
    @ObservationIgnored private var currentExported = false

    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var restoring = false
    @ObservationIgnored private var photosChanged = false

    /// Saves the open draft a moment after the last change.
    private func scheduleSave() {
        guard !restoring, currentDraftID != nil else { return }
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    /// Writes the open draft to disk straight away.
    @MainActor
    private func saveNow() {
        saveTask?.cancel()
        guard let id = currentDraftID, !entry.isEmpty else { return }
        let draft = DraftStore.Saved(state: self, created: currentCreated, exported: currentExported)
        var files: [DraftStore.PhotoFile]?
        if photosChanged {
            files = photos.map { DraftStore.PhotoFile(index: $0.index, data: $0.sourceData,
                                                      thumb: DraftStore.thumbnail(of: $0.preview)) }
            photosChanged = false
        }
        Task.detached(priority: .utility) { [weak self] in
            DraftStore.write(id: id, saved: draft, photos: files)
            await self?.refreshDrafts()
        }
    }

    /// A new scan or pick: whatever is drafted next becomes a new draft.
    @MainActor
    func detachDraft() {
        saveNow()
        currentDraftID = nil
    }

    /// After saving to the camera roll: marks the draft as done in the Drafts list.
    @MainActor
    func markExported() {
        currentExported = true
        saveNow()
    }

    /// After saving: back to the empty start page. The draft stays in the Drafts list.
    @MainActor
    func startNewEntry() {
        saveNow()
        currentDraftID = nil
        writingTask?.cancel()
        candidates = []
        selectionChanged = false
        errorMessage = nil
        path = []
        // Clear the screen once the pages showing it have closed.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self, self.path.isEmpty, self.currentDraftID == nil else { return }
            self.restoring = true
            self.entry = []
            self.leftOut = []
            self.photos = []
            self.savedImages = []
            self.restoring = false
        }
    }

    /// Reloads the Drafts list from disk.
    @MainActor
    func refreshDrafts() async {
        let raw = await Task.detached(priority: .utility) { DraftStore.list() }.value
        drafts = raw.map { DraftStore.Summary(raw: $0) }
    }

    /// Opens a saved draft.
    @MainActor
    func openDraft(_ id: UUID) async -> Bool {
        if id == currentDraftID, !entry.isEmpty { return true }
        guard let saved = DraftStore.readSaved(id: id) else {
            errorMessage = "Couldn't open that draft."
            return false
        }
        let indexes = saved.photoIndexes
        let files = await Task.detached(priority: .userInitiated) { DraftStore.readPhotos(id: id, indexes) }.value
        let loaded = files.compactMap { DiaryPhoto(index: $0.0, data: $0.1) }
        guard !loaded.isEmpty else {
            errorMessage = "Couldn't open that draft's photos."
            return false
        }
        saveNow()
        writingTask?.cancel()
        restoring = true
        defer { restoring = false }
        currentDraftID = id
        currentCreated = saved.createdAt ?? Date()
        currentExported = saved.exported ?? false
        photos = loaded
        entry = saved.items.map(\.entryItem)
        leftOut = saved.leftOut.map { LeftOut(photoIndex: $0.photoIndex, reason: $0.reason) }
        greetingOn = saved.greetingOn
        signoffOn = saved.signoffOn
        photosChanged = false
        return true
    }

    /// Deletes a saved draft (and clears it from the screen if it's the open one).
    @MainActor
    func deleteDraft(_ id: UUID) {
        if id == currentDraftID {
            saveTask?.cancel()
            writingTask?.cancel()
            currentDraftID = nil
            restoring = true
            entry = []
            leftOut = []
            photos = []
            restoring = false
        }
        withAnimation(.snappy) { drafts.removeAll { $0.id == id } }
        Task.detached(priority: .utility) { DraftStore.delete(id: id) }
    }

    /// On launch: moves an older single draft into the list, then loads the list.
    @MainActor
    func loadDrafts() async {
        await Task.detached(priority: .utility) { DraftStore.migrateOldDraft() }.value
        await refreshDrafts()
    }

    var isWorking = false
    var status = ""
    /// While drafting: the photo Apple's model is looking at now, and the ones it has finished.
    var lookingAt: UUID?
    var lookedAt: Set<UUID> = []
    var errorMessage: String?

    var look: Look = Look.load() {
        didSet { look.save() }
    }
    var city: String = UserDefaults.standard.string(forKey: "city") ?? "lisbon" {
        didSet { UserDefaults.standard.set(city, forKey: "city") }
    }
    /// The cities you've added; `city` is the selected one.
    var cities: [DiaryCity] = DiaryCity.loadAll() {
        didSet { DiaryCity.saveAll(cities) }
    }
    var currentCity: DiaryCity? { cities.first { $0.name == city } }
    /// No choosing: Claude when an API key is saved, otherwise Apple's free on-device model.
    var engine: DraftEngine {
        (Keychain.read() ?? "").isEmpty ? .apple : .claude
    }
    var model: String = UserDefaults.standard.string(forKey: "model") ?? "claude-sonnet-5-5" {
        didSet { UserDefaults.standard.set(model, forKey: "model") }
    }

    /// Captions still being written after the draft opened.
    @ObservationIgnored private var writingTask: Task<Void, Never>?

    /// Writes captions for each card in turn, filling them in as they arrive.
    @MainActor
    private func startWriting(_ picked: [(photo: DiaryPhoto, facts: AppleDrafter.Facts)]) {
        writingTask?.cancel()
        for i in entry.indices { entry[i].isWriting = true }
        let city = self.city
        writingTask = Task { @MainActor [weak self] in
            for pick in picked {
                if Task.isCancelled { return }
                let lines = (try? await AppleDrafter.writeLines(facts: pick.facts.prompt, city: city, note: "")) ?? []
                guard let self, let j = self.entry.firstIndex(where: { $0.photoIndex == pick.photo.index }) else { continue }
                self.entry[j].options = Array(lines.prefix(3))
                self.entry[j].spare = Array(lines.dropFirst(3))
                if self.entry[j].line.isEmpty { self.entry[j].line = lines.first ?? "" }
                self.entry[j].isWriting = false
            }
        }
    }

    /// Loads the selected photos and drafts the entry with Claude (if a key is saved) or Apple's model.
    @MainActor
    func runDraft() async -> Bool {
        errorMessage = nil
        let engine = self.engine
        let apiKey = Keychain.read() ?? ""
        if engine == .apple, let problem = AppleDrafter.availabilityProblem() {
            errorMessage = problem
            return false
        }
        isWorking = true
        lookingAt = nil
        lookedAt = []
        defer {
            isWorking = false
            lookingAt = nil
            lookedAt = []
        }

        do {
            let chosen = candidates.filter(\.included)
            var loaded: [DiaryPhoto] = []
            /// Which grid photo each loaded photo came from, for the "looking at" animation.
            var candidateFor: [Int: UUID] = [:]
            for (i, candidate) in chosen.enumerated() {
                status = "Loading \(i + 1) of \(chosen.count)…"
                var data = candidate.data
                if data == nil, let id = candidate.assetID {
                    data = await LibraryScanner.fullData(assetID: id)
                }
                if let data, let photo = DiaryPhoto(index: loaded.count + 1, data: data) {
                    loaded.append(photo)
                    candidateFor[photo.index] = candidate.id
                }
            }
            guard !loaded.isEmpty else {
                errorMessage = "Couldn't open those photos."
                return false
            }
            if currentDraftID == nil {
                currentDraftID = UUID()
                currentCreated = Date()
                currentExported = false
            }
            photos = loaded

            let result: ClaudeClient.DraftResult
            switch engine {
            case .claude:
                status = "Looking closely at \(loaded.count) photos…"
                result = try await ClaudeClient(apiKey: apiKey, model: model)
                    .draft(photos: loaded, city: city, note: "")
            case .apple:
                guard #available(iOS 27.0, *) else {
                    errorMessage = AppleDrafter.availabilityProblem()
                    return false
                }
                // Look and pick now; open the draft; write captions card by card in the background.
                let looked = try await AppleDrafter.lookAndPick(
                    photos: loaded,
                    looking: { [weak self] index in
                        guard let self else { return }
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                            if let previous = self.lookingAt { self.lookedAt.insert(previous) }
                            self.lookingAt = candidateFor[index]
                        }
                    },
                    progress: { [weak self] message in
                        self?.status = message
                    })
                withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                    if let last = lookingAt { lookedAt.insert(last) }
                    lookingAt = nil
                }
                apply(ClaudeClient.DraftResult(entry: AppleDrafter.entryItems(for: looked.picked),
                                               left_out: looked.leftOut))
                selectionChanged = false
                startWriting(looked.picked)
                return true
            }
            apply(result)
            selectionChanged = false
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func photo(_ index: Int) -> DiaryPhoto? {
        photos.first { $0.index == index }
    }

    /// "dear … diary," on the first photo / "until next time" on the last one.
    var greetingOn = true { didSet { scheduleSave() } }
    var signoffOn = true { didSet { scheduleSave() } }

    func caption(at position: Int) -> String {
        guard entry.indices.contains(position) else { return "" }
        return Caption.compose(line: entry[position].line, position: position, count: entry.count,
                               city: city, greeting: greetingOn, signoff: signoffOn)
    }

    /// Moves a photo to a new position (e.g. first or last).
    func move(id: UUID, to index: Int) {
        guard let i = entry.firstIndex(where: { $0.id == id }) else { return }
        let item = entry.remove(at: i)
        entry.insert(item, at: min(max(index, 0), entry.count))
    }

    func apply(_ result: ClaudeClient.DraftResult) {
        func clamp(_ v: Double) -> CGFloat { CGFloat(min(max(v, 0), 1)) }

        var used = Set<Int>()
        entry = result.entry.compactMap { (item) -> EntryItem? in
            guard photo(item.photo) != nil, !used.contains(item.photo) else { return nil }
            used.insert(item.photo)
            let options = Caption.distinct(item.lines.map(Caption.cleanLine).filter { !$0.isEmpty })
            return EntryItem(
                photoIndex: item.photo,
                options: options,
                line: options.first ?? "",
                whatISaw: item.what_i_saw,
                textPosition: TextPosition(rawValue: item.text_position) ?? .bottom,
                focus: CGPoint(x: clamp(item.focus_x), y: clamp(item.focus_y)),
                isWildcard: item.wildcard
            )
        }

        var skipped: [LeftOut] = []
        for skip in result.left_out where photo(skip.photo) != nil && !used.contains(skip.photo) {
            used.insert(skip.photo)
            skipped.append(LeftOut(photoIndex: skip.photo, reason: skip.reason))
        }
        // Anything Claude forgot to mention still shows up, so nothing gets lost.
        for p in photos where !used.contains(p.index) {
            skipped.append(LeftOut(photoIndex: p.index, reason: ""))
        }
        leftOut = skipped
        greetingOn = true
        signoffOn = true
    }

    func remove(id: UUID) {
        guard let i = entry.firstIndex(where: { $0.id == id }) else { return }
        leftOut.insert(LeftOut(photoIndex: entry[i].photoIndex, reason: "You took this out"), at: 0)
        entry.remove(at: i)
    }

    func move(id: UUID, by offset: Int) {
        guard let i = entry.firstIndex(where: { $0.id == id }) else { return }
        let j = i + offset
        guard entry.indices.contains(j) else { return }
        entry.swapAt(i, j)
    }

    /// Adds a left-out photo back into the entry at `index`.
    @discardableResult
    func add(_ item: LeftOut, at index: Int) -> EntryItem {
        let new = EntryItem(
            photoIndex: item.photoIndex,
            options: [],
            line: "",
            whatISaw: item.reason.isEmpty ? "You added this one" : item.reason,
            textPosition: .bottom,
            focus: CGPoint(x: 0.5, y: 0.5),
            isWildcard: false
        )
        leftOut.removeAll { $0.id == item.id }
        entry.insert(new, at: min(max(index, 0), entry.count))
        return new
    }
}

// MARK: - Helpers

enum ImageLoader {
    /// Decodes and shrinks an image in one step, with orientation baked in.
    static func downsample(_ data: Data, maxPixel: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ] as CFDictionary
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return UIImage(cgImage: cg)
    }
}

enum Keychain {
    private static let service = "com.example.deardiary"
    private static let account = "anthropic-api-key"

    static func save(_ value: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(base as CFDictionary)
        guard !value.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }

    static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Saved drafts

/// Drafts on disk: one folder each, with the photos as files and everything else in one small JSON file.
enum DraftStore {
    struct Item: Codable {
        var photoIndex: Int
        var options: [String]
        var line: String
        var whatISaw: String
        var textPosition: String
        var focusX: Double
        var focusY: Double
        var isWildcard: Bool
        var adjust: [Double]
        var spare: [String]?

        init(_ item: EntryItem) {
            photoIndex = item.photoIndex
            options = item.options
            line = item.line
            whatISaw = item.whatISaw
            textPosition = item.textPosition.rawValue
            focusX = item.focus.x
            focusY = item.focus.y
            isWildcard = item.isWildcard
            let a = item.adjust
            adjust = [a.exposure, a.shadows, a.saturation, a.warmth, a.shade]
            spare = item.spare
        }

        var entryItem: EntryItem {
            var item = EntryItem(photoIndex: photoIndex, options: options, line: line, whatISaw: whatISaw,
                                 textPosition: TextPosition(rawValue: textPosition) ?? .top,
                                 focus: CGPoint(x: focusX, y: focusY), isWildcard: isWildcard)
            if adjust.count == 5 {
                item.adjust = PhotoAdjust(exposure: adjust[0], shadows: adjust[1], saturation: adjust[2],
                                          warmth: adjust[3], shade: adjust[4])
            }
            item.spare = spare ?? []
            return item
        }
    }

    struct Skipped: Codable {
        var photoIndex: Int
        var reason: String
    }

    struct Saved: Codable {
        var items: [Item]
        var leftOut: [Skipped]
        var photoIndexes: [Int]
        var greetingOn: Bool
        var signoffOn: Bool
        // Optional so drafts saved by the previous version still open.
        var createdAt: Date?
        var updatedAt: Date?
        var exported: Bool?
        var city: String?

        init(state: AppState, created: Date, exported: Bool) {
            items = state.entry.map(Item.init)
            leftOut = state.leftOut.map { Skipped(photoIndex: $0.photoIndex, reason: $0.reason) }
            photoIndexes = state.photos.map(\.index)
            greetingOn = state.greetingOn
            signoffOn = state.signoffOn
            createdAt = created
            updatedAt = Date()
            self.exported = exported
            city = state.city
        }
    }

    struct PhotoFile {
        var index: Int
        var data: Data
        var thumb: Data?
    }

    /// One row in the Drafts list, as read from disk.
    struct RawSummary {
        var id: UUID
        var saved: Saved
        var thumbs: [Data]
    }

    /// One row in the Drafts list.
    struct Summary: Identifiable {
        var id: UUID
        var title: String
        var photoCount: Int
        var date: Date
        var exported: Bool
        var thumbs: [UIImage]

        init(raw: RawSummary) {
            id = raw.id
            let first = raw.saved.items.map(\.line).first { !$0.isEmpty } ?? ""
            title = first.isEmpty ? "dear \(raw.saved.city ?? "lisbon") diary" : first
            photoCount = raw.saved.items.count
            date = raw.saved.updatedAt ?? raw.saved.createdAt ?? .distantPast
            exported = raw.saved.exported ?? false
            thumbs = raw.thumbs.compactMap(UIImage.init(data:))
        }
    }

    private static var root: URL {
        URL.applicationSupportDirectory.appending(path: "Drafts", directoryHint: .isDirectory)
    }
    private static func folder(_ id: UUID) -> URL {
        root.appending(path: id.uuidString, directoryHint: .isDirectory)
    }
    private static func jsonURL(_ id: UUID) -> URL { folder(id).appending(path: "draft.json") }
    private static func photoURL(_ id: UUID, _ index: Int) -> URL { folder(id).appending(path: "photo-\(index).data") }
    private static func thumbURL(_ id: UUID, _ index: Int) -> URL { folder(id).appending(path: "thumb-\(index).jpg") }

    /// A small JPEG for the Drafts list.
    static func thumbnail(of image: UIImage) -> Data? {
        let longest = max(image.size.width, image.size.height)
        guard longest > 0 else { return nil }
        let scale = 240 / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return image.preparingThumbnail(of: size)?.jpegData(compressionQuality: 0.7)
    }

    static func write(id: UUID, saved: Saved, photos: [PhotoFile]?) {
        let fm = FileManager.default
        let dir = folder(id)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        if let photos {
            // Replace the photo files with the new set.
            if let old = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
                for url in old where url.pathExtension == "data" || url.pathExtension == "jpg" {
                    try? fm.removeItem(at: url)
                }
            }
            for photo in photos {
                try? photo.data.write(to: photoURL(id, photo.index), options: .atomic)
                try? photo.thumb?.write(to: thumbURL(id, photo.index), options: .atomic)
            }
        }
        if let json = try? JSONEncoder().encode(saved) {
            try? json.write(to: jsonURL(id), options: .atomic)
        }
    }

    static func readSaved(id: UUID) -> Saved? {
        guard let data = try? Data(contentsOf: jsonURL(id)),
              let saved = try? JSONDecoder().decode(Saved.self, from: data),
              !saved.items.isEmpty else { return nil }
        return saved
    }

    static func readPhotos(id: UUID, _ indexes: [Int]) -> [(Int, Data)] {
        indexes.compactMap { index in
            (try? Data(contentsOf: photoURL(id, index))).map { (index, $0) }
        }
    }

    /// Every draft on disk, newest first, with small pictures of its first photos.
    static func list() -> [RawSummary] {
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return [] }
        let found: [RawSummary] = dirs.compactMap { dir in
            guard let id = UUID(uuidString: dir.lastPathComponent) else { return nil }
            guard var saved = readSaved(id: id),
                  saved.photoIndexes.contains(where: { fm.fileExists(atPath: photoURL(id, $0).path) }) else {
                // Unreadable, or saved without its photos by an earlier version: nothing to open.
                try? fm.removeItem(at: dir)
                return nil
            }
            if saved.updatedAt == nil {
                // Drafts from the earlier version have no date; use when the file was last written.
                saved.updatedAt = (try? fm.attributesOfItem(atPath: jsonURL(id).path))?[.modificationDate] as? Date
            }
            let thumbs = saved.items.prefix(4).compactMap { item -> Data? in
                if let data = try? Data(contentsOf: thumbURL(id, item.photoIndex)) { return data }
                // Drafts saved before thumbnails existed: make one from the photo.
                guard let source = try? Data(contentsOf: photoURL(id, item.photoIndex)),
                      let small = ImageLoader.downsample(source, maxPixel: 240),
                      let jpeg = small.jpegData(compressionQuality: 0.7) else { return nil }
                try? jpeg.write(to: thumbURL(id, item.photoIndex), options: .atomic)
                return jpeg
            }
            return RawSummary(id: id, saved: saved, thumbs: thumbs)
        }
        return found.sorted {
            ($0.saved.updatedAt ?? .distantPast) > ($1.saved.updatedAt ?? .distantPast)
        }
    }

    static func delete(id: UUID) {
        try? FileManager.default.removeItem(at: folder(id))
    }

    /// The previous version kept one draft in "Draft"; move it into the list.
    static func migrateOldDraft() {
        let fm = FileManager.default
        let old = URL.applicationSupportDirectory.appending(path: "Draft", directoryHint: .isDirectory)
        guard fm.fileExists(atPath: old.path) else { return }
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        try? fm.moveItem(at: old, to: folder(UUID()))
    }
}
