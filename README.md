# PetsReborn

**An FFXI addon for HorizonXI (Ashita v4) that gives every pet job a full pet window HUD.**

PetsReborn draws a pet frame with HP/MP/TP, distance, status effects, and job-specific
readouts for all four pet jobs — SMN avatars, DRG wyverns, PUP automatons, and BST jug
and charmed pets. Everything is driven by a layout file, so the whole HUD can be
restyled without touching addon code.

---

<img width="1202" height="539" alt="petsrebornhud" src="https://github.com/user-attachments/assets/6694825f-a4f0-484f-af36-1ccd33dd9385" />

---

## Installation

1. Extract the `PetsReborn` folder into `Ashita4/addons/`
2. Install both fonts below
3. `/addon load PetsReborn`

> [!IMPORTANT]
> **The screenshot above will not look like that without the fonts.** The bundled layouts
> use two typefaces that do not ship with Windows. If either is missing, GDI silently
> substitutes a default face and the HUD's spacing and weight will be visibly wrong.

### Fonts

Install both from the release page:

- **Grammara**
- **Penumbra Serif Std**

The `default` and `Segoe UI` text in the layouts uses fonts Windows already provides.

## Features

- **All four pet jobs** — avatar, wyvern, automaton, and jug/charm pets each get their
  own module with the readouts that job actually cares about
- **Ability recast rows** — blood pact, wyvern breath, maneuver, and ready timers
- **PUP maneuver column** — active maneuvers plus live overload/burden tracking
- **Automaton internal cooldowns** — the latency its head enforces between casts, Shield Bash
  on a Valoredge frame, and its attachment ability recasts, none of which the client exposes
- **BST timers** — jug pet duration and charm duration, with jug timers surviving a zone
- **Pet status effects** — buffs and debuffs on your pet with real durations
- **Target frame** — what your pet is engaged with
- **Three bundled layouts** — `ffxi`, `xiv`, and `indoSpecial`; drop a new file in
  `layouts/` to add your own
- **In-game layout editor** and a config window for anchor, scale, and style selection

## Commands

| Command | Effect |
|---------|--------|
| `/petsreborn` or `/pr` | Toggle the config window |
| `/petsreborn help` | List commands |
| `/petsreborn reload` | Reload layout and settings |
| `/petsreborn debug` | Print current pet state to chat |

## Customising a layout

You do not need to understand the token system to build a style. Create a file under a new
name in `layouts/`, list only what you want to change, and select it in the config window:

```lua
-- layouts/myStyle.lua
return {
    extends = 'ffxi',
    petFrame = {
        hp = { bar = { imgBar = { color = '#FF4444FF' } } },
        statusEffects = { pos = {10, 4} },
    },
}
```

`extends` names another style in `layouts/`; that style is loaded first (following its own
`extends`, if any) and each value in your file is merged over the parent's value at the
same key:

- A value that is not a table (number, string, `true`/`false`) replaces the parent's.
- A table with a `[1]` entry is a full list and replaces the parent's value whole: give
  `pos`, `size`, `sliceBorder`, an `anchor` list, `thresholds` or `elementColors` in full
  to set all of it.
- Any other table — named keys, a sparse patch such as `{[5] = '#FF4444FF'}` or
  `{nil, 4}`, or `{}` — patches the parent's value: it starts from the parent's table (or
  an empty one when the parent has none there) and merges each of its keys by these same
  rules. So `imgBar = { color = ... }` keeps the parent's `path`, `size` and the rest of
  `imgBar`; a child `bind` changes only the keys it lists; `elementColors = {[5] = ...}`
  recolours one element; `pos = {nil, 4}` sets only the second coordinate;
  `thresholds = { default = ... }` adds a catch-all to the inherited ramp; `{}` changes
  nothing.
- The merged layout is built from copies: two keys that share one table in your file are
  independent after loading, and the parent style is unchanged.
- An inherited key cannot be removed. `false` is copied like any other value (keys such
  as `bold = false` are ordinary settings), so setting a section to `false` does not
  remove it and is unsupported. To drop a section, write a full layout instead.

A file without `extends` is a complete layout on its own; copying `layouts/ffxi.lua` and
editing it still works. `layouts/ffxi.lua` documents every key. If the selected style or
any style it extends fails to load — missing, broken, or an `extends` cycle — the error is
printed and the `ffxi` layout is shown instead. If `ffxi` itself fails to load, its error
is printed and no pet window is drawn. Changes made in the in-game layout editor are saved
per style and apply on top of the merged layout.

- [`docs/TOKENS.md`](docs/TOKENS.md) — every token a layout can bind
- [`docs/BINDS.md`](docs/BINDS.md) — which element consumes which binding

## License

**GPL-3.0** — see [LICENSE](LICENSE).

PetsReborn bundles libraries under three licenses. The status library is GPL-3.0, and
because it is loaded into the same Lua state rather than merely shipped alongside, the
combined work is GPL-3.0 as a whole. Each library keeps its own notice:

| Path | License | Copyright |
|---|---|---|
| everything not listed below | GPL-3.0 | © 2026 Zaldas |
| [`libs/status/`](libs/status/LICENSE) | GPL-3.0 | © 2023 tirem — `statusicons.lua` also draws on statustimers, © 2022 Heals |
| [`libs/spui/`](libs/spui/LICENSE) | BSD 3-Clause | © 2023 Tylas ([XivParty](https://github.com/Tylas11/XivParty)) |
| [`libs/gdifonts/`](libs/gdifonts/LICENSE) | MIT | © 2023 Thorny |

`libs/spui/classes.lua` is in turn based on Paul Moore's classes library, © 2011 Strange
Ideas Software (MIT).

## Acknowledgements

- **[Tylas11](https://github.com/Tylas11/XivParty)** — the sprite library PetsReborn's
  rendering is built on, and the visual direction the HUD follows
- **[Thorny](https://github.com/ThornyFFXI)** and **[atom0s](https://github.com/atom0s)** —
  for everything they do for Ashita and the wider FFXI community
- **[tirem](https://github.com/tirem/XIUI)** — the status effect tracking library in
  `libs/status/`, and XIUI as pet bar inspiration
- **[PetMe](https://github.com/m4thmatic/PetMe)** — pet bar inspiration
