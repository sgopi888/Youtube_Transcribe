import Foundation

public enum KaraokeModel: String, CaseIterable, Identifiable, Sendable {
    case htdemucsCoreML, bsRoformer
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .htdemucsCoreML: return "Fast: HTDemucs (Core ML)"
        case .bsRoformer: return "Best quality: BS-Roformer Viperx 1297"
        }
    }
    public var engine: StemEngine {
        switch self {
        case .htdemucsCoreML: return DemucsCoreMLEngine()
        case .bsRoformer: return RoformerEngine()
        }
    }
}

/// Removes all vocals from `input` and writes the result as an MP3 at `output`.
public protocol StemEngine: Sendable {
    func makeInstrumental(input: URL, output: URL, progress: @escaping @Sendable (Double) -> Void) async throws
}

public enum KaraokeError: LocalizedError {
    case toolMissing(String)
    case modelMissing(String)
    case unsupportedOS(String)
    case failed(String)
    public var errorDescription: String? {
        switch self {
        case .toolMissing(let t): return "\(t) was not found."
        case .modelMissing(let m): return m
        case .unsupportedOS(let m): return m
        case .failed(let m): return m.isEmpty ? "Karaoke generation failed." : m
        }
    }
}

public enum Library {
    /// ~/Music/YTScribe: where downloaded MP3s live.
    public static var musicDir: URL {
        FileManager.default.urls(for: .musicDirectory, in: .userDomainMask)[0].appendingPathComponent("YTScribe")
    }
    /// ~/Downloads/YTScribe: one `<title> [id]` folder per summary, holding summary.md and transcript.txt.
    public static var summariesDir: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0].appendingPathComponent("YTScribe")
    }
    public static var originalsDir: URL { musicDir.appendingPathComponent("Originals") }
    public static var karaokeDir: URL { musicDir.appendingPathComponent("Karaoke") }

    /// Songs saved straight in ~/Music/YTScribe by earlier versions move into `originalsDir`. Never overwrites.
    public static func migrateLegacyOriginals(musicDir: URL = musicDir, originalsDir: URL = originalsDir) {
        let fm = FileManager.default
        let legacy = ((try? fm.contentsOfDirectory(at: musicDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? [])
            .filter { LibraryIndex.audioExtensions.contains($0.pathExtension.lowercased()) }
        guard !legacy.isEmpty else { return }
        try? fm.createDirectory(at: originalsDir, withIntermediateDirectories: true)
        for f in legacy {
            let dest = originalsDir.appendingPathComponent(f.lastPathComponent)
            if !fm.fileExists(atPath: dest.path) { try? fm.moveItem(at: f, to: dest) }
        }
    }
    public static var supportDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("YTScribe")
    }

    /// `<song> (karaoke).mp3` in `karaokeDir`; adds the model tag so two engines never overwrite each other.
    public static func karaokeURL(for input: URL, model: KaraokeModel, in dir: URL = karaokeDir) -> URL {
        let base = input.deletingPathExtension().lastPathComponent
        let tag = model == .bsRoformer ? " (karaoke, roformer)" : " (karaoke)"
        return dir.appendingPathComponent(base + tag + ".mp3")
    }
}

/// Runs a command and returns (exit status, stderr). Used for ffmpeg and the Roformer CLI.
func runProcess(_ exe: URL, _ args: [String], env: [String: String]? = nil, onStdoutLine: (@Sendable (String) -> Void)? = nil,
                onStderrLine: (@Sendable (String) -> Void)? = nil) async throws -> (Int32, String) {
    let p = Process()
    p.executableURL = exe
    p.arguments = args
    if let env { p.environment = ProcessInfo.processInfo.environment.merging(env) { $1 } }
    let out = Pipe(), err = Pipe()
    p.standardOutput = out; p.standardError = err
    let tail = TailBox()
    out.fileHandleForReading.readabilityHandler = { h in
        let d = h.availableData
        guard !d.isEmpty else { return }
        for l in String(decoding: d, as: UTF8.self).split(whereSeparator: { $0 == "\n" || $0 == "\r" }) { onStdoutLine?(String(l)) }
    }
    err.fileHandleForReading.readabilityHandler = { h in
        let d = h.availableData
        guard !d.isEmpty else { return }
        let s = String(decoding: d, as: UTF8.self)
        tail.append(s)
        for l in s.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) { onStderrLine?(String(l)) }
    }
    return try await withCheckedThrowingContinuation { cont in
        p.terminationHandler = { proc in
            out.fileHandleForReading.readabilityHandler = nil
            err.fileHandleForReading.readabilityHandler = nil
            cont.resume(returning: (proc.terminationStatus, tail.text))
        }
        do { try p.run() } catch { cont.resume(throwing: error) }
    }
}

private final class TailBox: @unchecked Sendable {
    private var s = ""; private let l = NSLock()
    func append(_ x: String) { l.lock(); s += x; if s.count > 8000 { s = String(s.suffix(8000)) }; l.unlock() }
    var text: String { l.lock(); defer { l.unlock() }; return s }
}

enum FFmpeg {
    static func locate() throws -> URL {
        guard let f = AudioDownloader.locate("ffmpeg") else { throw KaraokeError.toolMissing("ffmpeg") }
        return f
    }

    /// Decodes any audio file to raw interleaved 44.1 kHz stereo float32.
    static func decodeToRaw(_ input: URL, raw: URL) async throws {
        let (code, err) = try await runProcess(try locate(), ["-y", "-v", "error", "-i", input.path, "-vn", "-f", "f32le", "-ac", "2", "-ar", "44100", raw.path])
        guard code == 0 else { throw KaraokeError.failed("Could not read the audio file. " + err.suffix(300)) }
    }

    /// Encodes `source` to MP3 VBR V0.
    static func encodeMP3(from source: URL, rawFloat: Bool, to output: URL, title: String) async throws {
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        let inArgs = rawFloat ? ["-f", "f32le", "-ar", "44100", "-ac", "2", "-i", source.path] : ["-i", source.path]
        let (code, err) = try await runProcess(try locate(), ["-y", "-v", "error"] + inArgs + ["-codec:a", "libmp3lame", "-q:a", "0", "-metadata", "title=\(title)", output.path])
        guard code == 0 else { throw KaraokeError.failed("MP3 encoding failed. " + err.suffix(300)) }
    }
}
