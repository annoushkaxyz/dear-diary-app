import Foundation
import UIKit
import Vision
import FoundationModels

/// Which AI writes the draft. Apple's runs on the phone for free; Claude needs an API key.
enum DraftEngine: String, CaseIterable, Identifiable {
    case apple, claude
    var id: String { rawValue }
}

/// What Apple's on-device model returns for one photo.
/// The small model writes better lines when each option follows a concrete recipe,
/// so the three options are three different angles rather than three free-form tries.
@available(iOS 26.0, *)
@Generable
struct PhotoRead {
    @Guide(description: "One plain sentence: the small overlooked thing in this photo that could have a personality (a stain, crack, shadow, plant, object, sign, building detail), and where it is in the frame.")
    var whatISaw: String

    @Guide(description: "That thing in 1 to 4 plain lowercase words, e.g. 'the road', 'a little plant', 'an umbrella', 'two trees'.")
    var thing: String

    @Guide(description: "The thing as a character doing something only a person would do. Pattern: '<thing> was <human activity>'. Like: 'a road was having a meltdown', 'a stairwell needed a smoke break', 'a shy house was hiding behind the flowers', 'this building was day dreaming'.")
    var asCharacter: String

    @Guide(description: "A DIFFERENT idea from the character line, with a different verb, ideally about a different detail in the photo: something pretending, practicing or dressing up as something else it resembles. Like: 'some figs were pretending to be tennis balls', 'a mirror was practicing being pavement', 'a flower was wearing its boxing gloves', 'the building was shedding its skin'.")
    var asPretend: String

    @Guide(description: "A third, unexpected idea, different from both lines above: a tiny drama, rivalry, relationship, wish or failure. Like: 'two trees chose completely different paths in life', 'these hands confessed their love to strangers', 'a little plant tried to look scary and it almost worked', 'a car got into a fight and ended up with a black eye'.")
    var asDrama: String

    @Guide(description: "How surprising and characterful this moment is, from 0 (nothing there) to 10 (a perfect tiny drama).", .range(0...10))
    var score: Int
}

/// A plain, literal inventory of a photo, written before any jokes, so the captions stay grounded.
@available(iOS 26.0, *)
@Generable
struct PhotoFacts {
    @Guide(description: "One or two plain sentences describing exactly what is in the photo, as if to someone who can't see it: what the main things are, where they are, what they look like. Be specific and accurate. No jokes, no interpretation.")
    var summary: String

    @Guide(description: "What things in the photo could be mistaken for at a glance, because of their shape, colour or position: a face, an animal, a creature, a person, a gesture, an object. Each as 'X looks like Y', e.g. 'the crane looks like a giraffe', 'the stain looks like a small dinosaur'. Only real visual similarity; empty if there is none.", .maximumCount(3))
    var resemblances: [String]

    @Guide(description: "Plain names of the things actually visible, most prominent first, e.g. 'cobblestones', 'a dandelion', 'an orange peel', 'a parked car'. Only what you can really see.", .maximumCount(8))
    var things: [String]

    @Guide(description: "Where this is, in a few plain words, e.g. 'a pavement', 'a tiled wall', 'a café table'.")
    var setting: String

    @Guide(description: "Small details worth noticing: shapes, stains, cracks, shadows, textures, colours, anything that looks like a face or a creature.", .maximumCount(5))
    var details: [String]

    @Guide(description: "How much this photo has a small, surprising, characterful thing in it, from 0 (nothing there) to 10 (a perfect tiny drama).", .range(0...10))
    var interest: Int
}

/// Ideas first, then lines. The model fills properties in order, so writing the ideas
/// first works as a short think-before-you-write step, which helps the small model a lot.
@available(iOS 26.0, *)
@Generable
struct IdeaDraft {
    @Guide(description: "Three short ideas, each about a DIFFERENT thing in the photo. Each idea is one plain sentence: what the thing resembles because of its shape, colour or position, or what a person might be doing in its place. Example ideas: 'the crane is tall and thin like a giraffe', 'the bike on the roof rack is riding on the car like a child on shoulders', 'the cracked asphalt is falling apart like someone losing their temper'. Only things in the description. One short sentence each.", .count(3))
    var ideas: [String]

    @Guide(description: "Six caption lines, two for each idea, written exactly in the style of her lines: a real thing from the photo, named plainly, doing, wanting or feeling something that fits how it looks. A reader must get it instantly; if you couldn't explain the joke in one short sentence, write a simpler line. All lowercase, 4 to 12 words, past tense, no 'like', no end punctuation.", .count(6))
    var lines: [String]

    @Guide(description: "One simple, true diary line about the main thing in the photo, with no joke, e.g. 'i met a giant colourful horse in front of a tower'. All lowercase, past tense, no end punctuation.")
    var plain: String
}

/// A sober second look at candidate lines: does each one make sense?
@available(iOS 26.0, *)
@Generable
struct LineReview {
    @Guide(description: "The number of the line being reviewed.")
    var number: Int

    @Guide(description: "What the line means, in at most 8 plain words. If it doesn't make sense, write 'unclear'.")
    var meaning: String

    @Guide(description: "Would a reader instantly understand it and see how it fits the photo? 0 = nonsense or confusing, 5 = needs thinking, 10 = instantly clear and fitting.", .range(0...10))
    var clarity: Int
}

@available(iOS 26.0, *)
@Generable
struct LineReviews {
    @Guide(description: "One review for every numbered line, in order.", .maximumCount(10))
    var reviews: [LineReview]
}

/// The editor's pick among several candidate lines.
@available(iOS 26.0, *)
@Generable
struct Ranking {
    @Guide(description: "The numbers of the three best lines, best first.", .count(3))
    var best: [Int]
}

/// Her own line, understood first, then said three better ways. Filled in order, so the model
/// has to work out what she means before it writes anything.
@available(iOS 26.0, *)
@Generable
struct Rephrase {
    @Guide(description: "Who or what her line is about, in her own words, e.g. 'the giant cat', 'the road'.")
    var subject: String

    @Guide(description: "What she is saying about it, in one plain sentence, keeping her meaning exactly. Don't add anything.")
    var meaning: String

    @Guide(description: "Three new ways to say exactly what she means, best first. Same subject, same idea, only different words: sharper, funnier or more vivid. Never add a new action or a new idea. All lowercase, past tense, 4 to 12 words, no end punctuation.", .count(3))
    var lines: [String]
}

/// A proofread version of a caption you wrote yourself.
@available(iOS 26.0, *)
@Generable
struct GrammarCheck {
    @Guide(description: "The same caption with only grammar and spelling mistakes fixed. Keep her words, word order and style, all lowercase, no end punctuation. If nothing is wrong, return it exactly as it was.")
    var corrected: String

    @Guide(description: "Empty if the caption reads clearly. Otherwise one short plain sentence saying what is confusing (a missing word, unclear who did what, a tense mix-up). The series is deliberately absurd: objects acting like people, wanting things or having feelings is intended and never confusing.")
    var note: String
}

@available(iOS 26.0, *)
extension PhotoRead {
    var lines: [String] { [asCharacter, asPretend, asDrama] }
}

/// Every model call has a token cap, so a reply that starts repeating itself stops quickly
/// (and falls back) instead of running on for minutes.
/// Drafts an entry with Apple's on-device model, one photo at a time
/// (the on-device model only has room for one photo per request).
enum AppleDrafter {
    /// The most photos in one entry.
    static let maxPicks = 8
    /// Photos scoring below this are left out (unless that would leave fewer than 3).
    static let minScore = 5

    struct DrafterError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// nil when Apple's model is ready; otherwise a message saying what to do.
    static func availabilityProblem() -> String? {
        if #available(iOS 27.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return nil
            case .unavailable(let reason):
                switch reason {
                case .deviceNotEligible:
                    return "This iPhone can't run Apple Intelligence."
                case .appleIntelligenceNotEnabled:
                    return "Turn on Apple Intelligence in Settings › Apple Intelligence & Siri, then try again."
                case .modelNotReady:
                    return "Apple's model is still downloading. Try again in a little while."
                @unknown default:
                    return "Apple's model isn't available right now."
                }
            @unknown default:
                return "Apple's model isn't available right now."
            }
        }
        return "The free Apple model needs iOS 27. Update your iPhone."
    }

    typealias Facts = (description: String, prompt: String, interest: Int)

    /// Loads Apple's model into memory ahead of time, so the first request starts faster.
    static func prewarm() {
        if case .available = SystemLanguageModel.default.availability {
            LanguageModelSession().prewarm()
        }
    }

    /// Steps 1–2: look at every photo once (with an interest score), then keep the best ones
    /// in the order you took them. Fast enough to open the draft straight after.
    @available(iOS 27.0, *)
    static func lookAndPick(photos: [DiaryPhoto],
                            looking: @escaping @MainActor (Int) -> Void = { _ in },
                            progress: @escaping @MainActor (String) -> Void) async throws
        -> (picked: [(photo: DiaryPhoto, facts: Facts)], leftOut: [ClaudeClient.DraftResult.Skip]) {
        var looked: [(photo: DiaryPhoto, facts: Facts)] = []
        var leftOut: [ClaudeClient.DraftResult.Skip] = []
        for (i, photo) in photos.enumerated() {
            await progress("Looking at \(i + 1) of \(photos.count)…")
            await looking(photo.index)
            let facts = await groundedFacts(for: photo)
            if facts.prompt.isEmpty {
                leftOut.append(.init(photo: photo.index, reason: "Apple's model couldn't read this one"))
            } else {
                looked.append((photo, facts))
            }
        }
        guard !looked.isEmpty else {
            throw DrafterError(message: "Apple's model couldn't read any of these photos. Try again.")
        }
        let ranked = looked.sorted { $0.facts.interest > $1.facts.interest }
        var picked = Array(ranked.filter { $0.facts.interest >= minScore }.prefix(maxPicks))
        if picked.count < 3 {
            picked = Array(ranked.prefix(min(3, ranked.count)))
        }
        picked.sort { $0.photo.index < $1.photo.index }
        let pickedIndexes = Set(picked.map { $0.photo.index })
        for l in looked where !pickedIndexes.contains(l.photo.index) {
            leftOut.append(.init(photo: l.photo.index, reason: "\(l.facts.interest)/10 · \(l.facts.description)"))
        }
        return (picked, leftOut)
    }

    /// Entry cards for the picked photos (captions arrive later), with crop and text placement.
    static func entryItems(for picked: [(photo: DiaryPhoto, facts: Facts)],
                           lines: [Int: [String]] = [:]) -> [ClaudeClient.DraftResult.Item] {
        picked.map { (pick) -> ClaudeClient.DraftResult.Item in
            let focus = salientCenter(pick.photo.preview) ?? CGPoint(x: 0.5, y: 0.5)
            return ClaudeClient.DraftResult.Item(
                photo: pick.photo.index,
                lines: lines[pick.photo.index] ?? [],
                what_i_saw: pick.facts.description,
                // Put the text away from the thing it's about.
                text_position: focus.y < 0.5 ? "bottom" : "top",
                focus_x: Double(focus.x),
                focus_y: Double(focus.y),
                wildcard: false
            )
        }
    }

    @available(iOS 27.0, *)
    static func draft(photos: [DiaryPhoto],
                      city: String,
                      note: String,
                      progress: @escaping @MainActor (String) -> Void) async throws -> ClaudeClient.DraftResult {
        let result = try await lookAndPick(photos: photos, progress: progress)
        var lines: [Int: [String]] = [:]
        for (i, pick) in result.picked.enumerated() {
            await progress("Writing \(i + 1) of \(result.picked.count)…")
            lines[pick.photo.index] = Array(((try? await writeLines(facts: pick.facts.prompt, city: city, note: note)) ?? []).prefix(3))
        }
        let items = entryItems(for: result.picked, lines: lines)
        let leftOut = result.leftOut
        return ClaudeClient.DraftResult(entry: items, left_out: leftOut)
    }

    /// Three fresh caption options for one photo (or three lines building on yours).
    @available(iOS 27.0, *)
    static func moreLines(for photo: DiaryPhoto, city: String, avoid: [String], hint: String? = nil,
                          known description: String = "") async throws -> [String] {
        if let hint, !hint.trimmingCharacters(in: .whitespaces).isEmpty {
            return try await rephrase(hint, city: city)
        }
        // Looking at the photo again is the slow part. If it was looked at this session, reuse that;
        // for a reopened draft, the saved description is enough to write from.
        let facts: String
        if let cached = factsCache[photo.id] {
            facts = cached.prompt
        } else if !description.isEmpty {
            facts = "What is actually in the photo: \(description)"
        } else {
            facts = await groundedFacts(for: photo).prompt
        }
        return try await writeLines(facts: facts, city: city, note: "", avoid: avoid)
    }

    /// "Build on mine": keeps her idea and says it better. Her line is the truth about the photo,
    /// so the photo description isn't used here (the model sometimes gets the photo wrong).
    static func rephrase(_ line: String, city: String) async throws -> [String] {
        let mine = Caption.cleanLine(line)
        let session = LanguageModelSession(instructions: """
        You help her polish her own captions for "dear \(city) diary", a photo series where ordinary things \
        in the city are treated as characters with inner lives. She writes a rough line; you keep her subject \
        and her exact idea and say it better, in her voice: deadpan, plain words, a little childlike, quietly funny. \
        Never change what she means. Never add a new action, object or story.

        Examples:

        her line: the road was broken and angry
        meaning: the cracked road looks like it is losing its temper
        - a road was having a meltdown
        - the road completely lost its temper
        - the road was having a very bad day

        her line: the plant shadow wanted to be scary
        meaning: the plant's spiky shadow looks like it is trying to be frightening
        - a little plant tried to look scary and it almost worked
        - a small plant was practicing its scariest face
        - the plant's shadow tried very hard to be scary

        her line: the bike was on the car roof looking at the road
        meaning: the bike on the roof rack looks like a child on someone's shoulders
        - a little bike was sitting on a car's shoulders to see the road better
        - a bike got a ride on a car's shoulders
        - the little bike wanted a better view of the road
        """)
        let response = try await session.respond(
            to: "her line: \(mine)",
            generating: Rephrase.self,
            options: GenerationOptions(temperature: 0.5, maximumResponseTokens: 250))
        // Keep only versions that are still about her subject.
        let stop: Set<String> = ["a", "an", "the", "this", "that", "some", "little", "big", "giant", "small"]
        let subjectWords = Set(response.content.subject.lowercased().split(separator: " ").map(String.init))
            .subtracting(stop)
        let lines = Caption.distinct(response.content.lines.map(Caption.cleanLine)
            .filter { !$0.isEmpty && $0 != mine })
        let onSubject = subjectWords.isEmpty ? lines : lines.filter { line in
            subjectWords.contains { line.contains($0) }
        }
        let pool = onSubject.isEmpty ? lines : onSubject
        let good = pool.filter(Caption.fitsStyle)
        return good.isEmpty ? pool : good
    }

    /// Step 2, text only: from the literal description, the model first lists ideas, then writes
    /// lines, copying the pattern of her lines whose photos are most like this one. Lines that are
    /// the wrong length or full of clichés are dropped in code, then an "editor" keeps the best three.
    static func writeLines(facts: String, city: String, note: String,
                           avoid: [String] = []) async throws -> [String] {
        let avoidText = avoid.isEmpty ? "" : "\n\nDon't repeat or reword these: \(avoid.joined(separator: "; "))."
        let prompt = """
        Her lines for photos like this one:

        \(StyleGuide.examplesBlock(for: facts))

        Now this photo.
        \(facts)\(avoidText)

        First list the ideas, then write the lines in her style. Keep everything short.
        """
        let session = LanguageModelSession(instructions: StyleGuide.appleWriterInstructions(city: city, note: note))
        let response = try await session.respond(to: prompt, generating: IdeaDraft.self,
                                                 options: GenerationOptions(temperature: 0.75, maximumResponseTokens: 400))
        let cleaned = Caption.distinct(response.content.lines.map(Caption.cleanLine)
            .filter { !$0.isEmpty && !avoid.contains($0) })
        let good = cleaned.filter(Caption.fitsStyle)
        var pool = good.count >= 3 ? good : cleaned
        let plain = Caption.cleanLine(response.content.plain)
        if !plain.isEmpty, !avoid.contains(plain), !pool.contains(plain) { pool.append(plain) }
        guard !pool.isEmpty else {
            throw DrafterError(message: "Apple's model couldn't write lines for this photo.")
        }
        return await keepSensible(pool, plain: plain, facts: shortFacts(facts))
    }

    /// Reads every candidate back soberly, says in plain words what each one means, and keeps
    /// only lines a reader would get straight away (best first). Nonsense like "people wished
    /// the jaw had lips" fails here. The plain, true line is the fallback if too few pass.
    /// Just the first sentence block of the facts (the plain description), to keep the check quick.
    static func shortFacts(_ facts: String) -> String {
        guard let range = facts.range(of: " Things:") else { return facts }
        return String(facts[..<range.lowerBound])
    }

    static func keepSensible(_ pool: [String], plain: String, facts: String) async -> [String] {
        let numbered = pool.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        let session = LanguageModelSession(instructions: """
        You check captions for a photo diary before they are shown. The captions are meant to be gently absurd: \
        things in the photo acting like people (a road having a meltdown, figs pretending to be tennis balls). \
        That is fine. What is not fine is a line that doesn't make sense, mixes up what is in the photo, \
        or that a reader couldn't understand without explanation. Be strict and honest.
        """)
        let response = try? await session.respond(
            to: "\(facts)\n\nCaptions:\n\(numbered)\n\nReview every caption. Be brief.",
            generating: LineReviews.self,
            options: GenerationOptions(temperature: 0.1, maximumResponseTokens: 400))
        guard let reviews = response?.content.reviews, !reviews.isEmpty else {
            return Array(pool.prefix(3))
        }
        var scored: [(line: String, clarity: Int, score: Int)] = []
        for review in reviews where review.number >= 1 && review.number <= pool.count {
            let line = pool[review.number - 1]
            guard !scored.contains(where: { $0.line == line }) else { continue }
            let unclear = review.meaning.lowercased().contains("unclear")
            let clarity = unclear ? 0 : review.clarity
            // Ties keep the writer's own order (its best ideas come first).
            scored.append((line, clarity, clarity * 10 - scored.count))
        }
        // Jokes that land first, then the plain line, then lines that need a little thinking.
        // The first three are shown; the rest are kept as spares for "New options".
        var chosen = scored.filter { $0.clarity >= 7 && $0.line != plain }
            .sorted { $0.score > $1.score }.map(\.line)
        if !plain.isEmpty, !chosen.contains(plain) { chosen.append(plain) }
        chosen += scored.filter { !chosen.contains($0.line) && $0.clarity >= 5 }
            .sorted { $0.score > $1.score }.map(\.line)
        return chosen.isEmpty ? Array(pool.prefix(3)) : Array(chosen.prefix(6))
    }

    /// The editor: picks the three best candidate lines, judged against her style.
    static func pickBest(_ pool: [String], facts: String, city: String) async -> [String] {
        let numbered = pool.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        let samples = ExamplePicker.nearest(to: facts, count: 6).map { "- \($0.line)" }.joined(separator: "\n")
        let session = LanguageModelSession(instructions: """
        You are a strict editor for the photo series "dear \(city) diary". Its lines are deadpan, specific, \
        gently absurd and true to the photo. Some of its best lines:
        \(samples)
        """)
        let response = try? await session.respond(
            to: "\(facts)\n\nCandidate lines:\n\(numbered)\n\nPick the three best. A good line treats a thing in the photo as a character with an inner life, is true to what is in the photo, reads naturally, and is quietly funny. Skip lines that only describe the photo, that are confusing, or that sound poetic. The three should be different from each other.",
            generating: Ranking.self,
            options: GenerationOptions(temperature: 0.2, maximumResponseTokens: 60))
        var chosen: [String] = []
        for n in response?.content.best ?? [] where n >= 1 && n <= pool.count && !chosen.contains(pool[n - 1]) {
            chosen.append(pool[n - 1])
        }
        for line in pool where chosen.count < 3 && !chosen.contains(line) {
            chosen.append(line)
        }
        return Array(chosen.prefix(3))
    }

    /// Facts already worked out for a photo this session (looking is the slow part).
    nonisolated(unsafe) private static var factsCache: [UUID: (description: String, prompt: String, interest: Int)] = [:]

    /// Step 1, before any jokes: what is literally in the photo, from Apple's image classifier,
    /// any text in it, and a sober description by the on-device model.
    @available(iOS 27.0, *)
    static func groundedFacts(for photo: DiaryPhoto) async -> (description: String, prompt: String, interest: Int) {
        if let cached = factsCache[photo.id] { return cached }
        guard let image = photo.preview.cgImage else { return ("", "", 0) }
        let hints = visionHints(photo.preview)
        var result = (description: "", prompt: hints, interest: 0)
        let session = LanguageModelSession(instructions: "You describe photos literally and accurately. Look carefully at the whole frame, including the edges and background. Name only what is really visible. No interpretation, no jokes, no guessing.")
        var response: LanguageModelSession.Response<PhotoFacts>?
        if let closeUp = detailCrop(of: photo) {
            response = try? await session.respond(generating: PhotoFacts.self,
                                                  options: GenerationOptions(temperature: 0.2, maximumResponseTokens: 500)) {
                "Describe what is in this photo. The first image is the whole photo; the second is a close-up of its most eye-catching part, for detail. \(hints)"
                Attachment(image).label("whole photo")
                Attachment(closeUp).label("close-up")
            }
        }
        if response == nil {
            // Fall back to the whole photo alone (e.g. if two images don't fit).
            let single = LanguageModelSession(instructions: "You describe photos literally and accurately. Look carefully at the whole frame, including the edges and background. Name only what is really visible. No interpretation, no jokes, no guessing.")
            response = try? await single.respond(generating: PhotoFacts.self,
                                                 options: GenerationOptions(temperature: 0.2, maximumResponseTokens: 500)) {
                "Describe what is in this photo. \(hints)"
                Attachment(image)
            }
        }
        if let facts = response?.content {
            var text = "What is actually in the photo: \(facts.summary) Things: \(facts.things.joined(separator: ", ")). Setting: \(facts.setting)."
            if !facts.details.isEmpty {
                text += " Details: \(facts.details.joined(separator: "; "))."
            }
            if !facts.resemblances.isEmpty {
                text += " Resemblances: \(facts.resemblances.joined(separator: "; "))."
            } else {
                text += " Nothing here clearly resembles something else."
            }
            result = (facts.summary, text, facts.interest)
        }
        factsCache[photo.id] = result
        return result
    }

    /// A sharp, square close-up of the most eye-catching area, cut from the full-size photo,
    /// so the small model can see the small details the series is about.
    static func detailCrop(of photo: DiaryPhoto) -> CGImage? {
        guard let preview = photo.preview.cgImage else { return nil }
        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        try? VNImageRequestHandler(cgImage: preview, options: [:]).perform([request])
        guard let box = request.results?.first?.salientObjects?.first?.boundingBox,
              let full = ImageLoader.downsample(photo.sourceData, maxPixel: 2400)?.cgImage else { return nil }
        let w = CGFloat(full.width), h = CGFloat(full.height)
        let shortSide = min(w, h)
        var side = max(box.width * w, box.height * h) * 1.4
        side = min(max(side, shortSide * 0.35), shortSide)
        // A close-up that's nearly the whole photo adds nothing.
        guard side < shortSide * 0.9 else { return nil }
        let centerX = box.midX * w
        let centerY = (1 - box.midY) * h // Vision measures from the bottom
        let x = min(max(centerX - side / 2, 0), w - side)
        let y = min(max(centerY - side / 2, 0), h - side)
        return full.cropping(to: CGRect(x: x, y: y, width: side, height: side).integral)
    }

    /// Apple's built-in image classifier and text reader: labels like "cobblestone", "plant", plus any words.
    static func visionHints(_ image: UIImage) -> String {
        guard let cg = image.cgImage else { return "" }
        let classify = VNClassifyImageRequest()
        let readText = VNRecognizeTextRequest()
        readText.recognitionLevel = .fast
        try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([classify, readText])
        let labels = (classify.results ?? [])
            .filter { $0.confidence > 0.25 }
            .prefix(8)
            .map { $0.identifier.replacingOccurrences(of: "_", with: " ") }
        let words = (readText.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .prefix(4)
        var parts: [String] = []
        if !labels.isEmpty { parts.append("An image classifier sees: \(labels.joined(separator: ", ")).") }
        if !words.isEmpty { parts.append("Text in the photo: \(words.joined(separator: " / ")).") }
        return parts.joined(separator: " ")
    }

    /// Grammar, spelling and sense check for a caption you wrote yourself (text only).
    static func checkGrammar(_ line: String) async throws -> (corrected: String, note: String) {
        let session = LanguageModelSession(instructions: """
        You proofread short lowercase diary captions. Fix grammar and spelling mistakes only, and say if the sentence doesn't make sense. \
        Never rewrite for style, never add or remove ideas, never capitalise, never add punctuation at the end. \
        The captions are deliberately absurd (a road having a meltdown, figs pretending to be tennis balls); that is never a mistake.
        """)
        let response = try await session.respond(to: "Caption: \(line)", generating: GrammarCheck.self,
                                                 options: GenerationOptions(temperature: 0.1, maximumResponseTokens: 120))
        return (response.content.corrected, response.content.note)
    }

    /// Where the eye goes in the photo (top-left origin), so the crop keeps it.
    static func salientCenter(_ image: UIImage) -> CGPoint? {
        guard let cg = image.cgImage else { return nil }
        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([request])
        guard let box = request.results?.first?.salientObjects?.first?.boundingBox else { return nil }
        // Vision measures from the bottom-left; the app measures from the top-left.
        return CGPoint(x: box.midX, y: 1 - box.midY)
    }
}
