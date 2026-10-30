import Foundation

public struct Transcript: Sendable {
    public let videoID: String
    public let title: String
    public let text: String
}

public enum TranscriptError: LocalizedError {
    case unparsable
    case unplayable(String)
    case noCaptions
    case http(Int)

    public var errorDescription: String? {
        switch self {
        case .unparsable: return "Could not read YouTube's response (page format may have changed)."
        case .unplayable(let why): return "Video not available: \(why)"
        case .noCaptions: return "This video has no captions, so there is nothing to transcribe."
        case .http(let code): return "YouTube returned HTTP \(code)."
        }
    }
}

/// Fetches captions through YouTube's InnerTube player API, the same flow `youtube-transcript-api` uses.
/// (yt-dlp's subtitle download was rate-limited with HTTP 429 on this network; this path was not.)
public struct TranscriptFetcher: Sendable {
    private static let clientVersion = "20.10.38"
    private let session: URLSession

    public init(session: URLSession = .shared) { self.session = session }

    public func fetch(videoID: String, languages: [String] = ["en", "hi"]) async throws -> Transcript {
        let html = try await watchPage(videoID)
        guard let key = Self.firstMatch(#""INNERTUBE_API_KEY":\s*"([A-Za-z0-9_-]+)""#, in: html) else {
            throw TranscriptError.unparsable
        }
        let player = try await playerResponse(videoID: videoID, apiKey: key)

        let status = player["playabilityStatus"] as? [String: Any]
        if let s = status?["status"] as? String, s != "OK" {
            throw TranscriptError.unplayable((status?["reason"] as? String) ?? s)
        }
        let tracks = ((player["captions"] as? [String: Any])?["playerCaptionsTracklistRenderer"] as? [String: Any])?["captionTracks"] as? [[String: Any]]
        guard let track = Self.pickTrack(tracks ?? [], languages: languages), let base = track["baseUrl"] as? String else {
            throw TranscriptError.noCaptions
        }
        let url = URL(string: base.replacingOccurrences(of: "&fmt=srv3", with: ""))!
        let (data, resp) = try await session.data(from: url)
        try Self.check(resp)
        let title = ((player["videoDetails"] as? [String: Any])?["title"] as? String) ?? videoID
        return Transcript(videoID: videoID, title: title, text: Self.parseCaptionXML(data))
    }

    // MARK: network

    private func watchPage(_ id: String) async throws -> String {
        var req = URLRequest(url: URL(string: "https://www.youtube.com/watch?v=\(id)")!)
        req.setValue("en-US", forHTTPHeaderField: "Accept-Language")
        var html = try await text(req)
        if html.contains(#"action="https://consent.youtube.com/s""#),
           let v = Self.firstMatch(#"name="v" value="(.*?)""#, in: html) {
            req.setValue("CONSENT=YES+\(v)", forHTTPHeaderField: "Cookie")
            html = try await text(req)
        }
        return Self.unescapeHTML(html)
    }

    private func text(_ req: URLRequest) async throws -> String {
        let (data, resp) = try await session.data(for: req)
        try Self.check(resp)
        return String(decoding: data, as: UTF8.self)
    }

    private func playerResponse(videoID: String, apiKey: String) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: "https://www.youtube.com/youtubei/v1/player?key=\(apiKey)")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "context": ["client": ["clientName": "ANDROID", "clientVersion": Self.clientVersion]],
            "videoId": videoID,
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await session.data(for: req)
        try Self.check(resp)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw TranscriptError.unparsable }
        return json
    }

    private static func check(_ resp: URLResponse) throws {
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { throw TranscriptError.http(http.statusCode) }
    }

    // MARK: parsing (internal for tests)

    /// For each preferred language: manual captions first, then auto-generated. Falls back to the first track.
    static func pickTrack(_ tracks: [[String: Any]], languages: [String]) -> [String: Any]? {
        for lang in languages {
            let matches = tracks.filter { ($0["languageCode"] as? String) == lang }
            if let manual = matches.first(where: { ($0["kind"] as? String) != "asr" }) ?? matches.first { return manual }
        }
        return tracks.first
    }

    static func parseCaptionXML(_ data: Data) -> String {
        let collector = CaptionCollector()
        let parser = XMLParser(data: data)
        parser.delegate = collector
        parser.parse()
        let joined = collector.lines
            .map { unescapeHTML($0).replacingOccurrences(of: #"<[^>]*>"#, with: "", options: .regularExpression) }
            .joined(separator: " ")
        return joined.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// YouTube double-escapes caption text (e.g. `&amp;#39;`), so the XML parser's single decode isn't enough.
    static func unescapeHTML(_ s: String) -> String {
        var out = s
        for (k, v) in [("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " ")] {
            out = out.replacingOccurrences(of: k, with: v)
        }
        let regex = try! NSRegularExpression(pattern: #"&#(x?[0-9A-Fa-f]+);"#)
        for m in regex.matches(in: out, range: NSRange(out.startIndex..., in: out)).reversed() {
            guard let whole = Range(m.range, in: out), let num = Range(m.range(at: 1), in: out) else { continue }
            let raw = out[num]
            let code = raw.hasPrefix("x") ? UInt32(raw.dropFirst(), radix: 16) : UInt32(raw)
            if let code, let scalar = Unicode.Scalar(code) { out.replaceSubrange(whole, with: String(Character(scalar))) }
        }
        return out.replacingOccurrences(of: "&amp;", with: "&")
    }

    static func firstMatch(_ pattern: String, in s: String) -> String? {
        guard let m = s.range(of: pattern, options: .regularExpression) else { return nil }
        let regex = try! NSRegularExpression(pattern: pattern)
        guard let r = regex.firstMatch(in: s, range: NSRange(m, in: s)), let g = Range(r.range(at: 1), in: s) else { return nil }
        return String(s[g])
    }
}

private final class CaptionCollector: NSObject, XMLParserDelegate {
    var lines: [String] = []
    private var current: String?

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        if name == "text" { current = "" }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { current? += string }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if name == "text", let c = current, !c.isEmpty { lines.append(c) }
        if name == "text" { current = nil }
    }
}
