import Foundation

/// BS-Roformer (Viperx 1297) through `audio-separator` in a private Python venv under Application Support.
/// Set up once by `scripts/setup_roformer.sh` (the app runs it automatically on first use).
public struct RoformerEngine: StemEngine {
    public static let modelFile = "model_bs_roformer_ep_317_sdr_12.9755.ckpt"
    public static var venvDir: URL { Library.supportDir.appendingPathComponent("roformer/venv") }
    public static var modelsDir: URL { Library.supportDir.appendingPathComponent("roformer/models") }
    static var executable: URL { venvDir.appendingPathComponent("bin/audio-separator") }
    public static var isInstalled: Bool { FileManager.default.isExecutableFile(atPath: executable.path) }

    public init() {}

    /// Runs the bundled setup script (first use only). Returns when the venv is ready.
    public static func setUp(onLine: @escaping @Sendable (String) -> Void = { _ in }) async throws {
        let script = [Bundle.main.resourceURL?.appendingPathComponent("setup_roformer.sh"),
                      URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../scripts/setup_roformer.sh").standardized]
            .compactMap { $0 }.first { FileManager.default.isExecutableFile(atPath: $0.path) }
        guard let script else { throw KaraokeError.modelMissing("setup_roformer.sh was not found.") }
        let (code, err) = try await runProcess(script, [], onStdoutLine: onLine, onStderrLine: onLine)
        guard code == 0, isInstalled else { throw KaraokeError.failed("Roformer setup failed. " + err.suffix(300)) }
    }

    static func arguments(input: URL, outDir: URL) -> [String] {
        [input.path, "--model_filename", modelFile, "--model_file_dir", modelsDir.path,
         "--output_dir", outDir.path, "--output_format", "WAV", "--single_stem", "Instrumental"]
    }

    public func makeInstrumental(input: URL, output: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        guard Self.isInstalled else {
            throw KaraokeError.modelMissing("The Roformer engine is not set up yet. Run scripts/setup_roformer.sh once (it needs internet).")
        }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("ytscribe-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try FileManager.default.createDirectory(at: Self.modelsDir, withIntermediateDirectories: true)

        progress(0.03)
        // audio-separator prints tqdm bars like " 45%|" on stderr; scrape the percentage for the progress bar.
        let (code, err) = try await runProcess(Self.executable, Self.arguments(input: input, outDir: tmp),
                                               env: ["PYTORCH_ENABLE_MPS_FALLBACK": "1"],
                                               onStdoutLine: nil,
                                               onStderrLine: { line in
            if let r = line.range(of: #"(\d{1,3})%\|"#, options: .regularExpression),
               let pct = Double(line[r].dropLast(2)) { progress(0.05 + 0.8 * min(pct, 100) / 100) }
        })
        guard code == 0 else { throw KaraokeError.failed(String(err.suffix(400))) }
        let outputs = (try? FileManager.default.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil)) ?? []
        guard let wav = outputs.first(where: { $0.pathExtension.lowercased() == "wav" && $0.lastPathComponent.contains("Instrumental") }) ?? outputs.first(where: { $0.pathExtension.lowercased() == "wav" }) else {
            throw KaraokeError.failed("The separator produced no output file.")
        }
        try await FFmpeg.encodeMP3(from: wav, rawFloat: false, to: output, title: input.deletingPathExtension().lastPathComponent + " (karaoke)")
        progress(1)
    }
}
