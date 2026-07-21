import Foundation

public enum AIError: LocalizedError, Equatable {
    case noKey
    case emptyResponse
    case httpError(Int, String)
    case network(String)

    public var errorDescription: String? {
        switch self {
        case .noKey:
            return L("尚未配置 Anthropic API Key，请先在设置中填写。")
        case .emptyResponse:
            return L("AI 没有返回内容，请重试。")
        case .httpError(let code, let message):
            return L("AI 请求失败（HTTP \(code)）：\(message)")
        case .network(let message):
            return L("网络错误：\(message)")
        }
    }
}

/// AI-assisted authoring over the Anthropic Messages API (bring-your-own-key).
/// Swift has no official Anthropic SDK, so this talks raw HTTP. Prompt
/// construction and response cleaning are pure and unit-tested; the network
/// call is a thin wrapper on top.
public enum SkillDoctor {
    static let model = "claude-opus-4-8"
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    /// Cap the source we send so a giant SKILL.md can't blow up the request.
    static let maxBodyChars = 12000

    // MARK: - Prompt construction (pure, testable)

    public static func descriptionSystemPrompt() -> String {
        """
        You write the `description` field for an AI coding-tool Skill (Claude Code / Codex).
        The description is what the tool matches against a user's task to decide whether to \
        auto-load the skill, so it must be specific and rich in trigger keywords.

        Rules:
        - One paragraph, plain text, no markdown, no surrounding quotes.
        - Start with what the skill does, then state WHEN to use it ("Use when …") with concrete \
          trigger scenarios and keywords a user might say.
        - Keep it under 500 characters. Be concrete, never generic.
        - Write in the SAME language as the skill's content.
        - Output ONLY the description text — no preamble, no explanation, no labels.
        """
    }

    public static func descriptionUserPrompt(name: String, body: String) -> String {
        let trimmedBody = String(body.prefix(maxBodyChars))
        return """
        Skill name (folder): \(name)

        Skill body (SKILL.md without frontmatter):
        \"\"\"
        \(trimmedBody)
        \"\"\"

        Write the best possible `description` for this skill.
        """
    }

    public static func bodySystemPrompt() -> String {
        """
        You write the body of an AI coding-tool Skill file (SKILL.md, the part after the \
        YAML frontmatter). Produce clear, actionable instructions the AI agent will follow.

        Rules:
        - Output GitHub-flavored markdown for the body only — do NOT include the `---` \
          frontmatter block.
        - Start with a `#` H1 title, then concise sections (Overview, Instructions/Steps, and \
          others as appropriate).
        - Write in the SAME language as the skill's name/description.
        - Output ONLY the markdown body — no preamble, no explanation, no code fence around \
          the whole thing.
        """
    }

    public static func bodyUserPrompt(name: String, description: String) -> String {
        """
        Skill name (folder): \(name)
        Description: \(description.isEmpty ? "(none)" : description)

        Write a complete, useful SKILL.md body for this skill.
        """
    }

    /// Cleans a model reply meant to be a single description: strips wrapping
    /// quotes, code fences, and an accidental "Description:" label.
    public static func cleanDescription(_ raw: String) -> String {
        var text = stripCodeFence(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        // Drop a leading label like "Description:" / "描述：".
        if let match = text.firstMatch(of: /^\s*(description|描述)\s*[:：]\s*/.ignoresCase()) {
            text.removeSubrange(match.range)
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Unwrap surrounding quotes.
        for quote in ["\"", "\u{201C}", "'"] where text.hasPrefix(quote) && text.count >= 2 {
            let closer = quote == "\u{201C}" ? "\u{201D}" : quote
            if text.hasSuffix(closer) {
                text = String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        // Collapse to a single line (descriptions are one paragraph).
        return text.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
    }

    /// Cleans a model reply meant to be a markdown body: strips a code fence
    /// that wraps the whole thing.
    public static func cleanBody(_ raw: String) -> String {
        stripCodeFence(raw).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Removes a single fenced code block that wraps the entire reply
    /// (```markdown … ```), which models sometimes add.
    static func stripCodeFence(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```"), trimmed.hasSuffix("```") else { return text }
        var lines = trimmed.components(separatedBy: "\n")
        guard lines.count >= 2 else { return text }
        lines.removeFirst() // opening ```lang
        if lines.last?.trimmingCharacters(in: .whitespaces) == "```" {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - API call

    public static func generateDescription(name: String, body: String) async throws -> String {
        let text = try await call(
            system: descriptionSystemPrompt(),
            user: descriptionUserPrompt(name: name, body: body),
            maxTokens: 1024
        )
        return cleanDescription(text)
    }

    public static func generateBody(name: String, description: String) async throws -> String {
        let text = try await call(
            system: bodySystemPrompt(),
            user: bodyUserPrompt(name: name, description: description),
            maxTokens: 4096
        )
        return cleanBody(text)
    }

    /// Single-turn Messages API call. Opus 4.8 without thinking for a snappy,
    /// focused generation; the system prompts enforce "output only …".
    static func call(system: String, user: String, maxTokens: Int) async throws -> String {
        guard let key = AnthropicAuth.key() else { throw AIError.noKey }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 60

        let payload: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": system,
            "messages": [["role": "user", "content": user]],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AIError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw AIError.emptyResponse
        }
        guard http.statusCode == 200 else {
            throw AIError.httpError(http.statusCode, apiErrorMessage(data))
        }
        guard let text = extractText(data), !text.isEmpty else {
            throw AIError.emptyResponse
        }
        return text
    }

    /// Pulls concatenated `text` blocks out of a Messages API response.
    static func extractText(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]] else {
            return nil
        }
        let text = content
            .filter { ($0["type"] as? String) == "text" }
            .compactMap { $0["text"] as? String }
            .joined()
        return text.isEmpty ? nil : text
    }

    /// Best-effort extraction of the API's error message for display.
    static func apiErrorMessage(_ data: Data) -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any],
              let message = error["message"] as? String else {
            return String(data: data, encoding: .utf8) ?? ""
        }
        return message
    }
}
