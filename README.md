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
- **Automaton internal cooldowns** — the latency its head enforces between casts, and its
  attachment ability recasts, neither of which the client exposes
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
| `/petsreborn reload` | Reload layout and settings |
| `/petsreborn debug` | Print current pet state to chat |

## Customising a layout

You do not need to understand the token system to build a style. Copy `layouts/ffxi.lua`,
change what you want, save it under a new name in `layouts/`, and select it in the config
window.

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
