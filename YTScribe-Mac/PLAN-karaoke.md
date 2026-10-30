# YTScribe: Music Library + Karaoke Plan

## What We're Building

Two additions to the existing app:

1. **Music library.** Downloaded MP3s move from `~/Downloads/YTScribe/Audio/` to **`~/Music/YTScribe/`**. A new library view lists every MP3 in that folder.
2. **Karaoke.** Pick a song from the library, press **Make karaoke**, and get a new MP3 with the human lead vocal removed and the instruments kept. Done locally on the Mac, no upload.

Two different results are possible, so the app offers both:

| Mode | Removes | Keeps |
|---|---|---|
| **Instrumental** | All vocals (lead and backing) | Instruments only |
| **Karaoke** (default) | Lead vocal only | Instruments and backing vocals |

## Current vs Target

| | Today | Target |
|---|---|---|
| MP3 location | `~/Downloads/YTScribe/Audio/` | `~/Music/YTScribe/` |
| Finding old downloads | Finder | Library tab inside the app |
| Vocal removal | None | One click, per song, runs in parallel with other jobs |
| Output | n/a | `~/Music/YTScribe/Karaoke/<song> (karaoke).mp3` |

## Research Findings (browsed 2026-10-29)

Everything below was read from the pages linked. Items marked **UNVERIFIED** I could not confirm and you should not treat as fact.

| Tool | What it does | Apple Silicon | License | Source |
|---|---|---|---|---|
| **Demucs** (`htdemucs`, `htdemucs_ft`, `htdemucs_6s`) | Splits into drums, bass, other, vocals (6s adds piano, guitar). **Vocals vs everything else only; it cannot split lead from backing vocals.** README states 9.00 dB SDR (MUSDB HQ) for htdemucs; `ft` is 4x slower and "a bit better". | Runs through PyTorch. | MIT. **Repo archived by Meta on 2025-01-01**, maintained fork at adefossez/demucs. | https://github.com/facebookresearch/demucs |
| **demucs.cpp** | C++17 port of Demucs (ggml + Eigen, OpenMP). No Python. Pre-converted weights on Hugging Face. Weight files: 6-source 53 MB, each fine-tuned model 81 MB, hdemucs_mmi 160 MB. States it "sacrifices speed" for low memory. | CPU only as written (no Metal/CoreML path mentioned). Speed **UNVERIFIED**. | See repo. | https://github.com/sevagh/demucs.cpp |
| **python-audio-separator** | One wrapper for UVR's MDX-Net (.onnx), VR (.pth), Demucs, and Roformer (.ckpt) models. | **Documented:** MDX .onnx uses CoreML; VR, Demucs and Roformer use PyTorch MPS. Needs PyTorch 2.13 or newer on Apple Silicon. | MIT (wrapper). Model weights have their own terms. | https://github.com/nomadkaraoke/python-audio-separator |
| **Karaoke Roformer models** (lead vs backing) | Listed in audio-separator's `models.json`: Mel-Roformer-Karaoke by aufr33 and viperx (file name carries "sdr_10.1956"), Gabox karaoke and v2, becruily karaoke (Mel-Band), frazer-becruily (BS), anvuew (BS). These are the models that **keep backing vocals and remove only the lead.** | PyTorch MPS via audio-separator. | **UNVERIFIED per checkpoint.** Check before sharing the app. | https://raw.githubusercontent.com/nomadkaraoke/python-audio-separator/main/audio_separator/models.json |
| **ONNX port of the aufr33 karaoke model** | Community ONNX export on Hugging Face (`bdsqlsz`). Would allow ONNX Runtime with the CoreML provider and no Python. Quality vs the original, size, and license **UNVERIFIED**. | Possible, **UNVERIFIED** | **UNVERIFIED** | https://huggingface.co/bdsqlsz/mel_band_roformer_karaoke_aufr33-ONNX |
| **Roformer training repo** | Reference code for `bs_roformer` and `mel_band_roformer`; has a "convert models to ONNX" section. | n/a | MIT | https://github.com/ZFTurbo/Music-Source-Separation-Training |
| **Spleeter** | Not browsed. From memory only: older and generally lower quality than the above. **UNVERIFIED**, not recommended for this reason alone. | n/a | n/a | n/a |

**Not found:** real speed numbers on Apple Silicon for any of these, and a verified CoreML or MLX port of Demucs. The first spike measures speed on your Mac instead of trusting claims.

## Popularity Check (browsed 2026-10-29)

| Tool | GitHub stars | PyPI downloads, last month | Notes |
|---|---|---|---|
| Spleeter | 28.5k | 8,511 | Last release v2.3.0; usage has collapsed. Legacy. |
| Ultimate Vocal Remover (UVR) | 26.8k | n/a (GUI app) | Active: releases up to v5.6. The community's main karaoke/vocal-removal app. |
| Demucs (Meta, archived) | 10.4k | 528,428 | Highest downloads, but downloads include other projects installing it as a dependency. Cannot split lead from backing vocals. |
| python-audio-separator | 1.5k | 172,281 | The pip/CLI wrapper around UVR's models, including the karaoke Roformers. |

Sources: github.com/Anjok07/ultimatevocalremovergui, github.com/deezer/spleeter, github.com/facebookresearch/demucs, pypistats.org/packages/{demucs,spleeter,audio-separator}.

## Update: Non-Python, Recently Updated Options (browsed 2026-10-29, for M4 Pro 24 GB)

You asked for AI separation that is not Python-based and was updated in the last month or two. Python was the only route in the first round; these are the fresh native ones.

| Project | Language / runtime | Updated | What it does | License | Source |
|---|---|---|---|---|---|
| **Isolate** | Swift, **HTDemucs v4 on Core ML**, native macOS app | Releases v1.3.0 (Sep 25-26) to v1.3.2 | 4 stems (vocals, drums, bass, other). Has a Karaoke macro that only turns vocals down 12 dB. Model is included in the release, no Python, no download. Measured **3.0-3.3x realtime** (4:37 song in 1:33) on an unnamed M-series MacBook Pro running macOS 27; memory about 1.6-2.7 GB. | App MIT, model MIT | https://github.com/neokumar1/Isolate |
| **Passable** | Swift, HTDemucs v4 on Core ML | 2 days ago | DJ set builder. States about 5 s for a 4-minute track **on an M5**. Models (~200 MB and ~80 MB) must be exported once with a Python script, so the export step is Python, the app is not. | See repo | https://github.com/nikolaus018/passable |
| **OpenKara** | Rust + Tauri, Demucs **ONNX** model | Active | Karaoke app: 2-stem or 4-stem separation, synced lyrics. Only 36 stars; model runtime details not fully confirmed. | See repo | https://github.com/thedavidweng/OpenKara |
| stemgen-rt | C++ AU/VST3 plugin, Apple Silicon | 2 days ago | Real-time stem plugin, not a file tool. Not a fit. | See repo | https://github.com/sweetspotsoundsystem/stemgen-rt |

Isolate's own warning: Core ML on **macOS 14 and 15** computes its model incorrectly on some compute paths; **macOS 26 and 27 are correct on every path**. Your Mac is on macOS 26, so this is fine.

**Important limit:** HTDemucs has one vocals stem. It cannot split lead from backing vocals. So the native options give **Instrumental** (all vocals removed, instruments kept). **Karaoke with backing vocals kept** needs the Roformer karaoke models, and I found **no native (non-Python) port of those**; the only Core ML Roformer repo I found is Python and was last updated May 27.

**Speed on your Mac is unmeasured.** The only numbers are from other Macs (3.3x realtime on an M-series MacBook Pro; "5 s per 4 minutes" on an M5). Treat both as unverified for an M4 Pro until Phase 3.

## Decision

**Selected: HTDemucs v4 on Core ML, using Isolate's approach (Swift, MIT).**
- It is not Python, it is recent (v1.3.2 this autumn), it targets Apple Silicon, and it runs on macOS 26.
- 24 GB RAM is plenty: the model needs about 1.6-2.7 GB.
- License is MIT for both the code and the model, so it can be built into YTScribe.
- **Trade-off you are accepting:** Instrumental mode only (all vocals removed). Backing vocals cannot be kept until a native Roformer karaoke port exists.
- Rejected: Spleeter (8.5k downloads a month, no release since v2.3.0). Python Roformer path is kept as a later, optional "keep backing vocals" mode.

**How I'll use it:** read Isolate's separation code, reuse the Core ML model and its chunking logic inside YTScribe with its MIT notice. I will not download or run its ad-hoc-signed DMG on your Mac. If you want to hear the quality first, you can install it yourself and verify the checksum from its `SHA256SUMS.txt`.


## Revised Scope v2 (supersedes the single-engine decision above)

You asked for **both models inside the app**, shown on the Audio tab, plus **drag and drop**, plus a **DMG other Macs can install**.

### In the app
1. After an MP3 finishes on the Audio tab, its card gets a **Karaoke** section: a **model menu**, a **Generate karaoke** button, a progress bar, and a result card (click to play, drag out, Save As, Show in Finder).
2. A **drop zone** on the Audio tab accepts MP3 (and other audio files) dragged from Finder. A dropped file gets the same model menu and button.
3. Model menu entries:

| Menu entry | Engine | Runs on | Notes |
|---|---|---|---|
| **Fast: HTDemucs (Core ML)** | Swift + Core ML | Neural Engine/GPU | No Python. Quality vs Roformer unknown until tested. |
| **Best quality: BS-Roformer Viperx 1297** | Python + PyTorch child process | Apple GPU (MPS) | Highest instrumental SDR found (16.01 dB). Large to ship. |

4. Output: `~/Music/YTScribe/Karaoke/<song> (karaoke).mp3` (all vocals removed). MP3s now save to `~/Music/YTScribe/`.
5. Code shape: one `StemEngine` protocol (`separate(file, progress) -> instrumental file`) with two implementations, so the UI does not care which engine runs.

### Shipping to other Macs (DMG)
Everything the app needs must live inside the `.app`. Today it does not:

| Needed | Today | For the DMG |
|---|---|---|
| yt-dlp | bundled | keep; add an in-app "Update yt-dlp" (YouTube breaks it often) |
| Node (JS challenge) | bundled | keep (MIT) |
| ffmpeg | **Homebrew only** | must bundle; license of the build matters (GPL vs LGPL) |
| HTDemucs Core ML model | n/a | MIT; fetch on first use or bundle (~200 MB) |
| Python + PyTorch + Roformer | n/a | very large; weights license **UNVERIFIED** |
| Signing | ad-hoc | **Developer ID + notarization** so other Macs open it without warnings |
| Architecture | arm64 | Apple Silicon only; Intel Macs unsupported |

DMG build: a `make_dmg.sh` that signs nested binaries, builds the app, creates the DMG (drag-to-Applications layout), notarizes and staples it if a Developer ID is available.

**Legal note:** giving other people an app that downloads YouTube audio is a different risk from personal use (YouTube's terms), and the Roformer weights' licenses are unconfirmed. Check both before wide distribution.

### Order of work
1. Music folder + Library listing. 2. `StemEngine` + Core ML engine + Karaoke section + drop zone (works fully without Python). 3. Roformer engine behind the same menu. 4. ffmpeg bundling + `make_dmg.sh` + signing. 5. Test on a clean user account/second Mac.

## Quality Ranking for "Remove All Vocals" (computed 2026-10-29)

Average **instrumental SDR** over the 40-track evaluation in python-audio-separator's `models-scores.json` (higher is better; source: https://raw.githubusercontent.com/nomadkaraoke/python-audio-separator/main/audio_separator/models-scores.json):

| Rank | Model | Instrumental SDR | Runtime |
|---|---|---|---|
| 1 | BS-Roformer-Viperx-1297 | 16.01 dB | Python / PyTorch |
| 2 | MelBand Roformer Kim Inst V2 (unwa) | 15.94 dB | Python / PyTorch |
| 3 | BS-Roformer-Viperx-1296 | 15.91 dB | Python / PyTorch |
| 4-5 | MelBand Roformer Kim InstVoc Duality V1 / V2 (unwa) | 15.89 / 15.85 dB | Python / PyTorch |
| 6-7 | MDX23C InstVoc HQ 2 / HQ | 15.81 / 15.77 dB | ONNX / PyTorch |
| 10-12 | MDX-Net (kuielab, Kim Vocal 1, Voc FT) | 15.4 dB | ONNX (CoreML on Mac) |
| not listed | HTDemucs v4 (the Core ML option) | **no comparable score found** | Core ML, Swift |

The top nine sit within about 0.3 dB of each other, which is small. Demucs' published 9.00 dB is an average over four different stems, so it cannot be compared to the numbers above. How far HTDemucs trails the Roformers on instrumentals is **unknown** until you listen.

## Recommendation

**Ship HTDemucs v4 on Core ML (Swift, no Python) for Instrumental mode.** Keep the Python Roformer karaoke route only as a later, optional mode for "keep backing vocals", and only if you decide it is worth bundling Python.

## Tech Stack

| Layer | Choice | Why |
|---|---|---|
| Inference (shipped) | HTDemucs v4 Core ML model, run from Swift with chunking and STFT done in Accelerate (the approach Isolate and Passable use) | Not Python, MIT, built for Apple Silicon, fits 24 GB easily. |
| Model delivery | Download on first use into `~/Library/Application Support/YTScribe/models/` | Keeps the app small; Isolate's whole app with model is about 313 MB. |
| Optional later mode | `python-audio-separator` with the aufr33/viperx karaoke Roformer, bundled Python, run as a child process | Only route found that keeps backing vocals. Costs app size; PyTorch size **UNVERIFIED**. |
| Audio in/out | Existing ffmpeg step (still Homebrew; bundling decision pending) | Already in the app. |
| UI | New **Library** tab: list of MP3s in `~/Music/YTScribe/`, Make karaoke button, progress, result card (same click/drag/Save As as Audio) | Matches the Audio tab you already use. |

## Phases

### Phase 1: Move MP3s to the Music folder. Risk: low
- **File:** [JobStore.swift](Sources/YTScribe/JobStore.swift), the `audioDir` property → `~/Music/YTScribe`.
- Update the card text "Also saved in Downloads/YTScribe/Audio".
- **Existing files:** old MP3s in Downloads are left alone. I will not move or delete them unless you say so.
- **Exit check:** a new download lands in `~/Music/YTScribe/`.

### Phase 2: Library tab. Risk: low
- Lists MP3s in the folder, newest first, with click-to-play and a refresh on focus.
- **Exit check:** previously downloaded files show up after you copy them in.

### Phase 3: Spike (throwaway, no app changes). Risk: medium
- **Primary:** read Isolate's source, build only its Core ML separation step, run it on 3 of your MP3s (the vocals-removed mix = drums + bass + other).
- **Head-to-head:** run BS-Roformer-Viperx-1297 on the same 3 songs and compare by ear. Ship Core ML unless the Roformer is clearly better.
- **Optional comparison:** in a venv, run `audio-separator` with the aufr33/viperx karaoke model on the same songs, to hear what keeping backing vocals sounds like (one clean pop track, one dense mix, one with heavy backing vocals).
- Record: wall-clock time per 4-minute song on your Mac, output quality (you listen), peak memory.
- **Exit check:** you say the result is good enough. If not, try the becruily and Gabox models before changing approach.

### Phase 4: Package it. Risk: high (size, signing, model licenses)
- Convert or fetch the HTDemucs Core ML model, wire the Swift separation step into the app.
- Model files stored in `~/Library/Application Support/YTScribe/models/`, downloaded on first use rather than shipped in the app.
- **Exit check:** works from `/Applications` with no terminal and no venv on PATH.

### Phase 5: Karaoke UI + queue. Risk: medium
- Make karaoke button, mode toggle (Karaoke vs Instrumental), progress, parallel jobs with a cap (separation is memory-heavy; start with 1 at a time).
- Output to `~/Music/YTScribe/Karaoke/`.
- **Exit check:** three songs queued, run in order, each result plays.

## Tests

- Unit: output path and file-name builder, library folder listing, job state transitions (using a fake separator).
- Integration (gated like the existing live tests): one short real song end to end.
- Manual: you listen to the three spike songs and sign off.

## Golden Rule (Migration)

**The installed app keeps working until the new build is confirmed.** All work happens in `YTScribe-Mac/` and the throwaway spike venv. I will not replace `/Applications/YTScribe.app` until each phase passes its exit check. Blast radius per phase: Phase 1-2 touch only the app's own folder paths; Phase 3 touches nothing in the app. Your existing MP3s and the Summary/Audio tabs are unaffected.

## Open Questions (defaults in bold)

1. Default mode: **Karaoke (remove lead, keep backing vocals)**, with Instrumental as a toggle.
2. Output format: **MP3 (V0)**. WAV/FLAC would avoid a third lossy step; say so if you want it.
3. Use: **personal use on this Mac.** If you ever distribute the app, model licenses must be checked first (marked UNVERIFIED above).
4. Move existing Downloads MP3s into Music? **No, leave them.**
5. Concurrent karaoke jobs: **1 at a time** until memory use is measured.
