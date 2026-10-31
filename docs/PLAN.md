# screen-cap — Build Plan

Status: plan only, nothing built. Written 2026-10-31 from CleanShot X's public
[features page](https://cleanshot.com/features) and [URL scheme API](https://cleanshot.com/docs-api).
Scope for this plan: **screenshots, editing and saving**. Screen recording and everything
built on it is Phase 2 (§10).

## 1. Goal

A native macOS menu-bar app, **ScreenCap** (repo `screen-cap`), free and MIT-licensed, that:

1. Captures an area, window, the full screen or a scrolling page, from global shortcuts.
2. Shows each capture in a small overlay to copy, save, drag, annotate, pin or OCR it.
3. Has a full annotation editor: shapes, arrows, text, blur/pixelate, spotlight, counters,
   crop, backgrounds, and saves an editable project file.
4. Keeps a month of capture history.
5. Is scriptable through a `screencap://` URL scheme.

v1 is done when every row marked **v1** in §3 works on macOS 14 and later, on Apple Silicon
and Intel, and passes the acceptance checks in §7.

## 2. Platform and stack

| Choice | Why |
|---|---|
| **macOS 14 Sonoma+** | `SCScreenshotManager` (ScreenCaptureKit stills) arrived in 14. `CGWindowListCreateImage` is deprecated in 15 and shows extra privacy prompts |
| **Swift 6**, strict concurrency | Current language mode; catches capture/UI threading bugs at compile time |
| **AppKit** for the menu bar, capture overlays, Quick Access and pinned panels; **SwiftUI** for the editor chrome, settings and history | Overlays need `NSPanel` window levels, key handling and click-through that SwiftUI can't do; SwiftUI is faster for forms and lists |
| **ScreenCaptureKit** | Displays, windows (with or without shadow), exclusion of our own windows |
| **Vision** | On-device OCR (`VNRecognizeTextRequest`, 30+ languages with `automaticallyDetectsLanguage`), QR/barcodes (`VNDetectBarcodesRequest`), scroll stitching (`VNTranslationalImageRegistrationRequest`) |
| **Core Image** | Blur, pixelate, background compositing, shadows |
| **Core Graphics** | Annotation rendering to PNG/JPEG/TIFF/HEIC/PDF |
| **XcodeGen** (`project.yml`) | Keeps the `.xcodeproj` out of git, so merges never conflict on `project.pbxproj` |

Dependencies (each earns its place):

| Package | Why it's worth adding |
|---|---|
| [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) (MIT) | User-recordable global hotkeys with a settings UI and conflict detection. Writing this on top of Carbon `RegisterEventHotKey` is a week of edge cases |
| [Sparkle 2](https://sparkle-project.org) (MIT) | Signed, standard auto-updates outside the App Store |

Everything else is Apple frameworks.

**Distribution.** GitHub Releases (`.dmg`) plus a Homebrew cask. Signing with a Developer ID
and notarizing needs an Apple Developer account ($99/yr). Until there is one, releases are
ad-hoc signed and the README documents right-click → Open. The Mac App Store is out: the
sandbox blocks the auto-scroll and Finder-level overlays this app needs.

## 3. Feature matrix

**v1** = in this plan. **Later** = after v1, still screenshot side. **P2** = screen recording
phase. **Drop** = not planned.

### 3.1 Capture

| Feature | Plan | Notes |
|---|---|---|
| Capture Area | v1 | Drag a rectangle on a frozen-screen overlay spanning all displays |
| Capture Window | v1 | Hover highlights the window under the cursor; click to capture. Space toggles area/window |
| Capture Fullscreen | v1 | Display under the cursor, or all displays |
| Capture previous area | v1 | Re-capture the last rectangle |
| Self-timer | v1 | 3 / 5 / 10 s countdown, then Capture Area at the chosen rectangle |
| Scrolling capture | v1 | Vertical and horizontal; manual or auto-scroll (§5.4) |
| All-In-One mode | v1 | One shortcut: pick a rectangle, then choose area / window / fullscreen / scrolling / OCR / timer from a toolbar |
| Fixed size and locked aspect ratio | v1 | Typed W×H or ratio in All-In-One; remembers the last selection |
| Crosshair, magnifier | v1 | Magnifier shows pixel grid, coordinates and size, hex color under cursor |
| Freeze screen | v1 | On by default: the overlay shows a still taken at shortcut time (§5.1) |
| Window with background | v1 | Padding, wallpaper / custom image / solid color / gradient |
| Window transparent, shadow on/off | v1 | `SCStreamConfiguration.ignoreShadowsSingleWindow` |
| Hide desktop icons while capturing | v1 | Wallpaper-only overlay window at the desktop-icon level; toggle in menu bar |
| Capture cursor | Later | |
| "Integration" (unexplained on the source page) | Drop | No description to build from |

### 3.2 After capture: Quick Access overlay

| Feature | Plan | Notes |
|---|---|---|
| Thumbnail overlay in a screen corner | v1 | Non-activating `NSPanel`, stacks multiple captures |
| Copy, Save, Annotate, Pin, OCR, Close, Delete buttons | v1 | Plus Reveal in Finder |
| Drag & drop to any app | v1 | `NSDraggingSource` with a file URL and image data |
| File info (dimensions, size) | v1 | |
| Position, size, auto-close timer, which display | v1 | Settings |
| Swipe gestures | v1 | Swipe away to dismiss, swipe toward the edge to save |
| Restore recently closed | v1 | From history |
| Temporarily hide overlays | v1 | Shortcut and menu item |
| After-capture action per shortcut | v1 | Show overlay / copy / save / annotate / pin / upload-later. Same as the source app's `action` parameter |

### 3.3 Annotate editor

| Tool / feature | Plan | Notes |
|---|---|---|
| Arrow, 4 styles incl. curved | v1 | Straight, thick tapered, double-headed, curved (draggable control point) |
| Rectangle, filled rectangle, ellipse, line | v1 | Stroke width, corner radius, fill, shadow |
| Text, 7 preset styles | v1 | Plain, outlined, filled background, monospace, etc.; rich editing in place |
| Counter (numbered steps) | v1 | Auto-incrementing; renumbers on delete |
| Pencil with auto-smoothing | v1 | Catmull-Rom smoothing of input points |
| Highlighter with smart text-size detection | v1 | Uses Vision text boxes under the stroke to snap height to the text line |
| Blur (secure / smooth) | v1 | Secure = pixelate first then blur so it can't be reversed |
| Pixelate with randomization | v1 | Adds random per-block jitter so the original can't be recovered |
| Spotlight | v1 | Dims everything outside one or more shapes |
| Crop with aspect ratios and edge snapping | v1 | Free, 1:1, 4:3, 16:9, custom; snaps to image edges and detected UI edges |
| Rotate, flip, resize | v1 | |
| Color picker with screen sampling and saved palette | v1 | `NSColorSampler`; palette saved in settings |
| Combine images (drop another image onto the canvas) | v1 | Becomes an image layer |
| Undo/redo, select/move/resize any object, z-order, copy/paste objects | v1 | Every object stays editable |
| Dark and light mode | v1 | |
| Editable project file | v1 | Open `.screencap` package (§5.3) |
| Background tool | v1 | 20 bundled original backgrounds, custom image, padding, alignment, aspect ratio, corner radius, shadow, Auto Balance (§5.5), presets |
| Emoji/sticker, magnify loupe callout | Later | Not on the source page; easy wins |
| Share sheet (Mail, Messages, AirDrop, etc.) | v1 | `NSSharingServicePicker`; the source page lists "many sharing options" |

### 3.4 Other

| Feature | Plan | Notes |
|---|---|---|
| Floating (pinned) screenshots | v1 | Always on top, resize, opacity, arrow-key nudge, Lock Mode (click-through via `ignoresMouseEvents`) |
| Text recognition (OCR) | v1 | Area → text on clipboard, keep or strip line breaks, language list; also on any image in the editor |
| QR / barcode reading | v1 | Same flow; copies payload, offers to open URLs |
| Capture history | v1 | Grid of the last 30 days, filter by type, search by OCR text, delete, restore |
| URL scheme | v1 | §6 |
| Settings | v1 | General, Shortcuts, Quick Access, Screenshots, Annotate, Wallpaper, Advanced, About |
| Launch at login | v1 | `SMAppService.mainApp` |
| Save options | v1 | Folder, filename template (date, app name, window title), PNG/JPEG/HEIC/TIFF, Retina 2x or 1x, JPEG quality, copy file vs image |
| Upload to user-owned storage | Later | S3-compatible, or a custom shell command that returns a URL. No hosted cloud |
| Hosted cloud, links, comments, teams, SSO | Drop | Needs a service; out of scope for an open-source local app |
| Screen recording, GIF, video editor, camera, keystrokes, clicks | P2 | §10 |

## 4. Architecture

```
project.yml                    XcodeGen spec (app target, test target, URL scheme, entitlements)
App/                           ScreenCap.app target: thin shell
  AppDelegate.swift            menu bar item, shortcut registration, URL scheme routing
  MenuBar/                     status item menu
  Overlays/                    capture selection overlay, window picker, magnifier (AppKit)
  QuickAccess/                 thumbnail panels
  Pin/                         floating screenshot panels
  Editor/                      editor window, toolbar, inspector (SwiftUI + AppKit canvas view)
  History/  Settings/          SwiftUI
Packages/ScreenCapKit/         Swift package, all testable logic
  Capture/                     ScreenCaptureKit wrapper, display geometry, freeze snapshots
  Scrolling/                   frame grabber, stitcher, auto-scroller
  Document/                    Annotation model (Codable), undo stack, project file read/write
  Render/                      Core Graphics renderer for every annotation type, export encoders
  Effects/                     blur, pixelate, spotlight, background, auto-balance
  Vision/                      OCR, barcodes, text-line boxes for the highlighter
  History/                     on-disk store and index
  Automation/                  URL scheme parser and command model
  Settings/                    typed settings over UserDefaults
Tests/                         unit and snapshot tests
```

**Core model.** A `Document` holds the base image (pixel size + scale), a canvas size, an
optional background, and an ordered list of `Annotation` values (enum with associated data:
arrow, shape, text, counter, path, highlight, blur, pixelate, spotlight, image layer). The
editor view and the exporter both draw through one `Renderer`, so what you see is exactly
what gets saved.

**Coordinates.** Everything in the model is in image pixels. Display points ↔ pixels go
through one `DisplayGeometry` type that knows each screen's frame and backing scale, with
tests for mixed-DPI multi-monitor layouts (Retina laptop + 1x external, displays above/left
of the main one, negative origins).

## 5. Hard parts and how we'll solve them

### 5.1 Area capture with frozen screen
On the shortcut, grab every display with `SCScreenshotManager.captureImage` (excluding our
own windows) in parallel, then show one borderless `NSPanel` per display at
`.screenSaver` level showing that still. The user selects on the still, and we crop the
still. This gives freeze-screen for free and makes the selection overlay instant. Live
(non-frozen) mode re-captures the rectangle after the overlay hides.

### 5.2 Window capture
`SCShareableContent.current` for on-screen windows, ordered front to back; hit-test the
cursor against window frames to highlight. Capture with
`SCContentFilter(desktopIndependentWindow:)` so overlapping windows don't show through,
with the shadow on or off. Background/padding composited afterwards in `Effects`.

### 5.3 Project file
`.screencap` is a document package (a folder macOS shows as one file): `document.json`
(versioned schema of the model), `base.png`, `layers/*.png` for image layers, and
`preview.png` for Quick Look. Register a UTI and a Quick Look thumbnail extension. The
format is documented in `docs/file-format.md` so other tools can read it.

### 5.4 Scrolling capture
1. User selects the scrolling region.
2. Grab frames from a lightweight `SCStream` on that rectangle (or repeated stills).
3. For each new frame, find the vertical (or horizontal) offset against the previous frame
   with `VNTranslationalImageRegistrationRequest`, confirmed by row-hash matching. Drop frames
   with no movement.
4. Detect and exclude fixed headers/footers: rows identical across all frames are kept once.
5. Append the new strip to the stitched image; show a live preview beside the region.
6. **Auto-scroll** posts `CGEvent` scroll-wheel events to the region (needs Accessibility
   permission, requested only when first used); stops when two frames match (end reached),
   at a max length, or on Esc.

*Acceptance:* stitches Safari, Chrome, Mail, Slack, Xcode, Terminal and Finder lists without
visible seams or duplicated rows at 1x and 2x.

### 5.5 Background Auto Balance
Find the content's bounding box (non-transparent or non-background pixels), then choose
padding so the visual weight is centered, accounting for window shadows (which are
asymmetric, heavier at the bottom). Unit-tested with fixture screenshots.

### 5.6 Secure redaction
Blur and pixelate are applied destructively at export, never as a filter over intact
pixels, and "secure" modes add random noise per block so no deconvolution or averaging
attack recovers text. A test exports a redacted line of text and asserts Vision can no
longer read it.

### 5.7 Permissions
Screen Recording (TCC) is required for any capture. First run shows an onboarding window
that explains it, opens System Settings to the right pane, and detects when it's granted.
Accessibility is asked for only when auto-scroll is first used.

## 6. URL scheme

`screencap://` with the same command set as the source app minus recording, so existing
Raycast/Alfred/Shortcuts habits carry over. Coordinates are in points with (0,0) at the
lower-left of the display, `display` is 1-based.

| Command | Parameters |
|---|---|
| `all-in-one` | `x y width height display` |
| `capture-area` | `x y width height display action` |
| `capture-previous-area`, `capture-fullscreen`, `capture-window`, `self-timer` | `action` |
| `scrolling-capture` | `x y width height display start autoscroll` |
| `capture-text` | `filepath` or `x y width height display`, `linebreaks` |
| `open-annotate`, `pin` | `filepath` |
| `open-from-clipboard`, `open-history`, `restore-recently-closed` | — |
| `add-quick-access-overlay` | `filepath` (images only in v1) |
| `toggle-desktop-icons`, `hide-desktop-icons`, `show-desktop-icons` | — |
| `open-settings` | `tab` |

`action` = `copy | save | annotate | pin | overlay`. `filepath` must be a readable image; the
parser rejects anything else. Shortcuts.app actions (App Intents) for the main capture
commands are **Later**.

## 7. Milestones and acceptance

Each milestone is one or more PRs with tests green on a `macos-15` GitHub Actions runner
(`xcodebuild test` + `swift test`), and a short screen recording in the PR description.

**M0 — Skeleton.** `project.yml`, menu-bar app with no Dock icon, ScreenCapKit package,
CI, SwiftLint, launch at login, permission onboarding.
*Accept:* app builds from a clean clone with `xcodegen generate && xcodebuild`; onboarding
detects Screen Recording permission.

**M1 — Capture core.** Fullscreen, area (frozen overlay, crosshair, magnifier, fixed size),
window (with/without shadow), previous area, self-timer, global shortcuts, save/copy with
filename template and formats.
*Accept:* `DisplayGeometry` tests for 5 multi-monitor layouts; pixel-exact crop test (a
captured test pattern matches the expected rectangle at 1x and 2x).

**M2 — Quick Access.** Overlay panels, buttons, drag-out, gestures, auto-close, hide, restore.
*Accept:* dragging into Finder, Mail, Slack and a browser upload field works.

**M3 — Editor basics.** Document model, renderer, undo/redo, select/move/resize, arrow
(4 styles), shapes, line, text (7 styles), counter, pencil, crop/rotate/flip/resize, color
picker and palette, export, `.screencap` save/open.
*Accept:* snapshot tests render every annotation type identically in the editor and in
exported PNG; a saved project reopens with every object still editable.

**M4 — Editor advanced.** Blur, pixelate, spotlight, highlighter with text detection,
combine images, background tool with Auto Balance and presets, share sheet.
*Accept:* redaction test (§5.6) passes; Auto Balance fixtures within 2 px of expected padding.

**M5 — OCR, QR, pin.** Capture Text, barcodes, pinned screenshots with Lock Mode.
*Accept:* OCR fixture set (English, German, Japanese, code) ≥ 98% character accuracy;
pinned panel stays above full-screen apps and passes clicks through when locked.

**M6 — Scrolling capture.** §5.4.
*Accept:* the app list in §5.4.

**M7 — History, All-In-One, URL scheme, desktop icons.**
*Accept:* every §6 command has a parser test and a manual run from Terminal with `open`.

**M8 — Ship.** Settings polish, Sparkle feed, `.dmg` build in CI, Homebrew cask, README
with screenshots, `docs/file-format.md`.
*Accept:* fresh macOS 14 and macOS 26 installs go from download to first capture with only
the Screen Recording prompt.

## 8. Planned commands

```bash
brew install xcodegen swiftlint
xcodegen generate                                   # creates ScreenCap.xcodeproj
xcodebuild -scheme ScreenCap -configuration Debug build
xcodebuild -scheme ScreenCap test
swift test --package-path Packages/ScreenCapKit     # fast logic tests, no app
swiftlint
open "screencap://capture-area?action=copy"        # automation smoke test
```

## 9. Risks

| Risk | Mitigation |
|---|---|
| Development needs a Mac; this repo was planned on Linux | All code and CI target macOS runners; ScreenCapKit logic tests run headless |
| macOS shows a recurring "screen recording" reminder to apps using ScreenCaptureKit | Use `SCScreenshotManager` stills (not a persistent stream) except during scrolling capture; document the system prompt |
| Unsigned builds trip Gatekeeper | Documented right-click → Open now; Developer ID + notarization in CI once an account exists |
| Scroll stitching fails on animated or lazily loaded pages | Frame-difference gating, fixed-header detection, user can stop and trim; ship with the §5.4 app list as the bar |
| Frozen overlay on many/high-res displays uses a lot of memory | Capture at native scale but downsample the overlay image for display; free stills as soon as capture ends |
| Global shortcut conflicts with macOS's own ⇧⌘3/4/5 | Default to ⇧⌘1-style alternates and offer to take over the system shortcuts in onboarding |
| Feature creep toward CleanShot's cloud | Cloud is Drop; uploads are Later and only to user-owned storage |

## 10. Phase 2: screen recording (not in this plan)

Recorded here so v1 choices don't block it: MP4 (H.264/HEVC via `SCRecordingOutput` /
AVAssetWriter) and GIF, area/window/fullscreen, mic and system audio, FPS/quality, Do Not
Disturb, cursor, click and keystroke overlays, camera bubble, then a video editor with zooms,
cursor smoothing, backgrounds, motion blur and platform aspect ratios. v1's capture
geometry, Quick Access overlay, history and URL scheme are all built media-type-agnostic
(a `Capture` has a `kind`) so recordings slot in without reworking them.

## 11. Originality

Feature names describe generic behavior. ScreenCap uses its own name, icon, UI layout,
copy, bundled backgrounds and file format, and does not reuse CleanShot assets, artwork or
text.
