import SwiftUI
import AVFoundation

/// Peak amplitudes of an audio file, decoded off the main thread and cached per path.
@MainActor
final class WaveformCache: ObservableObject {
    static let shared = WaveformCache()
    @Published private(set) var peaks: [String: [Float]] = [:]
    private var loading: Set<String> = []

    func peaks(for url: URL, bins: Int = 160) -> [Float]? {
        if let p = peaks[url.path] { return p }
        guard !loading.contains(url.path) else { return nil }
        loading.insert(url.path)
        Task.detached(priority: .utility) {
            let p = Self.load(url, bins: bins)
            await MainActor.run { self.peaks[url.path] = p; self.loading.remove(url.path) }
        }
        return nil
    }

    nonisolated static func load(_ url: URL, bins: Int) -> [Float] {
        guard let file = try? AVAudioFile(forReading: url), file.length > 0,
              let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 8192) else { return [] }
        let perBin = max(1, Int(file.length) / bins)
        var out = [Float](repeating: 0, count: bins)
        var frame = 0
        while (try? file.read(into: buf)) != nil, buf.frameLength > 0, let ch = buf.floatChannelData?[0] {
            // shortcut: samples every 8th frame of channel 0, enough for a display waveform.
            for i in stride(from: 0, to: Int(buf.frameLength), by: 8) {
                let b = min(bins - 1, (frame + i) / perBin)
                out[b] = max(out[b], abs(ch[i]))
            }
            frame += Int(buf.frameLength)
        }
        let top = max(out.max() ?? 1, 0.001)
        return out.map { $0 / top }
    }
}

/// Mirrored bar waveform; bars left of `progress` take the active tint, plus a playhead.
struct WaveformView: View {
    let url: URL?
    var progress: Double = 0
    var tint: Color = Theme.tertiary
    var showsPlayhead = true
    var onSeek: ((Double) -> Void)? = nil
    @ObservedObject private var cache = WaveformCache.shared

    var body: some View {
        GeometryReader { g in
            let peaks = url.flatMap { cache.peaks(for: $0) } ?? Array(repeating: Float(0.08), count: 160)
            let w = g.size.width / CGFloat(peaks.count)
            ZStack(alignment: .leading) {
                HStack(alignment: .center, spacing: 0) {
                    ForEach(peaks.indices, id: \.self) { i in
                        let played = Double(i) / Double(peaks.count) < progress
                        Capsule()
                            .fill(played ? tint : Theme.outline.opacity(0.35))
                            .frame(width: max(1, w * 0.55), height: max(2, CGFloat(peaks[i]) * g.size.height * 0.9))
                            .frame(width: w)
                    }
                }
                .frame(maxHeight: .infinity)
                if showsPlayhead && progress > 0 {
                    Rectangle().fill(.white).frame(width: 1.5)
                        .shadow(color: .white.opacity(0.8), radius: 3)
                        .offset(x: g.size.width * progress)
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onEnded { v in onSeek?(min(max(v.location.x / g.size.width, 0), 1)) })
        }
    }
}
