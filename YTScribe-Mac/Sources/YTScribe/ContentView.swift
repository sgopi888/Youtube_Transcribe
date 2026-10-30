import SwiftUI
import AppKit
import UniformTypeIdentifiers
import YTScribeCore

/// Window shell: unified top bar, source sidebar, and the active tab's workspace.
struct ContentView: View {
    @EnvironmentObject var store: JobStore
    @StateObject private var player = Player()
    @State private var dropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            TopBar()
            HStack(spacing: 0) {
                Sidebar().frame(width: 240)
                main.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.surface)
        .ignoresSafeArea(.container, edges: .top)
        .environmentObject(player)
        .preferredColorScheme(.dark)
        .tint(Theme.primary)
        // ⌘V anywhere in the window starts jobs, no need to focus the field first.
        .onPasteCommand(of: [.plainText]) { providers in
            for p in providers { _ = p.loadObject(ofClass: NSString.self) { s, _ in
                if let s = s as? String { Task { @MainActor in store.add(from: s) } }
            } }
        }
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            for p in providers {
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    if let url { Task { @MainActor in store.addFiles([url]) } }
                }
            }
            return true
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.primary, style: StrokeStyle(lineWidth: 2, dash: [10, 6]))
                    .background(Theme.primary.opacity(0.08))
                    .overlay(Label(store.mode == .karaoke ? "Drop audio to separate vocals" : "Drop audio to add it", systemImage: "waveform").font(.ui(22, .semibold)))
                    .padding(10).allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder private var main: some View {
        if store.showVault { VaultView() }
        else {
            switch store.mode {
            case .summary: SummaryTab()
            case .audio: AudioTab()
            case .video: VideoTab()
            case .karaoke: KaraokeTab()
            }
        }
    }
}

/// Picks audio files; `dir` opens the panel in that folder.
@MainActor func chooseAudioFiles(_ store: JobStore, in dir: URL? = nil) {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = true
    panel.allowedContentTypes = [.audio]
    if let dir { panel.directoryURL = dir }
    if panel.runModal() == .OK { store.addFiles(panel.urls) }
}

/// Copies `file` to a location the user picks.
@MainActor func saveCopy(of file: URL) {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = file.lastPathComponent
    panel.allowedContentTypes = [UTType(filenameExtension: file.pathExtension) ?? .mp3]
    guard panel.runModal() == .OK, let dest = panel.url else { return }
    try? FileManager.default.removeItem(at: dest)
    try? FileManager.default.copyItem(at: file, to: dest)
}

// MARK: - Top bar

struct TopBar: View {
    @EnvironmentObject var store: JobStore

    private var tab: Binding<Mode> {
        Binding(get: { store.mode }, set: { store.mode = $0; store.showVault = false })
    }

    var body: some View {
        ZStack {
            HStack(spacing: 12) {
                // Room for the window's own traffic lights.
                Color.clear.frame(width: 64, height: 1)
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 26, height: 26)
                Text("YTScribe").font(.ui(15, .semibold)).tracking(-0.2).foregroundStyle(Theme.onSurface)
                Spacer()
                HStack(spacing: 5) {
                    StatusDot()
                    Image(systemName: "cpu").font(.ui(11)).foregroundStyle(Theme.tertiary)
                    Text(store.activeCount > 0 ? "\(store.activeCount) job\(store.activeCount == 1 ? "" : "s") running" : "On-device engine ready")
                        .font(.mono(11, .medium)).foregroundStyle(Theme.variant)
                }
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Theme.container.opacity(0.6), in: Capsule())
                Button { revealInFinder(Library.musicDir) } label: {
                    Label(tildePath(Library.musicDir), systemImage: "folder.badge.gearshape").font(.mono(12))
                }
                .buttonStyle(.plain).foregroundStyle(Theme.variant).help("Open the YTScribe music folder")
                SettingsLink { Image(systemName: "gearshape").font(.ui(15)) }
                    .buttonStyle(IconButtonStyle(size: 28, fill: .clear, tint: Theme.variant)).help("Settings")
                SettingsLink {
                    Image(systemName: "person.fill").font(.ui(14)).foregroundStyle(Theme.onPrimary)
                        .frame(width: 30, height: 30).background(Theme.primary, in: Circle())
                }
                .buttonStyle(.plain).help("OpenAI key and model")
            }
            GlassSegmented(selection: tab, items: [("AI Summary", .summary), ("Audio Downloader", .audio), ("Video Downloader", .video), ("Karaoke AI", .karaoke)], size: 12.5)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(Theme.lowest.opacity(0.85))
        .shadow(color: .black.opacity(0.4), radius: 4, y: 1)
        .zIndex(1)
    }
}

// MARK: - Sidebar

struct Sidebar: View {
    @EnvironmentObject var store: JobStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Transcriptions").sectionLabel().padding(.horizontal, 6).padding(.top, 14)
            VStack(spacing: 2) {
                item("captions.bubble", "Recent Captions", active: !store.showVault && store.mode == .summary) { store.mode = .summary; store.showVault = false }
                item("icloud.and.arrow.down", "Downloads Queue", active: !store.showVault && store.mode == .audio) { store.mode = .audio; store.showVault = false }
                item("film", "Video Downloads", active: !store.showVault && store.mode == .video) { store.mode = .video; store.showVault = false }
                item("mic", "Stem Separation", active: !store.showVault && store.mode == .karaoke) { store.mode = .karaoke; store.showVault = false }
                item("music.note.list", "Audio Vault", active: store.showVault) { store.showVault = true }
            }
            Spacer()
            activeCard
        }
        .padding(.horizontal, 10).padding(.bottom, 12)
        .frame(maxHeight: .infinity)
        .background(Theme.low.opacity(0.75))
    }

    private func item(_ icon: String, _ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon).font(.ui(13)).frame(width: 18)
                Text(title).font(.ui(13, active ? .semibold : .regular))
                Spacer()
            }
            .foregroundStyle(active ? Theme.onSurface : Theme.variant)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(active ? Theme.high : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Live job load, in the slot the mockup uses for its compute meter.
    private var activeCard: some View {
        let total = store.jobs.count + store.audioJobs.count + store.videoJobs.count
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Active Jobs").font(.ui(11, .medium)).foregroundStyle(Theme.variant)
                Spacer()
                Text("\(store.activeCount) of \(total)").font(.mono(11, .medium)).foregroundStyle(Theme.tertiary)
            }
            ProgressBar(value: total == 0 ? 0 : Double(total - store.activeCount) / Double(total), fill: AnyShapeStyle(Theme.tertiary))
        }
        .card(10, fill: Theme.lowest.opacity(0.6))
    }
}

extension JobStore {
    /// Summaries, downloads and karaoke separations still in progress.
    var activeCount: Int {
        jobs.filter { if case .fetching = $0.status { return true }; if case .summarizing = $0.status { return true }; return false }.count
            + audioJobs.filter {
                if case .downloading = $0.status { return true }
                switch $0.karaoke { case .running, .settingUp: return true; default: return false }
            }.count
            + videoJobs.filter { if case .downloading = $0.status { return true }; return false }.count
    }
}

// MARK: - Shared bits

struct StatusChip: View {
    let status: Job.Status
    var body: some View {
        Pill(tint: tint) {
            switch status {
            case .fetching: Text("Fetching transcript")
            case .summarizing(let i, let n): Text(n > 1 ? "Summarizing \(i)/\(n)" : "Summarizing")
            case .done: Image(systemName: "checkmark.seal"); Text("Complete")
            case .failed: Image(systemName: "exclamationmark.triangle"); Text("Failed")
            }
        }
    }
    private var tint: Color {
        switch status { case .done: Theme.tertiary; case .failed: Theme.error; default: Theme.primary }
    }
}

struct AudioChip: View {
    let status: AudioJob.Status
    var body: some View {
        Pill(tint: tint) {
            switch status {
            case .downloading(let p): Text(p > 0 ? "Downloading" : "Starting")
            case .done: Image(systemName: "checkmark.seal"); Text("Complete")
            case .failed: Image(systemName: "exclamationmark.triangle"); Text("Failed")
            }
        }
    }
    private var tint: Color {
        switch status { case .done: Theme.tertiary; case .failed: Theme.error; default: Theme.secondary }
    }
}

struct KaraokeChip: View {
    let state: AudioJob.Karaoke
    var body: some View {
        Pill(tint: tint) {
            switch state {
            case .idle: Text("Ready")
            case .settingUp: Text("Setting up")
            case .running(let p): Text("Separating \(Int(p * 100))%")
            case .done: Image(systemName: "checkmark.seal"); Text("Instrumental ready")
            case .failed: Image(systemName: "exclamationmark.triangle"); Text("Failed")
            }
        }
    }
    private var tint: Color {
        switch state { case .done: Theme.tertiary; case .failed: Theme.error; default: Theme.secondary }
    }
}

/// Stat tile used under the Summary and Audio workspaces.
struct StatTile<Footer: View>: View {
    let label: String
    var trailing: String? = nil
    let value: String
    var suffix: String? = nil
    var detail: String? = nil
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label).sectionLabel()
                Spacer()
                if let trailing { Text(trailing).font(.mono(11)).foregroundStyle(Theme.tertiary).lineLimit(1) }
            }
            (Text(value).font(.ui(20, .semibold)).foregroundStyle(Theme.onSurface)
             + Text(suffix.map { " " + $0 } ?? "").font(.ui(14)).foregroundStyle(Theme.variant))
                .lineLimit(1).minimumScaleFactor(0.7)
            if let detail { Text(detail).font(.ui(12.5)).foregroundStyle(Theme.variant).fixedSize(horizontal: false, vertical: true) }
            Spacer(minLength: 0)
            footer
        }
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
        .card(16)
    }
}
