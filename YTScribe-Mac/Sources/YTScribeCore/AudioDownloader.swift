import Foundation

public enum AudioError: LocalizedError {
    case toolMissing(String)
    case failed(String)
    public var errorDescription: String? {
        switch self {
        case .toolMissing(let t): return "\(t) was not found. Reinstall the app or run `brew install \(t)`."
        case .failed(let m): return m.isEmpty ? "Audio download failed." : m
        }
    }
}

public enum AudioEvent: Equatable {
    case title(String)
    case progress(Double)  // 0...100
    case file(URL)
}

/// Downloads YouTube's best audio stream and encodes it to MP3 (VBR V0, ~245 kbps) with yt-dlp + ffmpeg.
/// The MP3 is a second lossy step on top of YouTube's Opus/AAC; V0 keeps that loss inaudible.
public struct AudioDownloader: Sendable {
    public let ytdlp: URL
    public let ffmpeg: URL
    /// YouTube hides the real audio streams behind a JS challenge; without a runtime only HLS dubs show up.
    public let node: URL?

    public init() throws {
        guard let y = Self.locate("yt-dlp") else { throw AudioError.toolMissing("yt-dlp") }
        guard let f = Self.locate("ffmpeg") else { throw AudioError.toolMissing("ffmpeg") }
        ytdlp = y; ffmpeg = f; node = Self.locate("node")
    }

    /// App bundle first (shipped copy), then Homebrew.
    static func locate(_ name: String) -> URL? {
        let nvm = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".nvm/versions/node")
        let nvmBins = ((try? FileManager.default.contentsOfDirectory(atPath: nvm.path)) ?? []).sorted().reversed().map { nvm.appendingPathComponent($0).appendingPathComponent("bin").path }
        // YT_TOOLS_DIR is a dev/test override.
        let dirs = [ProcessInfo.processInfo.environment["YT_TOOLS_DIR"], Bundle.main.resourceURL?.path, "/opt/homebrew/bin", "/usr/local/bin"].compactMap { $0 } + nvmBins
        return dirs.map { URL(fileURLWithPath: $0).appendingPathComponent(name) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static func arguments(url: String, outDir: URL, ffmpegDir: URL, node: URL? = nil) -> [String] {
        (node.map { ["--js-runtimes", "node:\($0.path)"] } ?? []) + ["-f", "bestaudio", "-x", "--audio-format", "mp3", "--audio-quality", "0",
         "--embed-metadata", "--no-playlist", "--no-simulate", "--newline",
         "--ffmpeg-location", ffmpegDir.path,
         "--print", "before_dl:TITLE\t%(title)s",
         "--print", "after_move:FILE\t%(filepath)s",
         "--progress-template", "download:PCT\t%(progress._percent_str)s",
         "-o", outDir.appendingPathComponent("%(title).80s [%(id)s].%(ext)s").path,
         url]
    }

    static func parse(line: String) -> AudioEvent? {
        let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        switch parts[0] {
        case "TITLE": return .title(parts[1])
        case "FILE": return .file(URL(fileURLWithPath: parts[1].trimmingCharacters(in: .whitespacesAndNewlines)))
        case "PCT":
            let n = parts[1].replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)
            return Double(n).map { .progress($0) }
        default: return nil
        }
    }

    /// MP4 qualities. Fixed heights prefer H.264 + AAC so QuickTime plays the file; "best" takes the highest
    /// resolution, which on YouTube is often VP9/AV1 (plays in IINA/VLC/browsers, not always QuickTime).
    public static let videoQualities: [(id: String, title: String)] = [("best", "Best (up to 4K)"), ("1080", "1080p"), ("720", "720p"), ("480", "480p"), ("360", "360p")]

    static func videoArguments(url: String, outDir: URL, quality: String, ffmpegDir: URL, node: URL? = nil) -> [String] {
        let sort = quality == "best" ? "res,fps" : "res:\(quality),vcodec:h264,acodec:m4a"
        return (node.map { ["--js-runtimes", "node:\($0.path)"] } ?? []) + ["-f", "bv*+ba/b", "-S", sort, "--merge-output-format", "mp4",
         "--embed-metadata", "--no-playlist", "--no-simulate", "--newline",
         "--ffmpeg-location", ffmpegDir.path,
         "--print", "before_dl:TITLE\t%(title)s",
         "--print", "after_move:FILE\t%(filepath)s",
         "--progress-template", "download:PCT\t%(progress._percent_str)s",
         "-o", outDir.appendingPathComponent("%(title).80s [%(id)s] \(quality).%(ext)s").path,
         url]
    }

    /// Downloads the video as MP4 at `quality` (an id from `videoQualities`). Returns the MP4 URL.
    public func downloadVideo(videoID: String, outDir: URL, quality: String, onEvent: @escaping @Sendable (AudioEvent) -> Void) async throws -> URL {
        try await run(Self.videoArguments(url: "https://www.youtube.com/watch?v=\(videoID)", outDir: outDir, quality: quality,
                                          ffmpegDir: ffmpeg.deletingLastPathComponent(), node: node), outDir: outDir, onEvent: onEvent)
    }

    /// Runs the download; `onEvent` is called for title, progress and the final file. Returns the MP3 URL.
    public func download(videoID: String, outDir: URL, onEvent: @escaping @Sendable (AudioEvent) -> Void) async throws -> URL {
        try await run(Self.arguments(url: "https://www.youtube.com/watch?v=\(videoID)", outDir: outDir, ffmpegDir: ffmpeg.deletingLastPathComponent(), node: node),
                      outDir: outDir, onEvent: onEvent)
    }

    private func run(_ arguments: [String], outDir: URL, onEvent: @escaping @Sendable (AudioEvent) -> Void) async throws -> URL {
        try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let p = Process()
        p.executableURL = ytdlp
        p.arguments = arguments
        let out = Pipe(), err = Pipe()
        p.standardOutput = out; p.standardError = err

        let box = Box()
        out.fileHandleForReading.readabilityHandler = { h in
            let data = h.availableData
            guard !data.isEmpty else { return }
            for line in String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline) {
                guard let ev = Self.parse(line: String(line)) else { continue }
                if case .file(let u) = ev { box.file = u }
                onEvent(ev)
            }
        }
        let errData = ErrBox()
        err.fileHandleForReading.readabilityHandler = { h in errData.append(h.availableData) }

        return try await withCheckedThrowingContinuation { cont in
            p.terminationHandler = { proc in
                out.fileHandleForReading.readabilityHandler = nil
                err.fileHandleForReading.readabilityHandler = nil
                if proc.terminationStatus == 0, let f = box.file, FileManager.default.fileExists(atPath: f.path) {
                    cont.resume(returning: f)
                } else {
                    let msg = errData.text.split(separator: "\n").last(where: { $0.contains("ERROR") }).map(String.init) ?? errData.text
                    cont.resume(throwing: AudioError.failed(msg.trimmingCharacters(in: .whitespacesAndNewlines)))
                }
            }
            do { try p.run() } catch { cont.resume(throwing: error) }
        }
    }
}

private final class Box: @unchecked Sendable { var file: URL? }
private final class ErrBox: @unchecked Sendable {
    private var data = Data()
    private let lock = NSLock()
    func append(_ d: Data) { lock.lock(); data.append(d); lock.unlock() }
    var text: String { lock.lock(); defer { lock.unlock() }; return String(decoding: data, as: UTF8.self) }
}
