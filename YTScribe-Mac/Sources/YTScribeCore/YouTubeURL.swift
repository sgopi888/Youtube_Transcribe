import Foundation

public enum YouTubeURL {
    private static let patterns = [
        #"(?:youtube\.com/(?:watch\?(?:[^\s#]*&)?v=|shorts/|live/|embed/|v/)|youtu\.be/)([A-Za-z0-9_-]{11})"#,
    ]

    /// All distinct video IDs found in `text`, in order of appearance.
    /// Accepts watch/shorts/live/embed/youtu.be links; a lone 11-char token counts only if it is the whole input.
    public static func videoIDs(in text: String) -> [String] {
        var ids: [String] = []
        for pattern in patterns {
            let regex = try! NSRegularExpression(pattern: pattern)
            let range = NSRange(text.startIndex..., in: text)
            for match in regex.matches(in: text, range: range) {
                if let r = Range(match.range(at: 1), in: text) {
                    let id = String(text[r])
                    if !ids.contains(id) { ids.append(id) }
                }
            }
        }
        let bare = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if ids.isEmpty, bare.range(of: #"^[A-Za-z0-9_-]{11}$"#, options: .regularExpression) != nil {
            ids.append(bare)
        }
        return ids
    }
}
