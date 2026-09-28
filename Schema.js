.pragma library

// Hyprforge's curated catalogue.
//
// Every entry names a real Hyprland option (checked against `hyprctl
// descriptions` by test/run.js) or an `hf:` synthetic that Engine.js turns
// into rules/animations. Anything not listed here is still reachable from the
// "Every option" section, which is built at runtime from `hyprctl descriptions`.
//
// Item fields
//   key        Hyprland option path (`section:sub:name`), or `hf:*`
//   label      row title
//   desc       one-line explanation
//   type       bool | int | float | enum | text | gaps | vec2 | color | gradient
//   min/max    comfortable slider range (not Hyprland's hard limit)
//   step       slider/keyboard step; decimals for display
//   unit       suffix shown after the value
//   options    enum choices [{ value, label }]
//   needs      key of a bool that must be on for the row to be live
//   needsValue with `needs`: the row only shows when that key equals this
//   advanced   collapsed behind "Show advanced" in its section
//   keywords   extra search terms
//   preview    true when the mock desktop should show for this section

var I = {
  home: "\u{F02DC}", window: "\u{F05B2}", border: "\u{F00CE}", corner: "\u{F14FC}",
  opacity: "\u{F05CC}", dim: "\u{F00DD}", blur: "\u{F00B5}", shadow: "\u{F0637}",
  glow: "\u{F0674}", anim: "\u{F0A90}", layout: "\u{F0574}", group: "\u{F04E9}",
  input: "\u{F097B}", cursor: "\u{F01BF}", gesture: "\u{F0ABF}", misc: "\u{F08BB}",
  rules: "\u{F0B60}", all: "\u{F062E}", profiles: "\u{F0E16}", palette: "\u{F03D8}",
  workspace: "\u{F0A1D}", undo: "\u{F054C}", redo: "\u{F044E}", reset: "\u{F0450}",
  close: "\u{F0156}", plus: "\u{F0415}", trash: "\u{F0A7A}", play: "\u{F040A}",
  check: "\u{F012C}", search: "\u{F0349}", warn: "\u{F0026}", link: "\u{F0337}",
  up: "\u{F0143}", down: "\u{F0140}", copy: "\u{F018F}", export: "\u{F0207}",
  history: "\u{F02DA}", star: "\u{F04CE}", bolt: "\u{F140B}", expand: "\u{F084E}", save: "\u{F0193}", forge: "\u{F1323}", eye: "\u{F0208}"
}

function it(key, label, desc, type, extra) {
  var o = { key: key, label: label, desc: desc || "", type: type }
  if (extra) for (var k in extra) o[k] = extra[k]
  return o
}

function opts(pairs) {
  var out = []
  for (var i = 0; i < pairs.length; i += 2) out.push({ value: pairs[i], label: pairs[i + 1] })
  return out
}

var SECTIONS = [
  {
    id: "home", icon: I.home, title: "Overview", view: "home",
    blurb: "Live preview, one-click looks and everything you've changed."
  },
  {
    id: "windows", icon: I.window, title: "Windows & Gaps", preview: true,
    blurb: "Space around windows, border thickness and how floating windows snap.",
    items: [
      it("general:gaps_in", "Inner gaps", "Space between neighbouring windows.", "gaps", { min: 0, max: 40, unit: "px" }),
      it("general:gaps_out", "Outer gaps", "Space between windows and the screen edge. Expand for per-side values.", "gaps", { min: 0, max: 80, unit: "px" }),
      it("general:gaps_workspaces", "Workspace gaps", "Extra space between workspaces while they slide.", "int", { min: 0, max: 100, unit: "px" }),
      it("general:float_gaps", "Floating gaps", "Gap kept around floating windows at the screen edge.", "gaps", { min: 0, max: 40, unit: "px", advanced: true }),
      it("general:border_size", "Border width", "Thickness of every window border.", "int", { min: 0, max: 12, unit: "px" }),
      it("decoration:border_part_of_window", "Border inside window", "Count the border as part of the window instead of drawing it around it.", "bool"),
      it("hf:smart_gaps", "Smart gaps", "Drop gaps when a workspace has a single tiled window.", "bool", { keywords: "single one window no gaps" }),
      it("hf:smart_borders", "Smart borders", "Drop the border and rounding on a lone tiled window.", "bool", { keywords: "single one window no border" }),
      it("general:resize_on_border", "Resize from borders", "Drag a border or gap to resize windows.", "bool"),
      it("general:extend_border_grab_area", "Border grab area", "Extra grab margin around borders for resizing.", "int", { min: 0, max: 40, unit: "px", needs: "general:resize_on_border" }),
      it("general:hover_icon_on_border", "Resize cursor on hover", "Show a resize cursor over borders.", "bool", { needs: "general:resize_on_border" }),
      it("general:resize_corner", "Floating resize corner", "Force a corner for resizing floating windows.", "enum",
         { options: opts([0, "Nearest", 1, "Top left", 2, "Top right", 3, "Bottom right", 4, "Bottom left"]), advanced: true }),
      it("general:snap:enabled", "Snapping", "Snap floating windows to each other and to screen edges.", "bool"),
      it("general:snap:window_gap", "Snap to windows", "Distance at which floating windows snap together.", "int", { min: 0, max: 50, unit: "px", needs: "general:snap:enabled" }),
      it("general:snap:monitor_gap", "Snap to edges", "Distance at which floating windows snap to screen edges.", "int", { min: 0, max: 50, unit: "px", needs: "general:snap:enabled" }),
      it("general:snap:border_overlap", "Overlap borders", "Snap so only one border's width sits between windows.", "bool", { needs: "general:snap:enabled" }),
      it("general:snap:respect_gaps", "Respect gaps", "Keep the gap size when snapping.", "bool", { needs: "general:snap:enabled" }),
      it("general:allow_tearing", "Allow tearing", "Master switch for screen tearing (games with the immediate rule).", "bool", { advanced: true }),
      it("general:no_focus_fallback", "No focus fallback", "Don't jump to another window when moving focus into empty space.", "bool", { advanced: true }),
      it("general:modal_parent_blocking", "Block modal parents", "Parents of dialogs can't be clicked while the dialog is open.", "bool", { advanced: true })
    ]
  },
  {
    id: "borders", icon: I.border, title: "Borders & Colors", preview: true,
    blurb: "Border colors are picked by palette name, so they re-resolve whenever you change theme.",
    items: [
      it("general:col.active_border", "Focused border", "Gradient drawn around the focused window.", "gradient", { keywords: "active color gradient accent" }),
      it("general:col.inactive_border", "Unfocused border", "Color around every other window.", "gradient", { keywords: "inactive color" }),
      it("hf:border_rotate", "Rotating gradient", "Spin the focused border's gradient continuously. Renders every frame, so it costs some power.", "bool", { keywords: "animate angle loop rainbow" }),
      it("hf:border_rotate_speed", "Rotation time", "Seconds for one full turn.", "float", { min: 1, max: 30, step: 0.5, decimals: 1, unit: "s", needs: "hf:border_rotate" }),
      it("group:col.border_active", "Group border (focused)", "Border of the focused window in a group.", "gradient", { advanced: true }),
      it("group:col.border_inactive", "Group border (unfocused)", "Border of unfocused grouped windows.", "gradient", { advanced: true }),
      it("group:col.border_locked_active", "Locked group (focused)", "Border of a focused window in a locked group.", "gradient", { advanced: true }),
      it("group:col.border_locked_inactive", "Locked group (unfocused)", "Border of unfocused windows in a locked group.", "gradient", { advanced: true }),
      it("general:col.nogroup_border_active", "No-group border (focused)", "Focused window that can't join a group.", "gradient", { advanced: true }),
      it("general:col.nogroup_border", "No-group border (unfocused)", "Unfocused window that can't join a group.", "gradient", { advanced: true })
    ]
  },
  {
    id: "corners", icon: I.corner, title: "Corners", preview: true,
    blurb: "Window corner radius. The Omarchy bar, menus and panels follow it too.",
    items: [
      it("decoration:rounding", "Rounding", "Corner radius. 0 is square.", "int", { min: 0, max: 30, unit: "px" }),
      it("decoration:rounding_power", "Roundness curve", "2 is a circular arc; higher values give a squircle.", "float", { min: 2, max: 10, step: 0.1, decimals: 1 })
    ]
  },
  {
    id: "opacity", icon: I.opacity, title: "Opacity", preview: true,
    blurb: "Translucency. Pair it with Blur for a frosted-glass look.",
    items: [
      it("hf:base_active", "Base focused opacity", "Omarchy's own per-window rule (0.985 stock). Set to 1 for fully opaque windows.", "float", { min: 0.5, max: 1, step: 0.005, decimals: 3, keywords: "omarchy default translucent glass" }),
      it("hf:base_inactive", "Base unfocused opacity", "Omarchy's own per-window rule (0.96 stock).", "float", { min: 0.5, max: 1, step: 0.005, decimals: 3 }),
      it("decoration:active_opacity", "Focused multiplier", "Global multiplier for the focused window.", "float", { min: 0.3, max: 1, step: 0.01, decimals: 2 }),
      it("decoration:inactive_opacity", "Unfocused multiplier", "Global multiplier for every other window.", "float", { min: 0.3, max: 1, step: 0.01, decimals: 2 }),
      it("decoration:fullscreen_opacity", "Fullscreen", "Opacity of fullscreen windows.", "float", { min: 0.3, max: 1, step: 0.01, decimals: 2 })
    ]
  },
  {
    id: "dimming", icon: I.dim, title: "Dimming", preview: true,
    blurb: "Darken what you aren't looking at.",
    items: [
      it("decoration:dim_inactive", "Dim unfocused", "Darken every window except the focused one.", "bool"),
      it("decoration:dim_strength", "Dim strength", "How much unfocused windows are darkened.", "float", { min: 0, max: 1, step: 0.01, decimals: 2, needs: "decoration:dim_inactive" }),
      it("decoration:dim_special", "Behind scratchpad", "Dim the desktop while a special workspace is open.", "float", { min: 0, max: 1, step: 0.01, decimals: 2 }),
      it("decoration:dim_around", "Dim-around strength", "Used by windows with the dim_around rule.", "float", { min: 0, max: 1, step: 0.01, decimals: 2 }),
      it("decoration:dim_modal", "Dim behind dialogs", "Darken a window while one of its dialogs is open.", "bool")
    ]
  },
  {
    id: "blur", icon: I.blur, title: "Blur", preview: true,
    blurb: "Background blur behind translucent windows and shell surfaces. Costs GPU time.",
    items: [
      it("decoration:blur:enabled", "Blur", "Master switch for all blur.", "bool"),
      it("decoration:blur:size", "Radius", "Blur distance.", "int", { min: 1, max: 20, needs: "decoration:blur:enabled" }),
      it("decoration:blur:passes", "Passes", "More passes are smoother and slower. 3 is plenty.", "int", { min: 1, max: 6, needs: "decoration:blur:enabled" }),
      it("decoration:blur:noise", "Noise", "Grain that hides banding.", "float", { min: 0, max: 0.2, step: 0.005, decimals: 3, needs: "decoration:blur:enabled" }),
      it("decoration:blur:contrast", "Contrast", "Contrast of the blurred image.", "float", { min: 0, max: 2, step: 0.01, decimals: 2, needs: "decoration:blur:enabled" }),
      it("decoration:blur:brightness", "Brightness", "Brightness of the blurred image.", "float", { min: 0, max: 2, step: 0.01, decimals: 2, needs: "decoration:blur:enabled" }),
      it("decoration:blur:vibrancy", "Vibrancy", "Saturation boost for blurred colors.", "float", { min: 0, max: 1, step: 0.01, decimals: 2, needs: "decoration:blur:enabled" }),
      it("decoration:blur:vibrancy_darkness", "Vibrancy in shadows", "How much vibrancy reaches dark areas.", "float", { min: 0, max: 1, step: 0.01, decimals: 2, needs: "decoration:blur:enabled" }),
      it("decoration:blur:xray", "X-ray", "Floating windows blur the wallpaper, not the windows below.", "bool", { needs: "decoration:blur:enabled" }),
      it("decoration:blur:ignore_opacity", "Ignore window opacity", "Blur at full strength no matter how translucent the window is.", "bool", { needs: "decoration:blur:enabled" }),
      it("decoration:blur:new_optimizations", "Optimizations", "Faster blur. Leave on unless you see artifacts.", "bool", { needs: "decoration:blur:enabled", advanced: true }),
      it("decoration:blur:special", "Behind scratchpad", "Blur behind special workspaces (expensive).", "bool", { needs: "decoration:blur:enabled" }),
      it("decoration:blur:popups", "Popups", "Blur behind right-click menus and tooltips.", "bool", { needs: "decoration:blur:enabled" }),
      it("decoration:blur:popups_ignorealpha", "Popup alpha cutoff", "Pixels more transparent than this are not blurred.", "float", { min: 0, max: 1, step: 0.01, decimals: 2, needs: "decoration:blur:popups", advanced: true }),
      it("decoration:blur:input_methods", "Input methods", "Blur behind IME popups (fcitx5 and friends).", "bool", { needs: "decoration:blur:enabled", advanced: true }),
      it("hf:shell_blur", "Blur the Omarchy shell", "Frosted glass behind the bar, menus and notifications. Make the bar transparent to see it.", "bool", { keywords: "bar menu layer glass waybar", needs: "decoration:blur:enabled" }),
      it("hf:shell_blur_alpha", "Shell alpha cutoff", "Ignore pixels more transparent than this, so shadows around shell surfaces don't blur.", "float", { min: 0, max: 0.9, step: 0.01, decimals: 2, needs: "hf:shell_blur" }),
      it("decoration:motion_blur:enabled", "Motion blur", "Blur windows while they move or resize.", "bool", { keywords: "movement" }),
      it("decoration:motion_blur:samples", "Motion blur samples", "More samples are smoother and slower.", "int", { min: 1, max: 32, needs: "decoration:motion_blur:enabled" })
    ]
  },
  {
    id: "shadow", icon: I.shadow, title: "Shadow", preview: true,
    blurb: "Drop shadows under windows. Tint them with a palette color for a soft glow.",
    items: [
      it("decoration:shadow:enabled", "Shadow", "Master switch for window shadows.", "bool"),
      it("decoration:shadow:range", "Size", "How far the shadow reaches.", "int", { min: 0, max: 60, unit: "px", needs: "decoration:shadow:enabled" }),
      it("decoration:shadow:render_power", "Falloff", "Higher values fade out faster.", "int", { min: 1, max: 4, needs: "decoration:shadow:enabled" }),
      it("decoration:shadow:sharp", "Hard edge", "Solid shadow with no falloff.", "bool", { needs: "decoration:shadow:enabled" }),
      it("decoration:shadow:scale", "Scale", "Shadow size relative to the window.", "float", { min: 0, max: 1, step: 0.01, decimals: 2, needs: "decoration:shadow:enabled" }),
      it("decoration:shadow:offset", "Offset", "Move the shadow, e.g. down and right for a lifted look.", "vec2", { min: -30, max: 30, unit: "px", needs: "decoration:shadow:enabled" }),
      it("decoration:shadow:color", "Color", "Focused window's shadow. Alpha is the shadow's strength.", "color", { needs: "decoration:shadow:enabled" }),
      it("decoration:shadow:color_inactive", "Unfocused color", "Shadow color for unfocused windows.", "color", { needs: "decoration:shadow:enabled" })
    ]
  },
  {
    id: "glow", icon: I.glow, title: "Glow", preview: true,
    blurb: "An inner halo along window edges.",
    items: [
      it("decoration:glow:enabled", "Glow", "Master switch for the glow.", "bool"),
      it("decoration:glow:range", "Size", "How far the glow reaches.", "int", { min: 0, max: 60, unit: "px", needs: "decoration:glow:enabled" }),
      it("decoration:glow:render_power", "Falloff", "Higher values fade out faster.", "int", { min: 1, max: 4, needs: "decoration:glow:enabled" }),
      it("decoration:glow:color", "Color", "Focused window's glow.", "color", { needs: "decoration:glow:enabled" }),
      it("decoration:glow:color_inactive", "Unfocused color", "Glow on every other window.", "color", { needs: "decoration:glow:enabled" })
    ]
  },
  {
    id: "animations", icon: I.anim, title: "Animations", view: "animations",
    blurb: "Presets, global speed, per-animation control, and a bezier/spring curve editor.",
    items: [
      it("animations:enabled", "Animations", "Master switch.", "bool"),
      it("hf:anim_speed", "Global speed", "Multiplier over every animation. 2× is twice as fast.", "float", { min: 0.25, max: 4, step: 0.05, decimals: 2, unit: "×", needs: "animations:enabled" }),
      it("animations:workspace_wraparound", "Wrap workspaces", "Slide the short way between the first and last workspace.", "bool", { needs: "animations:enabled" }),
      it("misc:animate_manual_resizes", "Animate manual resizes", "Animate keyboard/mouse resizes and moves.", "bool"),
      it("misc:animate_mouse_windowdragging", "Animate mouse drags", "Animate windows while you drag them.", "bool")
    ]
  },
  {
    id: "layout", icon: I.layout, title: "Layout",
    blurb: "The tiling engine and the knobs of whichever one is active.",
    items: [
      it("general:layout", "Engine", "Scrolling gives niri-style columns; monocle shows one window at a time.", "enum",
         { options: opts(["dwindle", "Dwindle", "master", "Master", "scrolling", "Scrolling", "monocle", "Monocle"]) }),
      it("layout:single_window_aspect_ratio", "Lone window aspect", "Keep a single window at this aspect ratio (0 0 = off). Great on ultrawides.", "vec2", { min: 0, max: 21, step: 1, keywords: "ultrawide ratio" }),
      it("layout:single_window_aspect_ratio_tolerance", "Aspect tolerance", "How far off the ratio may be before it applies.", "float", { min: 0, max: 1, step: 0.01, decimals: 2, advanced: true }),

      it("dwindle:force_split", "New window side", "Where a new window lands when splitting.", "enum",
         { options: opts([0, "Cursor", 1, "Left/top", 2, "Right/bottom"]), needs: "general:layout", needsValue: "dwindle" }),
      it("dwindle:preserve_split", "Preserve split", "Keep the split direction no matter what.", "bool", { needs: "general:layout", needsValue: "dwindle" }),
      it("dwindle:smart_split", "Smart split", "Split direction follows where the cursor is in the window.", "bool", { needs: "general:layout", needsValue: "dwindle" }),
      it("dwindle:smart_resizing", "Smart resizing", "Resize direction follows the cursor position.", "bool", { needs: "general:layout", needsValue: "dwindle" }),
      it("dwindle:split_width_multiplier", "Side-by-side bias", "Above 1 favours side-by-side splits on wide windows.", "float", { min: 0.5, max: 2.5, step: 0.05, decimals: 2, needs: "general:layout", needsValue: "dwindle" }),
      it("dwindle:default_split_ratio", "Split ratio", "Size of a new split relative to its sibling.", "float", { min: 0.3, max: 1.7, step: 0.05, decimals: 2, needs: "general:layout", needsValue: "dwindle" }),
      it("dwindle:split_bias", "Ratio goes to", "Which window receives the split ratio.", "enum", { options: opts([0, "Direction", 1, "Current"]), needs: "general:layout", needsValue: "dwindle", advanced: true }),
      it("dwindle:use_active_for_splits", "Split the focused window", "Prefer the focused window over the cursor position.", "bool", { needs: "general:layout", needsValue: "dwindle", advanced: true }),
      it("dwindle:special_scale_factor", "Scratchpad scale", "Window size on the special workspace.", "float", { min: 0.5, max: 1, step: 0.01, decimals: 2, needs: "general:layout", needsValue: "dwindle" }),
      it("dwindle:precise_mouse_move", "Precise mouse drops", "Drop dragged windows exactly where the mouse is.", "bool", { needs: "general:layout", needsValue: "dwindle", advanced: true }),
      it("dwindle:permanent_direction_override", "Sticky preselect", "Keep a preselected split direction.", "bool", { needs: "general:layout", needsValue: "dwindle", advanced: true }),

      it("master:mfact", "Master size", "Share of the screen the master area takes.", "float", { min: 0.1, max: 0.9, step: 0.01, decimals: 2, needs: "general:layout", needsValue: "master" }),
      it("master:orientation", "Master side", "Edge the master area occupies.", "enum",
         { options: opts(["left", "Left", "right", "Right", "top", "Top", "bottom", "Bottom", "center", "Center"]), needs: "general:layout", needsValue: "master" }),
      it("master:new_status", "New windows become", "Where a new window goes.", "enum",
         { options: opts(["master", "Master", "slave", "Stack", "inherit", "Inherit"]), needs: "general:layout", needsValue: "master" }),
      it("master:new_on_top", "New on top of stack", "Put new windows at the top of the stack.", "bool", { needs: "general:layout", needsValue: "master" }),
      it("master:new_on_active", "Place relative to focus", "Insert new windows before/after the focused one.", "enum",
         { options: opts(["none", "Off", "before", "Before", "after", "After"]), needs: "general:layout", needsValue: "master" }),
      it("master:slave_count_for_center_master", "Center after N windows", "With center orientation, center the master only once this many stack windows exist.", "int", { min: 0, max: 6, needs: "general:layout", needsValue: "master" }),
      it("master:center_master_fallback", "Center fallback", "Side used before the center threshold is reached.", "enum",
         { options: opts(["left", "Left", "right", "Right", "top", "Top", "bottom", "Bottom"]), needs: "general:layout", needsValue: "master", advanced: true }),
      it("master:allow_small_split", "Small master splits", "Allow extra masters in a horizontal split.", "bool", { needs: "general:layout", needsValue: "master", advanced: true }),
      it("master:smart_resizing", "Smart resizing", "Resize direction follows the cursor position.", "bool", { needs: "general:layout", needsValue: "master" }),
      it("master:drop_at_cursor", "Drop at cursor", "Dragged windows land at the cursor.", "bool", { needs: "general:layout", needsValue: "master" }),
      it("master:always_keep_position", "Keep master position", "Keep the master where it is even without stack windows.", "bool", { needs: "general:layout", needsValue: "master", advanced: true }),
      it("master:focus_master_on_close", "Focus master on close", "Closing a window focuses the master.", "bool", { needs: "general:layout", needsValue: "master", advanced: true }),
      it("master:special_scale_factor", "Scratchpad scale", "Window size on the special workspace.", "float", { min: 0.5, max: 1, step: 0.01, decimals: 2, needs: "general:layout", needsValue: "master" }),

      it("scrolling:column_width", "Column width", "Default column width as a share of the screen.", "float", { min: 0.2, max: 1, step: 0.01, decimals: 2, needs: "general:layout", needsValue: "scrolling" }),
      it("scrolling:direction", "Scroll direction", "Where new columns appear.", "enum",
         { options: opts(["right", "Right", "left", "Left", "down", "Down", "up", "Up"]), needs: "general:layout", needsValue: "scrolling" }),
      it("scrolling:fullscreen_on_one_column", "Lone column fills screen", "A single column spans the whole screen.", "bool", { needs: "general:layout", needsValue: "scrolling" }),
      it("scrolling:focus_fit_method", "Bring into view by", "How a focused column is scrolled into view.", "enum", { options: opts([0, "Centering", 1, "Fitting"]), needs: "general:layout", needsValue: "scrolling" }),
      it("scrolling:follow_focus", "Follow focus", "Scroll to the focused window automatically.", "bool", { needs: "general:layout", needsValue: "scrolling" }),
      it("scrolling:follow_min_visible", "Follow threshold", "Only scroll when less than this share of the window is visible.", "float", { min: 0, max: 1, step: 0.05, decimals: 2, needs: "general:layout", needsValue: "scrolling" }),
      it("scrolling:explicit_column_widths", "Width presets", "Comma-separated widths cycled by colresize +conf/-conf.", "text", { needs: "general:layout", needsValue: "scrolling" }),
      it("scrolling:wrap_focus", "Wrap focus", "Focus wraps from last column to first.", "bool", { needs: "general:layout", needsValue: "scrolling", advanced: true }),
      it("scrolling:wrap_swapcol", "Wrap column moves", "Moving a column wraps around.", "bool", { needs: "general:layout", needsValue: "scrolling", advanced: true })
    ]
  },
  {
    id: "groups", icon: I.group, title: "Groups & Tabs",
    blurb: "Tabbed window groups and their tab bar. Tab colors come from your palette.",
    items: [
      it("group:groupbar:enabled", "Tab bar", "Show the tab strip on grouped windows.", "bool"),
      it("group:groupbar:height", "Height", "Tab strip height.", "int", { min: 1, max: 40, unit: "px", needs: "group:groupbar:enabled" }),
      it("group:groupbar:font_size", "Font size", "Size of tab titles.", "int", { min: 6, max: 24, unit: "px", needs: "group:groupbar:enabled" }),
      it("group:groupbar:render_titles", "Show titles", "Draw window titles in the tabs.", "bool", { needs: "group:groupbar:enabled" }),
      it("group:groupbar:gradients", "Filled tabs", "Paint tab backgrounds.", "bool", { needs: "group:groupbar:enabled" }),
      it("group:groupbar:rounding", "Tab rounding", "Corner radius of the indicator.", "int", { min: 0, max: 20, unit: "px", needs: "group:groupbar:enabled" }),
      it("group:groupbar:gradient_rounding", "Fill rounding", "Corner radius of the tab fill.", "int", { min: 0, max: 20, unit: "px", needs: "group:groupbar:gradients" }),
      it("group:groupbar:indicator_height", "Indicator height", "Thickness of the tab indicator line.", "int", { min: 1, max: 12, unit: "px", needs: "group:groupbar:enabled" }),
      it("group:groupbar:indicator_gap", "Indicator gap", "Space between indicator and title.", "int", { min: 0, max: 20, unit: "px", needs: "group:groupbar:enabled" }),
      it("group:groupbar:gaps_in", "Gap between tabs", "", "int", { min: 0, max: 20, unit: "px", needs: "group:groupbar:enabled" }),
      it("group:groupbar:gaps_out", "Gap to window", "", "int", { min: 0, max: 20, unit: "px", needs: "group:groupbar:enabled" }),
      it("group:groupbar:stacked", "Vertical tabs", "Stack tabs vertically.", "bool", { needs: "group:groupbar:enabled" }),
      it("group:groupbar:disable_when_only", "Hide with one tab", "Hide the strip for single-window groups.", "bool", { needs: "group:groupbar:enabled" }),
      it("group:groupbar:blur", "Blur tab bar", "Background blur behind the tab strip.", "bool", { needs: "group:groupbar:enabled" }),
      it("group:groupbar:col.active", "Active tab", "", "color", { needs: "group:groupbar:enabled" }),
      it("group:groupbar:col.inactive", "Inactive tab", "", "color", { needs: "group:groupbar:enabled" }),
      it("group:groupbar:text_color", "Title color", "", "color", { needs: "group:groupbar:enabled" }),
      it("group:groupbar:text_color_inactive", "Inactive title color", "", "color", { needs: "group:groupbar:enabled", advanced: true }),
      it("group:groupbar:scrolling", "Scroll to switch tabs", "", "bool", { needs: "group:groupbar:enabled", advanced: true }),
      it("group:groupbar:middle_click_close", "Middle-click closes", "", "bool", { needs: "group:groupbar:enabled", advanced: true }),
      it("group:auto_group", "Auto-group", "New windows join the focused group.", "bool"),
      it("group:insert_after_current", "Insert after current", "New group windows open next to the current tab.", "bool"),
      it("group:drag_into_group", "Drag into group", "Dragging a window onto a group merges it.", "enum", { options: opts([0, "Off", 1, "On", 2, "Tab bar only"]) }),
      it("group:merge_groups_on_drag", "Merge groups on drag", "", "bool", { advanced: true }),
      it("group:focus_removed_window", "Focus removed window", "", "bool", { advanced: true })
    ]
  },
  {
    id: "input", icon: I.input, title: "Keyboard & Mouse",
    blurb: "Overrides ~/.config/hypr/input.lua for anything you change here.",
    items: [
      it("input:repeat_rate", "Key repeat rate", "Repeats per second while a key is held.", "int", { min: 10, max: 100, unit: "/s", keywords: "keyboard" }),
      it("input:repeat_delay", "Key repeat delay", "Wait before repeating starts.", "int", { min: 150, max: 1000, step: 10, unit: "ms", keywords: "keyboard" }),
      it("input:numlock_by_default", "Num Lock on", "Engage Num Lock at login.", "bool"),
      it("input:sensitivity", "Pointer speed", "-1 slowest, 0 default, 1 fastest.", "float", { min: -1, max: 1, step: 0.05, decimals: 2, keywords: "mouse" }),
      it("input:accel_profile", "Acceleration", "Flat is 1:1 and great for games.", "enum", { options: opts(["", "Default", "adaptive", "Adaptive", "flat", "Flat"]), keywords: "mouse" }),
      it("input:natural_scroll", "Natural scrolling (mouse)", "Content follows your fingers.", "bool"),
      it("input:scroll_factor", "Mouse scroll speed", "", "float", { min: 0.1, max: 3, step: 0.05, decimals: 2 }),
      it("input:left_handed", "Left-handed", "Swap left and right buttons.", "bool"),
      it("input:follow_mouse", "Focus follows mouse", "", "enum", { options: opts([0, "Off", 1, "Always", 2, "Loose", 3, "Separate"]) }),
      it("input:mouse_refocus", "Refocus on hover", "Hovering a window re-focuses it.", "bool", { advanced: true }),
      it("input:focus_on_close", "After closing, focus", "", "enum", { options: opts([0, "Next", 1, "Under cursor", 2, "Last used"]) }),
      it("input:float_switch_override_focus", "Float toggle focus", "Focus the window under the cursor when toggling floating.", "int", { min: 0, max: 2, advanced: true }),
      it("input:special_fallthrough", "Scratchpad fall-through", "Floating-only scratchpads don't block the workspace below.", "bool", { advanced: true }),
      it("input:touchpad:natural_scroll", "Natural scrolling (touchpad)", "", "bool", { keywords: "trackpad laptop" }),
      it("input:touchpad:scroll_factor", "Touchpad scroll speed", "", "float", { min: 0.1, max: 3, step: 0.05, decimals: 2, keywords: "trackpad" }),
      it("input:touchpad:disable_while_typing", "Disable while typing", "", "bool", { keywords: "trackpad" }),
      it("input:touchpad:tap-to-click", "Tap to click", "", "bool", { keywords: "trackpad" }),
      it("input:touchpad:tap-and-drag", "Tap and drag", "", "bool", { keywords: "trackpad" }),
      it("input:touchpad:drag_lock", "Drag lock", "Lifting a finger mid-drag doesn't drop.", "enum", { options: opts([0, "Off", 1, "Timeout", 2, "Sticky"]), keywords: "trackpad" }),
      it("input:touchpad:clickfinger_behavior", "Finger-count clicks", "1/2/3-finger clicks for left/right/middle.", "bool", { keywords: "trackpad" }),
      it("input:touchpad:middle_button_emulation", "Middle-click emulation", "Left+right together is a middle click.", "bool", { keywords: "trackpad" }),
      it("input:touchpad:drag_3fg", "Three-finger drag", "", "enum", { options: opts([0, "Off", 1, "3 fingers", 2, "4 fingers"]), keywords: "trackpad" })
    ]
  },
  {
    id: "cursor", icon: I.cursor, title: "Cursor & Zoom",
    blurb: "Pointer behaviour, auto-hide and the screen magnifier.",
    items: [
      it("cursor:zoom_factor", "Zoom", "Magnify the screen around the cursor. Drag to try it live.", "float", { min: 1, max: 5, step: 0.05, decimals: 2, unit: "×", keywords: "magnifier accessibility" }),
      it("cursor:zoom_rigid", "Rigid zoom", "Zoomed view follows the cursor exactly.", "bool"),
      it("cursor:zoom_detached_camera", "Detached camera", "Camera only moves when the cursor nears the edge.", "bool", { advanced: true }),
      it("cursor:inactive_timeout", "Hide when idle", "Hide the cursor after this many idle seconds (0 = never).", "float", { min: 0, max: 20, step: 0.5, decimals: 1, unit: "s" }),
      it("cursor:hide_on_key_press", "Hide while typing", "", "bool"),
      it("cursor:hide_on_touch", "Hide on touch input", "", "bool", { advanced: true }),
      it("cursor:no_warps", "Never warp", "Don't move the cursor on focus changes.", "bool"),
      it("cursor:persistent_warps", "Remember position", "Return the cursor to where it was in a window.", "bool"),
      it("cursor:warp_on_change_workspace", "Warp on workspace switch", "", "enum", { options: opts([0, "Off", 1, "On", 2, "Always"]) }),
      it("cursor:warp_on_toggle_special", "Warp on scratchpad", "", "enum", { options: opts([0, "Off", 1, "On", 2, "Always"]) }),
      it("cursor:hotspot_padding", "Edge padding", "Keep the cursor this far from screen edges.", "int", { min: 0, max: 20, unit: "px", advanced: true }),
      it("cursor:no_hardware_cursors", "Software cursor", "Fix flicker/invisible cursor on some GPUs.", "enum", { options: opts([2, "Auto", 0, "Hardware", 1, "Software"]), advanced: true }),
      it("cursor:enable_hyprcursor", "Hyprcursor themes", "", "bool", { advanced: true })
    ]
  },
  {
    id: "gestures", icon: I.gesture, title: "Gestures",
    blurb: "Touchpad and touchscreen workspace swipes.",
    items: [
      it("gestures:workspace_swipe_distance", "Swipe distance", "Travel needed for a full workspace swipe.", "int", { min: 50, max: 1200, step: 10, unit: "px" }),
      it("gestures:workspace_swipe_cancel_ratio", "Commit threshold", "How far you must swipe before it commits.", "float", { min: 0.05, max: 1, step: 0.05, decimals: 2 }),
      it("gestures:workspace_swipe_min_speed_to_force", "Flick speed", "A fast flick commits regardless of distance.", "int", { min: 0, max: 100 }),
      it("gestures:workspace_swipe_invert", "Invert (touchpad)", "", "bool"),
      it("gestures:workspace_swipe_create_new", "Swipe creates workspace", "Swiping past the last workspace makes a new one.", "bool"),
      it("gestures:workspace_swipe_forever", "Swipe through many", "Keep going past neighbouring workspaces.", "bool"),
      it("gestures:workspace_swipe_direction_lock", "Direction lock", "", "bool", { advanced: true }),
      it("gestures:workspace_swipe_touch", "Touchscreen edge swipe", "", "bool"),
      it("gestures:workspace_swipe_touch_invert", "Invert (touchscreen)", "", "bool", { advanced: true }),
      it("gestures:workspace_swipe_use_r", "Relative workspaces", "Swipe by relative index rather than by monitor.", "bool", { advanced: true })
    ]
  },
  {
    id: "behavior", icon: I.misc, title: "Behavior & Performance",
    blurb: "Focus, fullscreen, swallowing, VRR and rendering.",
    items: [
      it("misc:focus_on_activate", "Focus on activate", "Let apps steal focus when they ask.", "bool"),
      it("misc:vrr", "Variable refresh rate", "Adaptive sync.", "enum", { options: opts([0, "Off", 1, "Always", 2, "Fullscreen", 3, "Games"]), keywords: "freesync gsync adaptive" }),
      it("misc:enable_swallow", "Window swallowing", "A terminal hides while the app it launched is open.", "bool"),
      it("misc:swallow_regex", "Swallowing terminals", "Class regex of terminals that swallow.", "text", { needs: "misc:enable_swallow" }),
      it("misc:swallow_exception_regex", "Swallow exceptions", "Title regex that never gets swallowed.", "text", { needs: "misc:enable_swallow", advanced: true }),
      it("misc:on_focus_under_fullscreen", "Focus under fullscreen", "When a window behind a fullscreen one asks for focus.", "enum", { options: opts([0, "Ignore", 1, "Take over", 2, "Exit fullscreen"]) }),
      it("misc:exit_window_retains_fullscreen", "Keep fullscreen on close", "The next window inherits fullscreen.", "bool"),
      it("misc:close_special_on_empty", "Close empty scratchpad", "", "bool"),
      it("misc:middle_click_paste", "Middle-click paste", "", "bool"),
      it("misc:mouse_move_enables_dpms", "Wake screen on mouse", "", "bool"),
      it("misc:key_press_enables_dpms", "Wake screen on key", "", "bool"),
      it("misc:mouse_move_focuses_monitor", "Mouse focuses monitor", "", "bool", { advanced: true }),
      it("misc:render_unfocused_fps", "Background app FPS", "FPS cap for windows with render_unfocused.", "int", { min: 1, max: 120, advanced: true }),
      it("binds:workspace_back_and_forth", "Workspace back-and-forth", "Switching to the current workspace goes back to the previous one.", "bool"),
      it("binds:allow_workspace_cycles", "Workspace cycles", "Remember history for previous-workspace.", "bool", { advanced: true }),
      it("binds:hide_special_on_workspace_change", "Hide scratchpad on switch", "", "bool"),
      it("binds:movefocus_cycles_fullscreen", "Focus cycles fullscreen", "", "bool", { advanced: true }),
      it("binds:movefocus_cycles_groupfirst", "Focus cycles tabs first", "", "bool", { advanced: true }),
      it("binds:window_direction_monitor_fallback", "Cross monitors", "Directional focus moves to the next monitor.", "bool", { advanced: true }),
      it("render:direct_scanout", "Direct scanout", "Lower latency for fullscreen games.", "enum", { options: opts([0, "Off", 1, "On", 2, "Auto"]) }),
      it("render:new_render_scheduling", "New render scheduling", "Can raise FPS on weaker GPUs.", "bool"),
      it("xwayland:force_zero_scaling", "Crisp XWayland", "Don't upscale X11 apps on HiDPI (they render at native size).", "bool", { advanced: true }),
      it("misc:font_family", "Hyprland UI font", "Font for Hyprland's own text (group titles, errors).", "text", { advanced: true })
    ]
  },
  {
    id: "rules", icon: I.rules, title: "App Rules", view: "rules",
    blurb: "Per-app opacity, blur, floating, size, workspace and more. Pick from running windows."
  },
  {
    id: "profiles", icon: I.profiles, title: "Profiles & History", view: "profiles",
    blurb: "Save looks, switch between them, export, and roll back any applied change."
  },
  {
    id: "all", icon: I.all, title: "Every option", view: "all",
    blurb: "All Hyprland options, straight from the running compositor."
  }
]

// Synthetic keys and their defaults (what they are when not set).
var SYNTHETIC = {
  "hf:smart_gaps": false,
  "hf:smart_borders": false,
  "hf:border_rotate": false,
  "hf:border_rotate_speed": 6,
  "hf:base_active": 0.985,
  "hf:base_inactive": 0.96,
  "hf:shell_blur": false,
  "hf:shell_blur_alpha": 0.2,
  "hf:anim_speed": 1
}

function isSynthetic(key) { return String(key).indexOf("hf:") === 0 }

var _index = null
function index() {
  if (_index) return _index
  _index = {}
  for (var i = 0; i < SECTIONS.length; i++) {
    var items = SECTIONS[i].items || []
    for (var j = 0; j < items.length; j++) {
      items[j].section = SECTIONS[i].id
      _index[items[j].key] = items[j]
    }
  }
  return _index
}

function itemFor(key) { return index()[key] || null }

function sectionById(id) {
  for (var i = 0; i < SECTIONS.length; i++) if (SECTIONS[i].id === id) return SECTIONS[i]
  return null
}

// Every key belonging to the given section ids.
function keysInSections(ids) {
  var out = {}
  for (var s = 0; s < ids.length; s++) {
    var sec = sectionById(ids[s])
    var items = sec && sec.items ? sec.items : []
    for (var i = 0; i < items.length; i++) out[items[i].key] = true
  }
  return out
}

function allItems() {
  var out = []
  var idx = index()
  for (var k in idx) out.push(idx[k])
  return out
}

// Real Hyprland keys in the catalogue (what `getoption` can answer).
function liveKeys() {
  var out = []
  var items = allItems()
  for (var i = 0; i < items.length; i++) if (!isSynthetic(items[i].key)) out.push(items[i].key)
  return out
}

// Human label for a Hyprland key not in the catalogue: "blur:new_optimizations"
// -> "New optimizations".
function prettyKey(key) {
  var parts = String(key).split(/[:.]/)
  var leaf = parts[parts.length - 1].replace(/[_-]/g, " ")
  return leaf.charAt(0).toUpperCase() + leaf.slice(1)
}

// Search across every catalogued item. Returns [{ item, score }] best first.
function search(query, extraItems) {
  var q = String(query || "").toLowerCase().trim()
  if (!q) return []
  var terms = q.split(/\s+/)
  var pool = allItems().concat(extraItems || [])
  var seen = {}
  var out = []
  for (var i = 0; i < pool.length; i++) {
    var item = pool[i]
    if (seen[item.key]) continue
    seen[item.key] = true
    var label = String(item.label || "").toLowerCase()
    var hay = label + " " + String(item.desc || "").toLowerCase() + " " + item.key.toLowerCase()
      + " " + String(item.keywords || "").toLowerCase() + " " + String(item.section || "")
    var score = 0
    var ok = true
    for (var t = 0; t < terms.length; t++) {
      var at = hay.indexOf(terms[t])
      if (at < 0) { ok = false; break }
      score += label.indexOf(terms[t]) === 0 ? 5 : (label.indexOf(terms[t]) > 0 ? 3 : 1)
    }
    if (!ok) continue
    if (item.section) {
      score += 1
      var sec = sectionById(item.section)
      var title = sec ? String(sec.title).toLowerCase() : ""
      for (var u = 0; u < terms.length; u++) if (title.indexOf(terms[u]) !== -1) score += 4
    }
    out.push({ item: item, score: score })
  }
  out.sort(function(a, b) { return b.score - a.score || String(a.item.label).localeCompare(String(b.item.label)) })
  return out
}
