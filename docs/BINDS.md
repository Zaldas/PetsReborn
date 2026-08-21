# PetsReborn — Data Bind System

Layout elements connect to live data through a `bind = {}` table declared inline on the element. `Utils.applyBinds()` reads the bind table every frame and updates the element accordingly.

---

## How Binds Work

Every element in a layout section can declare a `bind` table:

```lua
txt = {
    font = 'Grammara', size = 12,
    pos  = {0, 0},
    bind = {
        value   = 'pet.name',
        visible = 'pet.active',
    },
}
```

If `bind` is absent the element is created but never updated — it shows whatever was set at initialization (useful for purely static decorative elements).

---

## Bind Keys

### `visible` — show/hide the element

```lua
visible = 'tokenName'
```

Shows the element when `tokens[tokenName] == true`, hides it otherwise. The token must be a boolean.

```lua
bind = { visible = 'pet.active' }
```

---

### `visibleAnd` — secondary visibility condition

```lua
visibleAnd = 'tokenName'
```

ANDed with `visible`. Both must be true for the element to show. Either can be omitted independently.

```lua
bind = {
    visible    = 'target.active',
    visibleAnd = 'ui.showTargetBar',
}
```

---

### `value` — data source (uiText and uiBar)

```lua
value = 'tokenName'
```

Unified data key — behavior depends on element type:

**uiBar** — numeric token sets bar fill (0.0–1.0). Triggers animation tick.

```lua
bind = { value = 'pet.hppNorm' }
```

**uiText** — string/format token sets display text. Empty string if token is nil.

```lua
-- plain token
bind = { value = 'pet.hppPct' }

-- format string: if value contains '{', {tokenName} patterns are substituted from the token table
bind = { value = '{pet.tpStr} / 3000' }

-- mixed static + token
bind = { value = 'Lv.{pet.level}' }
```

---

### `color` — threshold color (uiText and uiBar)

```lua
color = 'threshold'
```

Unified color key — behavior depends on element type:

**uiBar** — sets bar fill color from the section's `thresholds` table using `value` as the normalized input.

**uiText** — sets text color from the section's `thresholds` table using `colorValue` (or `value`) as the normalized input.

```lua
-- bar
bind = {
    value = 'pet.hppNorm',
    color = 'threshold',
}

-- text
bind = {
    value        = 'pet.hppPct',
    color        = 'threshold',
    colorValue   = 'pet.hppNorm',
    defaultColor = '#F0FFFFFF',
}
```

---

### `colorValue` — normalized input for text threshold color

```lua
colorValue = 'tokenName'
```

The 0.0–1.0 token used when resolving `color = 'threshold'` on a uiText. Separates the display token (`value`) from the color source, e.g. display `'75%'` while color is driven by `0.75`.

If absent, falls back to the `value` token.

---

### `defaultColor` — fallback color when above all thresholds (uiText only)

```lua
defaultColor = '#RRGGBBAA'
```

Hex color applied when `colorValue` is above all threshold entries (i.e. full health). Without this, text color is not reset on recovery — it stays at the last matched threshold color.

```lua
bind = {
    color        = 'threshold',
    colorValue   = 'pet.hppNorm',
    defaultColor = '#F0FFFFFF',
}
```

---

## Thresholds Table

Declared on the **section**, shared by all elements within it.

```lua
hp = {
    thresholds = {
        { below = 0.25, color = '#FC8182FF' },  -- red    hp < 25%
        { below = 0.50, color = '#F3F37CFF' },  -- yellow hp < 50%
        { below = 0.75, color = '#F8BA80FF' },  -- orange hp < 75%
    },
    bar = { bind = { value = 'pet.hppNorm', color = 'threshold' } },
    txt = { bind = { value = 'pet.hppPct',  color = 'threshold', colorValue = 'pet.hppNorm', defaultColor = '#F0FFFFFF' } },
}
```

Thresholds are checked in order; first `value < below` wins. If none match, `defaultColor` is used (text only).

---

## Element Support Matrix

| Bind key       | uiText | uiBar | uiImage | uiBackground |
|----------------|--------|-------|---------|--------------|
| `visible`      | ✓      | ✓     | ✓       | ✓            |
| `visibleAnd`   | ✓      | ✓     | ✓       | ✓            |
| `value`        | ✓      | ✓     | —       | —            |
| `color`        | ✓      | ✓     | —       | —            |
| `colorValue`   | ✓      | ✓     | —       | —            |
| `defaultColor` | ✓      | ✓     | —       | —            |

> **Note — img/bg dynamic binds:** `uiImage` and `uiBackground` currently support only `visible`/`visibleAnd`. Dynamic binding (path, color, opacity from tokens) is a planned future expansion.

---

## Complete Example

```lua
hp = {
    anchor = 'name.bottom',
    pos    = {0, 0},
    bind   = { visible = 'pet.active' },       -- section-level: hides bar+text together
    thresholds = {
        { below = 0.25, color = '#FC8182FF' },
        { below = 0.50, color = '#F3F37CFF' },
        { below = 0.75, color = '#F8BA80FF' },
    },
    bar = {
        pos = {0, 0}, zOrder = 1, animSpeed = 0.2,
        imgBg  = { ... },
        imgBar = { ... },
        imgFg  = { ... },
        bind = {
            value   = 'pet.hppNorm',
            color   = 'threshold',
            visible = 'pet.active',
        },
    },
    txt = {
        font = 'Grammara', size = 10, align = 'right',
        pos  = {105, -1}, zOrder = 6,
        bind = {
            value        = 'pet.hppPct',
            color        = 'threshold',
            colorValue   = 'pet.hppNorm',
            defaultColor = '#F0FFFFFF',
            visible      = 'pet.active',
        },
    },
    -- optional: standalone image overlay on this section
    img = {
        path = 'layouts/assets/ffxi/HpIcon.png',
        size = {12, 12}, pos = {-14, 1}, zOrder = 5,
        bind = { visible = 'pet.active' },
    },
},
```

---

## Maneuver Column Keys (`petFrame.maneuvers`)

`modules/maneuverRows.lua` reads this section directly, not through `Utils.applyBinds()`. `bind`
is the only true bind table in it -- every other key below is geometry or render behaviour owned
by the module, so the generic bind keys documented above do not apply to them.

### `bind` -- column visibility

```lua
bind = {
    visible    = 'pet.active',
    visibleAnd = 'ui.showManeuvers',
},
```

ANDed on top of the module's own gate, so a layout can narrow the column's visibility but never
widen it.

---

### `anchor`, `columnWidth`, `firstRowPos`, `rowHeight` -- column geometry

```lua
anchor      = {'name.y'},
columnWidth = 72,
firstRowPos = {-20, 5},
rowHeight   = 20,
```

`anchor` resolves through the position registry like any other section. The column origin is the
resolved anchor plus `firstRowPos`; row `i` sits at that origin plus `(0, (i - 1) * rowHeight)`.
`columnWidth` sets the column's extent and the frame's drag hit-rect; it does not set the
`background` panel width, which is authored in the slice sizes.

`marginBottom` (optional) pads the reported column height past the last row.

---

### `iconSize`, `iconZOrder`, `iconActive`, `iconResidual` -- pip sprites

```lua
iconSize     = {16, 16},
iconZOrder   = 5,
iconActive   = 'layouts/assets/ffxi/pips/diamondFill-16.png',
iconResidual = 'layouts/assets/ffxi/pips/diamondLine-16.png',
```

Every pip in a row renders at `iconSize`. `iconResidual` draws pip 1 when the element has no
maneuver up; `iconActive` draws it otherwise and draws every pip past 1. Sprites are tinted
multiplicatively, so the source art must be white-scale to reach the element colour.

---

### `maxPips` -- how many pips a row may draw

```lua
maxPips = 3,
```

A layout capacity, not the game's cap. `data/maneuvers.lua` `MAX_ACTIVE` states what the game
permits; the two may differ. A `maxPips` past the end of `pipOffsets` clamps to the offsets that
exist.

---

### `pipOffsets` -- pip placement

```lua
pipOffsets = {
    { 0,  0},   -- 1: main pip, the only one drawn at count 0
    {-8, -8},   -- 2
    {-8,  8},   -- 3
},
```

Array of `{x, y}`; entry N is pip N's offset from the row origin. The module draws
`min(count, maxPips, #pipOffsets)` of them, always including pip 1. A cluster, a vertical line and
a horizontal run are all layout edits with no code change.

---

### `blink` -- expiry pulse

```lua
blink = {
    threshold  = 15,
    alphaFloor = 0.3,
    period     = 1,
},
```

`threshold` is the seconds remaining at which the pulse starts. `alphaFloor` is a 0-1 **multiplier**
on the element colour's authored alpha, not a hex alpha. `period` is seconds per full cycle.
Absent, or with a non-positive `period` or `threshold`, there is no pulsing. Only the last-drawn
pip of an element pulses; the percentage never does.

---

### `pctOffset`, `pctAlign` -- percentage placement

```lua
pctOffset = {-7, 0},
pctAlign  = 'right',
```

`pctOffset` is measured from pip 1, not from the row origin. `pctAlign` picks which edge of the
percentage lands on that point, and owns alignment for the element, so `txt.align` is not read.

---

### `pctFormat` -- percentage text

```lua
pctFormat = '%d%%',
```

`string.format` pattern taking the integer chance. Validated once at create and falls back to
the default above if `string.format` rejects it.

---

### `elementColors`, `thresholds` -- colour

```lua
elementColors = {
    '#F0603FFF',  -- 1 fire
    '#A6DCEEFF',  -- 2 ice
    -- ... 3 wind, 4 earth, 5 thunder, 6 water, 7 light, 8 dark
},
thresholds = {
    { below = 0.40, color = '#F0E6C8FF' },
    { below = 1.01, color = '#FFAE32FF' },   -- catch-all, not a `default` key
},
```

`elementColors` is indexed 1-8 in element order and is applied in both pip states.
`thresholds` colours the percentage and is keyed on `pet.maneuver[N].norm`.

The ramp must end in a `{ below = 1.01 }` catch-all rather than carrying a `default` key: selene's
`mixed_table` rule rejects a string key beside array entries.

---

### `txt`, `recastTxt` -- fonts

```lua
txt       = { font = 'Segoe UI', size = 11, color = '#F0FFFFFF', zOrder = 6 },
recastTxt = {
    font          = 'Grammara',
    size          = 12,
    color         = '#F0FFFFFF',
    overloadColor = '#FF5A4BFF',
    pos           = {16, -22},
    zOrder        = 6,
},
```

`txt` is the per-row percentage font; it carries neither `pos` nor `align`. `recastTxt` is the
shared recast row above the pips, positioned by its own `pos` from the column origin.
`recastTxt.overloadColor` replaces `color` while Overload is up, when the row counts down Overload
instead of the maneuver recast.

---

### `background` -- optional column panel

```lua
background = {
    pos       = {-44, 0},
    imgTop    = { path = '...', size = {64, 6},  pos = {0, 0},  zOrder = 0 },
    imgMid    = { path = '...', size = {64, 18}, pos = {0, 6},  zOrder = 0 },
    imgBottom = { path = '...', size = {64, 6},  pos = {0, 24}, zOrder = 0 },
},
```

A 3-slice panel behind the pip rows, sized to the frame's height. All three slice tables are
required. `pos` moves the whole panel; the `pos` inside each slice is an offset within it.
`extraHeight` (optional) pads the panel's bottom edge past the frame's.

This section must carry **no** `sliceBorder`. Border values are texture pixels scaled by
`destH / nativeH`, so the frame's `{60, 60, 0, 0}` would exceed the narrow column's width and drop
the texture middle.

---

## Overload Label Keys (`petFrame.overload`)

```lua
overload = {
    pos          = {0, 0},
    raisedOffset = {0, -22},
    txt = {
        font = 'Penumbra Serif Std', size = 20, align = 'center',
        color = '#FF5A4BFF',
        pos   = {90, -30},   -- keep equal to special.txt.pos
        zOrder = 6,
        bind = {
            value   = 'pet.overloadLabel',
            visible = 'pet.overloadActive',
        },
    },
},
```

`raisedOffset` is applied only while `pet.specialActive`, lifting the label one line clear of the
2hr text so the two stack instead of overlapping. Absent means the label never leaves the 2hr slot.
It moves the text only -- section extras (`img`/`bg`) are positioned once at create and never
repositioned.

**Invariant:** `overload.pos + txt.pos` must equal `special.pos + txt.pos`. Both elements resolve
from the same base, so moving one without the other makes them silently drift apart.
