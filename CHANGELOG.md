# Changelog

All notable changes to ScreenCap. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and versions follow [Semantic Versioning](https://semver.org).

<!-- Releasing: replace "Unreleased" under 0.1.0 with the tag date (YYYY-MM-DD), add a fresh
     [Unreleased] section, and use the version's section as the annotated tag message
     (release.yml turns the tag message into the GitHub Release notes). -->

## [Unreleased]

- Fix custom-image Background presets across documents by storing their images separately and importing them when applied.

## [0.1.0] - Unreleased

First release, not yet tagged. Ad-hoc signed, not notarized.

### Added

#### Capture
- Area, window, fullscreen, previous area, self-timer (3/5/10 s), all-in-one and scrolling
  capture from the menu bar or global ⌃⇧ shortcuts that don't clash with macOS's own.
- Frozen-screen overlay with crosshair, magnifier (pixel grid, coordinates, size, hex color),
  typed fixed size and locked aspect ratio.
- Window capture with or without shadow, Space to toggle area/window.
- Scrolling capture with live preview, manual or auto-scroll, fixed headers kept once.
- Capture text: OCR to the clipboard, plus QR and barcode reading.
- Hide desktop icons while capturing.

#### After capture
- Quick Access overlay: copy, save, annotate, pin, OCR, reveal, delete, drag out to any app,
  swipe gestures, auto-close, hide overlays, restore recently closed.
- Per-shortcut after-capture action.

#### Annotate
- Editor with arrows (4 styles), shapes, line, text (7 styles), counter, pencil, highlighter
  with text-line snapping, secure blur and pixelate, spotlight, crop, rotate, flip, resize,
  color picker with saved palette, combine images, background tool with Auto Balance and
  presets, undo/redo, share sheet.
- Export PNG, JPEG, HEIC, TIFF, PDF; save and reopen editable `.screencap` projects.

#### Everything else
- Pinned screenshots with opacity, nudge and click-through Lock Mode.
- History of the last 30 days, searchable by recognized text.
- `screencap://` URL scheme for scripts, Raycast, Alfred and Shortcuts.
- Settings: General, Shortcuts, Quick Access, Screenshots, Scrolling, Text Recognition,
  Annotate, Wallpaper, Advanced, About. Launch at login.
- Welcome window: Screen Recording permission, then the main shortcuts and a
  "Take Your First Screenshot" button. Reopen it from the menu with Welcome….
- Check for Updates… (Sparkle 2; opens the releases page until the update key is set).
- DMG build (`make dmg`), tag-driven GitHub Release workflow, Homebrew cask.

#### Added during pre-release QA
- Wallpaper → "Add background to window captures" puts window captures on the wallpaper
  background, centered with even shadow margins (#95, #107).
- Opening a `.screencap` project or an image from Finder or `open -a` opens it in the editor (#96).
- Quitting with unsaved editor work asks to save each window first (#84, #106).
- Lowering "Keep captures for" asks before deleting older captures (#107).
- Keyboard control of Quick Access: ⌃⇧Q focuses the newest panel; ⌘C, ⌘S, ⌘E or Return, ⌘P,
  ⌘T, ⌘R, ⌫ and Esc act on it; Tab and the arrows move between panels (#129).
- Keyboard control of History: arrows move (⇧ extends), Return opens, Space previews, ⌘C copies,
  ⌘A selects all, ⌫ deletes (#130).
- The welcome window spots an update that lost Screen Recording and gives the `tccutil reset`
  command to copy, then waits for the new grant. Ad-hoc builds need this after every update (#141, #146).

### Fixed

Found in the pre-release QA passes.

#### Capture
- `--quit` exits with a code that says what happened, and failed captures, saves and copies
  show a HUD instead of failing silently (#68, #83).
- Saves in the same second no longer overwrite each other; long names are trimmed safely (#67, #68).
- Areas that span displays capture correctly; self-timer always lets you pick the area (#68).
- Fixed sizes reject `inf`, `nan` and absurd values; the magnifier shows live pixels when the
  screen isn't frozen (#94).
- Capture Text writes its History record again (#83).
- An invalid `--region` fails with an exit code instead of opening the overlay and hanging `--quit` (#119).
- The selection overlay follows display changes, so no part of the screen is out of reach (#131).

#### Scrolling capture
- Fast scrolls and repeating content (logs, tables, Terminal) stitch correctly; real gaps are
  marked with a seam and a HUD instead of duplicated rows (#69, #93, #108).
- Auto-scroll keeps the top of the region and no longer stops early on repetitive pages (#108).
- `--region` rejects `nan`, `inf`, hex and exponents (#105).
- Auto-scroll on repeating output is period-aware: no repeated blocks or silently dropped rows,
  and it runs to the end (#112, #126).
- A display change mid-capture stops scrolling capture cleanly, so `--quit` exits (#127).

#### Quick Access and History
- Restore to Quick Access works, and OCR text reaches History (#66).
- History expiry applies while the app runs, not just at launch (#95).
- Drag-out uses the same output scale as Save; a cancelled swipe no longer moves the panel (#95).
- Panels still on screen at quit come back with Restore Recently Closed (#107).
- Delete reports a file that couldn't be moved to the Trash (#105).
- History write failures are reported instead of losing closed captures silently (#113).
- Temporary drag, copy and share files are cleaned up (#114).
- Quick Access panels stay on screen instead of stacking past the display edge (#116).
- History thumbnails of tall scrolling captures are readable, not a sliver (#133).

#### Annotate
- Redactions defeat OCR, Smooth blur is labeled as not for secrets, and saved projects bake
  redactions so the original pixels aren't kept (#65).
- Opaque shapes over text can be used as redactions and are baked the same way (#84, #106).
- Auto Balance survives later edits; resize keeps the image scale; counter handles resize;
  undo memory is capped (#64).
- A file that can't be opened shows a HUD instead of a modal that could hide behind other windows (#105).
- Resize has sane limits, closed editor windows free their memory, and opaque images no longer
  show a checkerboard strip at the edges (#110, #111, #118).

#### URL scheme and settings
- `open-settings` knows every tab; `scrolling-capture` and `capture-text` handle all their
  parameters and queue behind a running capture (#67, #83, #107).
- Region numbers must be plain decimals (#107).
- Reset All Settings resets every setting (#67) and keeps History captures and their retention (#125).
- Settings uses a sidebar so every pane title shows in full (#104) and opens fully on screen,
  even on a 13" display (#115).

#### Accessibility
- VoiceOver reads tool names, sliders, swatches, popups, History thumbnails, the Resize fields
  and "Keep captures for" instead of SF Symbol names or nothing (#117, #132).

#### Build
- Every build gets a real build number, and CI checks the bundle (#82).
- The app ships its dependencies' resource bundles, so the Shortcuts pane works on any Mac (#96).
- Ad-hoc builds keep codesign's default cdhash designated requirement, and `check-bundle.sh` fails
  any ad-hoc build whose requirement isn't cdhash-anchored (#146). #141 had pinned the requirement
  to the bundle identifier so updates kept Screen Recording; that was reverted for security,
  because an ad-hoc signature has no certificate to anchor to and any ad-hoc app claiming
  ScreenCap's identifier would have inherited its grant. Each new version needs a fresh grant
  until builds are Developer ID signed (`SIGN_IDENTITY`, which grants then survive).
- Every file in the bundle is user-writable, so `xattr -d com.apple.quarantine` succeeds (#142).
- `make test` no longer leaves test preference files in `~/Library/Preferences` (#120).

### Documentation
- Install steps for macOS 15 and later, which removed right-click → Open for unnotarized apps:
  Privacy & Security → Open Anyway, or `xattr -d com.apple.quarantine`. The DMG and the
  welcome window carry the same note (#128, #142).
- README: ⌃⇧Q and the Quick Access and History keys, the welcome window as it really is, and
  how to re-grant Screen Recording after an update (#141, #143).

[Unreleased]: https://github.com/ContractorKeith/screen-cap/commits/main
[0.1.0]: https://github.com/ContractorKeith/screen-cap/commits/main
