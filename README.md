# Hyprforge

A Hyprland studio for [Omarchy](https://omarchy.org). Every visual and behavioural
knob Hyprland has, with a live scale model of your desktop, theme-aware colors,
an animation curve editor, per-app rules, profiles and full history. Everything
previews instantly on your real windows and is checked by Hyprland before it's saved.

![Hyprforge](preview.png)

## Install

```bash
omarchy plugin add https://github.com/AbdulazizAlwabel/omarchy-hyprforge --enable --yes
```

Open it with **SUPER+SPACE › Hyprforge** or `omarchy-shell hyprforge toggle`.

**First run — one line, only with your consent.** Hyprforge writes its settings to
its own file, `~/.config/hypr/hyprforge.lua`. Hyprland only reads that file once
`~/.config/hypr/hyprland.lua` loads it, so the panel shows a **Connect** button
the first time. Clicking it adds a single optional-require line. A full backup
(`hyprland.lua.bak.hyprforge-XXXXXX`) is written first, and the edit is skipped
if the backup fails or the file changed since the panel read it; a symlinked
dotfile stays a symlink. Nothing else in your config is ever edited, and nothing
is changed until you click Connect.

Requirements: Omarchy 4 (Quattro) with Hyprland ≥ 0.56 (Lua config) and `lua`
(already a Hyprland dependency). No network access, no sudo.

## What's inside

| Section | Highlights |
|---|---|
| **Overview** | Live model of your screen (your wallpaper, bar, layout, gaps, borders, rounding, shadow, glow, blur, opacity, dim; click windows to move focus), 9 one-click **Looks**, 7 **Motion** presets, and a list of everything you've changed |
| **Windows & Gaps** | Inner/outer gaps (uniform or per side), workspace and floating gaps, border width, **smart gaps** and **smart borders** (none on a lone window), resize-on-border, snapping |
| **Borders & Colors** | Gradient builder using **theme palette names** (accent, cyan, magenta, …) plus alpha and angle, a **rotating gradient**, group/locked/no-group borders |
| **Corners** | Rounding and squircle power |
| **Opacity** | Omarchy's own per-window opacity rule (make windows fully opaque or glassy), focused/unfocused/fullscreen multipliers |
| **Dimming** | Dim unfocused, strength, behind scratchpad, dim-around, dialogs |
| **Blur** | Everything in `decoration:blur`, **frosted glass behind the Omarchy bar/menus/notifications**, motion blur |
| **Shadow / Glow** | Size, falloff, sharpness, scale, offset, and palette-tinted colors for focused and unfocused windows |
| **Animations** | Global speed multiplier, presets, per-animation enable/duration/curve/style (popin %, slidefade %), and a **curve studio**: drag bezier handles or build a physical spring, then play it back |
| **Layout** | Dwindle / Master / Scrolling / Monocle, with only the active engine's options shown; lone-window aspect ratio for ultrawides |
| **Groups & Tabs** | Tab bar size, fonts, fill, rounding, indicator, palette colors, grouping behaviour |
| **Keyboard & Mouse** | Repeat rate/delay, pointer speed, acceleration, natural scroll, focus-follows-mouse, full touchpad setup |
| **Cursor & Zoom** | Screen magnifier, hide when idle/typing, warping |
| **Gestures** | Workspace swipe distance, threshold, flick speed, direction |
| **Behavior & Performance** | Focus stealing, VRR, swallowing, fullscreen handling, scratchpad, DPMS wake, direct scanout |
| **App Rules** | Pick a running app → opacity, blur, shadow, dim, rounding, border (palette color), float, center, size, pin, workspace, monitor, idle inhibit, animation style, screen-share hiding, scroll speed and more |
| **Profiles & History** | Save/apply/share profiles, import from clipboard, restore any applied change, copy the generated Lua |
| **Every option** | All ~350 Hyprland options straight from `hyprctl descriptions`, filterable by group |

Global search (`/`) covers all of it.

## Colors follow your theme

Colors are stored as palette names, not hex. The generated Lua reads the active
theme's `colors.toml` every time Hyprland loads, and `omarchy theme set` reloads
Hyprland, so borders, shadows, glow and tab colors re-color themselves with
every theme. The panel itself uses the shell's theme tokens. A fixed `#hex` is
still available when you want one.

## Keys

| | |
|---|---|
| `Tab` / `Shift+Tab`, `1`–`9` | sections |
| `j` `k` / `↑` `↓` | rows |
| `h` `l` / `←` `→` | adjust (`Shift` = ×10) |
| `Space` / `Enter` | toggle / next choice |
| `Backspace` | reset the row to Omarchy |
| `/` or `Ctrl+F` | search |
| `Ctrl+Z`, `Ctrl+Shift+Z` | undo, redo |
| `P` | peek at the desktop (panel goes see-through) |
| `A` | show/hide advanced options |
| `Esc` | clear search / close |

## Scripting and keybindings

```bash
omarchy-shell hyprforge toggle
omarchy-shell hyprforge section blur            # open at a section
omarchy-shell hyprforge profile "Gaming"        # apply a saved profile
omarchy-shell hyprforge cycleProfile
omarchy-shell hyprforge saveProfile "Work"
omarchy-shell hyprforge look glass              # stock glass neon soft flat zen compact retro performance
omarchy-shell hyprforge motion bouncy           # omarchy snappy smooth bouncy slide fade minimal
omarchy-shell hyprforge set decoration:rounding 12
omarchy-shell hyprforge unset decoration:rounding
omarchy-shell hyprforge reset                   # back to stock
```

Example binding for `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + ALT + P", "Next Hyprforge profile", "omarchy-shell hyprforge cycleProfile")
```

## How it works and why it's safe

* **One file, one line.** Settings live in `~/.config/hypr/hyprforge/state.json`
  (with profiles; history is in `history.json`). They are rendered to
  `~/.config/hypr/hyprforge.lua`, which `hyprland.lua` loads with a single
  optional require (added only when you click Connect) placed after your own
  files and before Omarchy's toggles, so toggles like "no gaps" still work.
  Remove the plugin and nothing breaks.
* **Live preview** sends the same Lua to `hyprctl eval`, so what you see while
  dragging is exactly what gets saved.
* **Checked before saved.** Every commit is type-checked, then dry-run through
  `hyprctl eval`. Only if Hyprland accepts it is the file written and Hyprland
  reloaded. If a reload still reports an error from `hyprforge.lua`, the last
  good state is restored automatically. (A reload-time config error can make
  Hyprland draw its error bar, which on some systems freezes the compositor —
  that is why validation happens first.)
* **Colors never pinned.** Unlike writing `general:col.*` into
  `looknfeel.lua`, palette names keep `omarchy theme set` working.
* **Omarchy's defaults stay visible.** Changed rows show what the value was
  underneath (`was 5px`), captured by the generated Lua at load time.

## Optional: menu entry and keybinding

Turn **Menu › Style › Hyprland** into a submenu by adding this to
`~/.config/omarchy/extensions/omarchy-menu.jsonc` (reusing the id with no
`action` makes it a submenu; the original editor moves into a child):

```jsonc
"style.hyprland": {"icon":"","label":"Hyprland","aliases":["hyprland","looknfeel"]},
"style.hyprland.hyprforge": {"icon":"󱌣","label":"Hyprforge Studio","aliases":["hyprforge"],"action":"omarchy-shell shell toggle aziz.hyprforge '{}'"},
"style.hyprland.edit": {"icon":"󰏫","label":"Edit looknfeel.lua","action":"omarchy-launch-config-editor \"$HOME/.config/hypr/looknfeel.lua\""}
```

A key to open it, in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + ALT + H", "Hyprforge", "omarchy-shell shell toggle aziz.hyprforge '{}'")
```

## Uninstall

1. `omarchy-shell hyprforge reset` — returns Hyprland to your own config (optional; your profiles are kept in `~/.config/hypr/hyprforge/`).
2. In the panel, **Profiles & History › Disconnect from Hyprland**, or delete the line containing `hypr.hyprforge` from `~/.config/hypr/hyprland.lua`.
3. `omarchy plugin remove aziz.hyprforge --yes`
4. Optionally delete `~/.config/hypr/hyprforge.lua`, `~/.config/hypr/hyprforge/` and `~/.cache/hyprforge/`.

The launcher entry (`~/.local/share/applications/hyprforge.desktop`) is removed
automatically when the plugin is disabled or removed.

## Development

```
manifest.json        panel + service
Panel.qml            state, preview/commit pipeline, window, keyboard
Service.qml          launcher entry + `omarchy-shell hyprforge …` IPC
Schema.js            curated catalogue (208 options, 19 sections)
Engine.js            validation, Lua renderer, presets, curves, rules, hook
baseline.lua         reads Omarchy's stock animations with recording stubs
components/          OptionRow, PaletteEditor, PreviewCanvas, CurveEditor, views…
test/run.js          node test/run.js   — offline: catalogue vs Hyprland, Lua syntax, presets
test/live.js         node test/live.js  — dry-runs every preset in the running Hyprland via `hyprctl eval`
```

Plugin QML is cached by URL, so after editing run `omarchy restart shell`.

## License

MIT — see [LICENSE](LICENSE).
