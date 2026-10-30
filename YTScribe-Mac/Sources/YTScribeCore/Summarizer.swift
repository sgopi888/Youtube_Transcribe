import Foundation

public protocol LLMClient: Sendable {
    func complete(instructions: String, input: String) async throws -> String
}

public struct Summarizer: Sendable {
    /// Model context window in tokens. Transcripts above this are summarized in chunks.
    public static let contextWindow = 255_000
    /// Per-chunk budget: leaves room for instructions and the (long) response.
    public static let chunkBudget = 200_000

    private let client: LLMClient
    private let chunkBudget: Int

    public init(client: LLMClient, chunkBudget: Int = Summarizer.chunkBudget) {
        self.client = client
        self.chunkBudget = chunkBudget
    }

    static let format = """
    Write a detailed technical summary in Markdown with these sections:
    ## TL;DR (2-3 sentences)
    ## Detailed Breakdown (topic by topic, in the order discussed; keep concrete specifics)
    ## Technical Details (tools, versions, commands, code, architectures, numbers, benchmarks, configs, trade-offs mentioned)
    ## Key Takeaways & Action Items
    ## Caveats (claims that are unsupported, uncertain, or promotional)
    Only use information from the transcript. Do not invent details; omit a section if the transcript has nothing for it.
    """

    /// `progress` reports (chunk, total) as work proceeds; total is 1 for a single call.
    public func summarize(title: String, transcript: String, progress: @Sendable (Int, Int) -> Void = { _, _ in }) async throws -> String {
        let chunks = Chunker.split(transcript, maxTokens: chunkBudget)
        if chunks.count == 1 {
            progress(1, 1)
            return try await client.complete(instructions: Self.format, input: "Video title: \(title)\n\nTranscript:\n\(chunks[0])")
        }

        var partials: [String] = []
        for (i, chunk) in chunks.enumerated() {
            progress(i + 1, chunks.count + 1)
            let instr = "You are summarizing part \(i + 1) of \(chunks.count) of a long video transcript. Extract every technical detail, number, name, command and claim faithfully, topic by topic, as Markdown notes. Do not conclude; more parts follow."
            partials.append(try await client.complete(instructions: instr, input: "Video title: \(title)\n\nTranscript part \(i + 1)/\(chunks.count):\n\(chunk)"))
        }
        progress(chunks.count + 1, chunks.count + 1)
        let notes = partials.enumerated().map { "### Notes from part \($0.offset + 1)\n\($0.element)" }.joined(separator: "\n\n")
        return try await client.complete(instructions: Self.format + "\nThe input is ordered notes from consecutive parts of one video; merge them into one coherent summary.", input: "Video title: \(title)\n\n\(notes)")
    }
}

/// OpenAI Responses API (same endpoint family the existing openai_client.py uses).
public struct OpenAIClient: LLMClient {
    public static let defaultModel = "gpt-6-luna"
    let apiKey: String
    let model: String
    let session: URLSession

    public init(apiKey: String, model: String = OpenAIClient.defaultModel, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.model = model
        self.session = session
    }

    public func complete(instructions: String, input: String) async throws -> String {
        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 600
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model, "instructions": instructions, "input": input, "max_output_tokens": 16_000,
        ] as [String: Any])

        let (data, resp) = try await session.data(for: req)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let msg = ((json?["error"] as? [String: Any])?["message"] as? String) ?? "HTTP \(http.statusCode)"
            throw LLMError.api(msg)
        }
        let text = Self.outputText(json ?? [:])
        guard !text.isEmpty else { throw LLMError.empty }
        return text
    }

    static func outputText(_ json: [String: Any]) -> String {
        if let t = json["output_text"] as? String, !t.isEmpty { return t.trimmingCharacters(in: .whitespacesAndNewlines) }
        let parts = (json["output"] as? [[String: Any]] ?? [])
            .flatMap { ($0["content"] as? [[String: Any]]) ?? [] }
            .filter { ($0["type"] as? String) == "output_text" }
            .compactMap { $0["text"] as? String }
        return parts.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public enum LLMError: LocalizedError {
    case api(String), empty, missingKey
    public var errorDescription: String? {
        switch self {
        case .api(let m): return "OpenAI error: \(m)"
        case .empty: return "OpenAI returned an empty summary."
        case .missingKey: return "Add your OpenAI API key in Settings (⌘,)."
        }
    }
}
