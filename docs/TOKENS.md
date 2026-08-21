# PetsReborn — Token & Style Binding Reference

---

## The Short Version

**You don't need to read this document to create a style.** Each layout file (`ffxi.lua`, `xiv.lua`)
is a complete self-contained table. Copy one, change what you want, save it as a new file in
`layouts/`, then select it in the config window (`/pr`).

```lua
-- layouts/myStyle.lua — a complete, valid style with no token knowledge required
return {
    petWindow = {
        name = {
            font = 'Arial', size = 18,
            color = '#FFFF00FF',              -- yellow name text
        },
        hp = {
            bar = {
                imgBar = { color = '#FF4444FF' },  -- red HP bar
            },
            thresholds = {                         -- custom threshold colors
                { below = 0.25, color = '#FF0000FF' },
                { below = 0.50, color = '#FF8800FF' },
            },
        },
    },
}
```

---

## Token Naming Convention

All multi-word token segments use **camelCase** — not underscores.

| Wrong (old design docs) | Correct |
|------------------------|---------|
| `pet.hpp_norm` | `pet.hppNorm` |
| `pet.tp_norm` | `pet.tpNorm` |
| `pet.mpp_active` | `pet.mppActive` |
| `pet.timer_active` | `pet.timerActive` |
| `pet.tp_full` | `pet.tpFull` |
| `pet.dist_far` | `pet.distFar` |
| `pet.dist_num` | `pet.distNum` |
| `target.hpp_norm` | `target.hppNorm` |
| `target.dist_far` | `target.distFar` |
| `charm.remaining_norm` | `charm.remainingNorm` |
| `jug.remaining_norm` | `jug.remainingNorm` |
| `avatar.recast[N].charges_norm` | not implemented (use charges/maxCharges) |

---

## How Styles Work

Layout files are loaded directly — no base+override merging. Each file is complete.

```lua
-- petsreborn.lua
local function loadLayout()
    local styleName = prSettings.layout or 'ffxi'
    local layoutPath = addon.path .. 'layouts/' .. styleName .. '.lua'
    if not ashita.fs.exists(layoutPath) then
        layoutPath = addon.path .. 'layouts/ffxi.lua'
    end
    local fn = loadfile(layoutPath)
    ...
end
```

`deepMerge` still exists in `utils.lua` but is not used during style loading.

---

## Anchor Declarations (Layout Feature)

Elements can declare `anchor` to position relative to another registered element:

```lua
tp = {
    anchor = {'mp', 'hp'},   -- try mp first; fall back to hp
    pos    = {0, 2},         -- offset from the resolved anchor
    ...
}
```

Registered anchors (populated at init, updated during relayout):
- `name` — name text element (registered if `name` section present)
- `hp` — HP bar origin (registered if `hp` section present)
- `mp` — MP bar origin (avatar and automaton only; nil when MP hidden or type inactive)
- `tp` — TP bar origin (nil when TP hidden or `tp` section absent)
- `petTimer` — 2hr/familiar countdown timer (registered if `petTimer` section present)
- `stay` — BST Stay counter (charm only; nil when Stay counter hidden or `stay` section absent)
- `recast` — first recast row position (nil if `recast` section absent)
- `window` — full window bounds `{x=0, y=0, h=layoutHeight}`; always registered; used by `targetBar` anchor (`window.bottom`)

`anchor = nil` or absent: position is relative to window origin (0, 0).

**All sections are optional.** Every layout section is nil-guarded in all modules. Omitting a section means those UI elements are not created. Anchors that reference a missing section fall through to their next fallback.

---

## Bind Table Syntax

The `bind` sub-table can appear on any element definition. All fields are optional.

```lua
hp = {
    pos  = {90, -7},
    bind = { visible = 'pet.active' },    -- composite-level visibility
    thresholds = { ... },                  -- shared by children
    bar = {
        bind = {
            value = 'pet.hppNorm',         -- animated bar fill (0-1)
            color = 'threshold',            -- inherited threshold colors
        },
    },
    txt = {
        bind = {
            value        = 'pet.hppPct',   -- display text (string or format string)
            color        = 'threshold',
            colorValue   = 'pet.hppNorm',  -- normalized input for threshold lookup
            defaultColor = '#F0FFFFFF',    -- applied when above all thresholds
        },
    },
}
```

> See `docs/BINDS.md` for the complete bind system reference, including all keys,
> format string syntax (`'{pet.tpStr} / 3000'`), and element support matrix.

| Bind property | Element | Notes |
|---|---|---|
| `visible` | all | Hides element when token is `false` |
| `visibleAnd` | all | Secondary visibility ANDed with `visible` |
| `value` | uiText, uiBar | Text: display string or `{token}` format. Bar: animated fill (0–1) |
| `color` | uiText, uiBar | `'threshold'` resolves from parent thresholds table |
| `colorValue` | uiText, uiBar | Normalized (0–1) input for threshold lookup; falls back to `value` |
| `defaultColor` | uiText, uiBar | `'#RRGGBBAA'` applied when above all thresholds (prevents stuck color) |

---

## Threshold Color System

When `bind.color = 'threshold'`, color is resolved
from the element's (or parent composite's) `thresholds` array:

```lua
thresholds = {
    default = '#RRGGBBAA',              -- optional: used when no entry matches
    { below = 0.25, color = '#FC8182FF' },   -- red
    { below = 0.50, color = '#F3F37CFF' },   -- yellow
    { below = 0.75, color = '#F8BA80FF' },   -- orange
},
```

Checked in order, first match (`tokenValue < t.below`) wins. No match → `thresholds.default`
→ `imgBar.color` (static fallback). Children inherit `thresholds` from parent composite unless
they define their own.

---

## Token Catalog

All tokens are always present with safe defaults (never nil). Types:
- **bool** — `true` or `false`
- **number** — integer or float
- **string** — text content
- **color** (not a bind target directly; resolved internally by threshold system)

---

### Core Pet Tokens

| Token | Type | Value |
|-------|------|-------|
| `pet.active` | bool | Pet entity is present, alive, and in range |
| `pet.serverId` | number | Pet entity server ID; `0` when inactive |
| `pet.type` | string | `'avatar'` \| `'charm'` \| `'jug'` \| `'wyvern'` \| `'automaton'` \| `''` |
| `pet.name` | string | Entity name — e.g. `'Carbuncle'`, `'Wyvern'` |
| `pet.level` | string | Pet level — e.g. `'75'`. Empty string when unknown. Charm: real mob level from `/check` packet. All others: player main job level |
| **HP (percent family — source: `pet.HPPercent` entity field)** | | |
| `pet.hpp` | number 0–100 | HP percent integer |
| `pet.hppNorm` | number 0–1 | HP normalized (hpp / 100). **`1.0` when `outOfRange`** |
| `pet.hppStr` | string | `'75'` integer only. **`'???'` when `outOfRange`** |
| `pet.hppPct` | string | `'75%'` with symbol. **`'???'` when `outOfRange`** |
| `pet.hpText` | string | What the HP row displays. `'1394'` for an automaton (exact HP from 0x0044), `hppPct` for every other type and whenever `automatonHpDisplay == 'percent'`. **`'???'` when `outOfRange`** |
| **MP (source: `player:GetPetMPPercent()`)** | | |
| `pet.mpp` | number 0–100 | MP percent; 0 when no MP pool |
| `pet.mppNorm` | number 0–1 | MP normalized |
| `pet.mppStr` | string | `'50'` |
| `pet.mpText` | string | What the MP row displays. `'209'` for an automaton (exact MP from 0x0044), `mppStr` for every other type |
| `pet.mppActive` | bool | `true` for an active avatar, an automaton whose frame has an MP pool (0x0044 `MaxMP > 0`, or no packet seen yet), and a charm with `mpp > 0` |
| **TP (source: `player:GetPetTP()`; values > 3000 clamped to 0)** | | |
| `pet.tp` | number 0–3000 | TP value |
| `pet.tpNorm` | number 0–1 | tp / 3000 (clamped to 1) |
| `pet.tpStr` | string | `'1500'` |
| `pet.tpPct` | string | `'50%'` |
| `pet.tpFull` | bool | `true` when tp >= 3000 |
| **Distance** | | |
| `pet.dist` | string | `'12.3'` — 1 decimal place. **`'>50'` when `outOfRange`** |
| `pet.distNum` | number | Raw float yalms. **`50.0` when `outOfRange`** |
| `pet.distFar` | bool | `true` when distance > 20 yalms or out of range |

**Out-of-range state**: When `PetTargetIndex` is set but the entity is not loaded (pet > 50
yalms away), `State.outOfRange = true`. The window remains visible with frozen HP but live
MP/TP (still readable from player memory) and live recasts (from recast memory).

---

### Pet Target Tokens

Available when `target.active == true` (pet has an active target that is not itself).

| Token | Type | Value |
|-------|------|-------|
| `target.active` | bool | Pet has a valid external target |
| `target.name` | string | Target entity name |
| `target.hpp` | number 0–100 | Target HP percent |
| `target.hppNorm` | number 0–1 | Normalized |
| `target.hppStr` | string | `'42'` |
| `target.hppPct` | string | `'42%'` |
| `target.dist` | string | `'8.5'` |
| `target.distNum` | number | Raw float yalms |
| `target.distFar` | bool | `true` when distance > 20 |

---

### Virtual Timer Tokens

| Token | Type | Resolves to (by `pet.type`) |
|-------|------|-----------------------------|
| `pet.timer` | string | `charm`: formatted remaining or `'??'` if unknown; `jug`: formatted remaining; SMN/DRG/PUP 2hr: countdown; `''` otherwise |
| `pet.timerActive` | bool | `true` when any timer is active (charm, jug, or 2hr special) |
| `pet.specialActive` | bool | `true` when a 2hr/special ability timer is running (Astral Flow, Spirit Surge, Overdrive, Familiar) |
| `pet.specialName` | string | Name of the active special — `'Astral Flow'` \| `'Spirit Surge'` \| `'Overdrive'` \| `'Familiar'` \| `''` |

**Timer routing priority** (first match wins):
1. SMN Astral Flow (`afRemaining > 0`) — `specialActive=true`, `specialName='Astral Flow'`
2. DRG Spirit Surge (`ssRemaining > 0`) — `specialActive=true`, `specialName='Spirit Surge'`
3. PUP Overdrive (`odRemaining > 0`) — `specialActive=true`, `specialName='Overdrive'`
4. BST Familiar (`familiar.expireTime ~= nil`, charm/jug active) — `specialActive=true`, `specialName='Familiar'`; `pet.timer` counts up (`+M:SS`) after familiar expires while pet lives
5. BST Charm (`petType == 'charm'`) — `specialActive=false`; `pet.timer = '??'` until known from `/check`
6. BST Jug (`petType == 'jug'`) — `specialActive=false`; `pet.timer` = remaining duration
7. None — `pet.timer = ''`, `pet.timerActive = false`, `pet.specialActive = false`

---

### Virtual Recast Tokens

Routed from the active type's specific recast array. Slots N = 1–6.

| Token | Resolves to |
|-------|------------|
| `pet.recast[N].name` | e.g. `avatar.recast[N].name` for current type |
| `pet.recast[N].time` | Formatted timer string, or `'Ready'` |
| `pet.recast[N].norm` | 0–1 progress (0 = freshly used, 1 = ready) |
| `pet.recast[N].ready` | bool |
| `pet.recast[N].charges` | int (0 for non-charge abilities) |
| `pet.recast[N].maxCharges` | int (0 for non-charge abilities) |
| `pet.recast[N].active` | bool — slot N is populated for the current type |

---

### Avatar Tokens (SMN)

Available when `pet.type == 'avatar'`. Slots N = 1–6.

| Token | Type | Value |
|-------|------|-------|
| `avatar.recast[N].name` | string | `'BP: Rage'`, `'BP: Ward'`, etc. or `''` |
| `avatar.recast[N].time` | string | `'1:30'` or `'Ready'` |
| `avatar.recast[N].norm` | number 0–1 | Recharge progress (1 = ready) |
| `avatar.recast[N].ready` | bool | Recast == 0 |
| `avatar.recast[N].charges` | number | Always 0 (avatar BPs are not charge abilities in v1) |
| `avatar.recast[N].maxCharges` | number | Always 0 |
| `avatar.recast[N].active` | bool | Slot N is populated |

---

### Jug Pet Tokens (BST Jug)

Available when `pet.type == 'jug'`. Slots N = 1–3 (Ready / Reward / Call Beast).

| Token | Type | Value |
|-------|------|-------|
| `jug.name` | string | Jug pet name (e.g. `'CourierCarrie'`) |
| `jug.remaining` | string | `'45:30'` countdown — formatted via `_formatTimer` |
| `jug.remainingNorm` | number 0–1 | `remaining / duration` |
| `jug.elapsed` | string | `''` (not implemented in v1) |
| `jug.expired` | bool | `true` when `os.time() >= expireTime` |
| `jug.recast[1].name` | string | `'Ready'` |
| `jug.recast[1].charges` | number | 0–3 (charge ability) |
| `jug.recast[1].maxCharges` | number | 3 |
| `jug.recast[N].name` | string | `'Reward'`, `'Call Beast'` for N=2,3 |
| `jug.recast[N].ready` | bool | |
| `jug.recast[N].active` | bool | |

---

### Charm Tokens (BST Charmed Mob)

Available when `pet.type == 'charm'`.

| Token | Type | Value |
|-------|------|-------|
| `charm.known` | bool | Duration was calculated from mob level check |
| `charm.remaining` | string | `'12:30'` or `'??'` if unknown |
| `charm.remainingNorm` | number 0–1 | `remaining / totalDuration`; 0 when unknown |
| `charm.elapsed` | string | `''` (not implemented in v1) |
| `charm.urgent` | bool | `true` when remaining < 60 seconds |
| `charm.recast[1].name` | string | `'Sic'` |
| `charm.recast[2].name` | string | `'Reward'` |
| `charm.recast[N].ready` | bool | |
| `charm.recast[N].active` | bool | |

---

### BST Stay Tokens

Available for both `charm` and `jug` pet types. Tracks the Stay command tick counter.

| Token | Type | Value |
|-------|------|-------|
| `bst.stayActive` | bool | `true` when BST Stay command is active (pet held in place) |
| `bst.stayTicks` | string | Seconds remaining on the active Stay tick; `'--'` when inactive |

The Stay recast row is always visible when the pet is active, showing `--` when Stay is not in progress.

---

### Wyvern Tokens (DRG)

Available when `pet.type == 'wyvern'`. Slots N = 1–3 (Call Wyvern / Spirit Link / Steady Wing).

| Token | Type | Value |
|-------|------|-------|
| `wyvern.recast[N].name` | string | Ability name |
| `wyvern.recast[N].time` | string | `'0:30'` or `'Ready'` |
| `wyvern.recast[N].norm` | number 0–1 | Recharge progress |
| `wyvern.recast[N].ready` | bool | Ability available |
| `wyvern.recast[N].active` | bool | Slot populated |

---

### Automaton Tokens (PUP)

Available when `pet.type == 'automaton'`. Slots N = 1–6.

| Token | Type | Value |
|-------|------|-------|
| `automaton.recast[N].name` | string | `'Activate'`, `'Repair'`, `'Deploy'`, etc. |
| `automaton.recast[N].time` | string | `'0:45'` or `'Ready'` |
| `automaton.recast[N].norm` | number 0–1 | Recharge progress |
| `automaton.recast[N].ready` | bool | |
| `automaton.recast[N].active` | bool | Slot populated |

---

### Maneuver Tokens (PUP)

Elements N = 1-8, in `data/maneuvers.lua` order: 1 fire, 2 ice, 3 wind, 4 earth, 5 thunder,
6 water, 7 light, 8 dark.

Emitted for every pet type, not just `automaton`, and zeroed when the player owns no automaton.
Overload outlives the automaton, so these keep counting down after Deactivate.

| Token | Type | Value |
|-------|------|-------|
| `pet.maneuver[N].pct` | number | Overload chance for that element; 0 when unknown |
| `pet.maneuver[N].norm` | number 0-1 | `pct / 100`, clamped. What a threshold ramp keys on |
| `pet.maneuver[N].count` | number | How many maneuvers of that element are active |
| `pet.maneuver[N].active` | bool | `count > 0` |
| `pet.maneuver[N].burdened` | bool | `pct > 0` |
| `pet.maneuver[N].element` | string | `'fire'`, `'ice'`, `'wind'`, `'earth'`, `'thunder'`, `'water'`, `'light'`, `'dark'` |
| `pet.maneuver[N].remaining` | number | Seconds until the soonest maneuver of that element drops; 0 = none up or unknown |

Column-wide tokens:

| Token | Type | Value |
|-------|------|-------|
| `pet.maneuverCount` | number | Maneuvers active across all eight elements combined |
| `pet.maneuverRecast` | string | Formatted shared-recast timer, or `'Ready'` |
| `pet.maneuverRecastNorm` | number 0-1 | Recast progress (1 = ready) |
| `pet.maneuverReady` | bool | Shared recast is 0 |
| `pet.maneuverUsable` | bool | `false` while Overload is up |
| `pet.overloadActive` | bool | Overload is on the player |
| `pet.overloadLabel` | string | `'OVERLOAD'` |
| `pet.overloadRemaining` | number | Seconds of Overload remaining |
| `pet.overloadTimer` | string | `'--'`, `'0:00'`, or `'M:SS'` |
| `pet.overdriveActive` | bool | Overdrive is on the player |

`pct` is the server's reported overload chance, less the burden decayed since it was reported.
The addon never computes a chance. Decay is 1 point per 3s tick, plus 1 per active Water
Maneuver while Heatsink is attached.

During Overdrive the server reports 0 for every maneuver, so the column reads clean through that
window and re-anchors on the first report after it drops.

`pct` and `count` are independent -- an element can carry burden with no maneuver up.

`overloadTimer` distinguishes `'--'` (no expiry known, e.g. the addon loaded mid-Overload) from
`'0:00'`.

---

### UI Visibility Tokens

Injected by `petsreborn.lua` after `buildTokenTable()`. Values come directly from
`prSettings` — they are not part of the game state and cannot be set from style files.

| Token | Type | Source |
|-------|------|--------|
| `ui.showMpBar` | bool | `prSettings.showMpBar` — hides MP bar; TP/recast cascade via posRegistry |
| `ui.showTpBar` | bool | `prSettings.showTpBar` — hides TP bar |
| `ui.showRecasts` | bool | `prSettings.showRecasts` — hides all recast rows across all pet types |
| `ui.showTargetBar` | bool | `prSettings.showTargetBar` — hides target sub-window |
| `ui.showManeuvers` | bool | `prSettings.showManeuvers` -- hides the PUP maneuver column |
| `pet.statusActive` | bool | `true` when pet has active status effects OR `hideStatusWhenEmpty == false` |
| `pet.alwaysShow` | bool | Computed: `alwaysShow==true AND no active pet AND valid job` |

These tokens drive module-level visibility decisions. `ui.showRecasts = false` overrides all
per-ability `recastVisible` settings — the whole recast section disappears.

The layout `bind.visible = 'ui.showRecasts'` on the `recast` section is the canonical way to
declare this in style files; the actual gating is enforced in each type module's `update()`.

---

## Timer Format

`State._formatTimer(seconds)`:
- `seconds <= 0` → `'Ready'`
- Otherwise → `'M:SS'` (e.g. `'1:30'`, `'0:05'`, `'12:00'`)

---

## Style Examples

### Minimal: Colors Only

Omitting sections entirely is valid — those elements simply won't render.

```lua
-- layouts/darkTheme.lua
return {
    petWindow = {
        name = { color = '#FFD700FF', size = 16 },
        hp = {
            bar = { imgBar = { color = '#CC2222FF' } },
            thresholds = {
                { below = 0.20, color = '#FF0000FF' },
                { below = 0.40, color = '#FF6600FF' },
            },
        },
        mp = { bar = { imgBar = { color = '#2266CCFF' } } },
        tp = {
            bar          = { imgBar = { color = '#44AA44FF' } },
            tpFullColor  = '#88FF88FF',
        },
        -- recast, stay, statusEffects omitted → those elements not rendered
    },
    targetBar = {
        hp = { bar = { imgBar = { color = '#CC2222FF' } } },
    },
}
```

### Advanced: Data Remapping

Show TP in the MP slot (e.g., when you want a visible TP bar for jug/charm types
without MP that still have the MP slot position available in the layout):

```lua
mp = {
    bar = {
        imgBar = { color = '#8EB4F9FF' },
        bind   = { value = 'pet.tpNorm' },    -- fill from TP instead of MP
    },
},
```

---

## What Changed vs. Original Design Docs

| Original | Actual |
|---|---|
| `layouts/default.lua` + deep merge | Each style file is standalone; no default.lua |
| Token names use `_` separators | Token names use camelCase |
| `pet.timer_active` | `pet.timerActive` |
| `pet.hp_color` (virtual color token) | Not implemented; use `bind.color = 'threshold'` |
| `pet.hp`, `pet.hp_max`, `pet.hp_frac` | Not implemented in v1 (require party data) |
| `pet.mp`, `pet.mp_max`, `pet.mp_frac` | Not implemented in v1 |
| `avatar.recast[N].charges_norm` | Not implemented (use `charges` / `maxCharges` directly) |
| `jug.elapsed`, `charm.elapsed` | Tokens present but always `''` |
| `bind.color = color_token` | Partially supported; `'threshold'` is the primary use |
| No out-of-range state | `pet.hppNorm=1`, `pet.hppStr/hppPct='???'`, `pet.dist='>50'` when out of range |
| `charm.stayActive` / `charm.stayTicks` | Actual token is `bst.stayTicks` (string, `'--'` when inactive); no bool token |
| `ui.*` tokens | New — injected by orchestrator for component visibility toggles |
| `pet.alwaysShow` | New — computed by orchestrator for always-show recast mode |
| `pet.serverId` | New — pet entity server ID |
| `pet.specialActive` / `pet.specialName` | New — 2hr/special ability timer state |
| `bind.text` / `bind.barColor` | Renamed to `bind.value` / `bind.color` (unified across uiText and uiBar) |
| `bind.colorValue` / `bind.defaultColor` | Expanded to uiBar (previously uiText only) |
