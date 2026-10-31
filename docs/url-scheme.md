# screencap:// URL scheme

ScreenCap can be driven from scripts, Raycast, Alfred, Shortcuts or a terminal through
`screencap://` URLs. The format is `screencap://<command>?<param>=<value>&...`.

```bash
open "screencap://capture-area?action=copy"
```

The parser lives in `Packages/ScreenCapKit/Sources/ScreenCapKit/Automation/`
(`URLSchemeParser`, `AutomationCommand`, `URLSchemeBuilder`).

## Rules

- **Case.** The scheme, command names and parameter keys are case-insensitive
  (`SCREENCAP://Capture-Area?ACTION=copy` works). Values are case-sensitive
  (`action=Copy` is rejected).
- **Unknown parameters are errors**, so a typo like `acton=copy` fails loudly instead of being
  ignored. Repeating a parameter or leaving its value empty is also an error.
- **Optional parameters** fall back to the app's own behaviour when omitted: no region means
  you select one interactively, no `action` means your after-capture setting applies.
- **Values must be URL-encoded.** Encode spaces in paths as `%20`.

### Shared parameters

| Parameter | Values | Notes |
|---|---|---|
| `x`, `y` | number ≥ 0 | Points, (0,0) is the **lower-left** corner of the display |
| `width`, `height` | number > 0 | Points |
| `display` | integer ≥ 1 | 1-based display index. Default `1`. Only valid with a region |
| `action` | `copy`, `save`, `annotate`, `pin`, `overlay` | What to do after the capture |
| `filepath` | absolute path | Must exist, be readable and be an image. `~` is expanded |
| booleans | `true`, `false`, `1`, `0` | Lowercase only |

A region is all of `x`, `y`, `width` and `height`, or none of them. Giving only some is an
error.

## Commands

### all-in-one
Opens the all-in-one capture mode. Optional region pre-selects an area.

| Parameter | Default |
|---|---|
| `x y width height display` | interactive |

```bash
open "screencap://all-in-one"
open "screencap://all-in-one?x=100&y=100&width=800&height=600&display=1"
```

### capture-area
Captures an area. Without a region you select one.

| Parameter | Default |
|---|---|
| `x y width height display` | interactive |
| `action` | after-capture setting |

```bash
open "screencap://capture-area"
open "screencap://capture-area?x=0&y=0&width=1280&height=720&display=2&action=save"
```

### capture-previous-area, capture-fullscreen, capture-window, self-timer
Repeat the last area, capture the whole screen, pick a window, or start the self-timer.

| Parameter | Default |
|---|---|
| `action` | after-capture setting |

```bash
open "screencap://capture-previous-area?action=copy"
open "screencap://capture-fullscreen?action=save"
open "screencap://capture-window?action=annotate"
open "screencap://self-timer"
```

### scrolling-capture
Starts a scrolling capture.

| Parameter | Default | Meaning |
|---|---|---|
| `x y width height display` | interactive | The scrolling region |
| `start` | `false` | Begin capturing straight away instead of waiting for the Start button |
| `autoscroll` | `false` | Scroll the region automatically (needs Accessibility permission) |

```bash
open "screencap://scrolling-capture?x=200&y=100&width=900&height=700&start=true&autoscroll=true"
```

### capture-text
Recognises text (OCR) and copies it. Reads from an image file **or** a region, not both.
With neither, you select an area.

| Parameter | Default |
|---|---|
| `filepath` | — |
| `x y width height display` | interactive |
| `linebreaks` | `true` (keep line breaks) |

```bash
open "screencap://capture-text"
open "screencap://capture-text?filepath=/Users/me/Desktop/receipt.png&linebreaks=false"
open "screencap://capture-text?x=0&y=0&width=500&height=200"
```

### open-annotate, pin
Open an image in the editor, or pin it as a floating window. Without `filepath` the app asks
you to choose a file.

```bash
open "screencap://open-annotate?filepath=/Users/me/Desktop/shot.png"
open "screencap://pin?filepath=/Users/me/My%20Shots/shot%201.png"
```

### add-quick-access-overlay
Shows an image in the Quick Access overlay. `filepath` is **required**; images only in v1.

```bash
open "screencap://add-quick-access-overlay?filepath=/Users/me/Desktop/shot.png"
```

### open-from-clipboard, open-history, restore-recently-closed
No parameters. Open the clipboard image in the editor, open capture history, or bring back
the last closed overlay.

```bash
open "screencap://open-from-clipboard"
open "screencap://open-history"
open "screencap://restore-recently-closed"
```

### toggle-desktop-icons, hide-desktop-icons, show-desktop-icons
No parameters.

```bash
open "screencap://hide-desktop-icons"
```

### open-settings
Opens Settings, optionally on a tab.

| Parameter | Values | Default |
|---|---|---|
| `tab` | `general`, `shortcuts`, `quickaccess`, `screenshots`, `annotate`, `wallpaper`, `history`, `advanced`, `about` | last-used tab |

```bash
open "screencap://open-settings?tab=shortcuts"
```

## How the app runs each command

`URLSchemeRouter` (`App/Automation/`) dispatches every parsed command. Region coordinates are
converted to global AppKit points: display `N` is the `N`th entry of `NSScreen.screens` (display 1
is the one with the menu bar), and the rect is offset by that display's frame. A display that
doesn't exist, or a region that misses its display, shows an error.

Commands whose feature lives elsewhere are handed over as `NotificationCenter.default` posts
(file paths as `URL` under `url`, regions as `NSValue` rects in global AppKit points under `rect`):

| Command | Runs |
|---|---|
| `capture-area`, `all-in-one` | Capture coordinator; with a region, captures it directly (All-In-One opens with it pre-selected) |
| `capture-previous-area`, `capture-fullscreen`, `capture-window`, `self-timer` | Capture coordinator |
| `scrolling-capture` | No region: coordinator scrolling flow. Region: `.scrollingCaptureRequested` with `rect`, `start`, `autoscroll` (Bool) |
| `capture-text` | Neither: coordinator text flow. File: `.captureTextRequested` with `url`, `lineBreaks`. Region: same with `rect`, `lineBreaks` |
| `open-annotate` | `.openAnnotateRequested` with `url` (no `url` key = ask for a file) |
| `pin` | `.pinRequested` with `url` (no `url` key = ask for a file) |
| `add-quick-access-overlay` | `.addQuickAccessOverlayRequested` with `url` |
| `open-from-clipboard` | Writes the clipboard image to a temp PNG, then `.openAnnotateRequested` with `url`; error if the clipboard has no image |
| `open-history` | `.openHistoryRequested` (the History window) |
| `restore-recently-closed` | `.restoreRecentlyClosedRequested` (no userInfo) |
| `toggle-/hide-/show-desktop-icons` | `DesktopIconsController` |
| `open-settings` | Settings window on `tab`, or the last-used tab |

Errors (parse errors and missing displays) show a small HUD at the top of the screen for five
seconds and are logged; nothing blocks a script.

## Errors

Parsing fails with one of these (`URLSchemeParser.ParseError`):

| Error | When |
|---|---|
| `wrongScheme` | The URL isn't `screencap://` |
| `unknownCommand` | The command name (host) isn't listed above, or has a path after it |
| `missingParameter(name)` | A required parameter is absent, or a region is incomplete |
| `invalidParameter(name, value)` | A value is malformed, out of range, empty, repeated, a relative path, or `filepath` is combined with a region |
| `unreadableFile(path)` | `filepath` doesn't exist, is a folder, or can't be read |
| `notAnImage(path)` | `filepath` isn't an image type |
| `unknownParameter(name)` | A parameter this command doesn't take |
