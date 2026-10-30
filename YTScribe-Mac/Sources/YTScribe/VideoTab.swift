import SwiftUI
import AppKit
import YTScribeCore

/// Video Downloader tab: YouTube link → MP4 at the chosen quality, same flow as the Audio tab.
struct VideoTab: View {
    @EnvironmentObject var store: JobStore
    @EnvironmentObject var library: LibraryStore
    @State private var input = ""
    @State private var storage: (bytes: Int64, files: Int, free: Int64) = (0, 0, 0)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ingestCard
                vaultCard
                header
                if store.videoJobs.isEmpty { emptyCard }
                ForEach(store.videoJobs) { VideoJobCard(job: $0) }
                stats
            }
            .padding(14)
        }
        .scrollIndicators(.hidden)
        .onAppear(perform: refresh)
        .onChange(of: library.entries(.video).count) { _, _ in refresh() }
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
                Button { if store.add(from: input) > 0 { input = "" } } label: { Label("Download MP4", systemImage: "arrow.down.to.line") }
                    .buttonStyle(.primary)
            }
            HStack(spacing: 10) {
                Text("Video Quality:").font(.ui(13)).foregroundStyle(Theme.variant)
                GlassSegmented(selection: $store.videoQuality, items: AudioDownloader.videoQualities.map { ($0.title, $0.id) }, size: 12.5)
                Spacer()
                Text(store.videoQuality == "best" ? "Highest resolution · VP9/AV1 may need IINA or VLC" : "H.264 + AAC · plays in QuickTime")
                    .font(.mono(11)).foregroundStyle(Theme.variant)
            }
        }
        .card(16)
    }

    private var vaultCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "film.stack").font(.ui(18)).foregroundStyle(Theme.variant)
                .frame(width: 44, height: 44).background(Theme.high, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                (Text("Target Vault: ").font(.ui(16, .semibold)) + Text(tildePath(Library.videosDir)).font(.mono(12.5)).foregroundStyle(Theme.variant))
                Text("Every MP4 also appears under Videos in Audio Vault.").font(.ui(13)).foregroundStyle(Theme.variant)
            }
            Spacer()
            Button { revealInFinder(Library.videosDir) } label: { Label("Reveal in Finder", systemImage: "folder") }.buttonStyle(.glass)
        }
        .card(16)
    }

    private var header: some View {
        let downloading = store.videoJobs.filter { if case .downloading = $0.status { return true }; return false }.count
        return HStack(spacing: 8) {
            Text("Video Pipeline").font(.ui(12.5, .semibold)).tracking(1).textCase(.uppercase)
            Tag(text: "\(store.videoJobs.count) items", tint: Theme.primary, fill: Theme.primary.opacity(0.12))
            Spacer()
            StatusDot(size: 6)
            Text("Downloading: \(downloading)").font(.mono(11.5)).foregroundStyle(Theme.tertiary)
            Text("•").foregroundStyle(Theme.variant)
            Text("Ready: \(store.videoJobs.filter { $0.status == .done }.count)").font(.mono(11.5)).foregroundStyle(Theme.variant)
        }
        .padding(.top, 4)
    }

    private var emptyCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "film").font(.ui(34, .light)).foregroundStyle(Theme.gradient)
            Text("Paste a YouTube link").font(.ui(18, .semibold))
            Text("Get the video as an MP4 at the quality chosen above.\nPress ⌘V anywhere in this window.").font(.ui(13)).foregroundStyle(Theme.variant).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 180).card(16)
    }

    private func refresh() {
        Task.detached(priority: .utility) {
            let s = folderSize(Library.videosDir)
            let free = (try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage ?? 0
            await MainActor.run { storage = (s.bytes, s.files, free) }
        }
    }

    private var stats: some View {
        HStack(alignment: .top, spacing: 14) {
            StatTile(label: "Video Engine", trailing: "yt-dlp + ffmpeg", value: "MP4",
                     detail: "Best video and audio streams at the chosen height, merged into one MP4 with the video's metadata.") { EmptyView() }
            StatTile(label: "Video Storage", trailing: "This Mac", value: byteString(storage.bytes), suffix: "in \(storage.files) videos") {
                HStack {
                    Text(tildePath(Library.videosDir)).font(.mono(11)).foregroundStyle(Theme.variant)
                    Spacer()
                    Text("\(byteString(storage.free)) Available").font(.mono(11)).foregroundStyle(Theme.variant)
                }
            }
        }
    }
}

struct VideoJobCard: View {
    @EnvironmentObject var store: JobStore
    let job: VideoJob

    private var size: String? {
        guard let f = job.file, let b = try? FileManager.default.attributesOfItem(atPath: f.path)[.size] as? Int64 else { return nil }
        return byteString(b)
    }
    private var qualityName: String { AudioDownloader.videoQualities.first { $0.id == job.quality }?.title ?? job.quality }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Thumb(videoID: job.videoID, icon: "film").frame(width: 128, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(alignment: .bottomTrailing) {
                        Text(job.quality == "best" ? "MAX" : "\(job.quality)p").font(.mono(9.5, .medium)).padding(.horizontal, 4).padding(.vertical, 2)
                            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 3)).padding(4)
                    }
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(job.title).font(.ui(16, .semibold)).tracking(-0.2).lineLimit(1)
                        chip
                    }
                    HStack(spacing: 6) {
                        Text("YouTube").font(.ui(13, .medium)).foregroundStyle(Theme.primary)
                        Text("•").foregroundStyle(Theme.variant)
                        Text("youtu.be/\(job.videoID)").font(.mono(11.5)).foregroundStyle(Theme.variant)
                        Text("•").foregroundStyle(Theme.variant)
                        Text("MP4 \(qualityName)" + (size.map { " • \($0)" } ?? "")).font(.mono(11.5)).foregroundStyle(Theme.variant)
                    }
                }
                Spacer(minLength: 8)
                trailing
            }
            switch job.status {
            case .downloading(let p):
                ProgressBar(value: p > 0 ? p / 100 : nil, height: 5)
                HStack {
                    Text("Downloading video and audio streams, then merging into MP4…").font(.mono(11)).foregroundStyle(Theme.variant)
                    Spacer()
                    Text("yt-dlp").font(.mono(11)).foregroundStyle(Theme.variant)
                }
            case .failed(let msg):
                Text(msg).font(.ui(12.5)).foregroundStyle(Theme.error).textSelection(.enabled)
            case .done:
                if let f = job.file {
                    Label("Stored: \(tildePath(f))", systemImage: "checkmark.seal").font(.mono(11)).foregroundStyle(Theme.variant).lineLimit(1).truncationMode(.middle)
                }
            }
        }
        .card(16)
    }

    private var chip: some View {
        Pill(tint: { switch job.status { case .done: Theme.tertiary; case .failed: Theme.error; default: Theme.secondary } }()) {
            switch job.status {
            case .downloading(let p): Text(p > 0 ? "Downloading" : "Starting")
            case .done: Image(systemName: "checkmark.seal"); Text("Complete")
            case .failed: Image(systemName: "exclamationmark.triangle"); Text("Failed")
            }
        }
    }

    @ViewBuilder private var trailing: some View {
        switch job.status {
        case .downloading(let p):
            VStack(alignment: .trailing, spacing: 2) {
                Text(p > 0 ? "\(Int(p))%" : "—").font(.ui(20, .semibold))
                Text("Downloading").font(.mono(11)).foregroundStyle(Theme.tertiary)
            }
        case .failed:
            Button { store.retryVideo(job.id) } label: { Label("Retry", systemImage: "arrow.clockwise") }.buttonStyle(.primary)
        case .done:
            if let f = job.file {
                Button { NSWorkspace.shared.open(f) } label: { Label("Play", systemImage: "play.fill") }.buttonStyle(.glass)
                Button { NSWorkspace.shared.activateFileViewerSelecting([f]) } label: { Label("Show in Finder", systemImage: "folder") }.buttonStyle(.glass)
                Button { saveCopy(of: f) } label: { Label("Save As…", systemImage: "square.and.arrow.down") }.buttonStyle(.primary)
            }
        }
    }
}
