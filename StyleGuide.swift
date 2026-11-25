import Foundation
import NaturalLanguage

/// Everything Claude needs to know about the "dear diary" series.
/// Edit this file to tune the voice — it's the heart of the app.
enum StyleGuide {

    /// Lines from Dear Lisbon diary (anshka.com/dear-diary), each with what was in the photo.
    /// Replace them with your own: the app copies their voice.
    static let examples: [(seen: String, line: String)] = [
        ("a tall harbour crane against the sky", "i drove by a giant giraffe"),
        ("a dark stain on a concrete wall, half in shadow", "a dinosaur with tiny hands was creeping out of the darkness"),
        ("a bike on a car's roof rack", "a little bike was sitting on a car's shoulders to see the road better"),
        ("crumbling, buckled asphalt", "a road was having a meltdown"),
        ("an abandoned umbrella against a wall", "someone threw away a rainy day"),
        ("two street barriers touching at golden hour", "i met two strangers holding hands at sunset"),
        ("a plant's spiky shadow on a wall", "a little plant tried to look scary and it almost worked"),
        ("round vents on a roof", "the mushrooms were catching the last bits of summer sun"),
        ("a strip light in a dark stairwell that looks like a cigarette", "a stairwell needed a smoke break"),
        ("a building half hidden by bushes", "a shy house was hiding behind the flowers"),
        ("a seedling growing through asphalt", "i met a sprout so strong it broke the ground"),
        ("weeds sprouting from a drain grate", "a drain finally started to grow its hair back"),
        ("wavy striped shadows on the pavement", "the ground was flowing under my feet"),
        ("a peeling, textured facade", "the building was shedding its skin"),
        ("leaf shadows on a tiled bench", "the leaves were practicing calligraphy with sunlight"),
        ("a darkened, smudged tail light", "a car got into a fight and ended up with a black eye"),
        ("round red berries hanging from a plant", "a flower was wearing its boxing gloves"),
        ("a statue with cobwebs", "a spider added finishing touches to the sculpture"),
        ("a dolphin-shaped patch of peeling paint on blue tiles", "a dolphin was trying to escape the heat"),
        ("lichen patches that look like a map", "i found the world growing on the wall"),
        ("two neighbouring trees with opposite shapes", "two trees chose completely different paths in life"),
        ("a red sun at dusk", "the sun was showing off its red look"),
        ("a rooster striding across calçada", "a rooster had no time for small talk"),
        ("two door handles reaching towards each other", "these hands confessed their love to strangers"),
        ("a windshield sunshade printed with big eyes", "this car was flirting with someone"),
        ("a traffic light half hidden in a hedge", "this traffic light was playing hide and seek"),
        ("a white van glimpsed through a hazy window", "the ghost van parked for lunch"),
        ("figs in a tennis bag", "some figs were pretending to be tennis balls"),
        ("a facade gazing up into an empty blue sky", "this building was day dreaming"),
        ("a shattered mirror lying on calçada", "a mirror was practicing being pavement")
    ]

    static func systemPrompt(city: String) -> String {
        let learned = LearnedStore.all().prefix(20)
        let learnedSection = learned.isEmpty ? "" : "More of her recent lines (she chose or wrote these):\n"
            + learned.map { "- \($0.line) (\($0.seen))" }.joined(separator: "\n") + "\n\n"
        return """
        You help draft entries for "dear \(city) diary", a photo series about the small, slightly absurd things she notices around the city.

        THE FORMAT
        An entry is a short sequence of 3:4 photos. Each photo carries one short line of small white lowercase text. Read in order, the lines make one run-on diary entry, chained with "and". The app adds the scaffolding itself: "dear \(city) diary," above the first line, "today" at the start of the first line, " and" after every line except the last, and "until next time" after the last line. Do NOT write any of that scaffolding yourself.

        THE VOICE
        The trick of the series: objects, buildings, plants, shadows, stains and cars are treated as characters with inner lives. Pareidolia, personification, tiny dramas. The tone is deadpan, gentle, a little childlike and funny. Never cutesy, never a pun for its own sake, never explaining the joke.

        Her real lines, each with what was actually in the photo:
        - i drove by a giant giraffe (a tall harbour crane against the sky)
        - a dinosaur with tiny hands was creeping out of the darkness (a dark stain on a concrete wall, half in shadow)
        - a little bike was sitting on a car's shoulders to see the road better (a bike on a car's roof rack)
        - a road was having a meltdown (crumbling, buckled asphalt)
        - someone threw away a rainy day (an abandoned umbrella against a wall)
        - i met two strangers holding hands at sunset (two street barriers touching at golden hour)
        - a little plant tried to look scary and it almost worked (a plant's spiky shadow on a wall)
        - the mushrooms were catching the last bits of summer sun (round vents on a roof)
        - a stairwell needed a smoke break (a strip light in a dark stairwell that looks like a cigarette)
        - a shy house was hiding behind the flowers (a building half hidden by bushes)
        - i met a sprout so strong it broke the ground (a seedling growing through asphalt)
        - a drain finally started to grow its hair back (weeds sprouting from a drain grate)
        - the ground was flowing under my feet (wavy striped shadows on the pavement)
        - the building was shedding its skin (a peeling, textured facade)
        - the leaves were practicing calligraphy with sunlight (leaf shadows on a tiled bench)
        - a car got into a fight and ended up with a black eye (a darkened, smudged tail light)
        - a flower was wearing its boxing gloves (round red berries hanging from a plant)
        - a spider added finishing touches to the sculpture (a statue with cobwebs)
        - a dolphin was trying to escape the heat (a dolphin-shaped patch of peeling paint on blue tiles)
        - i found the world growing on the wall (lichen patches that look like a map)
        - two trees chose completely different paths in life (two neighbouring trees with opposite shapes)
        - the sun was showing off its red look (a red sun at dusk)
        - a rooster had no time for small talk (a rooster striding across calçada)
        - these hands confessed their love to strangers (two door handles reaching towards each other)
        - this car was flirting with someone (a windshield sunshade printed with big eyes)
        - this traffic light was playing hide and seek (a traffic light half hidden in a hedge)
        - the ghost van parked for lunch (a white van glimpsed through a hazy window)
        - some figs were pretending to be tennis balls (figs in a tennis bag)
        - this building was day dreaming (a facade gazing up into an empty blue sky)
        - a mirror was practicing being pavement (a shattered mirror lying on calçada)

        \(learnedSection)RULES FOR LINES
        - all lowercase, no emoji, no hashtags, no final punctuation
        - roughly 4 to 14 words
        - past tense, as if reporting what happened today ("was doing", "had", "tried to")
        - never start a line with "today" (the app adds it to the first photo)
        - say what the thing was doing or feeling, not what it is: "a road was having a meltdown", never "cracked asphalt"
        - prefer the specific, surprising reading over the obvious one
        - no landmarks, no tourist talk; the series is about overlooked things
        - vary sentence openings across the entry (not every line "a ... was ...")
        - avoid tired words: whisper, dance, secret, story, journey, peaceful, quietly, embrace, lonely, sleepy
        - no "like" or "as if"; say it as if it really happened

        YOUR JOB
        0. First see each photo literally and accurately: what is really there, where, what it looks like. Never invent objects. Metaphors come only from things that genuinely resemble something else (a face, a creature, a gesture); if nothing does, write a gentle, true diary line about what's there.
        1. Look at every photo closely, especially the ones that seem like throwaways: blurry, accidental, half-cropped, backgrounds. Scan edges, corners, shadows, reflections, textures, stains, signs and small background details, not only the main subject. Find faces, creatures, gestures, moods and tiny dramas she may not have noticed.
        2. Choose the photos that make the strongest entry (usually 4 to 8; fewer is fine if few are strong). Never use two photos of the same scene or object; keep only the stronger one. Order them so the entry has a small arc: an opener that sets up the day, a middle that wanders or escalates, a closer that lands quietly.
        3. Set wildcard = true for picks she probably wouldn't have chosen herself: the thing you saw isn't the obvious subject, the shot looks like a throwaway, or the detail sits in a corner. These are the point of this tool, so include at least one if any photo allows it.
        4. For each pick write THREE lines that are genuinely different from each other, not rewordings of one idea. Each should start from a different place: (a) the main overlooked thing as a character with a surprising inner life, (b) a different small detail elsewhere in the frame, or what something is pretending to be, (c) an unexpected relationship, wish, rivalry or tiny failure. Use different verbs and sentence shapes in each. Skip the first idea that comes to mind; go for the one that makes you smile. Best first.
        5. Choose text_position: "top", "middle" or "bottom", whichever band of the photo is calmer and plainer so white text reads well and doesn't cover the thing you saw.
        6. Give focus_x and focus_y (0 to 1, measured from the top-left of the photo) on the thing you saw, so the 4:5 crop keeps it.
        7. In what_i_saw, describe plainly and accurately what is in the photo (one or two sentences), then what it reminded you of, if anything, and where in the frame.
        8. Put every photo you didn't use in left_out with a short, honest reason.

        Always answer by calling the draft_entry tool.
        """
    }

    static let toolName = "draft_entry"

    static let tool: [String: Any] = [
        "name": toolName,
        "description": "Return the drafted dear diary entry.",
        "input_schema": [
            "type": "object",
            "properties": [
                "entry": [
                    "type": "array",
                    "description": "The chosen photos, in posting order.",
                    "items": [
                        "type": "object",
                        "properties": [
                            "photo": ["type": "integer", "description": "The photo number as labelled in the message."],
                            "lines": [
                                "type": "array",
                                "items": ["type": "string"],
                                "minItems": 3,
                                "maxItems": 3,
                                "description": "Three different diary lines for this photo, best first. No 'dear … diary', 'today', trailing 'and' or 'until next time'."
                            ],
                            "what_i_saw": ["type": "string", "description": "One plain sentence: what you noticed and where in the frame."],
                            "text_position": ["type": "string", "enum": ["top", "middle", "bottom"]],
                            "focus_x": ["type": "number", "description": "0 = left edge, 1 = right edge."],
                            "focus_y": ["type": "number", "description": "0 = top edge, 1 = bottom edge."],
                            "wildcard": ["type": "boolean", "description": "True if she probably wouldn't have picked this one herself."]
                        ],
                        "required": ["photo", "lines", "what_i_saw", "text_position", "focus_x", "focus_y", "wildcard"]
                    ]
                ],
                "left_out": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": [
                            "photo": ["type": "integer"],
                            "reason": ["type": "string"]
                        ],
                        "required": ["photo", "reason"]
                    ]
                ]
            ],
            "required": ["entry", "left_out"]
        ]
    ]

    /// Instructions for Apple's text-only writing step: the voice and the rules.
    /// The examples go in the prompt instead, picked per photo (see `ExamplePicker`),
    /// because the small model copies a few close examples far better than thirty loose ones.
    static func appleWriterInstructions(city: String, note: String) -> String {
        var text = """
        You write captions for "dear \(city) diary", a photo series about small, slightly absurd things in the city. \
        Ordinary objects, buildings, plants, shadows, cracks and stains are treated as characters with inner lives.

        How a line works: find a thing in the photo, notice what it resembles or what a person might be doing in its place, \
        then say plainly what it was doing, wanting or feeling, as if it were alive. Never explain the joke.

        Rules: all lowercase, 4 to 12 words, past tense, deadpan, a little childlike. \
        No "like", "as if", "seems" or "looks". No fancy or poetic words. \
        Only use things that are in the description. No end punctuation. Never start with "today".
        """
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            text += "\n\nA note about today: \(trimmed)"
        }
        return text
    }

    /// Her lines closest to this photo, as "photo → line" pairs for the prompt.
    static func examplesBlock(for facts: String, count: Int = 6) -> String {
        ExamplePicker.nearest(to: facts, count: count)
            .map { "photo: \($0.seen)\nline: \($0.line)" }
            .joined(separator: "\n\n")
    }

    /// Shorter version for Apple's on-device model, which has a small context window.
    /// The per-option recipes live in `PhotoRead`'s guides.
    static func appleInstructions(city: String, note: String) -> String {
        var text = """
        You write captions for "dear \(city) diary", a photo series about small, slightly absurd things in the city. Ordinary objects, buildings, plants, shadows, cracks and stains are treated as characters with inner lives.

        How to write a line:
        1. Ignore the obvious subject. Look for a small thing: a crack, a stain, a shadow, a plant, a sign, a reflection, a car part.
        2. Ask what it looks like it is DOING or FEELING, as if it were a person.
        3. Say it plainly in past tense, 4 to 12 words, all lowercase.

        Good: a road was having a meltdown
        Good: someone threw away a rainy day
        Good: a drain finally started to grow its hair back
        Bad: the cracked asphalt looks like a river (describes, explains the joke)
        Bad: a beautiful sunny day in the city (no character, no drama)
        Bad: the wall whispers ancient secrets (poetic, pretentious)

        Rules: deadpan and gentle, a little childlike. No "like" or "as if". No adjectives such as beautiful, lovely, ancient, mysterious. No hashtags, emoji or end punctuation. Never start with "today".
        """
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            text += "\n\nA note about today: \(trimmed)"
        }
        return text
    }

    static func userInstruction(photoCount: Int, note: String) -> String {
        var text = "Here are \(photoCount) photos from my day. Draft a dear diary entry from them."
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            text += "\n\nA note about today: \(trimmed)"
        }
        return text
    }
}

/// Builds the text that's printed on each photo.
enum Caption {
    static let signoff = "until next time"

    /// The first photo opens with "dear … diary," (+ "today"), the last one closes with
    /// "until next time"; either can be switched off. Lines in between end with "and".
    static func compose(line: String, position: Int, count: Int, city: String,
                        greeting: Bool = true, signoff showSignoff: Bool = true) -> String {
        var body = line.trimmingCharacters(in: .whitespacesAndNewlines)
        var text = ""
        if position == 0 && greeting {
            text += "dear \(city) diary,\n\n"
            if !body.isEmpty && !body.hasPrefix("today") {
                body = "today " + body
            }
        }
        if position == count - 1 {
            text += showSignoff ? body + "\n\n" + signoff : body
        } else {
            text += body + " and"
        }
        return text
    }

    /// Removes options that mostly repeat an earlier one (more than half the same words).
    static func distinct(_ lines: [String]) -> [String] {
        let stop: Set<String> = ["a", "an", "the", "was", "were", "and", "to", "of", "its", "it", "in", "on", "with", "at"]
        func words(_ s: String) -> Set<String> {
            Set(s.split(separator: " ").map(String.init)).subtracting(stop)
        }
        var kept: [String] = []
        for line in lines {
            let w = words(line)
            let repeats = kept.contains { other in
                let o = words(other)
                let union = w.union(o).count
                return union > 0 && Double(w.intersection(o).count) / Double(union) > 0.5
            }
            if !repeats { kept.append(line) }
        }
        return kept
    }

    /// Words the small model loves and her series never uses.
    static let offStyle = ["whisper", "danc", "embrac", "tapestry", "symphony", "secret", "stories",
                           "testament", "journey", "beckon", "serene", "vibrant", "majestic", "ancient",
                           "mysterious", "sentinel", "beautiful", "lovely", "soul", "essence", "timeless",
                           "like a", "as if", "seems", "seemed", "appears", "looks like", "looked like",
                           "adorn", "nestled", "bathed", "hues", "glisten"]

    /// True when a line is the right length and free of the model's favourite clichés.
    static func fitsStyle(_ line: String) -> Bool {
        let count = line.split(separator: " ").count
        guard (3...14).contains(count), !line.contains("?") else { return false }
        return !offStyle.contains { line.contains($0) }
    }

    /// Lowercase, no end punctuation, and none of the scaffolding the app adds itself.
    static func cleanLine(_ text: String) -> String {
        let junk = CharacterSet(charactersIn: " .!,;:\"'“”\n")
        var line = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if line.hasPrefix("dear"), let range = line.range(of: "diary,") {
            line = String(line[range.upperBound...])
        }
        line = line.trimmingCharacters(in: junk)
        for suffix in ["until next time", " and"] where line.hasSuffix(suffix) {
            line = String(line.dropLast(suffix.count))
        }
        line = line.trimmingCharacters(in: junk)
        if line.hasPrefix("today ") {
            line = String(line.dropFirst("today ".count))
        }
        return line
    }
}

/// Picks her lines whose photos are most like this one, using Apple's on-device sentence embeddings.
enum ExamplePicker {
    nonisolated(unsafe) private static var vectors: [String: [Double]] = [:]

    static func nearest(to text: String, count: Int) -> [(seen: String, line: String)] {
        let learned = LearnedStore.all().prefix(30).map { (seen: $0.seen, line: $0.line) }
        var pool = learned + StyleGuide.examples
        var seenLines = Set<String>()
        pool = pool.filter { !$0.seen.isEmpty && seenLines.insert($0.line).inserted }
        guard let embedding = NLEmbedding.sentenceEmbedding(for: .english),
              let query = embedding.vector(for: text) else {
            return Array(pool.shuffled().prefix(count))
        }
        let scored = pool.map { example -> (example: (seen: String, line: String), score: Double) in
            guard let v = vector(for: example.seen, embedding) else { return (example, -1) }
            return (example, cosine(query, v))
        }.sorted { $0.score > $1.score }
        // Mostly the closest ones, plus two others so the lines don't all copy one pattern.
        let close = scored.prefix(max(count - 2, 1)).map { $0.example }
        let others = scored.dropFirst(close.count).shuffled().prefix(count - close.count).map { $0.example }
        return close + others
    }

    private static func vector(for text: String, _ embedding: NLEmbedding) -> [Double]? {
        if let cached = vectors[text] { return cached }
        let v = embedding.vector(for: text)
        vectors[text] = v
        return v
    }

    private static func cosine(_ a: [Double], _ b: [Double]) -> Double {
        var dot = 0.0, na = 0.0, nb = 0.0
        for i in 0..<min(a.count, b.count) {
            dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i]
        }
        return na > 0 && nb > 0 ? dot / (na.squareRoot() * nb.squareRoot()) : 0
    }
}
