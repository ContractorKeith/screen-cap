# The `.screencap` file format

A `.screencap` file is a **document package**: a folder that macOS shows as a single file.
It keeps every annotation editable after saving. Schema version: **1**.

The reference implementation is `ProjectFile` and `Document` in
`Packages/ScreenCapKit/Sources/ScreenCapKit/Document/`.

## Package layout

```
Capture.screencap/
  document.json        the model (required)
  base.png             the captured image, full resolution (required)
  preview.png          flattened render for Quick Look, longest edge ≤ 512 px (optional)
  layers/              only present if the document has image layers
    <name>.png         one per image layer or custom background image
```

- `base.png` is exactly `baseImage.pixelWidth` × `baseImage.pixelHeight` pixels.
- Layer names are a single path component: not empty, no `/` or `:`, and not starting with `.`.
  `layers/<name>.png` is referenced by name (without `.png`) from `imageLayer` annotations and
  `customImage` background fills. Readers must fail if a referenced layer is missing.
- Writers build the package in a temporary directory on the same volume and swap it into place,
  so a failed save never leaves a half-written package.

## Conventions

- **Units.** Every coordinate and length is in **image pixels** of `base.png`, origin at the
  top-left, y increasing downward. `baseImage.scale` (1 or 2) records the source display's
  backing scale; divide by it to get points.
- **Geometry encoding** (CoreGraphics' Codable forms):
  - point: `[x, y]`
  - size: `[width, height]`
  - rect: `[[x, y], [width, height]]`
- **Color:** `{"red", "green", "blue", "alpha"}`, sRGB, each 0…1, alpha not premultiplied.
- **Enums with payloads** are an object with exactly one key, the case name, whose value holds
  the case's fields: `{"counter": {"number": 1, "center": [10, 10], "radius": 18}}`.
  Cases with no fields use an empty object: `{"straight": {}}`.
- **Optional fields** are omitted when absent.
- **Order.** `annotations` is in creation order; counters are numbered 1…n in this order.
  Drawing order is ascending `zIndex`, ties broken by array order.

## Versioning

`schemaVersion` is an integer at the top level. A reader must check it before decoding
anything else and refuse versions it doesn't know (ScreenCap throws
`ProjectFileError.unsupportedSchemaVersion`). Additive, backward-compatible changes may keep
the version; anything an older reader would misread bumps it.

## `document.json`

| Field | Type | Notes |
|---|---|---|
| `schemaVersion` | int | `1` |
| `baseImage` | object | `pixelWidth`, `pixelHeight` (int), `scale` (number) |
| `canvasSize` | size | exported image size; equals the base size unless a background adds padding |
| `background` | object? | see below |
| `annotations` | array | see below |

### Background

| Field | Type | Notes |
|---|---|---|
| `fill` | enum | `solid {color}`, `linearGradient {stops: [{color, location 0…1}], angle}` (degrees, 0 = left→right, 90 = bottom→top), `bundled {name}`, `customImage {layerName}` |
| `padding` | number | pixels between canvas edge and base image |
| `cornerRadius` | number | applied to the base image |
| `shadow` | shadow? | under the base image |
| `alignment` | string | `center`, `top`, `bottom`, `left`, `right`, `topLeft`, `topRight`, `bottomLeft`, `bottomRight` |

A shadow is `{"color": color, "radius": number, "offset": size}`.

### Annotation

| Field | Type | Notes |
|---|---|---|
| `id` | string | UUID |
| `zIndex` | int | draw order, higher on top |
| `style` | object | `strokeColor` color, `strokeWidth` number, `fillColor` color?, `shadow` shadow?, `opacity` 0…1 |
| `kind` | enum | one of the kinds below |

Kinds (fields of each case):

| Kind | Fields |
|---|---|
| `arrow` | `start` point, `end` point, `style`: `straight {}`, `tapered {}`, `doubleHeaded {}`, `curved {control: point}` |
| `rectangle` | `rect`, `filled` bool, `cornerRadius` number |
| `ellipse` | `rect` |
| `line` | `start` point, `end` point |
| `text` | `string`, `preset` int 1…7, `fontSize` number, `rect` |
| `counter` | `number` int, `center` point, `radius` number |
| `path` | `points` [point], `smoothed` bool (Catmull-Rom on render) |
| `highlight` | `region`: `rect {rect}` or `path {points}`; `color` |
| `blur` | `rect`, `mode` `"secure"` or `"smooth"`, `radius` number |
| `pixelate` | `rect`, `blockSize` int, `randomize` bool |
| `spotlight` | `shapes`: [`rect {rect}` or `ellipse {rect}`]; everything outside is dimmed |
| `imageLayer` | `layerName` string (→ `layers/<layerName>.png`), `rect` |

## Example

A Retina capture with a gradient background, a curved arrow, a counter and a secure blur.

```json
{
  "annotations" : [
    {
      "id" : "AFBADBDD-CC0B-4873-9350-A1469531CDD9",
      "kind" : {
        "arrow" : {
          "end" : [600, 400],
          "start" : [100, 120],
          "style" : { "curved" : { "control" : [300, 80] } }
        }
      },
      "style" : {
        "opacity" : 1,
        "shadow" : {
          "color" : { "alpha" : 0.4, "blue" : 0, "green" : 0, "red" : 0 },
          "offset" : [0, 4],
          "radius" : 8
        },
        "strokeColor" : { "alpha" : 1, "blue" : 0.19, "green" : 0.23, "red" : 1 },
        "strokeWidth" : 4
      },
      "zIndex" : 0
    },
    {
      "id" : "2CA2CC76-226A-488D-99FD-524BD11B352B",
      "kind" : { "counter" : { "center" : [640, 420], "number" : 1, "radius" : 18 } },
      "style" : {
        "opacity" : 1,
        "strokeColor" : { "alpha" : 1, "blue" : 0.19, "green" : 0.23, "red" : 1 },
        "strokeWidth" : 4
      },
      "zIndex" : 1
    },
    {
      "id" : "73099102-D576-4632-A300-9C857A589D76",
      "kind" : { "blur" : { "mode" : "secure", "radius" : 12, "rect" : [[900, 200], [400, 60]] } },
      "style" : {
        "opacity" : 1,
        "strokeColor" : { "alpha" : 1, "blue" : 0.19, "green" : 0.23, "red" : 1 },
        "strokeWidth" : 4
      },
      "zIndex" : 2
    }
  ],
  "background" : {
    "alignment" : "center",
    "cornerRadius" : 12,
    "fill" : {
      "linearGradient" : {
        "angle" : 90,
        "stops" : [
          { "color" : { "alpha" : 1, "blue" : 0.19, "green" : 0.23, "red" : 1 }, "location" : 0 },
          { "color" : { "alpha" : 1, "blue" : 1, "green" : 1, "red" : 1 }, "location" : 1 }
        ]
      }
    },
    "padding" : 64,
    "shadow" : {
      "color" : { "alpha" : 0.4, "blue" : 0, "green" : 0, "red" : 0 },
      "offset" : [0, 4],
      "radius" : 8
    }
  },
  "baseImage" : { "pixelHeight" : 1800, "pixelWidth" : 2880, "scale" : 2 },
  "canvasSize" : [3008, 1928],
  "schemaVersion" : 1
}
```

A unit test (`documentedExampleDecodes`) decodes this example, so it stays valid.
