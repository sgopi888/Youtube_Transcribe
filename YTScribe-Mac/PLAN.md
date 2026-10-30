# YTScribe for Mac — Desktop App Plan

## What We're Building

A native macOS app. Paste (or drop) a YouTube link and it starts working immediately — no terminal, no server to keep running. Every link becomes a **job** in a queue. Each job has three independent toggles:

| Toggle | Output |
|---|---|
| **MP3** | Audio extracted from the best available YouTube audio stream |
| **Transcript** | `.txt` transcript |
| **Summary** | `.md` summary (optional, uses OpenAI) |

Run one, two, or all three, on one link or many at once. Links can be pasted while others are still running. Default on paste: **MP3 on**, Transcript and Summary off (changeable in Settings).

## Current vs Target

| | Today | Target |
|---|---|---|
| Launch | `source venv/bin/activate && python server.py`, then open browser | Double-click **YTScribe.app** (Dock / Launchpad) |
| Input | One video ID, one at a time | Paste any number of links; clipboard auto-detect |
| MP3 | Not supported | Yes, with the quality policy below |
| Transcript | `youtube-transcript-api` via Python | Same result, no Python needed |
| Summary | Always a separate button | Optional toggle per job or per batch |
| Parallelism | None | N jobs at once (default 3, adjustable) |
| Dependencies | venv + brew `yt-dlp`/`ffmpeg` | All bundled inside the `.app` |
| API key | `.env` file in repo | macOS Keychain, entered in Settings |

## Quality Policy for MP3 (important)

YouTube serves audio as **Opus (webm)** or **AAC (m4a)**, both already lossy. Converting to MP3 is a second lossy step, so a truly lossless MP3 is not possible. The plan minimises loss:

1. Download the **highest-bitrate audio-only stream** (`bestaudio`), never a video stream.
2. Encode with **libmp3lame VBR V0** (~245 kbps, transparent) by default; **320 kbps CBR** as a Settings option.
3. Add a fourth, no-conversion choice: **"Original quality (.m4a / .opus)"**, a straight copy of the stream with zero re-encode. This is the only way to be bit-for-bit what YouTube has.
4. Embed title, channel and thumbnail as ID3 tags.

## Tech Stack

| Layer | Choice | Why |
|---|---|---|
| App shell + UI | **SwiftUI (macOS 14+)**, Xcode project | You build in Swift; Xcode is installed; truly native, small, Dock/menu bar/notifications for free. No Electron weight. |
| Download engine | **yt-dlp** standalone binary bundled in `Contents/Resources` | Already your tool; the most reliable YouTube extractor. |
| Audio conversion | **ffmpeg** static arm64 binary, bundled | Needed for MP3 encode and tagging. App works with no brew install. |
| Transcript | **yt-dlp subtitles** (`--write-auto-subs`, VTT → clean text) | Removes the Python/venv dependency. Falls back to `youtube-transcript-api` logic only if parity testing shows gaps. |
| Summary | OpenAI Responses API from Swift (`URLSession`), model `gpt-5-nano` as today | Matches the current behaviour; one HTTP call, no SDK needed. |
| Concurrency | Swift `actor JobQueue` + `Process` per job, max-parallel limiter | Safe parallel runs; each job isolated so one failure doesn't stop others. |
| Secrets | **Keychain** | Never a plaintext `.env` inside a distributed app. |
| Persistence | JSON job history in `~/Library/Application Support/YTScribe/` | Survives relaunch; failed jobs can be retried. |
| Output | Default `~/Downloads/YTScribe/<channel> - <title>/` (changeable) | One folder per video with `audio.mp3`, `transcript.txt`, `summary.md`. |

Alternative considered: Tauri/Electron reusing `ui/app.ts`. Rejected as the default because the current UI is a single-video form that will be rewritten anyway, and the bundled-binary story is cleaner natively. Say so if you would rather stay in TS.

## Architecture (short)

```
YTScribe.app
├─ SwiftUI views: LinkInput · JobList (progress rows) · Settings
├─ JobQueue (actor): enqueue → run up to N jobs → publish state
├─ Job pipeline (per link, steps run only if toggled):
│    1. resolve metadata (yt-dlp -J)
│    2. MP3        → yt-dlp -f bestaudio → ffmpeg → tag
│    3. Transcript → yt-dlp subs → clean → .txt
│    4. Summary    → needs transcript (auto-fetched if off) → OpenAI → .md
└─ Resources/: yt-dlp, ffmpeg (signed)
```

Rules: Summary requires a transcript, so toggling Summary silently fetches the transcript in memory even if the Transcript file toggle is off. Playlist URLs: v1 asks "add all N videos?" rather than silently queueing hundreds.

## Phases

### Phase 1 — Spike (prove the engine) — risk: low
- Command-line proof: bundled-style `yt-dlp` + `ffmpeg` produce a V0 MP3 and a clean transcript for 3 of your existing video IDs.
- Compare the transcript against your existing `transcript_*.txt` files for parity.
- **Exit check:** MP3 plays with correct tags; transcript matches within normal subtitle differences.

### Phase 2 — Core app + queue — risk: medium (concurrency)
- Xcode project, `JobQueue` actor, `Process` wrapper with live progress parsing, cancel and retry.
- UI: paste field, clipboard auto-detect, three toggles, job rows with progress.
- **Exit check:** paste 5 links quickly; 3 run in parallel, the rest queue; one deliberately bad link fails alone.

### Phase 3 — Transcript + Summary — risk: low
- Transcript step, then OpenAI summary step, Keychain-stored key, Settings pane.
- **Exit check:** all 8 toggle combinations behave correctly, including Summary-only.

### Phase 4 — Packaging — risk: medium (signing / Gatekeeper)
- Bundle binaries, code-sign with your Developer ID if you have one (otherwise ad-hoc signed for personal use on this Mac), build `YTScribe.app`, copy to `/Applications`.
- In-app **"Update yt-dlp"** button (YouTube breaks extractors regularly; this is the #1 long-term maintenance item).
- **Exit check:** launch from Launchpad on a clean login with the terminal closed and Homebrew PATH unavailable.

### Phase 5 — Polish — risk: low
- Notifications on completion, "Reveal in Finder", drag-and-drop links, menu-bar quick-paste, history view.

## Testing

- Unit tests: URL parsing/normalisation (watch, youtu.be, shorts, live, playlist), VTT-to-text cleaner, filename sanitiser, queue concurrency limit.
- Integration test: a short public video through all three steps.
- Manual: the Phase exit checks above.

## Golden Rule (Migration)

**Nothing in the existing project is touched.** All new work lives in `YTScribe-Mac/`. The current `server.py`, `ui/`, `youtube_transcribe.py` and your `.env` stay exactly as they are and keep working. Blast radius per phase: **existing project impact: NONE**. The old key is only copied into Keychain by you, in Settings.

## Open Questions (defaults in bold, I'll proceed with these unless you say otherwise)

1. Native SwiftUI vs Tauri/Electron reusing TS: **SwiftUI**.
2. MP3 default: **VBR V0**, with 320 kbps and Original-quality options.
3. Videos with no captions: **mark the transcript step "no captions available"**. Local Whisper transcription is a possible later add-on, not v1.
4. Distribution: **personal use on this Mac, ad-hoc signed**. Say so if you want to share it with others (needs Developer ID + notarisation).
5. Output folder: **~/Downloads/YTScribe/**.
6. Only download content you have the right to; YouTube's terms restrict downloading. This is a personal-use tool.
