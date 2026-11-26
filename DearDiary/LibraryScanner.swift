import SwiftUI
import Photos
import Vision
import CoreLocation
import UIKit
import ImageIO

/// Why a photo was left out before anything is sent to Claude.
enum SkipReason: String {
    case face = "Face"
    case frontCamera = "Front camera"
    case notCamera = "Saved image"
    case similar = "Similar"
    case elsewhere = "Other city"
    case document = "Document"
}

/// A photo from your library or picker, before drafting.
struct Candidate: Identifiable {
    let id = UUID()
    /// Set for photos found by scanning; the full file is loaded only if it's used.
    let assetID: String?
    /// Set for photos you picked by hand.
    var data: Data?
    let thumb: UIImage
    /// When the photo was taken (scans only); used to compare near-duplicates.
    var date: Date? = nil
    var skipReason: SkipReason?
    var included: Bool
}

enum ScanRange: String, CaseIterable, Identifiable {
    case week = "last week"
    case month = "last month"

    var id: String { rawValue }
    /// Shown on the chips.
    var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    var start: Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        switch self {
        case .week: return calendar.date(byAdding: .day, value: -6, to: today) ?? today
        case .month: return calendar.date(byAdding: .month, value: -1, to: today) ?? today
        }
    }
}

// MARK: - Filters (all on-device)

enum PhotoFilter {
    /// The lens the photo was taken with, e.g. "iPhone 16 Pro back triple camera 6.765mm f/1.78".
    static func lensModel(of data: Data) -> String? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return lensModel(from: source)
    }

    static func lensModel(at url: URL) -> String? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return lensModel(from: source)
    }

    private static func lensModel(from source: CGImageSource) -> String? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] else { return nil }
        return exif[kCGImagePropertyExifLensModel] as? String
    }

    /// True when Vision finds a human face (anything bigger than ~2% of the image width).
    static func hasFace(_ image: UIImage) -> Bool {
        guard let cg = image.cgImage else { return false }
        let request = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: cg,
                                            orientation: CGImagePropertyOrientation(image.imageOrientation),
                                            options: [:])
        do {
            try handler.perform([request])
        } catch {
            return false
        }
        return (request.results ?? []).contains { $0.confidence >= 0.5 && $0.boundingBox.width >= 0.02 }
    }

    /// `requireCamera`: when scanning, images with no camera info (downloads, saved images, your own exports) are skipped too.
    static func check(lens: String?, thumb: UIImage, requireCamera: Bool) -> SkipReason? {
        let lens = lens?.lowercased()
        if let lens, lens.contains("front") { return .frontCamera }
        if requireCamera && lens == nil { return .notCamera }
        if hasFace(thumb) { return .face }
        if isDocument(thumb) { return .document }
        return nil
    }

    /// True for photos of papers, receipts, screens and menus: Vision finds a document shape
    /// filling much of the frame, or a lot of text. A sign or graffiti with a few words passes.
    static func isDocument(_ image: UIImage) -> Bool {
        guard let cg = image.cgImage else { return false }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        let documentRequest = VNDetectDocumentSegmentationRequest()
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .fast
        textRequest.usesLanguageCorrection = false
        try? VNImageRequestHandler(cgImage: cg, orientation: orientation, options: [:])
            .perform([documentRequest, textRequest])

        let words = (textRequest.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .flatMap { $0.split(separator: " ") }
            .count
        if words >= 18 { return true }

        if let doc = documentRequest.results?.first, doc.confidence > 0.9 {
            let box = doc.boundingBox
            if box.width * box.height > 0.3 && words >= 4 { return true }
        }
        return false
    }
}

// MARK: - Near-duplicates (on-device)

enum SimilarityFilter {
    /// How alike two photos must be to count as "the same shot" (Vision feature-print distance).
    static let maxDistance: Float = 0.4
    /// Photos taken further apart than this are never grouped, even if they look alike.
    static let timeWindow: TimeInterval = 20 * 60

    /// Among the included photos, finds groups of near-identical shots and keeps only the
    /// best-looking one of each group (Apple's aesthetics score). The rest are marked "similar".
    static func keepBestOfSimilar(_ candidates: inout [Candidate]) {
        let included = candidates.indices.filter { candidates[$0].included }
        guard included.count > 1 else { return }
        let prints = included.map { featurePrint(candidates[$0].thumb) }

        var parent = Array(0..<included.count)
        func root(_ x: Int) -> Int {
            var x = x
            while parent[x] != x {
                parent[x] = parent[parent[x]]
                x = parent[x]
            }
            return x
        }

        for a in 0..<included.count {
            for b in (a + 1)..<included.count {
                guard let printA = prints[a], let printB = prints[b] else { continue }
                if let dateA = candidates[included[a]].date, let dateB = candidates[included[b]].date,
                   abs(dateA.timeIntervalSince(dateB)) > timeWindow { continue }
                var distance: Float = .greatestFiniteMagnitude
                do { try printA.computeDistance(&distance, to: printB) } catch { continue }
                if distance < maxDistance {
                    parent[root(b)] = root(a)
                }
            }
        }

        var groups: [Int: [Int]] = [:]
        for k in 0..<included.count {
            groups[root(k), default: []].append(k)
        }
        for members in groups.values where members.count > 1 {
            let scores = members.map { quality(candidates[included[$0]].thumb) }
            guard let bestPosition = scores.indices.max(by: { scores[$0] < scores[$1] }) else { continue }
            for (position, member) in members.enumerated() where position != bestPosition {
                candidates[included[member]].included = false
                candidates[included[member]].skipReason = .similar
            }
        }
    }

    static func featurePrint(_ image: UIImage) -> VNFeaturePrintObservation? {
        guard let cg = image.cgImage else { return nil }
        let request = VNGenerateImageFeaturePrintRequest()
        request.imageCropAndScaleOption = .scaleFill
        let handler = VNImageRequestHandler(cgImage: cg,
                                            orientation: CGImagePropertyOrientation(image.imageOrientation),
                                            options: [:])
        try? handler.perform([request])
        return request.results?.first
    }

    /// Apple's on-device "how good is this photo" score (sharpness, exposure, composition), -1…1.
    static func quality(_ image: UIImage) -> Float {
        guard let cg = image.cgImage else { return 0 }
        let request = VNCalculateImageAestheticsScoresRequest()
        let handler = VNImageRequestHandler(cgImage: cg,
                                            orientation: CGImagePropertyOrientation(image.imageOrientation),
                                            options: [:])
        try? handler.perform([request])
        return request.results?.first?.overallScore ?? 0
    }
}

// MARK: - Library scanning

enum LibraryScanner {
    /// The most photos sent to Claude at once.
    static let maxIncluded = 40
    /// Photos taken further than this from the diary's city are skipped.
    static let cityRadius: CLLocationDistance = 35_000

    /// The most photos looked at in one scan (spread evenly over the range).
    static let maxScanned = 600

    static func requestAccess() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return status == .authorized || status == .limited
    }

    struct Result {
        var candidates: [Candidate]
        var screenshots: Int
    }

    static func scan(_ range: ScanRange, city: DiaryCity?, progress: @escaping @MainActor (String) -> Void) async -> Result {
        let options = PHFetchOptions()
        // Photos only: videos never even get fetched.
        options.predicate = NSPredicate(format: "mediaType == %d AND creationDate >= %@",
                                        PHAssetMediaType.image.rawValue, range.start as NSDate)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]

        var assets: [PHAsset] = []
        PHAsset.fetchAssets(with: options).enumerateObjects { asset, _, _ in assets.append(asset) }

        let screenshots = assets.filter { $0.mediaSubtypes.contains(.photoScreenshot) }.count
        assets.removeAll { $0.mediaSubtypes.contains(.photoScreenshot) }
        if assets.count > maxScanned {
            let step = Double(assets.count) / Double(maxScanned)
            assets = (0..<maxScanned).map { assets[Int(Double($0) * step)] }
        }

        var candidates: [Candidate] = []
        for (i, asset) in assets.enumerated() {
            await progress("Checking \(i + 1) of \(assets.count)…")
            guard let thumb = await thumbnail(asset) else { continue }
            var reason: SkipReason?
            // Taken somewhere else? (Photos without a location are kept.)
            if let center = city?.location, let place = asset.location,
               place.distance(from: center) > cityRadius {
                reason = .elsewhere
            } else {
                let lens = await lensModel(asset)
                reason = PhotoFilter.check(lens: lens, thumb: thumb, requireCamera: true)
            }
            candidates.append(Candidate(assetID: asset.localIdentifier, data: nil, thumb: thumb,
                                        date: asset.creationDate,
                                        skipReason: reason, included: reason == nil))
        }

        // Several shots of the same thing: keep only the best one.
        await progress("Comparing similar photos…")
        SimilarityFilter.keepBestOfSimilar(&candidates)

        // Too many keepers: spread the selection evenly through the time range.
        let kept = candidates.indices.filter { candidates[$0].included }
        if kept.count > maxIncluded {
            let step = Double(kept.count) / Double(maxIncluded)
            let chosen = Set((0..<maxIncluded).map { kept[Int(Double($0) * step)] })
            for i in kept where !chosen.contains(i) {
                candidates[i].included = false
            }
        }

        return Result(candidates: candidates, screenshots: screenshots)
    }

    static func thumbnail(_ asset: PHAsset, side: CGFloat = 512) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isNetworkAccessAllowed = true
            PHImageManager.default().requestImage(for: asset,
                                                  targetSize: CGSize(width: side, height: side),
                                                  contentMode: .aspectFit,
                                                  options: options) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    /// Reads only the file's metadata, not the pixels.
    static func lensModel(_ asset: PHAsset) async -> String? {
        await withCheckedContinuation { continuation in
            let options = PHContentEditingInputRequestOptions()
            options.isNetworkAccessAllowed = true
            asset.requestContentEditingInput(with: options) { input, _ in
                guard let url = input?.fullSizeImageURL else {
                    continuation.resume(returning: nil)
                    return
                }
                continuation.resume(returning: PhotoFilter.lensModel(at: url))
            }
        }
    }

    static func fullData(assetID: String) async -> Data? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil).firstObject else { return nil }
        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.version = .current
            options.isNetworkAccessAllowed = true
            PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
                continuation.resume(returning: data)
            }
        }
    }
}

extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

// MARK: - Selection page

/// After a scan: every photo found, the chosen ones bright and checked, skipped ones dimmed
/// with the reason. Tap to change the selection, then draft.
struct SelectionView: View {
    @Environment(AppState.self) private var state
    private let columns = [GridItem(.flexible(), spacing: 3), GridItem(.flexible(), spacing: 3), GridItem(.flexible(), spacing: 3)]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: 3) {
                    ForEach(state.candidates.indices, id: \.self) { i in
                        cell(i)
                            .id(state.candidates[i].id)
                    }
                }
                .padding(.bottom, 24)
            }
            // Follows the photo being looked at.
            .onChange(of: state.lookingAt) { _, id in
                guard let id else { return }
                withAnimation(.smooth(duration: 0.6)) { proxy.scrollTo(id, anchor: .center) }
            }
        }
        .allowsHitTesting(!state.isWorking)
        .sensoryFeedback(.selection, trigger: state.lookingAt)
        .scrollEdgeEffectStyle(.soft, for: .all)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("\(state.includedCount) of \(state.candidates.count) selected")
        .navigationBarTitleDisplayMode(.inline)
        .backButtonOnly()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // Clear everything to pick by hand, or bring back the app's suggestions.
                Button(state.includedCount > 0 ? "Deselect all" : "Select suggested") {
                    Haptics.tap()
                    let clear = state.includedCount > 0
                    withAnimation(.snappy) {
                        for i in state.candidates.indices {
                            state.candidates[i].included = clear ? false : state.candidates[i].skipReason == nil
                        }
                    }
                    state.selectionChanged = true
                }
                .font(Theme.font(15))
                .foregroundStyle(Theme.ink)
                .disabled(state.isWorking)
            }
        }
        .safeAreaBar(edge: .bottom) {
            VStack(spacing: 10) {
                if state.isWorking {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small).tint(Theme.ink)
                        Text(state.status)
                            .font(Theme.font(13))
                            .foregroundStyle(Theme.muted)
                            .contentTransition(.numericText())
                            .animation(.snappy, value: state.status)
                    }
                } else if let error = state.errorMessage {
                    Text(error)
                        .font(Theme.font(13))
                        .foregroundStyle(Color(red: 1, green: 0.55, blue: 0.5))
                        .multilineTextAlignment(.center)
                }
                Button {
                    Haptics.bump(.medium)
                    Task {
                        if await state.runDraft() {
                            Haptics.success()
                            state.path.append(.draft)
                        } else {
                            Haptics.error()
                        }
                    }
                } label: {
                    Label("Draft entry", systemImage: "sparkles")
                }
                .buttonStyle(PillButtonStyle())
                .disabled(state.includedCount == 0 || state.isWorking)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
        .onAppear {
            state.errorMessage = nil
            // Load Apple's model while you're choosing, so drafting starts faster.
            AppleDrafter.prewarm()
        }
    }

    /// One photo in the grid. While drafting, the chosen photos wait small and dim, the one being
    /// looked at comes forward with a light sweeping over it, and finished ones get their tick back.
    private func cell(_ i: Int) -> some View {
        let candidate = state.candidates[i]
        let drafting = state.isWorking && candidate.included
        let looking = drafting && state.lookingAt == candidate.id
        let done = drafting && state.lookedAt.contains(candidate.id)
        let waiting = drafting && !looking && !done
        return Button {
            Haptics.tap()
            withAnimation(.snappy) {
                state.candidates[i].included.toggle()
            }
            state.selectionChanged = true
        } label: {
            Color.clear
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                .overlay {
                    Image(uiImage: candidate.thumb)
                        .resizable()
                        .scaledToFill()
                }
                .overlay {
                    if looking { ScanSweep().transition(.opacity) }
                }
                .clipShape(RoundedRectangle(cornerRadius: looking ? 10 : 0, style: .continuous))
                .overlay {
                    if looking {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(.white.opacity(0.9), lineWidth: 2)
                            .shadow(color: .white.opacity(0.6), radius: 10)
                            .transition(.opacity)
                    }
                }
                .opacity(candidate.included ? (waiting ? 0.5 : 1) : (state.isWorking ? 0.15 : 0.32))
                .scaleEffect(waiting ? 0.9 : 1)
                .overlay(alignment: .topTrailing) {
                    // While drafting, the ticks come back one by one as each photo is done.
                    if candidate.included && (!drafting || done) {
                        Image(systemName: "checkmark")
                            .font(Theme.font(12, .semibold))
                            .foregroundStyle(.black)
                            .frame(width: 24, height: 24)
                            .glassEffect(.regular.tint(.white), in: Circle())
                            .padding(7)
                            .transition(.scale(scale: 0.3).combined(with: .opacity))
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if !candidate.included, !state.isWorking, let reason = candidate.skipReason {
                        Text(reason.rawValue)
                            .font(Theme.font(11))
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .glassEffect(.regular, in: Capsule())
                            .padding(7)
                            .transition(.opacity)
                    }
                }
                .zIndex(looking ? 1 : 0)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: state.isWorking)
    }
}

/// A soft band of light moving up and down over a photo, as if it's being read.
private struct ScanSweep: View {
    @State private var down = false

    var body: some View {
        GeometryReader { geo in
            LinearGradient(colors: [.clear, .white.opacity(0.28), .clear],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: geo.size.height * 0.4)
                .offset(y: down ? geo.size.height * 0.8 : -geo.size.height * 0.2)
                .blendMode(.plusLighter)
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) { down = true }
        }
    }
}
