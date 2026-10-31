# Changelog

All notable changes to ScreenCap. Versions follow [Semantic Versioning](https://semver.org).

## Unreleased

Fixes from the post-release QA passes.

### Added
- Wallpaper → "Add background to window captures" puts window captures on the wallpaper
  background, centered with even shadow margins (#95, #107).
- Opening a `.screencap` project or an image from Finder or `open -a` opens it in the editor (#96).
- Quitting with unsaved editor work asks to save each window first (#84, #106).
- Lowering "Keep captures for" asks before deleting older captures (#107).

### Capture
- `--quit` exits with a code that says what happened, and failed captures, saves and copies
  show a HUD instead of failing silently (#68, #83).
- Saves in the same second no longer overwrite each other; long names are trimmed safely (#67, #68).
- Areas that span displays capture correctly; self-timer always lets you pick the area (#68).
- Fixed sizes reject `inf`, `nan` and absurd values; the magnifier shows live pixels when the
  screen isn't frozen (#94).
- Capture Text writes its History record again (#83).

### Scrolling capture
- Fast scrolls and repeating content (logs, tables, Terminal) stitch correctly; real gaps are
  marked with a seam and a HUD instead of duplicated rows (#69, #93, #108).
- Auto-scroll keeps the top of the region and no longer stops early on repetitive pages (#108).
- `--region` rejects `nan`, `inf`, hex and exponents (#105).

### Quick Access and History
- Restore to Quick Access works, and OCR text reaches History (#66).
- History expiry applies while the app runs, not just at launch (#95).
- Drag-out uses the same output scale as Save; a cancelled swipe no longer moves the panel (#95).
- Panels still on screen at quit come back with Restore Recently Closed (#107).
- Delete reports a file that couldn't be moved to the Trash (#105).

### Annotate
- Redactions defeat OCR, Smooth blur is labeled as not for secrets, and saved projects bake
  redactions so the original pixels aren't kept (#65).
- Opaque shapes over text can be used as redactions and are baked the same way (#84, #106).
- Auto Balance survives later edits; resize keeps the image scale; counter handles resize;
  undo memory is capped (#64).
- A file that can't be opened shows a HUD instead of a modal that could hide behind other windows (#105).

### URL scheme and settings
- `open-settings` knows every tab; `scrolling-capture` and `capture-text` handle all their
  parameters and queue behind a running capture (#67, #83, #107).
- Region numbers must be plain decimals (#107).
- Reset All Settings resets every setting (#67).
- Settings uses a sidebar so every pane title shows in full (#104).

### Build
- Every build gets a real build number, and CI checks the bundle (#82).
- The app ships its dependencies' resource bundles, so the Shortcuts pane works on any Mac (#96).

## 0.1.0 — 2026-10-31

First release. Ad-hoc signed, not yet notarized.

### Capture
- Area, window, fullscreen, previous area, self-timer (3/5/10 s), all-in-one and scrolling
  capture from the menu bar or global ⌃⇧ shortcuts that don't clash with macOS's own.
- Frozen-screen overlay with crosshair, magnifier (pixel grid, coordinates, size, hex color),
  typed fixed size and locked aspect ratio.
- Window capture with or without shadow, Space to toggle area/window.
- Scrolling capture with live preview, manual or auto-scroll, fixed headers kept once.
- Capture text: OCR to the clipboard, plus QR and barcode reading.
- Hide desktop icons while capturing.

### After capture
- Quick Access overlay: copy, save, annotate, pin, OCR, reveal, delete, drag out to any app,
  swipe gestures, auto-close, hide overlays, restore recently closed.
- Per-shortcut after-capture action.

### Annotate
- Editor with arrows (4 styles), shapes, line, text (7 styles), counter, pencil, highlighter
  with text-line snapping, secure blur and pixelate, spotlight, crop, rotate, flip, resize,
  color picker with saved palette, combine images, background tool with Auto Balance and
  presets, undo/redo, share sheet.
- Export PNG, JPEG, HEIC, TIFF, PDF; save and reopen editable `.screencap` projects.

### Everything else
- Pinned screenshots with opacity, nudge and click-through Lock Mode.
- History of the last 30 days, searchable by recognized text.
- `screencap://` URL scheme for scripts, Raycast, Alfred and Shortcuts.
- Settings: General, Shortcuts, Quick Access, Screenshots, Scrolling, Text Recognition,
  Annotate, Wallpaper, Advanced, About. Launch at login.
- Welcome window: Screen Recording permission, then the main shortcuts and a
  "Take Your First Screenshot" button. Reopen it from the menu with Welcome….
- Check for Updates… (Sparkle 2; opens the releases page until the update key is set).
- DMG build (`make dmg`), tag-driven GitHub Release workflow, Homebrew cask.
