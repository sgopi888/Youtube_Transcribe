import SwiftUI
import AppKit
import YTScribeCore

/// AI Summary tab: clipboard banner, ingest card, job cards + stats, and the document inspector.
struct SummaryTab: View {
    @EnvironmentObject var store: JobStore
    @EnvironmentObject var library: LibraryStore
    @State private var input = ""
    @State private var clip: String?
    @State private var ignoredClip: String?
    @State private var storage: (bytes: Int64, files: Int) = (0, 0)
    @FocusState private var focused: Bool

    private var selected: Job? { store.jobs.first { $0.id == store.selection } }

    var body: some View {
        VStack(spacing: 14) {
            if let clip { clipboardBanner(clip) }
            ingestCard
            HStack(alignment: .top, spacing: 14) {
                ScrollView {
                    VStack(spacing: 14) {
                        if store.jobs.isEmpty { emptyCard }
                        ForEach(store.jobs) { job in
                            SummaryJobCard(job: job, selected: job.id == store.selection)
                                .onTapGesture { store.selection = job.id }
                        }
                        statsRow
                    }
                }
                .scrollIndicators(.hidden)
                .frame(maxWidth: .infinity)
                SummaryInspector(job: selected).frame(width: 420)
            }
        }
        .padding(14)
        .onAppear { checkClipboard(); focused = true; refreshStorage() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in checkClipboard() }
        .onChange(of: store.jobs.map(\.id)) { _, _ in checkClipboard() }
        .onChange(of: library.entries(.summary).count) { _, _ in refreshStorage() }
    }

    // MARK: clipboard

    /// Offers a YouTube link sitting on the clipboard that is not queued yet.
    private func checkClipboard() {
        guard let s = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), s != ignoredClip else { clip = nil; return }
        let ids = YouTubeURL.videoIDs(in: s)
        clip = ids.contains(where: { id in !store.jobs.contains { $0.id == id } }) ? s : nil
    }

    private func clipboardBanner(_ link: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.on.clipboard").font(.ui(15)).foregroundStyle(Theme.tertiary)
                .frame(width: 34, height: 34).background(Theme.tertiary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            Text("Detected YouTube link from clipboard:").font(.ui(14, .medium)).foregroundStyle(Theme.onSurface)
            Text(link).font(.mono(12)).foregroundStyle(Theme.primary).lineLimit(1).truncationMode(.middle)
                .padding(.horizontal, 6).padding(.vertical, 3).background(Theme.lowest, in: RoundedRectangle(cornerRadius: 5))
            Spacer()
            Button("Ignore") { ignoredClip = link; clip = nil }.buttonStyle(.ghost)
            Button("Add to Queue") {
                let keep = store.selection
                store.add(from: link)
                if keep != nil { store.selection = keep }
            }.buttonStyle(.glass)
            Button { store.add(from: link) } label: { Label("Auto-Extract", systemImage: "bolt") }.buttonStyle(.primary)
        }
        .card(12, fill: Theme.container)
    }

    // MARK: ingest

    private var ingestCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Queue YouTube Summaries").font(.ui(17, .semibold)).tracking(-0.2)
                Tag(text: "OpenAI · \(store.model)")
                Spacer()
                Tag(text: "No audio download required", icon: "icloud.slash", tint: Theme.tertiary, fill: Theme.tertiary.opacity(0.1))
                Tag(text: "\(store.jobs.count) in queue", icon: "gauge.with.dots.needle.67percent", tint: Theme.primary, fill: Theme.primary.opacity(0.1))
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "link").foregroundStyle(Theme.outline).padding(.top, 2)
                    TextField("Paste single or multiple YouTube URLs (separate by line or comma)… e.g. https://youtube.com/watch?v=kCc8FmEb1nY", text: $input, axis: .vertical)
                        .textFieldStyle(.plain).font(.ui(13.5)).lineLimit(2...4).focused($focused)
                        // Auto-detect: any pasted/typed text containing a link starts jobs immediately.
                        .onChange(of: input) { _, new in if store.add(from: new) > 0 { input = "" } }
                }
                HStack(spacing: 6) {
                    Text("Shortcuts:").font(.ui(12.5)).foregroundStyle(Theme.variant)
                    Tag(text: "⌘V anywhere")
                    Tag(text: "Several links at once")
                    Spacer()
                    Tag(text: "Technical deep-dive", tint: Theme.onSurface, fill: Theme.highest)
                    Button { if store.add(from: input) > 0 { input = "" } } label: {
                        HStack(spacing: 8) {
                            Label("Batch Ingest", systemImage: "plus.rectangle.on.rectangle")
                            Image(systemName: "return").font(.ui(10, .bold)).padding(3).background(Theme.onPrimary.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    .buttonStyle(.primary).keyboardShortcut(.return, modifiers: .command)
                }
            }
            .card(12, fill: Theme.lowest.opacity(0.7), radius: 10)
        }
        .card(16)
    }

    private var emptyCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles").font(.ui(36, .light)).foregroundStyle(Theme.gradient)
            Text("Paste a YouTube link").font(.ui(18, .semibold))
            Text("Get a detailed technical summary in seconds.\nPress ⌘V anywhere in this window.").font(.ui(13)).foregroundStyle(Theme.variant).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 220).card(16)
    }

    // MARK: stats

    private func refreshStorage() {
        Task.detached(priority: .utility) {
            let s = folderSize(Library.summariesDir)
            await MainActor.run { storage = s }
        }
    }

    private var statsRow: some View {
        HStack(spacing: 14) {
            miniStat("cylinder.split.1x2", "Library Storage", byteString(storage.bytes), "(.md + transcripts)")
            miniStat("hourglass", "Summaries Saved", "\(library.entries(.summary).count)", "in Audio Vault")
            miniStat("cpu", "Summary Model", store.model, "OpenAI")
        }
    }

    private func miniStat(_ icon: String, _ label: String, _ value: String, _ suffix: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.ui(16)).foregroundStyle(Theme.primary)
                .frame(width: 38, height: 38).background(Theme.high, in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.ui(12)).foregroundStyle(Theme.variant)
                (Text(value).font(.ui(17, .semibold)) + Text(" " + suffix).font(.ui(13)).foregroundStyle(Theme.variant))
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity).card(14)
    }
}

// MARK: - Job card

struct SummaryJobCard: View {
    @EnvironmentObject var store: JobStore
    let job: Job
    let selected: Bool
    @State private var copied = false

    private var words: Int { (job.summary.isEmpty ? job.transcript : job.summary).split { $0.isWhitespace }.count }
    private var teaser: String {
        let lines = job.summary.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        return lines.first { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix("http") } ?? "youtu.be/\(job.id)"
    }
    private var running: Bool { switch job.status { case .fetching, .summarizing: true; default: false } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Thumb(videoID: job.id, icon: "play.rectangle")
                    .frame(width: 168, height: 94).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(alignment: .topLeading) { badge.padding(6) }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(job.title).font(.ui(16, .semibold)).tracking(-0.2).lineLimit(1)
                        Spacer(minLength: 6)
                        StatusChip(status: job.status)
                    }
                    Text(teaser.replacingOccurrences(of: "**", with: "")).font(.ui(13)).foregroundStyle(Theme.variant).lineLimit(1)
                    HStack(spacing: 8) {
                        Tag(text: store.model, icon: "sparkles", tint: Theme.onSurface, fill: Theme.high)
                        Link(destination: URL(string: "https://youtu.be/\(job.id)")!) { Tag(text: "youtu.be/\(job.id)", icon: "link") }
                        Spacer()
                        if words > 0 {
                            Label("\(words.formatted()) words", systemImage: running ? "text.alignleft" : "doc.text")
                                .font(.mono(11)).foregroundStyle(Theme.tertiary)
                        }
                    }
                    .padding(.top, 2)
                    if case .done = job.status, let f = job.folder {
                        Label(tildePath(f), systemImage: "folder").font(.mono(11)).foregroundStyle(Theme.primary).lineLimit(1).truncationMode(.middle)
                    }
                }
            }

            switch job.status {
            case .fetching, .summarizing:
                progressBlock
                if !job.transcript.isEmpty { streamBox }
            case .failed(let msg):
                Text(msg).font(.ui(12.5)).foregroundStyle(Theme.error).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).card(10, fill: Theme.error.opacity(0.08), radius: 8)
            case .done: EmptyView()
            }

            HStack(spacing: 8) {
                if case .failed = job.status {
                    Spacer()
                    Button { store.retry(job.id) } label: { Label("Retry", systemImage: "arrow.clockwise") }.buttonStyle(.primary)
                } else {
                    if case .done = job.status {
                        Tag(text: "Model: \(store.model)")
                        Tag(text: "Format: Markdown")
                    }
                    Spacer()
                    Button { copy() } label: {
                        Label(copied ? "Copied" : (job.summary.isEmpty ? "Copy Transcript" : "Copy .md"), systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.ghost).disabled(job.transcript.isEmpty && job.summary.isEmpty)
                    if let f = job.folder {
                        Button { NSWorkspace.shared.activateFileViewerSelecting([f]) } label: { Label("Reveal in Finder", systemImage: "folder") }.buttonStyle(.glass)
                    }
                    Button { store.selection = job.id } label: { Label("View Summary", systemImage: "eye") }
                        .buttonStyle(.primary).disabled(job.summary.isEmpty)
                }
            }
        }
        .card(16)
        .overlay(alignment: .top) {
            if selected {
                LinearGradient(colors: [Theme.tertiary, Theme.primary], startPoint: .leading, endPoint: .trailing)
                    .frame(height: 2).clipShape(Capsule()).padding(.horizontal, 8)
            }
        }
        .contentShape(Rectangle())
    }

    private var badge: some View {
        HStack(spacing: 4) {
            Circle().fill(running ? Theme.tertiary : .white).frame(width: 5, height: 5)
            Text(running ? "LIVE" : job.status == .done ? "COMPLETED" : "FAILED").font(.mono(9.5, .medium))
        }
        .foregroundStyle(running ? Theme.tertiary : .white)
        .padding(.horizontal, 6).padding(.vertical, 3)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
    }

    private var progressBlock: some View {
        let (text, value, count): (String, Double?, String) = {
            switch job.status {
            case .summarizing(let i, let n): return ("Synthesizing summary from the transcript…", n > 0 ? Double(i - 1) / Double(n) + 0.5 / Double(n) : nil, "\(i) / \(n) Chunks")
            default: return ("Fetching the transcript from YouTube…", nil, "")
            }
        }()
        return VStack(spacing: 8) {
            HStack {
                Label(text, systemImage: "arrow.triangle.2.circlepath").font(.ui(12.5, .medium)).foregroundStyle(Theme.onSurface)
                    .symbolEffect(.pulse)
                Spacer()
                Text(count).font(.mono(11)).foregroundStyle(Theme.variant)
            }
            ProgressBar(value: value, height: 5)
        }
    }

    private var streamBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Transcript stream (\(job.transcript.split { $0.isWhitespace }.count.formatted()) words)").sectionLabel()
                Spacer()
                Text("FETCHED FROM YOUTUBE").font(.mono(10.5, .medium)).foregroundStyle(Theme.tertiary)
            }
            Text(String(job.transcript.prefix(260)) + "…").font(.ui(12.5)).foregroundStyle(Theme.onSurface.opacity(0.85)).lineLimit(2)
        }
        .card(12, fill: Theme.lowest.opacity(0.7), radius: 8)
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(job.summary.isEmpty ? job.transcript : job.summary, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
    }
}

// MARK: - Inspector

struct SummaryInspector: View {
    @EnvironmentObject var store: JobStore
    let job: Job?
    @State private var tab = 0
    @State private var copied = false

    private var text: String { guard let job else { return "" }; return tab == 2 ? job.transcript : job.summary }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text").foregroundStyle(Theme.variant)
                Text(job.map { $0.folder?.lastPathComponent ?? $0.title } ?? "No summary selected").font(.ui(13.5, .medium)).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 4)
                GlassSegmented(selection: $tab, items: [("Rendered", 0), ("Raw .md", 1), ("Transcript", 2)], size: 11.5)
                Button { copy() } label: { Image(systemName: copied ? "checkmark" : "doc.on.doc") }
                    .buttonStyle(IconButtonStyle(size: 28, fill: .clear, tint: Theme.variant)).disabled(text.isEmpty).help("Copy")
                Button { if let f = job?.folder { NSWorkspace.shared.activateFileViewerSelecting([f.appendingPathComponent("summary.md")]) } } label: { Image(systemName: "square.and.arrow.down") }
                    .buttonStyle(IconButtonStyle(size: 28, fill: .clear, tint: Theme.variant)).disabled(job?.folder == nil).help("Show summary.md in Finder")
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            Divider().overlay(Theme.outlineVariant.opacity(0.4))

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let job {
                        Text("GENERATED BY YTSCRIBE • MODEL: \(store.model.uppercased())").font(.mono(11, .medium)).foregroundStyle(Theme.tertiary)
                        Text(job.title).font(.ui(24, .semibold)).tracking(-0.5).textSelection(.enabled)
                        Text("youtu.be/\(job.id) • \(job.transcript.split { $0.isWhitespace }.count.formatted()) transcript words").font(.mono(11.5)).foregroundStyle(Theme.variant)
                        if text.isEmpty {
                            HStack(spacing: 8) { ProgressView().controlSize(.small); Text(job.transcript.isEmpty ? "Fetching transcript…" : "Writing your summary…").foregroundStyle(Theme.variant) }
                                .padding(.vertical, 30).frame(maxWidth: .infinity)
                        } else if tab == 0 {
                            MarkdownView(text: job.summary)
                        } else {
                            Text(text).font(tab == 1 ? .mono(12) : .ui(14)).lineSpacing(4).textSelection(.enabled)
                        }
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "doc.richtext").font(.ui(34, .light)).foregroundStyle(Theme.gradient)
                            Text("Select a summary to read it here.").foregroundStyle(Theme.variant)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 80)
                    }
                }
                .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider().overlay(Theme.outlineVariant.opacity(0.4))
            HStack {
                StatusDot(color: job?.folder != nil ? Theme.tertiary : Theme.outline, size: 6)
                Text(job?.folder != nil ? "Saved to disk" : "Not saved yet").font(.mono(11)).foregroundStyle(Theme.variant)
                Spacer()
                Text("Encoding: UTF-8 • \(text.count.formatted()) chars").font(.mono(11)).foregroundStyle(Theme.variant)
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
        }
        .background(Theme.low, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .animation(.easeInOut(duration: 0.15), value: tab)
    }

    private func copy() {
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
    }
}
