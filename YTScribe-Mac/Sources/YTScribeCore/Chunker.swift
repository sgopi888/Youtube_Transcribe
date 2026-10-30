import Foundation

public enum Chunker {
    /// shortcut: ~4 chars/token is an English estimate; non-English text tokenizes worse, so the chunk
    /// budget below leaves headroom. Upgrade to a real tokenizer if chunks start overflowing.
    public static func estimateTokens(_ text: String) -> Int { (text.count + 3) / 4 }

    /// Splits `text` into pieces of at most `maxTokens` (estimated), breaking at sentence ends, else spaces.
    public static func split(_ text: String, maxTokens: Int) -> [String] {
        let maxChars = max(maxTokens * 4, 1)
        guard text.count > maxChars else { return [text] }
        var chunks: [String] = []
        var rest = Substring(text)
        while rest.count > maxChars {
            let window = rest.prefix(maxChars)
            let cut = window.lastIndex(where: { ".!?".contains($0) }).map { window.index(after: $0) }
                ?? window.lastIndex(of: " ").map { window.index(after: $0) }
                ?? window.endIndex
            chunks.append(String(rest[..<cut]).trimmingCharacters(in: .whitespaces))
            rest = rest[cut...]
        }
        let tail = String(rest).trimmingCharacters(in: .whitespaces)
        if !tail.isEmpty { chunks.append(tail) }
        return chunks
    }
}
