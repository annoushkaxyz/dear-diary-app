import Foundation

struct ClaudeClient {
    let apiKey: String
    let model: String

    struct DraftResult: Decodable {
        struct Item: Decodable {
            let photo: Int
            let lines: [String]
            let what_i_saw: String
            let text_position: String
            let focus_x: Double
            let focus_y: Double
            let wildcard: Bool
        }
        struct Skip: Decodable {
            let photo: Int
            let reason: String
        }
        let entry: [Item]
        let left_out: [Skip]
    }

    enum ClientError: LocalizedError {
        case api(String)
        var errorDescription: String? {
            switch self { case .api(let message): return message }
        }
    }

    /// Three fresh caption options for one photo.
    func moreLines(for photo: DiaryPhoto, city: String, avoid: [String], hint: String? = nil) async throws -> [String] {
        let tool: [String: Any] = [
            "name": "suggest_lines",
            "description": "Return three new diary lines for the photo.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "lines": ["type": "array", "items": ["type": "string"], "minItems": 3, "maxItems": 3]
                ],
                "required": ["lines"]
            ]
        ]
        let previous = avoid.isEmpty ? "" : " Don't repeat or reword these: " + avoid.joined(separator: " / ")
        let content: [[String: Any]] = [
            ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg",
                                         "data": photo.modelJPEG.base64EncodedString()]],
            ["type": "text", "text": (hint?.isEmpty == false)
                ? "I started writing this line for the photo: \"\(hint!)\". Write three lines that build on my idea: keep what I meant, and my words where they work, but make each one sharper, funnier or more specific in a different way."
                : "Write three new lines for this photo, three different readings (look for other overlooked details too).\(previous)"]
        ]
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 600,
            "system": StyleGuide.systemPrompt(city: city),
            "tools": [tool],
            "tool_choice": ["type": "tool", "name": "suggest_lines"],
            "messages": [["role": "user", "content": content]]
        ]
        let input = try await send(body)
        return (input["lines"] as? [String]) ?? []
    }

    /// Grammar, spelling and sense check for a caption you wrote yourself.
    func checkGrammar(_ line: String) async throws -> (corrected: String, note: String) {
        let tool: [String: Any] = [
            "name": "proofread",
            "description": "Return the caption with grammar and spelling fixed.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "corrected": ["type": "string"],
                    "note": ["type": "string", "description": "Empty if the caption reads clearly. Otherwise one short plain sentence saying what is confusing (a missing word, unclear who did what, a tense mix-up). The series is deliberately absurd: objects acting like people, wanting things or having feelings is intended and never confusing."]
                ],
                "required": ["corrected", "note"]
            ]
        ]
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 200,
            "system": "You proofread short lowercase diary captions. Fix grammar and spelling mistakes only, and say if the sentence doesn't make sense. Keep the writer's words, word order and style. Never capitalise, never add punctuation at the end. If nothing is wrong, return it unchanged with an empty note. The captions are deliberately absurd (a road having a meltdown, figs pretending to be tennis balls); that is never a mistake.",
            "tools": [tool],
            "tool_choice": ["type": "tool", "name": "proofread"],
            "messages": [["role": "user", "content": line]]
        ]
        let input = try await send(body)
        return ((input["corrected"] as? String) ?? line, (input["note"] as? String) ?? "")
    }

    private func send(_ body: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let message = (json?["error"] as? [String: Any])?["message"] as? String
            throw ClientError.api(message ?? "Claude didn't answer (status \((response as? HTTPURLResponse)?.statusCode ?? 0)).")
        }
        guard let blocks = json?["content"] as? [[String: Any]],
              let toolUse = blocks.first(where: { $0["type"] as? String == "tool_use" }),
              let input = toolUse["input"] as? [String: Any] else {
            throw ClientError.api("Claude answered, but not in the expected format. Try again.")
        }
        return input
    }

    func draft(photos: [DiaryPhoto], city: String, note: String) async throws -> DraftResult {
        var content: [[String: Any]] = []
        for photo in photos {
            content.append(["type": "text", "text": "Photo \(photo.index)"])
            content.append([
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": "image/jpeg",
                    "data": photo.modelJPEG.base64EncodedString()
                ]
            ])
        }
        content.append(["type": "text", "text": StyleGuide.userInstruction(photoCount: photos.count, note: note)])

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "system": StyleGuide.systemPrompt(city: city),
            "tools": [StyleGuide.tool],
            "tool_choice": ["type": "tool", "name": StyleGuide.toolName],
            "messages": [["role": "user", "content": content]]
        ]

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let message = (json?["error"] as? [String: Any])?["message"] as? String
            throw ClientError.api(message ?? "Claude didn't answer (status \((response as? HTTPURLResponse)?.statusCode ?? 0)).")
        }

        guard let blocks = json?["content"] as? [[String: Any]],
              let toolUse = blocks.first(where: { $0["type"] as? String == "tool_use" }),
              let input = toolUse["input"] else {
            throw ClientError.api("Claude answered, but not in the expected format. Try again.")
        }

        let inputData = try JSONSerialization.data(withJSONObject: input)
        return try JSONDecoder().decode(DraftResult.self, from: inputData)
    }
}
