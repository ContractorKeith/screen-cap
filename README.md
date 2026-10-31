# ScreenCap

An open-source screenshot tool for macOS. It lives in the menu bar, captures an area, a
window, the full screen, or a scrolling page from a global shortcut, and hands the result
to you as a file, a clipboard image, an editable annotation document, a pinned floating
image, or recognized text.

Swift 6, AppKit for the capture overlays, SwiftUI for settings. Capture goes through
Apple's ScreenCaptureKit; text and barcodes through Vision. One third-party package
(global shortcuts). No accounts, no cloud, no telemetry. MIT.

**Status:** in development, not yet released. The core library is built and tested; the
app's capture flow works end to end; the editor, Quick Access overlay, pin panels, and
history windows are still to come. Details under [Where it stands](#where-it-stands).
Requires macOS 14 Sonoma or newer.

## What it will do

### Capture

Every capture starts from a global shortcut or the menu bar icon. Defaults use ⌃⇧ plus a
key so they never fight macOS's own ⇧⌘3/4/5.

- **Area** (⌃⇧4): the screen freezes, a crosshair and magnifier appear, drag a rectangle.
  The magnifier shows the pixel grid, cursor coordinates, selection size, and the hex
  color under the cursor. Type an exact width and height, or lock an aspect ratio.
- **Window** (⌃⇧W): hover to highlight the window under the cursor, click to capture it
  cleanly even when other windows overlap, with or without its shadow. Press Space to
  flip between area and window mode.
- **Fullscreen** (⌃⇧3): the display under the cursor, or all displays.
- **Previous area** (⌃⇧R): recapture the last rectangle.
- **Self-timer** (⌃⇧T): 3, 5, or 10 seconds, then capture the chosen rectangle.
- **Scrolling** (⌃⇧S): select a region, scroll (or let the app scroll for you), and get
  one tall stitched image with fixed headers and footers kept once.
- **All-in-one** (⌃⇧5): draw a rectangle first, then pick what to do with it from a
  small toolbar: area, window, fullscreen, scrolling, text, or timer.
- **Capture text** (⌃⇧O): select an area and get its text on the clipboard. Also reads
  QR codes and barcodes and offers to open URLs.
- Hide desktop icons while capturing, from the menu bar.

Each shortcut has its own after-capture action: show the overlay, copy, save, annotate,
or pin.

### After capture

A small thumbnail slides into a screen corner. From it: copy, save, annotate, pin, OCR,
reveal in Finder, delete, or drag the image straight into Mail, Slack, Finder, or a
browser upload field. Multiple captures stack. Swipe it away or let it close itself.

### Annotate

An editor where every object stays editable: arrows (straight, tapered, double, curved),
rectangles, ellipses, lines, text in seven styles, numbered counters, smoothed pencil,
a highlighter that snaps to text lines, blur and pixelate that can't be reversed,
spotlight, crop with aspect ratios, rotate, flip, resize, a screen-sampling color picker
with a saved palette, and a background tool with padding, corner radius, shadow,
bundled or custom backgrounds, and automatic balancing. Undo, redo, reorder, copy and
paste objects. Save as PNG, JPEG, HEIC, TIFF, or PDF, or as a `.screencap` project you
can reopen and keep editing. Share through the standard macOS share sheet.

### Pin, history, automation

- **Pin** any capture as an always-on-top floating image. Resize it, set its opacity,
  nudge it with arrow keys, or lock it so clicks pass through.
- **History** keeps the last 30 days of captures in a grid, searchable by the text found
  in them.
- **URL scheme.** `screencap://capture-area?action=copy` and friends, so Raycast,
  Alfred, Shortcuts, and shell scripts can drive it.
- **Settings** for shortcuts, save folder and filename template (date, app name, window
  title), format and Retina scale, overlay position and auto-close, launch at login.

## How it works

The repository is one Swift package with two parts.

**ScreenCapKit** is a library with no UI and no screen access of its own, which is what
makes it testable on a CI runner. It holds:

- `Capture`: a ScreenCaptureKit wrapper (`SCScreenshotManager` stills, window capture by
  `SCContentFilter`, shadow on or off) and `DisplayGeometry`, the one place that converts
  between screen points and image pixels across mixed-DPI, multi-monitor layouts.
- `Document`: the annotation model (`Document`, `Annotation` enum, undo stack) and the
  `.screencap` package format (`document.json` plus PNG layers).
- `Render`: one Core Graphics renderer used by both the editor and the exporter, so what
  you see is what gets saved. Arrow geometry, text styles, path smoothing, encoders.
- `Effects`: blur, pixelate with per-block noise, spotlight, background compositing, and
  Auto Balance, which pads content so its visual weight (shadows included) sits centered.
- `Scrolling`: frame alignment with Vision's translational registration confirmed by row
  hashing, fixed-edge detection, the stitcher, and the auto-scroller that posts scroll
  events.
- `Vision`: OCR, barcode reading, and text-line boxes for the highlighter.
- `History`: on-disk capture store with thumbnails, search, and 30-day retention.
- `Automation`: the `screencap://` command model, parser, and builder.
- `Settings`: typed settings over `UserDefaults`, filename templates, save options.

**ScreenCap** (the `App/` target) is the thin shell: the menu bar item, the
`CaptureCoordinator` that runs each capture flow, the frozen-screen selection overlay
(one borderless panel per display at screen-saver level, showing a still taken at
shortcut time, so selection is instant and nothing moves under you), the window picker,
the magnifier, the self-timer, shortcut registration, permission onboarding, and the
settings window. Captured images are routed to a sink (save, copy, overlay, annotate,
pin) through `CaptureSinkRouter`.

Capture itself never uses the deprecated `CGWindowListCreateImage`. Stills come from
`SCScreenshotManager`, so macOS doesn't show the recurring screen-recording reminder
outside of scrolling capture.

Redaction is destructive by design: blur and pixelate are baked into the exported pixels,
never applied as a reversible filter, and the "secure" modes add random noise per block.
A test exports a redacted line of text and checks that Vision can no longer read it.

The full plan, feature matrix, and the reasoning behind each choice are in
[docs/PLAN.md](docs/PLAN.md).

## Where it stands

Done, with tests:

- ScreenCapKit: display geometry, capture service, document model and project file,
  renderer and exporters, effects and secure redaction, scrolling stitcher and
  auto-scroller, OCR and barcodes, history store, URL scheme parser, settings.
- App: menu bar, global shortcuts, permission onboarding, General and Shortcuts settings,
  and the capture flow for area, window, fullscreen, previous area, self-timer, and
  scrolling, with save and copy outputs.

Not yet built:

- Quick Access overlay panels, the annotation editor window, pinned screenshot panels,
  the history window, all-in-one toolbar, URL scheme routing in the app (the parser
  exists; the app currently logs incoming URLs), remaining settings panes, DMG release.

The test suite has 226 Swift Testing cases across the library and the app's pure logic.

## Permissions

Screen Recording is required for any capture; the first launch explains why and opens
the right System Settings pane. Accessibility is requested only the first time you use
auto-scroll, because scrolling for you means posting scroll events. Nothing else is
requested.

## Build from source

The primary build is SwiftPM and works with Command Line Tools alone, no Xcode needed.

```bash
git clone https://github.com/ContractorKeith/screen-cap.git
cd screen-cap
make build      # swift build
make test       # swift test (adds Swift Testing paths on a CLT-only Mac)
make bundle     # release build assembled into build/ScreenCap.app, ad-hoc signed
make run        # bundle, then launch
make lint       # swiftlint --strict
```

Xcode users can run `xcodegen generate && open ScreenCap.xcodeproj`; `project.yml` is a
secondary path and the generated project is not checked in.

The app has a hidden launch mode for driving captures from a script, used by the smoke
tests:

```bash
build/ScreenCap.app/Contents/MacOS/ScreenCap --capture area --action save --quit
```

Launched from Terminal like this, it uses Terminal's Screen Recording permission.

## Scope

Screenshots, editing, and saving. Screen recording (video, GIF, camera bubble, click and
keystroke overlays) is a later phase, and the capture, overlay, history, and URL-scheme
code is written so recordings can slot in without rework. Hosted cloud sharing, accounts,
and teams are not planned; uploading to storage you own may come later.

ScreenCap uses its own name, icon, interface, bundled backgrounds, and file format.

## Contributing

Open an issue before starting anything larger than a bug fix. Keep logic in ScreenCapKit
where it can be tested headless, and keep the app target thin. `make test` and
`make lint` must pass; CI runs both on every push.

## License

MIT. See [LICENSE](LICENSE).
