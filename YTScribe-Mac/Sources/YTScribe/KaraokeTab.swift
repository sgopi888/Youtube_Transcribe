import SwiftUI
import AppKit
import YTScribeCore

/// Karaoke AI tab: ingest drop zone, model engine + objective, stem workspace, separation queue.
struct KaraokeTab: View {
    @EnvironmentObject var store: JobStore

    private var jobs: [AudioJob] { store.audioJobs.filter(\.karaokeOnly) }
    private var selected: AudioJob? { jobs.first { $0.id == store.audioSelection } ?? jobs.first }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                topStrip
                HStack(alignment: .top, spacing: 16) {
                    ingestCard.frame(maxWidth: .infinity)
                    VStack(spacing: 16) { engineCard; objectiveCard }.frame(width: 380)
                }
                if let job = selected { StemWorkspace(job: job) }
                queue
            }
            .padding(16)
        }
        .scrollIndicators(.hidden)
    }

    private var topStrip: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                StatusDot()
                Text("Local Separation").font(.ui(13, .medium))
                Text("Core ML · PyTorch MPS").font(.mono(11.5)).foregroundStyle(Theme.variant)
            }
            .padding(.horizontal, 12).padding(.vertical, 6).background(Theme.container, in: Capsule())
            HStack(spacing: 6) {
                Image(systemName: "lock").font(.ui(12)).foregroundStyle(Theme.primary)
                Text("0 Cloud Uploads • 100% Offline Processing").font(.ui(12.5, .medium))
            }
            .padding(.horizontal, 12).padding(.vertical, 6).background(Theme.container, in: Capsule())
            Spacer()
            Text("Output Directory:").font(.mono(11.5)).foregroundStyle(Theme.variant)
            Button(tildePath(Library.karaokeDir)) { revealInFinder(Library.karaokeDir) }
                .buttonStyle(.plain).font(.mono(12)).foregroundStyle(Theme.tertiary)
                .padding(.horizontal, 8).padding(.vertical, 4).background(Theme.lowest, in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private var ingestCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 6) {
                Text("Audio Stem Ingest").font(.ui(12, .medium)).tracking(1).textCase(.uppercase)
                StatusDot(size: 6)
                Text("Ready").font(.mono(11.5)).foregroundStyle(Theme.tertiary)
                Spacer()
                Tag(text: "⌘O")
            }
            Spacer(minLength: 8)
            ZStack {
                Circle().fill(Theme.high.opacity(0.6)).frame(width: 96, height: 96)
                Image(systemName: "waveform").font(.ui(28, .medium)).foregroundStyle(Theme.tertiary)
                    .frame(width: 64, height: 64).background(Theme.lowest, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            Text("Drop MP3, WAV, or FLAC here").font(.ui(20, .semibold)).tracking(-0.3)
            Text("Vocal separation runs locally on Apple Silicon.\nIt starts as soon as a file arrives, with the model chosen on the right.")
                .font(.ui(13.5)).foregroundStyle(Theme.variant).multilineTextAlignment(.center)
            HStack(spacing: 8) {
                Button { chooseAudioFiles(store, in: Library.originalsDir) } label: { Label("Choose from ~/Music/YTScribe/", systemImage: "folder") }.buttonStyle(.glass)
                Button { chooseAudioFiles(store) } label: { Label("Browse Finder…", systemImage: "square.and.arrow.up") }
                    .buttonStyle(.ghost).keyboardShortcut("o")
            }
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                ForEach(["MP3", "WAV", "FLAC", "M4A / AAC", "AIFF / OGG"], id: \.self) { Tag(text: $0) }
                Spacer()
                Text("Batch Multi-Drop Supported").font(.mono(11)).foregroundStyle(Theme.variant)
            }
        }
        .frame(minHeight: 380)
        .padding(20)
        .background(
            RadialGradient(colors: [Theme.high.opacity(0.9), Theme.low], center: .top, startRadius: 10, endRadius: 420),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var engineCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Separation Model Engine", systemImage: "cpu").font(.ui(14, .semibold))
                Spacer()
                Tag(text: "\(KaraokeModel.allCases.count) engines", tint: Theme.secondary, fill: Theme.secondaryContainer.opacity(0.4))
            }
            ForEach(KaraokeModel.allCases) { m in
                let on = store.karaokeModel == m
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        if on { StatusDot(size: 6) }
                        Text(Self.name(m)).font(.ui(on ? 15 : 13.5, on ? .semibold : .medium))
                        Spacer()
                        Text(m == .bsRoformer ? "BEST QUALITY" : "FAST").font(.mono(10, .medium)).foregroundStyle(Theme.tertiary)
                            .padding(.horizontal, 5).padding(.vertical, 2).background(Theme.lowest, in: RoundedRectangle(cornerRadius: 3))
                    }
                    Text(Self.detail(m)).font(.ui(12.5)).foregroundStyle(Theme.variant).fixedSize(horizontal: false, vertical: true)
                    Text(Self.meta(m)).font(.mono(10.5)).foregroundStyle(Theme.tertiary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(on ? Theme.high : Theme.container, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .contentShape(Rectangle())
                .onTapGesture { store.karaokeModel = m }
            }
        }
        .card(16)
    }

    static func name(_ m: KaraokeModel) -> String { m == .bsRoformer ? "BS-Roformer Viperx 1297" : "HTDemucs v4 (Core ML)" }
    static func detail(_ m: KaraokeModel) -> String {
        m == .bsRoformer ? "State-of-the-art vocal boundary detection. Runs in a private Python environment on PyTorch MPS."
                         : "Bundled Core ML model. Vocals vs. drums, bass and other, merged back without the vocals."
    }
    static func meta(_ m: KaraokeModel) -> String {
        m == .bsRoformer ? (RoformerEngine.isInstalled ? "Installed • Slower, cleaner" : "One-time setup on first use • needs internet")
                         : "No setup • Starts instantly"
    }

    private var objectiveCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Separation Objective").font(.ui(14, .semibold))
                Spacer()
                Text("Output: MP3").font(.mono(11)).foregroundStyle(Theme.variant)
            }
            HStack(alignment: .top, spacing: 8) {
                objective("music.note", "Instrumental Mode", "Complete vocal subtraction. Outputs a clean backing track.", on: true)
                objective("mic", "Karaoke Mode", "Keeps backing vocals, strips the lead. Not available yet.", on: false).opacity(0.45)
            }
        }
        .card(16)
    }

    private func objective(_ icon: String, _ title: String, _ text: String, on: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon).font(.ui(16)).foregroundStyle(on ? Theme.tertiary : Theme.variant)
                Spacer()
                Circle().strokeBorder(on ? Theme.tertiary : Theme.outlineVariant, lineWidth: on ? 4 : 1.5).frame(width: 16, height: 16)
            }
            Text(title).font(.ui(13.5, .semibold))
            Text(text).font(.ui(12)).foregroundStyle(Theme.variant).fixedSize(horizontal: false, vertical: true)
        }
        .padding(12).frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
        .background(on ? Theme.high : Theme.container, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    // MARK: queue

    private var queue: some View {
        let pending = jobs.filter { switch $0.karaoke { case .running, .settingUp, .idle: true; default: false } }.count
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Separation Queue").font(.ui(17, .semibold))
                Tag(text: "\(pending) Jobs Pending", tint: Theme.tertiary, fill: Theme.tertiary.opacity(0.1))
                Spacer()
                Button("Clear Finished") {
                    store.audioJobs.removeAll { j in j.karaokeOnly && { if case .done = j.karaoke { return true }; return false }() }
                }
                .buttonStyle(.glass).disabled(jobs.count == pending)
            }
            VStack(spacing: 0) {
                if jobs.isEmpty {
                    Text("Dropped songs appear here and start separating right away.").font(.ui(13)).foregroundStyle(Theme.variant)
                        .frame(maxWidth: .infinity).padding(28)
                }
                ForEach(jobs) { job in
                    QueueRow(job: job, selected: job.id == selected?.id)
                        .onTapGesture { store.audioSelection = job.id }
                    if job.id != jobs.last?.id { Divider().overlay(Theme.outlineVariant.opacity(0.3)) }
                }
            }
            .background(Theme.low, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

struct QueueRow: View {
    @EnvironmentObject var store: JobStore
    let job: AudioJob
    let selected: Bool

    var body: some View {
        HStack(spacing: 14) {
            icon.frame(width: 40, height: 40).background(Theme.high, in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 3) {
                Text(job.file?.lastPathComponent ?? job.title).font(.ui(14, .medium)).lineLimit(1)
                Text("\(KaraokeTab.name(job.model)) • Instrumental Mode").font(.mono(11)).foregroundStyle(Theme.tertiary)
            }
            .frame(width: 320, alignment: .leading)
            middle.frame(maxWidth: .infinity)
            trailing.frame(width: 150, alignment: .trailing)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(selected ? Theme.primary.opacity(0.06) : .clear)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var icon: some View {
        switch job.karaoke {
        case .running, .settingUp: Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(Theme.tertiary).symbolEffect(.pulse)
        case .idle: Image(systemName: "hourglass").foregroundStyle(Theme.variant)
        case .done: Image(systemName: "checkmark.circle").foregroundStyle(Theme.tertiary)
        case .failed: Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.error)
        }
    }

    @ViewBuilder private var middle: some View {
        switch job.karaoke {
        case .running(let p):
            VStack(spacing: 6) {
                HStack {
                    Text("Separating vocals (\(job.model == .bsRoformer ? "PyTorch MPS" : "Core ML"))").font(.mono(11)).foregroundStyle(Theme.variant)
                    Spacer()
                    Text("\(Int(p * 100))%").font(.mono(11)).foregroundStyle(Theme.tertiary)
                }
                ProgressBar(value: p)
            }
        case .settingUp:
            VStack(alignment: .leading, spacing: 6) {
                Text("Setting up the Roformer engine (one time)…").font(.mono(11)).foregroundStyle(Theme.variant)
                ProgressBar(value: nil)
            }
        case .idle: Text("Queued").font(.mono(11)).foregroundStyle(Theme.variant).frame(maxWidth: .infinity, alignment: .leading)
        case .done: Text("Completed • Instrumental MP3 saved").font(.mono(11)).foregroundStyle(Theme.tertiary).frame(maxWidth: .infinity, alignment: .leading)
        case .failed(let msg): Text(msg).font(.mono(11)).foregroundStyle(Theme.error).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private var trailing: some View {
        switch job.karaoke {
        case .done(let url):
            Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: { Label("Show Finder", systemImage: "folder") }.buttonStyle(.ghost)
        case .failed:
            Button { store.makeKaraoke(job.id) } label: { Label("Retry", systemImage: "arrow.clockwise") }.buttonStyle(.glass)
        default:
            EmptyView()
        }
    }
}

// MARK: - Stem workspace

struct StemWorkspace: View {
    @EnvironmentObject var store: JobStore
    @EnvironmentObject var player: Player
    let job: AudioJob

    private var busy: Bool { switch job.karaoke { case .running, .settingUp: true; default: false } }
    private var output: URL? { if case .done(let u) = job.karaoke { return u }; return nil }
    private func progress(_ url: URL?) -> Double { url != nil && player.playingURL == url ? player.progress : 0 }
    private func time(_ t: Double) -> String { String(format: "%02d:%02d", Int(t) / 60, Int(t) % 60) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(systemName: "music.note").font(.ui(22)).foregroundStyle(Theme.primary)
                    .frame(width: 60, height: 60).background(LinearGradient(colors: [Theme.secondaryContainer, Theme.high], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(job.file?.lastPathComponent ?? job.title).font(.ui(20, .semibold)).tracking(-0.3).lineLimit(1)
                        Tag(text: job.file?.pathExtension.uppercased() ?? "AUDIO", tint: Theme.tertiary, fill: .clear)
                    }
                    HStack(spacing: 6) {
                        Text("Model: \(KaraokeTab.name(job.model))").font(.mono(11.5)).foregroundStyle(Theme.variant)
                        KaraokeChip(state: job.karaoke)
                    }
                }
                Spacer()
                if let f = job.file {
                    let playing = player.playingURL == f && player.isPlaying
                    Button { player.toggle(url: f) } label: { Image(systemName: playing ? "pause.fill" : "play.fill") }
                        .buttonStyle(IconButtonStyle(size: 40, fill: Theme.primary, tint: Theme.onPrimary)).help("Play the original")
                }
                Button { store.setModel(job.id, store.karaokeModel); store.makeKaraoke(job.id) } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(IconButtonStyle(size: 40)).disabled(busy).help("Run again with \(KaraokeTab.name(store.karaokeModel))")
                Button { if let f = job.file { NSWorkspace.shared.activateFileViewerSelecting([f]) } } label: { Image(systemName: "magnifyingglass") }
                    .buttonStyle(IconButtonStyle(size: 40)).help("Show the original in Finder")
            }

            // Master input lane
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Master Input (Full Mix)").font(.ui(13, .semibold))
                    Text("Original").font(.mono(11)).foregroundStyle(Theme.variant)
                    Spacer()
                    if player.playingURL == job.file {
                        Text("\(time(player.progress * player.duration)) / \(time(player.duration))").font(.mono(11)).foregroundStyle(Theme.variant)
                    }
                }
                WaveformView(url: job.file, progress: progress(job.file), tint: Theme.primary, onSeek: { f in seek(job.file, f) })
                    .frame(height: 60).padding(.horizontal, 8).background(Theme.lowest, in: RoundedRectangle(cornerRadius: 6))
            }
            .card(14, fill: Theme.container, radius: 10)

            // Instrumental lane
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) { Circle().fill(Theme.tertiary).frame(width: 9, height: 9); Text("Instrumental").font(.ui(14, .semibold)) }
                    Text(laneStatus).font(.mono(11)).foregroundStyle(Theme.tertiary)
                    if let out = output {
                        let playing = player.playingURL == out && player.isPlaying
                        Button(playing ? "PAUSE" : "PLAY") { player.toggle(url: out) }
                            .buttonStyle(.plain).font(.mono(11)).padding(.horizontal, 7).padding(.vertical, 3).background(Theme.highest, in: RoundedRectangle(cornerRadius: 4))
                    }
                }
                .frame(width: 210, alignment: .leading)
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(Theme.lowest)
                    switch job.karaoke {
                    case .done(let out):
                        WaveformView(url: out, progress: progress(out), tint: Theme.tertiary, onSeek: { f in seek(out, f) }).padding(.horizontal, 8)
                    case .running(let p):
                        VStack(spacing: 8) { Text("Separating… \(Int(p * 100))%").font(.mono(11)).foregroundStyle(Theme.variant); ProgressBar(value: p).frame(width: 260) }
                    case .settingUp:
                        VStack(spacing: 8) { Text("Setting up the Roformer engine…").font(.mono(11)).foregroundStyle(Theme.variant); ProgressBar(value: nil).frame(width: 260) }
                    case .failed(let msg):
                        Text(msg).font(.ui(12)).foregroundStyle(Theme.error).padding(10).textSelection(.enabled)
                    case .idle:
                        Text("Waiting to start").font(.mono(11)).foregroundStyle(Theme.variant)
                    }
                }
                .frame(height: 76)
            }
            .card(14, fill: Theme.container, radius: 10)

            if let out = output ?? job.file.map({ Library.karaokeURL(for: $0, model: job.model) }) {
                HStack(spacing: 6) {
                    Text("Instant Destination:").font(.ui(13)).foregroundStyle(Theme.variant)
                    Text(tildePath(out)).font(.mono(12)).foregroundStyle(Theme.onSurface).lineLimit(1).truncationMode(.middle)
                    if output != nil {
                        Button { NSWorkspace.shared.activateFileViewerSelecting([out]) } label: { Image(systemName: "arrow.up.forward.square") }.buttonStyle(.plain).foregroundStyle(Theme.variant)
                    }
                }
            }
            HStack(spacing: 8) {
                Button { if let f = job.file { NSWorkspace.shared.activateFileViewerSelecting([f]) } } label: { Label("Show Original", systemImage: "waveform") }
                    .buttonStyle(.glass).disabled(job.file == nil)
                Button { if let out = output { NSWorkspace.shared.activateFileViewerSelecting([out]) } } label: { Label("Show Instrumental", systemImage: "folder") }
                    .buttonStyle(.glass).disabled(output == nil)
                Button { if let out = output { saveCopy(of: out) } } label: { Label("Export Instrumental MP3", systemImage: "square.and.arrow.down") }
                    .buttonStyle(.primary).disabled(output == nil)
            }
        }
        .padding(20)
        .background(Theme.low, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onDrag { output.flatMap { NSItemProvider(contentsOf: $0) } ?? NSItemProvider() }
    }

    private var laneStatus: String {
        switch job.karaoke {
        case .done: "No vocals • ready"
        case .running(let p): "Separating \(Int(p * 100))%"
        case .settingUp: "Setting up engine"
        case .failed: "Failed"
        case .idle: "Queued"
        }
    }

    /// Seeks within `url`, starting playback first if a different file is playing.
    private func seek(_ url: URL?, _ fraction: Double) {
        guard let url else { return }
        if player.playingURL != url { player.toggle(url: url) }
        player.seek(fraction)
    }
}

// MARK: - Audio Vault

struct VaultView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Audio Vault").font(.ui(22, .semibold)).tracking(-0.4)
                Text("Every summary, downloaded original and karaoke track. Drag rows to reorder.").font(.ui(13)).foregroundStyle(Theme.variant)
            }
            LibraryPanel()
                .frame(maxWidth: 820, maxHeight: .infinity, alignment: .top)
                .background(Theme.low, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
