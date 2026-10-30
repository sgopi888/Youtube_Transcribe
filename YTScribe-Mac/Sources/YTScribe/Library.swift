import SwiftUI
import AVFoundation
import YTScribeCore

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var index: LibraryIndex
    private static let file = Library.supportDir.appendingPathComponent("library.json")

    init() {
        Library.migrateLegacyOriginals()
        index = LibraryIndex.load(from: Self.file)
        sync()
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.sync() }
        }
    }

    /// Re-reads the folders so the lists always match what is on disk.
    func sync() {
        var idx = index
        idx.sync(musicDir: Library.originalsDir, karaokeDir: Library.karaokeDir, summariesDir: Library.summariesDir, videosDir: Library.videosDir)
        if idx != index { index = idx; persist() }
    }

    func entries(_ kind: LibraryKind) -> [LibraryEntry] { index.list(kind) }

    func add(_ kind: LibraryKind, title: String, url: URL) { index.add(kind, title: title, url: url); persist() }

    func move(_ kind: LibraryKind, from: IndexSet, to: Int) { index.move(kind, from: from, to: to); persist() }

    /// Removes from the list. Only files inside ~/Music/YTScribe may be moved to the Trash, never a song the user dropped in from elsewhere.
    func remove(_ entry: LibraryEntry, trashFile: Bool) {
        if trashFile, let target = Self.trashTarget(entry) { try? FileManager.default.trashItem(at: target, resultingItemURL: nil) }
        index.remove(entry.id)
        persist()
    }

    /// Songs under ~/Music/YTScribe, videos under ~/Movies/YTScribe, or a summary's whole folder under ~/Downloads/YTScribe.
    /// Anything else is never trashed.
    static func trashTarget(_ e: LibraryEntry) -> URL? {
        if e.kind == .summary {
            let folder = e.url.deletingLastPathComponent()
            return folder.deletingLastPathComponent().path == Library.summariesDir.path ? folder : nil
        }
        if e.kind == .video { return e.path.hasPrefix(Library.videosDir.path + "/") ? e.url : nil }
        return e.path.hasPrefix(Library.musicDir.path + "/") ? e.url : nil
    }

    static func canTrash(_ e: LibraryEntry) -> Bool { trashTarget(e) != nil }

    private func persist() { index.save(to: Self.file) }
}

@MainActor
final class Player: ObservableObject {
    @Published private(set) var playingID: UUID?
    @Published private(set) var playingURL: URL?
    @Published private(set) var isPlaying = false
    @Published private(set) var duration = 0.0
    @Published var progress = 0.0
    private var player: AVAudioPlayer?
    private var timer: Timer?

    func toggle(_ e: LibraryEntry) { toggle(url: e.url, id: e.id) }

    /// Plays or pauses `url`; starting a different file stops the current one.
    func toggle(url: URL, id: UUID? = nil) {
        if playingURL == url, let p = player {
            if p.isPlaying { p.pause(); isPlaying = false } else { p.play(); isPlaying = true }
            return
        }
        stop()
        guard let p = try? AVAudioPlayer(contentsOf: url) else { return }
        player = p; playingID = id; playingURL = url; duration = p.duration
        p.play(); isPlaying = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func seek(_ fraction: Double) {
        guard let p = player else { return }
        p.currentTime = max(0, min(1, fraction)) * p.duration
        progress = fraction
    }

    func stop() {
        timer?.invalidate(); timer = nil
        player?.stop(); player = nil
        playingID = nil; playingURL = nil; isPlaying = false; progress = 0; duration = 0
    }

    private func tick() {
        guard let p = player else { return }
        if p.isPlaying { progress = p.currentTime / max(p.duration, 0.1) } else if isPlaying { stop() }  // reached the end
    }
}

struct LibraryPanel: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var store: JobStore
    @EnvironmentObject var player: Player
    @State private var kind: LibraryKind = .summary
    @State private var pending: LibraryEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GlassSegmented(selection: $kind, items: [("Summaries", LibraryKind.summary), ("Originals", LibraryKind.original), ("Karaoke", LibraryKind.karaoke), ("Videos", LibraryKind.video)])
            Button { openFolder(kind) } label: {
                Label("Open \(Self.name(kind)) folder (\(library.entries(kind).count))", systemImage: "folder").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass).help(Self.folder(kind).path)

            let items = library.entries(kind)
            if items.isEmpty {
                Spacer()
                Text(kind == .video ? "Downloaded MP4 videos show up here." : kind == .original ? "Downloaded and dropped songs show up here." : kind == .karaoke ? "Finished karaoke tracks show up here." : "Finished summaries show up here.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: .infinity)
                Spacer()
            } else {
                List {
                    ForEach(items) { e in
                        HistoryRow(entry: e, player: player, onOpen: { store.openSummary(e) }) { pending = e }
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                    .onMove { library.move(kind, from: $0, to: $1) }
                    .onDelete { offsets in if let i = offsets.first { pending = items[i] } }
                }
                .listStyle(.plain).scrollContentBackground(.hidden)
                Text("Drag rows to reorder").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .onChange(of: kind) { _, _ in player.stop() }
        .onAppear { library.sync() }
        .confirmationDialog("Remove “\(pending?.title ?? "")”?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), presenting: pending) { e in
            Button("Remove from history") { if playingID(e) { player.stop() }; library.remove(e, trashFile: false) }
            if LibraryStore.canTrash(e) {
                Button("Move file to Trash", role: .destructive) { if playingID(e) { player.stop() }; library.remove(e, trashFile: true) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { e in
            Text(LibraryStore.canTrash(e) ? (e.kind == .summary ? "The summary folder (with its transcript) can also be moved to the Trash." : "The file can also be moved to the Trash.") : "Your original file stays where it is.")
        }
    }

    static func folder(_ kind: LibraryKind) -> URL {
        switch kind { case .original: Library.originalsDir; case .karaoke: Library.karaokeDir; case .summary: Library.summariesDir; case .video: Library.videosDir }
    }

    static func name(_ kind: LibraryKind) -> String {
        switch kind { case .original: "Originals"; case .karaoke: "Karaoke"; case .summary: "Summaries"; case .video: "Videos" }
    }

    private func openFolder(_ kind: LibraryKind) {
        let dir = Self.folder(kind)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }

    private func playingID(_ e: LibraryEntry) -> Bool { player.playingID == e.id }
}

struct HistoryRow: View {
    let entry: LibraryEntry
    @ObservedObject var player: Player
    let onOpen: () -> Void
    let onDelete: () -> Void
    private var exists: Bool { FileManager.default.fileExists(atPath: entry.path) }
    private var active: Bool { player.playingID == entry.id }
    /// Date, plus the subfolder when the file lives below the kind's root directory.
    private var subtitle: String {
        if entry.kind == .summary { return entry.added.formatted(date: .abbreviated, time: .shortened) }
        let root = (entry.kind == .karaoke ? Library.karaokeDir : entry.kind == .video ? Library.videosDir : Library.originalsDir).path + "/"
        let folder = entry.url.deletingLastPathComponent().path + "/"
        let rel = folder.hasPrefix(root) ? String(folder.dropFirst(root.count).dropLast()) : ""
        let date = entry.added.formatted(date: .abbreviated, time: .shortened)
        return rel.isEmpty ? date : "\(rel) · \(date)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                // Videos open in the default player (QuickTime/IINA); AVAudioPlayer can't show video.
                Button { entry.kind == .summary ? onOpen() : entry.kind == .video ? _ = NSWorkspace.shared.open(entry.url) : player.toggle(entry) } label: {
                    Image(systemName: entry.kind == .summary ? "doc.text.fill" : entry.kind == .video ? "play.rectangle.fill" : active && player.isPlaying ? "pause.circle.fill" : "play.circle.fill").font(.title2)
                        .foregroundStyle(exists ? AnyShapeStyle(Theme.gradient) : AnyShapeStyle(Color.secondary))
                }
                .buttonStyle(.plain).disabled(!exists)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title).font(.callout.weight(.medium)).lineLimit(2)
                    Text(exists ? subtitle : "File missing").font(.caption)
                        .foregroundStyle(exists ? Color.secondary : Color.red)
                }
                Spacer(minLength: 0)
                Button(action: onDelete) { Image(systemName: "trash") }.buttonStyle(.plain).foregroundStyle(.secondary).help("Remove")
            }
            if active {
                Slider(value: Binding(get: { player.progress }, set: { player.seek($0) })).controlSize(.small).tint(Theme.cyan)
            }
        }
        .padding(10)
        .background(active ? Theme.accent.opacity(0.10) : .white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(active ? Theme.accent.opacity(0.6) : .white.opacity(0.08)))
        .contextMenu {
            if exists { Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) } }
            Button("Remove…", action: onDelete)
        }
    }
}
