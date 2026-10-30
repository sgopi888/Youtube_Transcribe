import SwiftUI
import AppKit
import YTScribeCore

/// Audio Downloader tab: URL bar, target vault, active pipeline, stats, now-playing bar.
struct AudioTab: View {
    @EnvironmentObject var store: JobStore
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var player: Player
    @State private var input = ""
    @State private var vault: (bytes: Int64, files: Int, free: Int64, volume: String) = (0, 0, 0, "")

    private var jobs: [AudioJob] { store.audioJobs.filter { !$0.karaokeOnly } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ingestCard
                vaultCard
                pipelineHeader
                if jobs.isEmpty { emptyCard }
                ForEach(jobs) { job in
                    AudioJobCard(job: job, selected: job.id == store.audioSelection)
                        .onTapGesture { store.audioSelection = job.id }
                }
                statsRow
            }
            .padding(14)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom) { if player.playingURL != nil { NowPlayingBar().padding(.horizontal, 60).padding(.bottom, 12) } }
        .onAppear(perform: refreshVault)
        .onChange(of: library.entries(.original).count + library.entries(.karaoke).count) { _, _ in refreshVault() }
    }

    private var ingestCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "link").foregroundStyle(Theme.outline)
                    TextField("https://youtube.com/watch?v=…  (paste one link or many)", text: $input)
                        .textFieldStyle(.plain).font(.ui(14))
                        // Auto-detect: any pasted/typed text containing a link starts downloads immediately.
                        .onChange(of: input) { _, new in if store.add(from: new) > 0 { input = "" } }
                        .onSubmit { if store.add(from: input) > 0 { input = "" } }
                    Button { if let s = NSPasteboard.general.string(forType: .string) { store.add(from: s) } } label: {
                        Tag(text: "Clipboard", icon: "doc.on.clipboard", tint: Theme.tertiary, fill: Theme.tertiary.opacity(0.1))
                    }
                    .buttonStyle(.plain).help("Download the link on the clipboard")
                    Tag(text: "⌘V")
                }
                .padding(.horizontal, 12).frame(height: 40)
                .background(Theme.lowest.opacity(0.8), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                Button { if store.add(from: input) > 0 { input = "" } } label: { Label("Enqueue Batch", systemImage: "arrow.down.to.line") }
                    .buttonStyle(.primary).controlSize(.large)
                Button { chooseAudioFiles(store) } label: { Image(systemName: "square.and.arrow.up") }
                    .buttonStyle(IconButtonStyle(size: 36)).help("Add an audio file from your Mac")
            }
            HStack(spacing: 10) {
                Text("Audio Profile:").font(.ui(13)).foregroundStyle(Theme.variant)
                HStack(spacing: 6) { StatusDot(size: 6); Text("MP3 VBR V0 (Best quality)").font(.ui(12.5, .medium)) }
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Theme.highest, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .padding(2).background(Theme.lowest.opacity(0.7), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.square.fill").foregroundStyle(Theme.primary)
                    Text("Embed Metadata").foregroundStyle(Theme.onSurface)
                }
                .font(.ui(12.5))
                Label("Parallel downloads", systemImage: "bolt").font(.mono(11.5)).foregroundStyle(Theme.tertiary)
            }
        }
        .card(16)
    }

    private var vaultCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "folder").font(.ui(18)).foregroundStyle(Theme.variant)
                .frame(width: 44, height: 44).background(Theme.high, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                (Text("Target Vault: ").font(.ui(16, .semibold)) + Text(tildePath(Library.originalsDir)).font(.mono(12.5)).foregroundStyle(Theme.variant))
                (Text("Karaoke tracks: ").font(.ui(13)).foregroundStyle(Theme.variant) + Text(tildePath(Library.karaokeDir)).font(.mono(12)).foregroundStyle(Theme.tertiary))
            }
            Spacer()
            Button { revealInFinder(Library.originalsDir) } label: { Label("Reveal in Finder", systemImage: "folder") }.buttonStyle(.glass)
            Button("Karaoke Folder") { revealInFinder(Library.karaokeDir) }.buttonStyle(.glass)
        }
        .card(16)
    }

    private var pipelineHeader: some View {
        let downloading = jobs.filter { if case .downloading = $0.status { return true }; return false }.count
        return HStack(spacing: 8) {
            Text("Active Pipeline").font(.ui(12.5, .semibold)).tracking(1).textCase(.uppercase).foregroundStyle(Theme.onSurface)
            Tag(text: "\(jobs.count) items", tint: Theme.primary, fill: Theme.primary.opacity(0.12))
            Spacer()
            StatusDot(size: 6)
            Text("Downloading: \(downloading)").font(.mono(11.5)).foregroundStyle(Theme.tertiary)
            Text("•").foregroundStyle(Theme.variant)
            Text("Ready: \(jobs.filter { $0.status == .done }.count)").font(.mono(11.5)).foregroundStyle(Theme.variant)
        }
        .padding(.top, 4)
    }

    private var emptyCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "music.note").font(.ui(34, .light)).foregroundStyle(Theme.gradient)
            Text("Paste a YouTube link").font(.ui(18, .semibold))
            Text("Get the audio as an MP3, then remove the vocals.\nPress ⌘V, or drop an MP3 file anywhere in this window.").font(.ui(13)).foregroundStyle(Theme.variant).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 180).card(16)
    }

    private func refreshVault() {
        Task.detached(priority: .utility) {
            let s = folderSize(Library.musicDir)
            let v = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeNameKey])
            let free = v?.volumeAvailableCapacityForImportantUsage ?? 0, name = v?.volumeName ?? ""
            await MainActor.run { vault = (s.bytes, s.files, free, name) }
        }
    }

    private var statsRow: some View {
        HStack(alignment: .top, spacing: 14) {
            StatTile(label: "Codec Engine", trailing: "yt-dlp + ffmpeg", value: "MP3 VBR V0",
                     detail: "Best audio stream, re-encoded with LAME at quality 0 and tagged with the video's metadata.") {
                Label("Saved straight into your Music folder", systemImage: "gauge.with.dots.needle.33percent").font(.mono(11)).foregroundStyle(Theme.tertiary)
            }
            StatTile(label: "Vault Capacity", trailing: vault.volume, value: byteString(vault.bytes), suffix: "used by YTScribe") {
                VStack(spacing: 8) {
                    ProgressBar(value: vault.free > 0 ? Double(vault.bytes) / Double(vault.bytes + vault.free) : 0, height: 5)
                    HStack {
                        Text("\(vault.files) Audio Files").font(.mono(11)).foregroundStyle(Theme.variant)
                        Spacer()
                        Text("\(byteString(vault.free)) Available").font(.mono(11)).foregroundStyle(Theme.variant)
                    }
                }
            }
            StatTile(label: "Karaoke Library", trailing: nil, value: "\(library.entries(.karaoke).count)", suffix: "instrumentals",
                     detail: library.entries(.karaoke).first.map { "Latest: \($0.title)" }) {
                HStack {
                    Text("Originals: \(library.entries(.original).count)").font(.mono(11)).foregroundStyle(Theme.variant)
                    Spacer()
                    Text(RoformerEngine.isInstalled ? "Roformer installed" : "HTDemucs ready").font(.mono(11)).foregroundStyle(Theme.variant)
                }
            }
        }
    }
}

// MARK: - Pipeline card

struct AudioJobCard: View {
    @EnvironmentObject var store: JobStore
    @EnvironmentObject var player: Player
    let job: AudioJob
    let selected: Bool

    private var videoID: String? { job.id.hasPrefix("file:") ? nil : job.id }
    private var size: String? {
        guard let f = job.file, let b = try? FileManager.default.attributesOfItem(atPath: f.path)[.size] as? Int64 else { return nil }
        return byteString(b)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Thumb(videoID: videoID).frame(width: 84, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(alignment: .bottomTrailing) {
                        Text("V0").font(.mono(9.5, .medium)).padding(.horizontal, 4).padding(.vertical, 2)
                            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 3)).padding(4)
                    }
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(job.title).font(.ui(16, .semibold)).tracking(-0.2).lineLimit(1)
                        AudioChip(status: job.status)
                    }
                    HStack(spacing: 6) {
                        Text(videoID == nil ? "Local file" : "YouTube").font(.ui(13, .medium)).foregroundStyle(Theme.primary)
                        Text("•").foregroundStyle(Theme.variant)
                        Text(videoID.map { "youtu.be/\($0)" } ?? (job.file?.lastPathComponent ?? "")).font(.mono(11.5)).foregroundStyle(Theme.variant).lineLimit(1)
                        if let size { Text("•").foregroundStyle(Theme.variant); Text("MP3 • \(size)").font(.mono(11.5)).foregroundStyle(Theme.variant) }
                    }
                }
                Spacer(minLength: 8)
                trailing
            }

            switch job.status {
            case .downloading(let p):
                ProgressBar(value: p > 0 ? p / 100 : nil, height: 5)
                HStack {
                    Text("Downloading the best audio stream and converting to MP3…").font(.mono(11)).foregroundStyle(Theme.variant)
                    Spacer()
                    Text("yt-dlp").font(.mono(11)).foregroundStyle(Theme.variant)
                }
            case .failed(let msg):
                Text(msg).font(.ui(12.5)).foregroundStyle(Theme.error).textSelection(.enabled)
            case .done:
                if let f = job.file {
                    HStack {
                        Label("Stored: \(tildePath(f))", systemImage: "checkmark.seal").font(.mono(11)).foregroundStyle(Theme.variant).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        KaraokeChip(state: job.karaoke)
                    }
                    if selected { KaraokeCard(job: job) }
                }
            }
        }
        .card(16)
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(selected ? Theme.primary.opacity(0.35) : .clear))
        .contentShape(Rectangle())
    }

    @ViewBuilder private var trailing: some View {
        switch job.status {
        case .downloading(let p):
            VStack(alignment: .trailing, spacing: 2) {
                Text(p > 0 ? "\(Int(p))%" : "—").font(.ui(20, .semibold))
                Text("Downloading").font(.mono(11)).foregroundStyle(Theme.tertiary)
            }
        case .failed:
            Button { store.retryAudio(job.id) } label: { Label("Retry", systemImage: "arrow.clockwise") }.buttonStyle(.primary)
        case .done:
            if let f = job.file {
                let playing = player.playingURL == f && player.isPlaying
                Button { player.toggle(url: f) } label: { Label(playing ? "Pause" : "Play Preview", systemImage: playing ? "pause.fill" : "play.fill") }.buttonStyle(.glass)
                Button { NSWorkspace.shared.activateFileViewerSelecting([f]) } label: { Label("Open in Finder", systemImage: "folder") }.buttonStyle(.glass)
                Menu {
                    Button("Open in default app") { NSWorkspace.shared.open(f) }
                    Button("Save As…") { saveCopy(of: f) }
                    Button("Remove vocals…") { store.audioSelection = job.id }
                } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 32, height: 32)
            }
        }
    }
}

/// Inline "remove vocals" controls for a finished download.
struct KaraokeCard: View {
    @EnvironmentObject var store: JobStore
    @EnvironmentObject var player: Player
    let job: AudioJob

    private var busy: Bool { if case .running = job.karaoke { return true }; if case .settingUp = job.karaoke { return true }; return false }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Label("Karaoke: remove all vocals", systemImage: "mic.slash").font(.ui(13.5, .semibold))
                Spacer()
                Picker("Model", selection: Binding(get: { job.model }, set: { store.setModel(job.id, $0) })) {
                    ForEach(KaraokeModel.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu).labelsHidden().frame(maxWidth: 300).disabled(busy)
                Button { store.makeKaraoke(job.id) } label: { Label(job.karaoke == .idle ? "Generate Karaoke" : "Run Again", systemImage: "wand.and.stars") }
                    .buttonStyle(.primary).disabled(busy)
            }
            if job.model == .bsRoformer && !RoformerEngine.isInstalled {
                Text("First use sets up a private Python environment (one-time download, needs internet).").font(.ui(12)).foregroundStyle(Theme.variant)
            }
            switch job.karaoke {
            case .idle: EmptyView()
            case .settingUp:
                HStack { ProgressView().controlSize(.small); Text("Setting up the Roformer engine…").foregroundStyle(Theme.variant) }
            case .running(let p):
                ProgressBar(value: p, height: 5)
                Text("Removing vocals… \(Int(p * 100))%").font(.mono(11)).foregroundStyle(Theme.variant)
            case .failed(let msg):
                Text(msg).foregroundStyle(Theme.error).textSelection(.enabled)
            case .done(let url):
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Theme.tertiary)
                    Text(url.lastPathComponent).font(.ui(13, .medium)).lineLimit(1)
                    Spacer()
                    let playing = player.playingURL == url && player.isPlaying
                    Button { player.toggle(url: url) } label: { Label(playing ? "Pause" : "Play", systemImage: playing ? "pause.fill" : "play.fill") }.buttonStyle(.glass)
                    Button { saveCopy(of: url) } label: { Label("Save As…", systemImage: "square.and.arrow.down") }.buttonStyle(.primary)
                    Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: { Label("Show in Finder", systemImage: "folder") }.buttonStyle(.glass)
                }
                .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
            }
        }
        .card(14, fill: Theme.lowest.opacity(0.6), radius: 10)
    }
}

// MARK: - Now playing

struct NowPlayingBar: View {
    @EnvironmentObject var store: JobStore
    @EnvironmentObject var player: Player

    private func time(_ t: Double) -> String { String(format: "%02d:%02d", Int(t) / 60, Int(t) % 60) }

    var body: some View {
        if let url = player.playingURL {
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    Image(systemName: "music.note").foregroundStyle(Theme.primary)
                        .frame(width: 40, height: 40).background(Theme.high, in: RoundedRectangle(cornerRadius: 6))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(url.deletingPathExtension().lastPathComponent).font(.ui(14, .medium)).lineLimit(1)
                        Text("\(url.pathExtension.uppercased()) (Previewing)").font(.mono(11)).foregroundStyle(Theme.primary)
                    }
                    .frame(width: 260, alignment: .leading)
                    Spacer()
                    Button { player.seek(player.progress - 10 / max(player.duration, 1)) } label: { Image(systemName: "gobackward.10") }
                        .buttonStyle(IconButtonStyle(size: 30, fill: .clear))
                    Button { player.toggle(url: url) } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.ui(15)).foregroundStyle(Theme.onPrimary)
                            .frame(width: 40, height: 40).background(Theme.primary, in: Circle())
                    }
                    .buttonStyle(.plain)
                    Button { player.seek(player.progress + 10 / max(player.duration, 1)) } label: { Image(systemName: "goforward.10") }
                        .buttonStyle(IconButtonStyle(size: 30, fill: .clear))
                    Button { player.stop() } label: { Image(systemName: "stop.fill") }
                        .buttonStyle(IconButtonStyle(size: 30, fill: .clear))
                    Spacer()
                    Button { store.mode = .karaoke; store.addFiles([url]) } label: { Label("Stem Split", systemImage: "chart.bar.fill") }
                        .buttonStyle(.glass).help("Remove the vocals from this track")
                        .frame(width: 260, alignment: .trailing)
                }
                HStack(spacing: 10) {
                    Text(time(player.progress * player.duration)).font(.mono(11)).foregroundStyle(Theme.variant)
                    WaveformView(url: url, progress: player.progress, tint: Theme.tertiary, onSeek: { player.seek($0) }).frame(height: 30)
                    Text("-" + time((1 - player.progress) * player.duration)).font(.mono(11)).foregroundStyle(Theme.variant)
                }
            }
            .padding(12)
            .background(Theme.container.opacity(0.92), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.5), radius: 16, y: 6)
        }
    }
}
