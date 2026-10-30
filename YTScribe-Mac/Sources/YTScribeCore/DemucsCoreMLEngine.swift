import Foundation
import CoreML
import Accelerate

/// Predicts one 10 s window (2 x 441000 floats, channel-major, already normalized) and returns the
/// instrumental part (drums + bass + other) in the same layout and scale.
protocol WindowPredictor {
    func instrumental(window: [Float]) throws -> [Float]
}

/// The windowing math, separated from Core ML so it can be tested with a fake predictor.
/// Whole-track normalization, 10 s windows at 50% overlap, Hann-weighted overlap-add (the approach Demucs uses).
enum DemucsPipeline {
    static let sampleRate = 44_100
    static let chunk = 441_000
    static let hop = 220_500

    /// `left`/`right` are the decoded channels; returns the instrumental channels.
    static func run(left: [Float], right: [Float], predictor: WindowPredictor, progress: (Double) -> Void) throws -> ([Float], [Float]) {
        let n = left.count
        precondition(right.count == n)
        guard n > 0 else { return ([], []) }

        // Normalize by the mono mix's mean and standard deviation.
        var mono = [Float](repeating: 0, count: n)
        vDSP_vadd(left, 1, right, 1, &mono, 1, vDSP_Length(n))
        var mean: Float = 0, std: Float = 0
        vDSP_normalize(mono, 1, nil, 1, &mean, &std, vDSP_Length(n))
        mean /= 2; std /= 2  // mono was L+R, not (L+R)/2
        std = max(std, 1e-4)

        var window = [Float](repeating: 0, count: chunk)
        vDSP_hann_window(&window, vDSP_Length(chunk), Int32(vDSP_HANN_DENORM))
        var accL = [Float](repeating: 0, count: n), accR = [Float](repeating: 0, count: n)
        var weight = [Float](repeating: 0, count: n)
        var input = [Float](repeating: 0, count: 2 * chunk)
        let instrumentalMean = mean * 3 / 4  // the mix mean is shared across four stems; drums+bass+other get three quarters

        let total = (n + hop - 1) / hop + 1
        for c in 0..<total {
            let start = c * hop - hop
            for i in 0..<chunk {
                let idx = start + i
                if idx >= 0 && idx < n {
                    input[i] = (left[idx] - mean) / std
                    input[chunk + i] = (right[idx] - mean) / std
                } else {
                    input[i] = 0; input[chunk + i] = 0
                }
            }
            let out = try predictor.instrumental(window: input)
            let lo = max(0, -start), hi = min(chunk, n - start)
            if hi > lo {
                for i in lo..<hi {
                    let idx = start + i, w = window[i]
                    accL[idx] += (out[i] * std + instrumentalMean) * w
                    accR[idx] += (out[chunk + i] * std + instrumentalMean) * w
                    weight[idx] += w
                }
            }
            progress(Double(c + 1) / Double(total))
        }
        for i in 0..<n {
            let w = max(weight[i], 1e-5)
            accL[i] /= w; accR[i] /= w
        }
        return (accL, accR)
    }
}

private struct CoreMLPredictor: WindowPredictor {
    let model: MLModel
    let input: MLMultiArray

    func instrumental(window: [Float]) throws -> [Float] {
        let n = DemucsPipeline.chunk
        window.withUnsafeBufferPointer { src in
            input.dataPointer.assumingMemoryBound(to: Float.self).update(from: src.baseAddress!, count: 2 * n)
        }
        let provider = try MLDictionaryFeatureProvider(dictionary: ["audio": MLFeatureValue(multiArray: input)])
        let result = try model.prediction(from: provider)
        guard let out = result.featureValue(for: "sources")?.multiArrayValue, out.shape.map(\.intValue) == [1, 4, 2, n] else {
            throw KaraokeError.failed("The model returned an unexpected output shape.")
        }
        let s = out.strides.map(\.intValue)
        var sum = [Float](repeating: 0, count: 2 * n)
        // Stem order from this model: vocals(0), drums(1), bass(2), other(3). Sum 1...3 = everything but vocals.
        out.withUnsafeBytes { raw in
            for stem in 1...3 {
                for ch in 0..<2 {
                    let base = stem * s[1] + ch * s[2]
                    if out.dataType == .float32 {
                        let p = raw.baseAddress!.assumingMemoryBound(to: Float.self)
                        for i in 0..<n { sum[ch * n + i] += p[base + i * s[3]] }
                    } else {
                        let p = raw.baseAddress!.assumingMemoryBound(to: Float16.self)
                        for i in 0..<n { sum[ch * n + i] += Float(p[base + i * s[3]]) }
                    }
                }
            }
        }
        return sum
    }
}

/// HTDemucs v4 converted to Core ML. No Python. The model is data only; it lives in
/// ~/Library/Application Support/YTScribe/HTDemucs.mlmodelc (see Library.supportDir).
public struct DemucsCoreMLEngine: StemEngine {
    public static let modelURL = Library.supportDir.appendingPathComponent("HTDemucs.mlmodelc")
    public init() {}

    public func makeInstrumental(input: URL, output: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        // Isolate's testing found Core ML on macOS 14/15 computes this model wrongly on some paths; 26+ is correct everywhere.
        guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 else {
            throw KaraokeError.unsupportedOS("The Core ML engine needs macOS 26 or later. Use the Roformer model on this Mac.")
        }
        guard FileManager.default.fileExists(atPath: Self.modelURL.path) else {
            throw KaraokeError.modelMissing("The HTDemucs model is not installed. Expected at \(Self.modelURL.path).")
        }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("ytscribe-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        progress(0.02)
        let raw = tmp.appendingPathComponent("in.f32")
        try await FFmpeg.decodeToRaw(input, raw: raw)
        let data = try Data(contentsOf: raw, options: .mappedIfSafe)
        let frames = data.count / 8
        guard frames > 0 else { throw KaraokeError.failed("The audio file is empty.") }
        var left = [Float](repeating: 0, count: frames), right = left
        data.withUnsafeBytes { b in
            let p = b.bindMemory(to: Float.self)
            for i in 0..<frames { left[i] = p[2 * i]; right[i] = p[2 * i + 1] }
        }

        let (l, r) = try await Task.detached(priority: .userInitiated) { () -> ([Float], [Float]) in
            let config = MLModelConfiguration()
            config.computeUnits = .all
            let model = try MLModel(contentsOf: Self.modelURL, configuration: config)
            let arr = try MLMultiArray(shape: [1, 2, NSNumber(value: DemucsPipeline.chunk)], dataType: .float32)
            return try DemucsPipeline.run(left: left, right: right, predictor: CoreMLPredictor(model: model, input: arr)) { progress(0.05 + 0.85 * $0) }
        }.value

        var interleaved = [Float](repeating: 0, count: 2 * frames)
        for i in 0..<frames { interleaved[2 * i] = l[i]; interleaved[2 * i + 1] = r[i] }
        let out = tmp.appendingPathComponent("out.f32")
        try interleaved.withUnsafeBytes { try Data($0).write(to: out) }
        try await FFmpeg.encodeMP3(from: out, rawFloat: true, to: output, title: input.deletingPathExtension().lastPathComponent + " (karaoke)")
        progress(1)
    }
}
