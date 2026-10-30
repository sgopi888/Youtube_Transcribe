import Foundation

public enum LibraryKind: String, Codable, Sendable { case original, karaoke, summary, video }

public struct LibraryEntry: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var kind: LibraryKind
    public var title: String
    public var path: String
    public var added = Date()
    public var url: URL { URL(fileURLWithPath: path) }
}

/// The history shown in the side panel. Order within each kind is the user's drag-and-drop order.
public struct LibraryIndex: Codable, Equatable, Sendable {
    public private(set) var entries: [LibraryEntry] = []
    /// Paths the user removed from the list but kept on disk, so a rescan does not bring them back.
    public private(set) var dismissed: Set<String> = []

    public init() {}

    public func list(_ kind: LibraryKind) -> [LibraryEntry] { entries.filter { $0.kind == kind } }

    /// New entries go on top; adding an existing path moves it to the top instead of duplicating it.
    public mutating func add(_ kind: LibraryKind, title: String, url: URL) {
        dismissed.remove(url.path)
        entries.removeAll { $0.kind == kind && $0.path == url.path }
        entries.insert(LibraryEntry(kind: kind, title: title, path: url.path), at: 0)
    }

    public mutating func remove(_ id: UUID) {
        guard let e = entries.first(where: { $0.id == id }) else { return }
        dismissed.insert(e.path)
        entries.removeAll { $0.id == id }
    }

    /// Reorders within one kind (same semantics as SwiftUI's `onMove`).
    public mutating func move(_ kind: LibraryKind, from: IndexSet, to: Int) {
        let sub = list(kind)
        let moving = from.sorted().map { sub[$0] }
        var rest = sub.enumerated().filter { !from.contains($0.offset) }.map(\.element)
        rest.insert(contentsOf: moving, at: to - from.filter { $0 < to }.count)
        entries = entries.filter { $0.kind != kind } + rest
    }

    public static let audioExtensions: Set<String> = ["mp3", "m4a", "wav", "flac", "aac", "ogg", "opus", "aiff", "aif"]
    public static let videoExtensions: Set<String> = ["mp4", "m4v", "mov", "webm", "mkv"]

    /// Makes the lists mirror the folders: Originals = every audio file under `musicDir` (subfolders included, `karaokeDir`
    /// excluded), Karaoke = every audio file under `karaokeDir`, Summaries = every `summary.md` under `summariesDir`,
    /// Videos = every video file under `videosDir`.
    /// Files gone from disk drop out; new ones go on top. Existing entries keep the user's order; removed ones stay hidden.
    public mutating func sync(musicDir: URL, karaokeDir: URL, summariesDir: URL? = nil, videosDir: URL? = nil) {
        let fm = FileManager.default
        func scan(_ dir: URL, skipping skip: String?, accepts: (URL) -> Bool) -> [URL] {
            guard let en = fm.enumerator(at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else { return [] }
            var found: [(URL, Date)] = []
            for case let f as URL in en {
                if f.resolvingSymlinksInPath().path == skip { en.skipDescendants(); continue }
                guard accepts(f) else { continue }
                found.append((f, (try? f.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast))
            }
            return found.sorted { $0.1 < $1.1 }.map(\.0)
        }
        let isAudio: (URL) -> Bool = { Self.audioExtensions.contains($0.pathExtension.lowercased()) }
        var roots: [(LibraryKind, URL, String?, (URL) -> Bool)] = [
            (.original, musicDir, karaokeDir.resolvingSymlinksInPath().path, isAudio), (.karaoke, karaokeDir, nil, isAudio)]
        if let s = summariesDir { roots.append((.summary, s, nil, { $0.lastPathComponent == "summary.md" })) }
        if let v = videosDir { roots.append((.video, v, nil, { Self.videoExtensions.contains($0.pathExtension.lowercased()) })) }
        for (kind, dir, skip, accepts) in roots {
            let files = scan(dir, skipping: skip, accepts: accepts)
            let onDisk = Set(files.map(\.path))
            entries.removeAll { $0.kind == kind && !onDisk.contains($0.path) }
            for f in files where !dismissed.contains(f.path) && !entries.contains(where: { $0.kind == kind && $0.path == f.path }) {
                let title = kind == .summary ? f.deletingLastPathComponent().lastPathComponent : f.deletingPathExtension().lastPathComponent
                entries.insert(LibraryEntry(kind: kind, title: title, path: f.path), at: 0)
            }
        }
    }

    public static func load(from url: URL) -> LibraryIndex {
        guard let data = try? Data(contentsOf: url), let idx = try? JSONDecoder().decode(LibraryIndex.self, from: data) else { return LibraryIndex() }
        return idx
    }

    public func save(to url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(self) { try? data.write(to: url, options: .atomic) }
    }
}
