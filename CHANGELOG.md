# Changelog

All notable changes to ScreenCap. Versions follow [Semantic Versioning](https://semver.org).

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
