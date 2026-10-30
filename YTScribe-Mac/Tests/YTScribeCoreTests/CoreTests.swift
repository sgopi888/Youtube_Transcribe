import XCTest
@testable import YTScribeCore

final class URLTests: XCTestCase {
    func testForms() {
        let t = "https://www.youtube.com/watch?v=O_irkwZoQw8 and https://youtu.be/zyNWbPBkq6E?si=abc\nhttps://www.youtube.com/live/1N2TXfy5FAg https://youtube.com/shorts/C3-4llQYT8o https://www.youtube.com/watch?feature=x&v=EQq_qQ_P67c"
        XCTAssertEqual(YouTubeURL.videoIDs(in: t), ["O_irkwZoQw8", "EQq_qQ_P67c", "zyNWbPBkq6E", "1N2TXfy5FAg", "C3-4llQYT8o"].sorted { t.range(of: $0)!.lowerBound < t.range(of: $1)!.lowerBound })
    }
    func testDedupeAndBareID() {
        XCTAssertEqual(YouTubeURL.videoIDs(in: "https://youtu.be/O_irkwZoQw8 https://youtu.be/O_irkwZoQw8"), ["O_irkwZoQw8"])
        XCTAssertEqual(YouTubeURL.videoIDs(in: "O_irkwZoQw8"), ["O_irkwZoQw8"])
        XCTAssertEqual(YouTubeURL.videoIDs(in: "hello world"), [])
    }
}

final class ParseTests: XCTestCase {
    func testCaptionXMLDoubleEscapedAndTags() {
        let xml = #"<transcript><text start="0" dur="1">it&amp;#39;s &lt;i&gt;great&lt;/i&gt;</text><text start="1" dur="1">a &amp;amp; b</text></transcript>"#
        XCTAssertEqual(TranscriptFetcher.parseCaptionXML(Data(xml.utf8)), "it's great a & b")
    }
    func testPickTrackPrefersManualInPreferredLanguage() {
        let tracks: [[String: Any]] = [["languageCode": "en", "kind": "asr", "baseUrl": "auto"], ["languageCode": "en", "baseUrl": "manual"], ["languageCode": "hi", "baseUrl": "hi"]]
        XCTAssertEqual(TranscriptFetcher.pickTrack(tracks, languages: ["en", "hi"])?["baseUrl"] as? String, "manual")
        XCTAssertEqual(TranscriptFetcher.pickTrack(tracks, languages: ["fr"])?["baseUrl"] as? String, "auto")
        XCTAssertNil(TranscriptFetcher.pickTrack([], languages: ["en"]))
    }
    func testOutputTextFallsBackToOutputArray() {
        let json: [String: Any] = ["output": [["content": [["type": "output_text", "text": "hi"]]]]]
        XCTAssertEqual(OpenAIClient.outputText(json), "hi")
    }
}

private final class FakeLLM: LLMClient, @unchecked Sendable {
    var calls: [(String, String)] = []
    func complete(instructions: String, input: String) async throws -> String {
        calls.append((instructions, input)); return "S\(calls.count)"
    }
}

final class ChunkTests: XCTestCase {
    func testSmallTextIsOneChunk() { XCTAssertEqual(Chunker.split("hello. world.", maxTokens: 100), ["hello. world."]) }

    func testSplitsAtSentenceAndLosesNothing() {
        let text = (0..<50).map { "Sentence number \($0)." }.joined(separator: " ")
        let chunks = Chunker.split(text, maxTokens: 25)  // 100 chars
        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertTrue(chunks.allSatisfy { $0.count <= 100 && $0.hasSuffix(".") })
        XCTAssertEqual(chunks.joined(separator: " "), text)
    }

    func testSingleCallWhenUnderBudget() async throws {
        let llm = FakeLLM()
        let out = try await Summarizer(client: llm, chunkBudget: 1000).summarize(title: "T", transcript: "short")
        XCTAssertEqual(out, "S1"); XCTAssertEqual(llm.calls.count, 1)
    }

    func testMapReduceWhenOverBudget() async throws {
        let llm = FakeLLM()
        let text = (0..<50).map { "Sentence number \($0)." }.joined(separator: " ")
        var seen: [(Int, Int)] = []
        let box = Box()
        let out = try await Summarizer(client: llm, chunkBudget: 25).summarize(title: "T", transcript: text) { box.add($0, $1) }
        seen = box.items
        let n = llm.calls.count
        XCTAssertGreaterThan(n, 2)
        XCTAssertEqual(out, "S\(n)")  // last call is the merge
        XCTAssertTrue(llm.calls.last!.1.contains("Notes from part 1"))
        XCTAssertEqual(seen.last?.0, n); XCTAssertEqual(seen.last?.1, n)
    }
}

private final class Box: @unchecked Sendable {
    var items: [(Int, Int)] = []
    func add(_ a: Int, _ b: Int) { items.append((a, b)) }
}

/// Hits YouTube. Run with: YT_LIVE=1 swift test --filter LiveTests
final class LiveTests: XCTestCase {
    func testFetchRealTranscript() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["YT_LIVE"] == "1")
        let t = try await TranscriptFetcher().fetch(videoID: "O_irkwZoQw8")
        XCTAssertFalse(t.title.isEmpty)
        XCTAssertGreaterThan(t.text.count, 1000)
        print("LIVE title=\(t.title) chars=\(t.text.count) head=\(t.text.prefix(120))")
    }
}

final class AudioTests: XCTestCase {
    func testParseLines() {
        XCTAssertEqual(AudioDownloader.parse(line: "TITLE\tMy Video"), .title("My Video"))
        XCTAssertEqual(AudioDownloader.parse(line: "PCT\t  42.5%"), .progress(42.5))
        XCTAssertEqual(AudioDownloader.parse(line: "FILE\t/tmp/a b [x].mp3"), .file(URL(fileURLWithPath: "/tmp/a b [x].mp3")))
        XCTAssertNil(AudioDownloader.parse(line: "[download] noise"))
        XCTAssertNil(AudioDownloader.parse(line: "PCT\tNA"))
    }
    func testArgumentsRequestBestAudioMP3V0() {
        let a = AudioDownloader.arguments(url: "u", outDir: URL(fileURLWithPath: "/o"), ffmpegDir: URL(fileURLWithPath: "/f"))
        XCTAssertEqual(a[a.firstIndex(of: "-f")! + 1], "bestaudio")
        XCTAssertEqual(a[a.firstIndex(of: "--audio-format")! + 1], "mp3")
        XCTAssertEqual(a[a.firstIndex(of: "--audio-quality")! + 1], "0")
        XCTAssertEqual(a.last, "u")
    }

    func testVideoArgumentsPreferH264AtFixedHeights() {
        let a = AudioDownloader.videoArguments(url: "u", outDir: URL(fileURLWithPath: "/o"), quality: "720", ffmpegDir: URL(fileURLWithPath: "/f"))
        XCTAssertEqual(a[a.firstIndex(of: "-S")! + 1], "res:720,vcodec:h264,acodec:m4a")
        XCTAssertEqual(a[a.firstIndex(of: "--merge-output-format")! + 1], "mp4")
        XCTAssertTrue(a[a.firstIndex(of: "-o")! + 1].hasSuffix("[%(id)s] 720.%(ext)s"))
        XCTAssertEqual(a.last, "u")
        let b = AudioDownloader.videoArguments(url: "u", outDir: URL(fileURLWithPath: "/o"), quality: "best", ffmpegDir: URL(fileURLWithPath: "/f"))
        XCTAssertEqual(b[b.firstIndex(of: "-S")! + 1], "res,fps")
        XCTAssertEqual(AudioDownloader.videoQualities.map(\.id), ["best", "1080", "720", "480", "360"])
    }
    func testLiveDownload() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["YT_LIVE"] == "1")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ytscribe-audio-test")
        let events = EventLog()
        let f = try await AudioDownloader().download(videoID: "O_irkwZoQw8", outDir: dir) { events.add($0) }
        let size = (try FileManager.default.attributesOfItem(atPath: f.path)[.size] as? Int) ?? 0
        XCTAssertEqual(f.pathExtension, "mp3")
        XCTAssertGreaterThan(size, 100_000)
        print("LIVE audio \(f.lastPathComponent) bytes=\(size) events=\(events.count)")
    }
}

private final class EventLog: @unchecked Sendable {
    private var n = 0; private let l = NSLock()
    func add(_ e: AudioEvent) { l.lock(); n += 1; l.unlock() }
    var count: Int { n }
}

private struct IdentityPredictor: WindowPredictor {
    func instrumental(window: [Float]) throws -> [Float] { window }
}

final class KaraokeTests: XCTestCase {
    private func tone(_ n: Int, _ f: Double) -> [Float] { (0..<n).map { Float(0.5 * sin(2 * .pi * f * Double($0) / 44_100)) } }

    func testPipelineReconstructsInputAcrossWindowBoundaries() throws {
        let n = 44_100 * 25  // 25 s: three overlapping windows plus edges
        let l = tone(n, 220), r = tone(n, 330)
        let (ol, or) = try DemucsPipeline.run(left: l, right: r, predictor: IdentityPredictor()) { _ in }
        XCTAssertEqual(ol.count, n); XCTAssertEqual(or.count, n)
        var worst: Float = 0
        for i in stride(from: 0, to: n, by: 97) { worst = max(worst, abs(ol[i] - l[i]), abs(or[i] - r[i])) }
        XCTAssertLessThan(worst, 0.01)
    }

    func testPipelineShortInputKeepsLength() throws {
        let l = tone(5_000, 440)
        let (ol, _) = try DemucsPipeline.run(left: l, right: l, predictor: IdentityPredictor()) { _ in }
        XCTAssertEqual(ol.count, 5_000)
        XCTAssertLessThan(abs(ol[2_500] - l[2_500]), 0.01)
    }

    func testPipelineReportsProgressToOne() throws {
        let l = tone(44_100 * 12, 220)
        var last = 0.0
        _ = try DemucsPipeline.run(left: l, right: l, predictor: IdentityPredictor()) { last = $0 }
        XCTAssertEqual(last, 1.0, accuracy: 1e-9)
    }

    func testKaraokeNamesDifferPerModel() {
        let dir = URL(fileURLWithPath: "/m/Karaoke")
        let song = URL(fileURLWithPath: "/m/My Song [abc].mp3")
        XCTAssertEqual(Library.karaokeURL(for: song, model: .htdemucsCoreML, in: dir).lastPathComponent, "My Song [abc] (karaoke).mp3")
        XCTAssertEqual(Library.karaokeURL(for: song, model: .bsRoformer, in: dir).lastPathComponent, "My Song [abc] (karaoke, roformer).mp3")
    }

    func testRoformerArgumentsAskForInstrumentalOnly() {
        let a = RoformerEngine.arguments(input: URL(fileURLWithPath: "/in.mp3"), outDir: URL(fileURLWithPath: "/out"))
        XCTAssertEqual(a[a.firstIndex(of: "--single_stem")! + 1], "Instrumental")
        XCTAssertEqual(a[a.firstIndex(of: "--model_filename")! + 1], "model_bs_roformer_ep_317_sdr_12.9755.ckpt")
    }

    /// Real model on a real file. Run with: YT_LIVE=1 YT_KARAOKE_FILE=/path/song.mp3 swift test --filter testLiveCoreML
    func testLiveCoreML() async throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["YT_LIVE"] == "1", "live")
        let src = URL(fileURLWithPath: try XCTUnwrap(env["YT_KARAOKE_FILE"]))
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("karaoke-live/out-coreml.mp3")
        let t0 = Date()
        try await DemucsCoreMLEngine().makeInstrumental(input: src, output: out) { _ in }
        let secs = Date().timeIntervalSince(t0)
        let size = (try FileManager.default.attributesOfItem(atPath: out.path)[.size] as? Int) ?? 0
        XCTAssertGreaterThan(size, 100_000)
        print("LIVE coreml seconds=\(secs) bytes=\(size) out=\(out.path)")
    }
}

extension KaraokeTests {
    /// Run with: YT_LIVE=1 YT_KARAOKE_FILE=/path/song.mp3 swift test --filter testLiveRoformer
    func testLiveRoformer() async throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["YT_LIVE"] == "1", "live")
        try XCTSkipUnless(RoformerEngine.isInstalled, "run scripts/setup_roformer.sh first")
        let src = URL(fileURLWithPath: try XCTUnwrap(env["YT_KARAOKE_FILE"]))
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("karaoke-live/out-roformer.mp3")
        let t0 = Date()
        try await RoformerEngine().makeInstrumental(input: src, output: out) { _ in }
        let size = (try FileManager.default.attributesOfItem(atPath: out.path)[.size] as? Int) ?? 0
        XCTAssertGreaterThan(size, 100_000)
        print("LIVE roformer seconds=\(Date().timeIntervalSince(t0)) bytes=\(size) out=\(out.path)")
    }
}

final class SecretStoreTests: XCTestCase {
    func testRoundTripPermissionsAndClear() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("secret-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertTrue(SecretStore.saveOpenAIKey("sk-test-123", dir: dir))
        XCTAssertEqual(SecretStore.openAIKey(dir: dir), "sk-test-123")
        let perms = try FileManager.default.attributesOfItem(atPath: SecretStore.fileURL(dir).path)[.posixPermissions] as? Int
        XCTAssertEqual(perms, 0o600)
        XCTAssertTrue(SecretStore.saveOpenAIKey("sk-test-456", dir: dir))
        XCTAssertEqual(SecretStore.openAIKey(dir: dir), "sk-test-456")
    }
}

final class LibraryIndexTests: XCTestCase {
    private func u(_ n: String) -> URL { URL(fileURLWithPath: "/m/\(n).mp3") }

    func testAddDedupesByPathAndMovesToTop() {
        var i = LibraryIndex()
        i.add(.original, title: "A", url: u("a")); i.add(.original, title: "B", url: u("b")); i.add(.original, title: "A", url: u("a"))
        XCTAssertEqual(i.list(.original).map(\.title), ["A", "B"])
        i.add(.karaoke, title: "A k", url: u("a"))  // same path, other kind: separate list
        XCTAssertEqual(i.list(.karaoke).count, 1); XCTAssertEqual(i.list(.original).count, 2)
    }

    func testMoveReordersOnlyThatKind() {
        var i = LibraryIndex()
        for n in ["c", "b", "a"] { i.add(.original, title: n, url: u(n)) }  // list: a b c
        i.add(.karaoke, title: "k", url: u("k"))
        i.move(.original, from: IndexSet(integer: 0), to: 3)  // a to the end
        XCTAssertEqual(i.list(.original).map(\.title), ["b", "c", "a"])
        i.move(.original, from: IndexSet(integer: 2), to: 0)  // a back to the front
        XCTAssertEqual(i.list(.original).map(\.title), ["a", "b", "c"])
        XCTAssertEqual(i.list(.karaoke).map(\.title), ["k"])
    }

    func testRemovedFileIsNotResyncedButReAddingWorks() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lib-" + UUID().uuidString)
        let kdir = dir.appendingPathComponent("Karaoke")
        try FileManager.default.createDirectory(at: kdir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        for f in [dir.appendingPathComponent("song.mp3"), kdir.appendingPathComponent("song (karaoke).mp3"), dir.appendingPathComponent("notes.txt")] {
            try Data([1]).write(to: f)
        }
        var i = LibraryIndex()
        i.sync(musicDir: dir, karaokeDir: kdir)
        XCTAssertEqual(i.list(.original).map(\.title), ["song"])
        XCTAssertEqual(i.list(.karaoke).map(\.title), ["song (karaoke)"])
        i.sync(musicDir: dir, karaokeDir: kdir)  // idempotent
        XCTAssertEqual(i.entries.count, 2)

        i.remove(i.list(.original)[0].id)
        i.sync(musicDir: dir, karaokeDir: kdir)
        XCTAssertEqual(i.list(.original).count, 0)
        i.add(.original, title: "song", url: dir.appendingPathComponent("song.mp3"))
        XCTAssertEqual(i.list(.original).count, 1)
    }

    func testMigrateMovesRootSongsAndKeepsKaraoke() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lib-" + UUID().uuidString)
        let orig = dir.appendingPathComponent("Originals"), kdir = dir.appendingPathComponent("Karaoke")
        try FileManager.default.createDirectory(at: kdir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        for f in ["a.mp3", "Karaoke/k.mp3"] { try Data([1]).write(to: dir.appendingPathComponent(f)) }
        Library.migrateLegacyOriginals(musicDir: dir, originalsDir: orig)
        XCTAssertTrue(FileManager.default.fileExists(atPath: orig.appendingPathComponent("a.mp3").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("a.mp3").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: kdir.appendingPathComponent("k.mp3").path))
    }

    func testSyncListsSummaryFoldersByTitle() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lib-" + UUID().uuidString)
        let s = dir.appendingPathComponent("Talk [abc]"), audio = dir.appendingPathComponent("Audio")
        for d in [s, audio] { try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true) }
        defer { try? FileManager.default.removeItem(at: dir) }
        for f in ["Talk [abc]/summary.md", "Talk [abc]/transcript.txt", "Audio/x.mp3"] { try Data([1]).write(to: dir.appendingPathComponent(f)) }
        var i = LibraryIndex()
        i.sync(musicDir: dir.appendingPathComponent("o"), karaokeDir: dir.appendingPathComponent("k"), summariesDir: dir)
        XCTAssertEqual(i.list(.summary).map(\.title), ["Talk [abc]"])
    }

    func testSyncListsVideosOnlyFromVideosDir() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lib-" + UUID().uuidString)
        let v = dir.appendingPathComponent("Movies")
        try FileManager.default.createDirectory(at: v, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        for f in ["Clip [id] 720.mp4", "notes.txt"] { try Data([1]).write(to: v.appendingPathComponent(f)) }
        var i = LibraryIndex()
        i.sync(musicDir: dir.appendingPathComponent("o"), karaokeDir: dir.appendingPathComponent("k"), videosDir: v)
        XCTAssertEqual(i.list(.video).map(\.title), ["Clip [id] 720"])
        XCTAssertTrue(i.list(.original).isEmpty)
    }

    func testSyncMirrorsFoldersIncludingSubfoldersAndDeletions() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lib-" + UUID().uuidString)
        let kdir = dir.appendingPathComponent("Karaoke"), sub = dir.appendingPathComponent("Album")
        for d in [kdir, sub] { try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true) }
        defer { try? FileManager.default.removeItem(at: dir) }
        let files = ["a.mp3", "b.m4a", "Album/c.flac", "Karaoke/a (karaoke).mp3", "Karaoke/x.wav", "notes.txt"].map { dir.appendingPathComponent($0) }
        for f in files { try Data([1]).write(to: f) }
        var i = LibraryIndex()
        i.sync(musicDir: dir, karaokeDir: kdir)
        XCTAssertEqual(Set(i.list(.original).map(\.title)), ["a", "b", "c"])
        XCTAssertEqual(Set(i.list(.karaoke).map(\.title)), ["a (karaoke)", "x"])
        try FileManager.default.removeItem(at: files[0])
        i.sync(musicDir: dir, karaokeDir: kdir)
        XCTAssertEqual(Set(i.list(.original).map(\.title)), ["b", "c"])
    }

    func testSaveLoadRoundTrip() {
        let f = FileManager.default.temporaryDirectory.appendingPathComponent("idx-" + UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: f) }
        var i = LibraryIndex(); i.add(.original, title: "A", url: u("a")); i.remove(i.entries[0].id)
        i.add(.karaoke, title: "K", url: u("k")); i.save(to: f)
        XCTAssertEqual(LibraryIndex.load(from: f), i)
        XCTAssertEqual(LibraryIndex.load(from: URL(fileURLWithPath: "/nonexistent.json")), LibraryIndex())
    }
}
