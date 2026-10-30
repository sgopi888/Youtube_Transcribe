import Foundation
import SwiftUI
import YTScribeCore

struct Job: Identifiable {
    enum Status: Equatable {
        case fetching
        case summarizing(Int, Int)
        case done
        case failed(String)
    }
    let id: String  // video ID
    var title: String
    var status: Status = .fetching
    var transcript = ""
    var summary = ""
    var folder: URL?
}

struct AudioJob: Identifiable {
    enum Status: Equatable { case downloading(Double), done, failed(String) }
    enum Karaoke: Equatable { case idle, settingUp, running(Double), done(URL), failed(String) }
    let id: String  // video ID, or "file:<path>" for a dropped file
    var title: String
    var status: Status = .downloading(0)
    var file: URL?
    var model: KaraokeModel = .htdemucsCoreML
    var karaoke: Karaoke = .idle
    var karaokeOnly = false  // created from the Karaoke tab, hidden from the Audio tab
}

enum Mode: String { case summary, audio, karaoke }

@MainActor
final class JobStore: ObservableObject {
    @Published var jobs: [Job] = []
    @Published var selection: String?
    @Published var mode: Mode = .summary
    @Published var showVault = false  // Audio Vault (History) fills the main area
    let library = LibraryStore()
    @Published var audioJobs: [AudioJob] = []
    @Published var audioSelection: String?
    @Published var karaokeModel: KaraokeModel = KaraokeModel(rawValue: UserDefaults.standard.string(forKey: "karaokeModel") ?? "") ?? .htdemucsCoreML {
        didSet { UserDefaults.standard.set(karaokeModel.rawValue, forKey: "karaokeModel") }
    }
    @AppStorage("model") var model = OpenAIClient.defaultModel

    /// Starts one job per new video ID found in `text`; returns how many started. Jobs run in parallel.
    @discardableResult
    func add(from text: String) -> Int {
        if mode == .karaoke { return 0 }
        if mode == .audio { return addAudio(from: text) }
        var started = 0
        for id in YouTubeURL.videoIDs(in: text) {
            if let existing = jobs.first(where: { $0.id == id }), existing.status != .done, !isFailed(existing) { continue }
            jobs.removeAll { $0.id == id }
            jobs.insert(Job(id: id, title: id), at: 0)
            selection = id
            started += 1
            Task { await run(id) }
        }
        return started
    }

    /// Reopens a saved summary from History in the Summary tab.
    func openSummary(_ e: LibraryEntry) {
        let folder = e.url.deletingLastPathComponent()
        let name = folder.lastPathComponent
        let id = name.range(of: #"\[([^\]]+)\]$"#, options: .regularExpression).map { String(name[$0]).dropFirst().dropLast() }.map(String.init) ?? name
        let summary = (try? String(contentsOf: e.url, encoding: .utf8)) ?? ""
        let transcript = (try? String(contentsOf: folder.appendingPathComponent("transcript.txt"), encoding: .utf8)) ?? ""
        jobs.removeAll { $0.id == id }
        jobs.insert(Job(id: id, title: name, status: .done, transcript: transcript, summary: summary, folder: folder), at: 0)
        selection = id
        mode = .summary
        showVault = false
    }

    func retry(_ id: String) { add(from: id) }

    private func isFailed(_ j: Job) -> Bool { if case .failed = j.status { return true } else { return false } }

    private func update(_ id: String, _ change: (inout Job) -> Void) {
        if let i = jobs.firstIndex(where: { $0.id == id }) { change(&jobs[i]) }
    }

    private func run(_ id: String) async {
        do {
            guard let key = SecretStore.openAIKey(), !key.isEmpty else { throw LLMError.missingKey }
            let t = try await TranscriptFetcher().fetch(videoID: id)
            update(id) { $0.title = t.title; $0.transcript = t.text; $0.status = .summarizing(1, 1) }

            let summarizer = Summarizer(client: OpenAIClient(apiKey: key, model: model))
            let summary = try await summarizer.summarize(title: t.title, transcript: t.text) { [weak self] i, n in
                Task { @MainActor in self?.update(id) { $0.status = .summarizing(i, n) } }
            }
            let folder = try save(t, summary: summary)
            update(id) { $0.summary = summary; $0.folder = folder; $0.status = .done }
            library.add(.summary, title: folder.lastPathComponent, url: folder.appendingPathComponent("summary.md"))
        } catch {
            update(id) { $0.status = .failed(error.localizedDescription) }
        }
    }

    /// ~/Downloads/YTScribe/<title> [id]/{transcript.txt,summary.md}
    private func save(_ t: Transcript, summary: String) throws -> URL {
        let safe = t.title.replacingOccurrences(of: #"[/:\\]"#, with: "-", options: .regularExpression).prefix(80)
        let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("YTScribe/\(safe) [\(t.videoID)]")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try t.text.write(to: dir.appendingPathComponent("transcript.txt"), atomically: true, encoding: .utf8)
        try ("# \(t.title)\n\nhttps://youtu.be/\(t.videoID)\n\n" + summary).write(to: dir.appendingPathComponent("summary.md"), atomically: true, encoding: .utf8)
        return dir
    }
}

// MARK: audio
extension JobStore {
    private var audioDir: URL { Library.originalsDir }

    func addAudio(from text: String) -> Int {
        var started = 0
        for id in YouTubeURL.videoIDs(in: text) {
            if let e = audioJobs.first(where: { $0.id == id }), case .downloading = e.status { continue }
            audioJobs.removeAll { $0.id == id }
            audioJobs.insert(AudioJob(id: id, title: id), at: 0)
            audioSelection = id
            started += 1
            Task { await runAudio(id) }
        }
        return started
    }

    func retryAudio(_ id: String) { _ = addAudio(from: id) }

    fileprivate func updateAudio(_ id: String, _ change: (inout AudioJob) -> Void) {
        if let i = audioJobs.firstIndex(where: { $0.id == id }) { change(&audioJobs[i]) }
    }

    private func runAudio(_ id: String) async {
        do {
            let file = try await AudioDownloader().download(videoID: id, outDir: audioDir) { [weak self] ev in
                Task { @MainActor in
                    switch ev {
                    case .title(let t): self?.updateAudio(id) { $0.title = t }
                    case .progress(let p): self?.updateAudio(id) { if case .downloading = $0.status { $0.status = .downloading(p) } }
                    case .file: break
                    }
                }
            }
            updateAudio(id) { $0.file = file; $0.status = .done }
            library.add(.original, title: file.deletingPathExtension().lastPathComponent, url: file)
        } catch {
            updateAudio(id) { $0.status = .failed(error.localizedDescription) }
        }
    }
}

// MARK: karaoke
extension JobStore {
    static let audioExtensions: Set<String> = ["mp3", "m4a", "wav", "flac", "aac", "ogg", "opus", "aiff", "aif"]

    /// Files from outside ~/Music/YTScribe are copied in (the original is untouched) so History matches the folder.
    private static func intoLibrary(_ url: URL) -> URL {
        let fm = FileManager.default
        if url.path.hasPrefix(Library.musicDir.path + "/") { return url }
        try? fm.createDirectory(at: Library.originalsDir, withIntermediateDirectories: true)
        var dest = Library.originalsDir.appendingPathComponent(url.lastPathComponent), n = 2
        while fm.fileExists(atPath: dest.path) {
            dest = Library.originalsDir.appendingPathComponent(url.deletingPathExtension().lastPathComponent + " \(n)." + url.pathExtension)
            n += 1
        }
        return (try? fm.copyItem(at: url, to: dest)) != nil ? dest : url
    }

    /// Adds audio files (drop or file picker). On the Karaoke tab each file starts converting immediately
    /// with the chosen model; elsewhere it is added to the Audio tab, ready for the Generate button.
    @discardableResult
    func addFiles(_ urls: [URL]) -> Int {
        let karaokeTab = mode == .karaoke
        var added = 0
        for dropped in urls where Self.audioExtensions.contains(dropped.pathExtension.lowercased()) {
            let url = Self.intoLibrary(dropped)
            let id = (karaokeTab ? "karaoke:" : "file:") + url.path
            audioSelection = id
            if audioJobs.contains(where: { $0.id == id }) { continue }
            audioJobs.insert(AudioJob(id: id, title: url.deletingPathExtension().lastPathComponent, status: .done, file: url,
                                      model: karaokeTab ? karaokeModel : .htdemucsCoreML, karaokeOnly: karaokeTab), at: 0)
            if !url.path.hasPrefix(Library.karaokeDir.path + "/") { library.add(.original, title: url.deletingPathExtension().lastPathComponent, url: url) }
            if karaokeTab { makeKaraoke(id) }
            added += 1
        }
        if added > 0 && !karaokeTab { mode = .audio }
        return added
    }

    func setModel(_ id: String, _ model: KaraokeModel) { updateAudio(id) { $0.model = model } }

    func makeKaraoke(_ id: String) {
        guard let job = audioJobs.first(where: { $0.id == id }), let file = job.file else { return }
        if case .running = job.karaoke { return }
        let model = job.model
        updateAudio(id) { $0.karaoke = .running(0) }
        Task {
            do {
                if model == .bsRoformer && !RoformerEngine.isInstalled {
                    updateAudio(id) { $0.karaoke = .settingUp }
                    try await RoformerEngine.setUp()
                }
                let out = Library.karaokeURL(for: file, model: model)
                updateAudio(id) { $0.karaoke = .running(0) }
                try await model.engine.makeInstrumental(input: file, output: out) { [weak self] p in
                    Task { @MainActor in self?.updateAudio(id) { if case .running = $0.karaoke { $0.karaoke = .running(p) } } }
                }
                updateAudio(id) { $0.karaoke = .done(out) }
                library.add(.karaoke, title: out.deletingPathExtension().lastPathComponent, url: out)
            } catch {
                updateAudio(id) { $0.karaoke = .failed(error.localizedDescription) }
            }
        }
    }
}
