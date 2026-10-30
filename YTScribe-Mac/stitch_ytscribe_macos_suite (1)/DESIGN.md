---
name: Liquid Graphite
colors:
  surface: '#0f131c'
  surface-dim: '#0f131c'
  surface-bright: '#353943'
  surface-container-lowest: '#0a0e17'
  surface-container-low: '#181b25'
  surface-container: '#1c1f29'
  surface-container-high: '#262a34'
  surface-container-highest: '#31353f'
  on-surface: '#dfe2ef'
  on-surface-variant: '#c7c4d7'
  inverse-surface: '#dfe2ef'
  inverse-on-surface: '#2c303a'
  outline: '#908fa0'
  outline-variant: '#464554'
  surface-tint: '#c0c1ff'
  primary: '#c0c1ff'
  on-primary: '#1000a9'
  primary-container: '#8083ff'
  on-primary-container: '#0d0096'
  inverse-primary: '#494bd6'
  secondary: '#d0bcff'
  on-secondary: '#3c0091'
  secondary-container: '#571bc1'
  on-secondary-container: '#c4abff'
  tertiary: '#4cd7f6'
  on-tertiary: '#003640'
  tertiary-container: '#009eb9'
  on-tertiary-container: '#002f38'
  error: '#ffb4ab'
  on-error: '#690005'
  error-container: '#93000a'
  on-error-container: '#ffdad6'
  primary-fixed: '#e1e0ff'
  primary-fixed-dim: '#c0c1ff'
  on-primary-fixed: '#07006c'
  on-primary-fixed-variant: '#2f2ebe'
  secondary-fixed: '#e9ddff'
  secondary-fixed-dim: '#d0bcff'
  on-secondary-fixed: '#23005c'
  on-secondary-fixed-variant: '#5516be'
  tertiary-fixed: '#acedff'
  tertiary-fixed-dim: '#4cd7f6'
  on-tertiary-fixed: '#001f26'
  on-tertiary-fixed-variant: '#004e5c'
  background: '#0f131c'
  on-background: '#dfe2ef'
  surface-variant: '#31353f'
typography:
  headline-xl:
    fontFamily: Inter
    fontSize: 28px
    fontWeight: '600'
    lineHeight: 36px
    letterSpacing: -0.022em
  headline-lg:
    fontFamily: Inter
    fontSize: 22px
    fontWeight: '600'
    lineHeight: 28px
    letterSpacing: -0.019em
  headline-md:
    fontFamily: Inter
    fontSize: 18px
    fontWeight: '600'
    lineHeight: 24px
    letterSpacing: -0.015em
  headline-sm:
    fontFamily: Inter
    fontSize: 15px
    fontWeight: '600'
    lineHeight: 20px
    letterSpacing: -0.012em
  body-lg:
    fontFamily: Inter
    fontSize: 15px
    fontWeight: '400'
    lineHeight: 24px
    letterSpacing: -0.009em
  body-md:
    fontFamily: Inter
    fontSize: 13px
    fontWeight: '400'
    lineHeight: 20px
    letterSpacing: -0.006em
  body-sm:
    fontFamily: Inter
    fontSize: 12px
    fontWeight: '400'
    lineHeight: 17px
    letterSpacing: -0.003em
  label-md:
    fontFamily: Inter
    fontSize: 12px
    fontWeight: '500'
    lineHeight: 16px
    letterSpacing: 0.01em
  label-sm:
    fontFamily: Inter
    fontSize: 11px
    fontWeight: '500'
    lineHeight: 14px
    letterSpacing: 0.02em
  code-timestamp:
    fontFamily: JetBrains Mono
    fontSize: 11px
    fontWeight: '500'
    lineHeight: 14px
    letterSpacing: 0.02em
  code-meta:
    fontFamily: JetBrains Mono
    fontSize: 12px
    fontWeight: '400'
    lineHeight: 16px
    letterSpacing: 0.00em
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  gutter: 0.75rem
  margin: 1.25rem
  space-xs: 0.25rem
  space-sm: 0.5rem
  space-md: 0.75rem
  space-lg: 1.25rem
  space-xl: 1.75rem
---

## Brand & Style
The design system embodies the tactile precision, optical clarity, and fluid materiality of modern macOS desktop environments (Sonoma and Sequoia). Engineered for content creators, researchers, and audio engineers using desktop transcription software, the interface emphasizes deep focus, high signal-to-noise ratio, and native desktop weight.

Visual execution relies on optical translucency, micro-refined borders, authentic glass refraction, and sleek slate-infused dark surfaces. The atmosphere balances professional utility with cutting-edge artificial intelligence: utility panels fade into the background through variable backdrop filters, while active processing states glow with controlled spectral energy. Interactions must feel instant, tactile, and rooted in desktop platform conventions—incorporating native window controls, unified toolbars, integrated split views, and physical spring ergonomics.

## Colors
The palette is built on deep slate and obsidian undertones, layered with translucent alpha stops to achieve authentic macOS vibrance. The dark mode palette rejects pure black (`#000000`) in favor of rich graphite and midnight obsidian foundations, preventing visual clipping and preserving optical depth across blurred surfaces.

- **Primary (`#6366F1` - Electric Indigo):** Anchors primary actions, high-confidence machine learning detections, active timeline scrubbing markers, and core navigation states.
- **Secondary (`#8B5CF6` - Spectral Violet):** Signifies generative AI operations, semantic summarization, speaker diarization tags, and processing badges.
- **Tertiary (`#06B6D4` - Cyber Cyan):** Represents raw waveform audio visualization, frequency analysis peaks, streaming playback status, and precision timestamps.
- **Neutral (`#090D16` - Deep Obsidian Slate):** Establishes the canvas base. Tinted with blue-gray undertones to allow frosted translucent overlays (`rgba(255, 255, 255, 0.04)` to `rgba(255, 255, 255, 0.12)`) to gleam without looking washed out.

### Surface System
- **Canvas Base:** `#090D16`
- **Sidebar Surface:** `rgba(18, 24, 38, 0.72)` with `backdrop-filter: blur(40px) saturate(190%)`
- **Window Chrome / Unified Toolbar:** `rgba(26, 34, 52, 0.65)` with `backdrop-filter: blur(50px)`
- **Content Panel:** `rgba(15, 20, 32, 0.85)`
- **Floating Overlays & Popovers:** `rgba(30, 41, 59, 0.88)` with `backdrop-filter: blur(60px)`
- **Hairline Borders:** `rgba(255, 255, 255, 0.08)` for regular edges; `rgba(255, 255, 255, 0.16)` for active focus indicators.

## Typography
Typography adheres strictly to system-native rendering paradigms using Inter (the web's closest analog to Apple's San Francisco Pro font metrics) combined with JetBrains Mono for technical timecode scrubbers, audio bitrates, and keycode shortcuts.

### Rationale & Typographic Principles
1. **Dynamic Kerning & Letter Spacing:** Negative letter-spacing is applied systematically across headline scales to mimic macOS display title tracking (`-0.022em` to `-0.012em`). Small labels and timestamps use expanded tracking (`+0.01em` to `+0.02em`) to ensure legibility on dark glass backgrounds.
2. **Text Smoothing:** Typography requires subpixel anti-aliasing emulation via `-webkit-font-smoothing: antialiased` to replicate the crispness of Retina display rendering.
3. **Hierarchy in Transcript Reading:** Body text for transcripts (`body-lg`) prioritizes comfortable scanning with a relaxed 1.6x line-height ratio, whereas UI toolbars, inspector panes, and metadata tables operate on strict compact scales (`body-md` and `body-sm`).

## Layout & Spacing
The layout adheres to a structured, 3-column desktop app structure standard in macOS productivity utilities:

1. **Source / Navigation Sidebar (Fixed/Collapsible):** Width fixed between 220px and 260px. Hosts collection trees, YouTube channel monitors, and recent transcription jobs.
2. **Main Workspace / Stage (Fluid):** Expands dynamically to house the synchronized video player, interactive audio waveform scrub bar, and time-aligned transcription document.
3. **Inspector Panel (Collapsible Drawer):** Width 300px to 340px on the right trailing side. Contains metadata tags, AI summary models, export formats, and speaker configuration.

### Rhythmic Scale
- **Density:** High-density desktop optimization based on a 4px/8px micro-grid. Component gutters default to `0.75rem` (12px) to maximize screen economy on 13" through 16" MacBook displays.
- **Window Padding:** Native window inner bounds utilize a clean `1.25rem` (20px) margin from outer window frames when content is decoupled from edges, while split-views dock flush to the window frame with hairline dividers.
- **Breakpoints & Adaptation:**
  - **Compact Desktop (<1024px):** Right inspector collapses into a modal sheet; sidebar drops to icons or hides behind a native toggle.
  - **Standard Desktop (1024px – 1440px):** Default 3-pane split view with fluid middle canvas.
  - **Ultrawide / Dual-Display (≥1440px):** Workspace allows two-up transcription comparison or simultaneous waveform and text editing.

## Elevation & Depth
Elevation is expressed through translucent stacking, frosted backdrop filtering, and multi-tier ambient occlusion rather than harsh directional drop shadows.

### Material Stack & Tiers
- **Tier 0 (Window Base Canvas):** `#090D16` solid foundation.
- **Tier 1 (Sidebar & Bottom Bar Vibrance):** `background: rgba(18, 24, 38, 0.72); backdrop-filter: blur(40px) saturate(190%); border-right: 1px solid rgba(255, 255, 255, 0.07);`
- **Tier 2 (Toolbar & Content Cards):** `background: rgba(255, 255, 255, 0.04); border: 1px solid rgba(255, 255, 255, 0.09); box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.06);`
- **Tier 3 (Floating HUDs, Context Menus, & Command Palettes):**
  - Background: `rgba(22, 29, 46, 0.88)`
  - Filter: `backdrop-filter: blur(60px) saturate(200%)`
  - Border: `1px solid rgba(255, 255, 255, 0.14)`
  - Shadow: `0 12px 32px -4px rgba(0, 0, 0, 0.55), 0 4px 12px -2px rgba(0, 0, 0, 0.35), inset 0 1px 1px rgba(255, 255, 255, 0.15)`

### Light Edge Highlights
Every elevated card, modal, and segment control possesses a subtle top edge highlight (`inset 0 1px 0 0 rgba(255, 255, 255, 0.12)`) simulating the physical bevel refraction typical of macOS glass title bars.

## Shapes
The design system employs macOS continuous curvature squircles (represented by level `2` roundedness):
- **Base Components (Buttons, Input Fields, Checkboxes):** 8px (`0.5rem`).
- **Cards, Popovers, Segmented Containers:** 12px to 16px (`0.75rem` – `1rem`).
- **Window Frames & Modal Dialogs:** 16px (`1rem`) to 20px (`1.25rem`).
- **Interactive Badges, Speaker Chips, Timecode Tags:** Full pill (`9999px`) to distinguish categorical metadata from actionable rectangular controls.

## Components

### Window Chrome & Traffic Lights
- Integrated unified title bar (height: 52px) housing native traffic light controls pinned at `top: 18px`, `left: 20px`: Close (`#FF5F56`), Minimize (`#FFBD2E`), Fullscreen (`#27C93F`) with 12px diameter and 8px gap.
- Window title is centered or trailing-aligned next to controls in `headline-sm` with muted opacity (`0.7`).

### Buttons
- **Primary Push Button:** Solid Indigo fill (`#6366F1`) with subtle gradient to `#4F46E5`. Top inner highlight (`rgba(255, 255, 255, 0.2)`), height 32px, padding 0 14px, squircle radius 8px. Hover adds brightness boost; active state presses inward scale (`scale(0.98)`).
- **Secondary / Glass Button:** Background `rgba(255, 255, 255, 0.06)`, border `1px solid rgba(255, 255, 255, 0.08)`. Hover fills to `rgba(255, 255, 255, 0.12)`.
- **Ghost / Toolbar Action Button:** Transparent background, radius 6px, hover `rgba(255, 255, 255, 0.08)`, icon color `#CBD5E1`.

### macOS Segmented Tab Control
- Recessed capsule container: `rgba(0, 0, 0, 0.35)` background, `1px solid rgba(255, 255, 255, 0.05)`, padding 2px, radius 8px.
- Segment item: Smooth slider pill indicator with `rgba(255, 255, 255, 0.12)` background, `box-shadow: 0 1px 3px rgba(0, 0, 0, 0.4)`, active text `#FFFFFF`. Inactive text `rgba(255, 255, 255, 0.5)`.

### Chips & Badges
- **Speaker Diarization Pill:** Dynamic speaker coloring (e.g., Speaker 1 in Indigo tint `rgba(99, 102, 241, 0.15)`, text `#A5B4FC`; Speaker 2 in Violet tint `rgba(139, 92, 246, 0.15)`, text `#C4B5FD`). Height 22px, border radius 9999px, typography `code-timestamp`.
- **Status & Confidence Badges:** Glowing 6px dot indicator accompanied by cyan timestamp or accuracy percentage.

### Input Fields & URL Search Bar
- **YouTube Link Ingest Bar:** Prominent toolbar input. Background `rgba(15, 20, 32, 0.6)`, hairline border `rgba(255, 255, 255, 0.1)`. Focus state illuminates with a dual ring: `box-shadow: 0 0 0 1px #6366F1, 0 0 0 3px rgba(99, 102, 241, 0.25)`.
- Features an embedded trailing keyboard shortcut badge (`⌘V` or `⏎`).

### Cards & Transcription Paragraph Blocks
- **Active Transcription Block:** Background `rgba(99, 102, 241, 0.06)`, left accent border 2px solid `#6366F1`.
- **Inactive Block:** Transparent background, transitions to `rgba(255, 255, 255, 0.03)` on hover with quick action icons (copy, re-generate, timestamp jump) fading into view.

### Audio Waveform Scrubbing Bar
- Canvas element with dual layered visualizer: cached amplitude bars in slate-gray (`rgba(255, 255, 255, 0.2)`), active playback filled with Cyber Cyan (`#06B6D4`) gradient down to Electric Indigo (`#6366F1`), accompanied by an ultra-thin 1px white playhead needle casting an ethereal glow.