.pragma library

// Hyprforge engine: settings in, Hyprland Lua out.
//
// The panel keeps one plain object (`cfg`) as the source of truth and saves it
// to ~/.config/hypr/hyprforge/state.json. Everything Hyprland sees is rendered
// from it into ~/.config/hypr/hyprforge.lua, which hyprland.lua requires after
// the user's own files. The same renderer feeds `hyprctl eval` for the live
// preview, so preview and saved state can't drift.
//
// cfg = {
//   options: { "<hypr key>" | "hf:<synthetic>": value }
//              value shapes: bool | number | string
//                            gaps  { top, right, bottom, left }
//                            vec2  [x, y]
//                            color { slots: ["accent", "#ff0000"], alpha: 0-255, angle? }
//   anims:   { <leaf>: { enabled, speed, curve, style } }   per-leaf overrides
//   curves:  { <name>: { type: "bezier", points: [x0, y0, x1, y1] }
//                      | { type: "spring", mass, stiffness, dampening } }
//   rules:   [ { id, enabled, name, match: {...}, effects: {...} } ]
// }
//
// Colors are stored as palette *names* and resolved by the generated Lua at
// load time from the active theme's colors.toml. `omarchy theme set` reloads
// Hyprland, so borders, shadows and glow re-color themselves with every theme.

var VERSION = 1
var CURVE_PREFIX = "hf_"

function defaultConfig() {
  return { options: {}, anims: {}, curves: {}, rules: [] }
}

function clone(v) {
  return v === undefined ? undefined : JSON.parse(JSON.stringify(v))
}

function normalize(cfg) {
  var c = cfg && typeof cfg === "object" ? clone(cfg) : {}
  if (!c.options || typeof c.options !== "object") c.options = {}
  if (!c.anims || typeof c.anims !== "object") c.anims = {}
  if (!c.curves || typeof c.curves !== "object") c.curves = {}
  if (!Array.isArray(c.rules)) c.rules = []
  return { options: c.options, anims: c.anims, curves: c.curves, rules: c.rules }
}

function isEmpty(cfg) {
  var c = normalize(cfg)
  return Object.keys(c.options).length === 0 && Object.keys(c.anims).length === 0
    && Object.keys(c.curves).length === 0 && c.rules.length === 0
}

function valuesEqual(a, b) {
  return JSON.stringify(a) === JSON.stringify(b)
}

// ------------------------------------------------------------------ values

function isColorSpec(v) {
  return v !== null && typeof v === "object" && Array.isArray(v.slots)
}

function isGaps(v) {
  return v !== null && typeof v === "object" && !Array.isArray(v) && v.top !== undefined
}

function gapsFrom(v) {
  if (isGaps(v)) return { top: Number(v.top), right: Number(v.right), bottom: Number(v.bottom), left: Number(v.left) }
  var n = Number(v)
  if (!isFinite(n)) n = 0
  return { top: n, right: n, bottom: n, left: n }
}

function gapsUniform(v) {
  var g = gapsFrom(v)
  return g.top === g.right && g.top === g.bottom && g.top === g.left
}

function quantize(item, value) {
  var type = item ? item.type : ""
  if (type === "bool") return value === true
  if (type === "enum") {
    if (item.options && item.options.length > 0 && typeof item.options[0].value === "number") return Number(value)
    return String(value)
  }
  if (type === "text") return String(value)
  if (type === "color" || type === "gradient" || type === "vec2") return clone(value)
  if (type === "gaps") {
    if (isGaps(value)) {
      var g = gapsFrom(value)
      return gapsUniform(g) ? Math.round(g.top) : { top: Math.round(g.top), right: Math.round(g.right), bottom: Math.round(g.bottom), left: Math.round(g.left) }
    }
    return Math.round(Number(value) || 0)
  }
  var n = Number(value)
  if (!isFinite(n)) n = 0
  if (type === "int") return Math.round(n)
  var decimals = item && item.decimals !== undefined ? item.decimals : 3
  var f = Math.pow(10, decimals)
  return Math.round(n * f) / f
}

function formatNumber(n, decimals) {
  var v = Number(n)
  if (!isFinite(v)) return "0"
  if (decimals === undefined) {
    if (Math.abs(v - Math.round(v)) < 1e-9) return String(Math.round(v))
    return String(parseFloat(v.toFixed(3)))
  }
  return v.toFixed(decimals)
}

// Short human text for a value, used in summaries and history.
function describe(item, value) {
  if (value === undefined || value === null) return "—"
  if (typeof value === "boolean") return value ? "on" : "off"
  if (isColorSpec(value)) return value.slots.join(" → ") + (value.angle !== undefined && value.slots.length > 1 ? " " + value.angle + "°" : "")
  if (isGaps(value)) { var g = gapsFrom(value); return g.top + " " + g.right + " " + g.bottom + " " + g.left }
  if (Array.isArray(value)) return value.join(" × ")
  if (item && item.type === "enum" && item.options) {
    for (var i = 0; i < item.options.length; i++)
      if (String(item.options[i].value) === String(value)) return item.options[i].label
  }
  if (typeof value === "number") return formatNumber(value, item ? item.decimals : undefined) + (item && item.unit ? item.unit : "")
  var s = String(value)
  return s === "" ? "(empty)" : s
}

// ------------------------------------------------------------ validation
//
// A reload-time config error makes Hyprland draw its error bar, and on some
// systems that deadlocks the compositor. So nothing reaches hyprforge.lua
// unless its shape matches the option's type; the panel additionally dry-runs
// the file through `hyprctl eval` before saving.

function finite(n) { return typeof n === "number" && isFinite(n) }

// type: catalogue type or live type (bool int float text gaps vec2 color gradient enum)
function checkValue(type, v) {
  if (v === undefined || v === null) return "no value"
  switch (type) {
  case "bool": return typeof v === "boolean" ? "" : "expects on/off"
  case "int":
  case "float": return finite(v) ? "" : "expects a number"
  case "enum": return (finite(v) || typeof v === "string") ? "" : "expects one of its choices"
  case "text": return typeof v === "string" && v.indexOf("\n") === -1 ? "" : "expects a single line of text"
  case "gaps":
    if (finite(v)) return v >= 0 ? "" : "gaps can't be negative"
    if (isGaps(v) && finite(v.top) && finite(v.right) && finite(v.bottom) && finite(v.left)) return ""
    return "expects a gap size"
  case "vec2": return Array.isArray(v) && v.length === 2 && finite(v[0]) && finite(v[1]) ? "" : "expects two numbers"
  case "any":
    if (typeof v === "boolean" || finite(v)) return ""
    if (typeof v === "string") return v.indexOf("\n") === -1 ? "" : "expects a single line of text"
    if (Array.isArray(v)) return v.length === 2 && finite(v[0]) && finite(v[1]) ? "" : "expects two numbers"
    if (isGaps(v)) return checkValue("gaps", v)
    if (isColorSpec(v)) return checkValue("color", v)
    return "unsupported value"
  case "color":
  case "gradient":
    if (!isColorSpec(v) || v.slots.length === 0) return "expects palette colors"
    for (var i = 0; i < v.slots.length; i++) {
      var sl = String(v.slots[i])
      if (!/^(#[0-9a-fA-F]{6}|[A-Za-z0-9_-]+)$/.test(sl)) return "bad color " + sl
    }
    if (v.alpha !== undefined && !(finite(v.alpha) && v.alpha >= 0 && v.alpha <= 255)) return "alpha must be 0-255"
    if (v.angle !== undefined && !finite(v.angle)) return "angle must be a number"
    return ""
  }
  return ""
}

// typeOf(key) -> type string or "" when unknown. Returns [{ key, problem }].
function validate(cfgIn, typeOf) {
  var cfg = normalize(cfgIn)
  var out = []
  for (var key in cfg.options) {
    if (!/^[A-Za-z0-9_-]+(:[A-Za-z0-9_.-]+)+$/.test(key)) { out.push({ key: key, problem: "not a valid option name" }); continue }
    var t = typeOf(key)
    if (!t) { out.push({ key: key, problem: "unknown option" }); continue }
    var why = checkValue(t, cfg.options[key])
    if (why) out.push({ key: key, problem: why })
  }
  for (var leaf in cfg.anims) {
    var a = cfg.anims[leaf]
    if (!/^[A-Za-z]+$/.test(leaf)) out.push({ key: "animation " + leaf, problem: "bad leaf name" })
    else if (a.enabled !== false && (!finite(Number(a.speed)) || Number(a.speed) <= 0)) out.push({ key: "animation " + leaf, problem: "speed must be positive" })
  }
  for (var name in cfg.curves) {
    var c = cfg.curves[name]
    if (!/^[A-Za-z0-9_]+$/.test(name)) out.push({ key: "curve " + name, problem: "bad curve name" })
    else if (c.type === "spring") { if (!finite(c.mass) || !finite(c.stiffness) || !finite(c.dampening)) out.push({ key: "curve " + name, problem: "spring needs numbers" }) }
    else if (!Array.isArray(c.points) || c.points.length !== 4 || !c.points.every(finite)) out.push({ key: "curve " + name, problem: "bezier needs four numbers" })
  }
  return out
}

// ------------------------------------------------------- reading hyprctl

// `hyprctl -j --batch "getoption a ; getoption b"` prints one object per
// option. Returns { key: value } in cfg shapes.
function parseGetoptions(raw) {
  var out = {}
  var objects = String(raw || "").match(/\{[^{}]*\}/g) || []
  for (var i = 0; i < objects.length; i++) {
    var e
    try { e = JSON.parse(objects[i]) } catch (err) { continue }
    if (!e || !e.option) continue
    var v = liveValue(e)
    if (v !== undefined) out[e.option] = v
  }
  return out
}

function liveValue(e) {
  if (e.bool !== undefined) return e.bool === true
  if (e.int !== undefined) return Number(e.int)
  if (e.float !== undefined) return Math.round(Number(e.float) * 10000) / 10000
  if (e.str !== undefined) return e.str === "[[EMPTY]]" ? "" : String(e.str)
  if (e.vec2 !== undefined) return [Number(e.vec2[0]), Number(e.vec2[1])]
  if (e.css !== undefined) {
    var p = String(e.css).match(/-?\d+/g) || ["0"]
    var t = Number(p[0]), r = Number(p[1] !== undefined ? p[1] : p[0])
    var b = Number(p[2] !== undefined ? p[2] : p[0]), l = Number(p[3] !== undefined ? p[3] : r)
    if (t === r && t === b && t === l) return t
    return { top: t, right: r, bottom: b, left: l }
  }
  if (e.gradient !== undefined) return { gradient: String(e.gradient) }
  if (e.custom !== undefined) return String(e.custom)
  return undefined
}

// Live types, keyed the way the "Every option" editor wants them.
function liveType(e) {
  if (e.bool !== undefined) return "bool"
  if (e.int !== undefined) return "int"
  if (e.float !== undefined) return "float"
  if (e.vec2 !== undefined) return "vec2"
  if (e.css !== undefined) return "gaps"
  if (e.gradient !== undefined) return "gradient"
  return "text"
}

function parseLiveTypes(raw) {
  var out = {}
  var objects = String(raw || "").match(/\{[^{}]*\}/g) || []
  for (var i = 0; i < objects.length; i++) {
    try {
      var e = JSON.parse(objects[i])
      if (e && e.option) out[e.option] = liveType(e)
    } catch (err) {}
  }
  return out
}

// ARGB int (how getoption reports plain colors) -> "#rrggbb" + alpha.
function argbToHex(n) {
  var v = Number(n) >>> 0
  var hex = (v & 0xffffff).toString(16)
  while (hex.length < 6) hex = "0" + hex
  return { hex: "#" + hex, alpha: (v >>> 24) & 0xff }
}

// "eea88bff ee5fd4ff 45deg" -> { colors: ["#a88bff", ...], alphas, angle }
function parseGradient(text) {
  var out = { colors: [], alphas: [], angle: 0 }
  var parts = String(text || "").trim().split(/\s+/)
  for (var i = 0; i < parts.length; i++) {
    var m = parts[i].match(/^([0-9a-fA-F]{2})([0-9a-fA-F]{6})$/)
    if (m) { out.alphas.push(parseInt(m[1], 16)); out.colors.push("#" + m[2].toLowerCase()); continue }
    var a = parts[i].match(/^(-?\d+(?:\.\d+)?)deg$/)
    if (a) out.angle = Math.round(Number(a[1]))
  }
  return out
}

// Build a "Every option" catalogue entry from `hyprctl descriptions` + live type.
function itemFromDescription(d, type) {
  var key = d.name
  var item = {
    key: key, label: prettyLeaf(key), desc: String(d.description || ""),
    group: key.split(":")[0], generated: true
  }
  if (d.map && d.map.length) {
    item.type = "enum"
    item.options = []
    for (var i = 0; i < d.map.length; i++) {
      for (var lbl in d.map[i]) item.options.push({ value: Number(d.map[i][lbl]), label: prettyWords(lbl) })
    }
    item.options.sort(function(a, b) { return a.value - b.value })
    return item
  }
  var def = d["default"]
  if (type === "int" && typeof def === "string" && /^(-1|[0-9a-fA-F]{8})$/.test(def)) {
    item.type = "color"
    return item
  }
  if (type === "gradient") { item.type = "gradient"; return item }
  item.type = type || (typeof def === "boolean" ? "bool" : typeof def === "number" ? "float" : "text")
  if (item.type === "int" || item.type === "float") {
    if (d.min !== undefined && d.min !== null) item.min = Number(d.min)
    if (d.max !== undefined && d.max !== null) item.max = Number(d.max)
    if (item.max !== undefined && item.max > 100000) item.max = undefined
    if (item.type === "float") { item.step = 0.01; item.decimals = 2 }
    if (item.min === undefined || item.max === undefined) item.freeform = true
  }
  if (item.type === "gaps") { item.min = 0; item.max = 80 }
  if (item.type === "vec2") { item.min = -50; item.max = 50 }
  return item
}

function prettyWords(s) {
  var t = String(s).replace(/[_-]/g, " ")
  return t.charAt(0).toUpperCase() + t.slice(1)
}

function prettyLeaf(key) {
  var parts = String(key).split(/[:]/)
  var leaf = parts.slice(1).join(" › ")
  return prettyWords(leaf || key)
}

// ---------------------------------------------------------- theme palette

// Ordered palette entries from a theme's colors.toml.
function parsePalette(text) {
  var out = []
  var seen = {}
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var m = lines[i].match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']#?([0-9A-Fa-f]{6})["']/)
    if (!m || seen[m[1]]) continue
    seen[m[1]] = true
    out.push({ name: m[1], hex: "#" + m[2].toLowerCase() })
  }
  return out
}

function paletteMap(entries) {
  var map = {}
  for (var i = 0; i < entries.length; i++) map[entries[i].name] = entries[i].hex
  if (!map.accent) map.accent = map.color4 || map.blue || "#88c0d0"
  if (!map.foreground) map.foreground = map.color7 || "#d8dee9"
  if (!map.background) map.background = map.color0 || "#101315"
  return map
}

function resolveSlot(slot, map) {
  var s = String(slot || "")
  if (s.charAt(0) === "#") return s.toLowerCase()
  return map[s] || map.accent || "#888888"
}

// ------------------------------------------------------------- Lua output

function luaString(s) {
  return '"' + String(s).replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\n/g, "\\n") + '"'
}

function luaNumber(n) {
  return formatNumber(n)
}

function luaKey(k) {
  return /^[A-Za-z_][A-Za-z0-9_]*$/.test(k) ? k : "[" + luaString(k) + "]"
}

function colorExpr(spec, gradient) {
  var slots = (spec.slots || []).filter(function(s) { return String(s) !== "" })
  if (slots.length === 0) slots = ["accent"]
  var alpha = Math.max(0, Math.min(255, Math.round(spec.alpha === undefined ? 255 : Number(spec.alpha))))
  var list = "{ " + slots.map(luaString).join(", ") + " }"
  if (gradient || slots.length > 1)
    return "hf.gradient(" + list + ", " + alpha + ", " + luaNumber(spec.angle === undefined ? 0 : spec.angle) + ")"
  return "hf.color(" + luaString(slots[0]) + ", " + alpha + ")"
}

var GRADIENT_KEYS = {
  "general:col.active_border": true, "general:col.inactive_border": true,
  "general:col.nogroup_border": true, "general:col.nogroup_border_active": true,
  "group:col.border_active": true, "group:col.border_inactive": true,
  "group:col.border_locked_active": true, "group:col.border_locked_inactive": true
}

function luaValue(key, v) {
  if (typeof v === "boolean") return v ? "true" : "false"
  if (typeof v === "number") return luaNumber(v)
  if (typeof v === "string") return luaString(v)
  if (isColorSpec(v)) return colorExpr(v, GRADIENT_KEYS[key] === true)
  if (isGaps(v)) {
    var g = gapsFrom(v)
    return "{ top = " + luaNumber(g.top) + ", right = " + luaNumber(g.right) + ", bottom = " + luaNumber(g.bottom) + ", left = " + luaNumber(g.left) + " }"
  }
  if (Array.isArray(v)) return "{ " + v.map(luaNumber).join(", ") + " }"
  return "nil"
}

// hyprctl names ("input:touchpad:tap-to-click") -> Lua table path
// (input.touchpad.tap_to_click): Hyprland's Lua API spells dashes as underscores.
function keyPath(key) {
  return String(key).split(/[:.]/).map(function(p) { return p.replace(/-/g, "_") })
}

function realOptions(options) {
  var out = {}
  for (var k in options) if (k.indexOf("hf:") !== 0 && options[k] !== undefined && options[k] !== null) out[k] = options[k]
  return out
}

function nest(options) {
  var tree = {}
  for (var key in options) {
    var parts = keyPath(key)
    var node = tree
    for (var i = 0; i < parts.length - 1; i++) {
      if (!node[parts[i]] || node[parts[i]].__leaf) node[parts[i]] = {}
      node = node[parts[i]]
    }
    node[parts[parts.length - 1]] = { __leaf: true, key: key, value: options[key] }
  }
  return tree
}

function renderTree(node, indent) {
  var pad = new Array(indent + 1).join(" ")
  var inner = pad + "  "
  var keys = Object.keys(node).sort()
  var lines = []
  for (var i = 0; i < keys.length; i++) {
    var n = node[keys[i]]
    if (n.__leaf) lines.push(inner + luaKey(keys[i]) + " = " + luaValue(n.key, n.value) + ",")
  }
  for (var j = 0; j < keys.length; j++) {
    var m = node[keys[j]]
    if (m.__leaf) continue
    lines.push(inner + luaKey(keys[j]) + " = " + renderTree(m, indent + 2) + ",")
  }
  return "{\n" + lines.join("\n") + "\n" + pad + "}"
}

var PRELUDE = [
  "local hf = {}",
  "",
  "-- The active theme's palette, read fresh on every reload so colors follow",
  "-- `omarchy theme set`. Fallbacks mirror the Omarchy shell's own.",
  "do",
  "  local P = {}",
  "  local file = io.open((os.getenv(\"HOME\") or \"\") .. \"/.local/state/omarchy/current/theme/colors.toml\", \"r\")",
  "  if file then",
  "    for line in file:lines() do",
  "      local name, hex = line:match(\"^%s*([%w_%-]+)%s*=%s*[\\\"']#?(%x%x%x%x%x%x)[\\\"']\")",
  "      if name and not P[name] then P[name] = hex:lower() end",
  "    end",
  "    file:close()",
  "  end",
  "  P.accent = P.accent or P.color4 or P.blue or \"88c0d0\"",
  "  P.foreground = P.foreground or P.color7 or \"d8dee9\"",
  "  P.background = P.background or P.color0 or \"101315\"",
  "  hf.palette = P",
  "end",
  "",
  "function hf.hex(slot)",
  "  if slot:sub(1, 1) == \"#\" then return slot:sub(2):lower() end",
  "  return hf.palette[slot] or hf.palette.accent",
  "end",
  "",
  "function hf.color(slot, alpha)",
  "  return string.format(\"rgba(%s%02x)\", hf.hex(slot), alpha)",
  "end",
  "",
  "function hf.gradient(slots, alpha, angle)",
  "  local colors = {}",
  "  for i, slot in ipairs(slots) do colors[i] = hf.color(slot, alpha) end",
  "  if #colors == 1 then return colors[1] end",
  "  return { colors = colors, angle = angle }",
  "end"
].join("\n")

// Records what each overridden key was *before* Hyprforge touched it, so the
// panel can show "Omarchy: 10px" next to a changed value. Best effort.
function renderBaseCapture(keys) {
  if (keys.length === 0) return ""
  var lines = [
    "-- Snapshot the values underneath these overrides for the panel's \"was\" hints.",
    "do",
    "  local keys = { " + keys.map(luaString).join(", ") + " }",
    "  local function enc(v)",
    "    local t = type(v)",
    "    if t == \"number\" then if v ~= v or v == math.huge or v == -math.huge then return \"null\" end return string.format(\"%.4f\", v):gsub(\"%.?0+$\", \"\") end",
    "    if t == \"boolean\" then return tostring(v) end",
    "    if t == \"string\" then return '\"' .. v:gsub('[%c\"\\\\]', '') .. '\"' end",
    "    if t == \"table\" then",
    "      if v.top ~= nil then return \"[\" .. enc(v.top) .. \",\" .. enc(v.right) .. \",\" .. enc(v.bottom) .. \",\" .. enc(v.left) .. \"]\" end",
    "      if v.x ~= nil then return \"{\\\"vec2\\\":[\" .. enc(v.x) .. \",\" .. enc(v.y) .. \"]}\" end",
    "    end",
    "    return \"null\"",
    "  end",
    "  local out = {}",
    "  for _, key in ipairs(keys) do",
    "    local ok, value = pcall(hl.get_config, key)",
    "    if ok then out[#out + 1] = '\"' .. key .. '\":' .. enc(value) end",
    "  end",
    "  local file = io.open((os.getenv(\"HOME\") or \"\") .. \"/.cache/hyprforge/base.json\", \"w\")",
    "  if file then file:write(\"{\" .. table.concat(out, \",\") .. \"}\\n\") file:close() end",
    "end"
  ]
  return lines.join("\n")
}

function renderConfig(options) {
  var real = realOptions(options)
  if (Object.keys(real).length === 0) return ""
  return "hl.config(" + renderTree(nest(real), 0) + ")"
}

// ------------------------------------------------------------- animations

var ANIM_LEAVES = [
  { leaf: "global", label: "Everything", styles: [] },
  { leaf: "windows", label: "Windows", styles: ["slide", "popin", "gnomed"], percent: "popin" },
  { leaf: "windowsIn", label: "Window open", styles: ["slide", "popin", "gnomed"], percent: "popin", parent: "windows" },
  { leaf: "windowsOut", label: "Window close", styles: ["slide", "popin", "gnomed"], percent: "popin", parent: "windows" },
  { leaf: "windowsMove", label: "Window move", styles: [], parent: "windows" },
  { leaf: "layers", label: "Shell surfaces", styles: ["slide", "popin", "fade"], parent: "global" },
  { leaf: "layersIn", label: "Surface open", styles: ["slide", "popin", "fade"], parent: "layers" },
  { leaf: "layersOut", label: "Surface close", styles: ["slide", "popin", "fade"], parent: "layers" },
  { leaf: "fade", label: "Fades", styles: [] },
  { leaf: "fadeIn", label: "Fade in", styles: [], parent: "fade" },
  { leaf: "fadeOut", label: "Fade out", styles: [], parent: "fade" },
  { leaf: "fadeSwitch", label: "Focus fade", styles: [], parent: "fade" },
  { leaf: "fadeDim", label: "Dim fade", styles: [], parent: "fade" },
  { leaf: "fadeLayersIn", label: "Surface fade in", styles: [], parent: "fade" },
  { leaf: "fadeLayersOut", label: "Surface fade out", styles: [], parent: "fade" },
  { leaf: "border", label: "Border color", styles: [] },
  { leaf: "workspaces", label: "Workspaces", styles: ["slide", "slidevert", "fade", "slidefade", "slidefadevert"], percent: "slidefade" },
  { leaf: "specialWorkspace", label: "Scratchpad", styles: ["slide", "slidevert", "fade", "slidefade", "slidefadevert"], percent: "slidefade", parent: "workspaces" },
  { leaf: "zoomFactor", label: "Zoom", styles: [] }
]

function leafInfo(leaf) {
  for (var i = 0; i < ANIM_LEAVES.length; i++) if (ANIM_LEAVES[i].leaf === leaf) return ANIM_LEAVES[i]
  return null
}

// Omarchy's shipped animation set, merged with a per-leaf override.
function effectiveAnim(leaf, baseline, anims) {
  var base = null
  for (var i = 0; i < (baseline ? baseline.animations.length : 0); i++)
    if (baseline.animations[i].leaf === leaf) base = baseline.animations[i]
  var over = anims ? anims[leaf] : null
  if (!base && !over) return null
  var out = { leaf: leaf, enabled: true, speed: 5, curve: "default", style: "" }
  if (base) {
    out.enabled = base.enabled !== false
    if (base.speed !== undefined && base.speed !== null && base.speed !== "") out.speed = Number(base.speed)
    if (base.curve) out.curve = base.curve
    if (base.style) out.style = base.style
  }
  if (over) {
    if (over.enabled !== undefined) out.enabled = over.enabled
    if (over.speed !== undefined) out.speed = Number(over.speed)
    if (over.curve !== undefined) out.curve = over.curve
    if (over.style !== undefined) out.style = over.style
  }
  out.overridden = !!over
  out.inherited = !base && !over
  return out
}

function curveKind(name, cfg, baseline) {
  if (cfg.curves[name]) return cfg.curves[name].type === "spring" ? "spring" : "bezier"
  if (baseline && baseline.curves) for (var i = 0; i < baseline.curves.length; i++)
    if (baseline.curves[i].name === name) return baseline.curves[i].type === "spring" ? "spring" : "bezier"
  return "bezier"
}

function renderCurves(cfg) {
  var names = Object.keys(cfg.curves).sort()
  var lines = []
  for (var i = 0; i < names.length; i++) {
    var c = cfg.curves[names[i]]
    if (c.type === "spring") {
      lines.push("hl.curve(" + luaString(names[i]) + ", { type = \"spring\", mass = " + luaNumber(c.mass || 1)
        + ", stiffness = " + luaNumber(c.stiffness || 100) + ", dampening = " + luaNumber(c.dampening || 10) + " })")
    } else {
      var p = c.points || [0.25, 0.1, 0.25, 1]
      lines.push("hl.curve(" + luaString(names[i]) + ", { type = \"bezier\", points = { { " + luaNumber(p[0]) + ", "
        + luaNumber(p[1]) + " }, { " + luaNumber(p[2]) + ", " + luaNumber(p[3]) + " } } })")
    }
  }
  return lines.join("\n")
}

function renderAnimation(a, speedMul, cfg, baseline) {
  var parts = ["leaf = " + luaString(a.leaf), "enabled = " + (a.enabled ? "true" : "false")]
  if (a.enabled) {
    var s = Math.max(0.1, Math.round((a.speed / speedMul) * 100) / 100)
    parts.push("speed = " + luaNumber(s))
    var kind = curveKind(a.curve, cfg, baseline)
    parts.push((kind === "spring" ? "spring = " : "bezier = ") + luaString(a.curve || "default"))
    if (a.style) parts.push("style = " + luaString(a.style))
  }
  return "hl.animation({ " + parts.join(", ") + " })"
}

function renderAnimations(cfg, baseline) {
  var lines = []
  var mul = Number(cfg.options["hf:anim_speed"])
  if (!isFinite(mul) || mul <= 0) mul = 1
  var leaves = {}
  if (mul !== 1 && baseline) for (var i = 0; i < baseline.animations.length; i++) leaves[baseline.animations[i].leaf] = true
  for (var l in cfg.anims) leaves[l] = true
  var order = Object.keys(leaves).sort(function(a, b) { return animOrder(a) - animOrder(b) })
  for (var j = 0; j < order.length; j++) {
    var eff = effectiveAnim(order[j], baseline, cfg.anims)
    if (eff) lines.push(renderAnimation(eff, mul, cfg, baseline))
  }
  if (cfg.options["hf:border_rotate"] === true) {
    var secs = Number(cfg.options["hf:border_rotate_speed"]) || 6
    lines.push("hl.animation({ leaf = \"borderangle\", enabled = true, speed = " + luaNumber(Math.max(1, Math.round(secs * 10))) + ", bezier = \"linear\", style = \"loop\" })")
  }
  return lines.join("\n")
}

function animOrder(leaf) {
  for (var i = 0; i < ANIM_LEAVES.length; i++) if (ANIM_LEAVES[i].leaf === leaf) return i
  return 100
}

// ------------------------------------------------------------------ rules

// Effects the rule editor offers. `type` drives the editor and the Lua shape.
var RULE_EFFECTS = [
  { key: "opacity", label: "Opacity", type: "opacity", desc: "Focused / unfocused opacity multiplier." },
  { key: "opaque", label: "Force opaque", type: "bool", desc: "Ignore every opacity setting for this app." },
  { key: "no_blur", label: "No blur", type: "bool" },
  { key: "no_shadow", label: "No shadow", type: "bool" },
  { key: "no_dim", label: "Never dim", type: "bool" },
  { key: "no_anim", label: "No animations", type: "bool" },
  { key: "rounding", label: "Rounding", type: "int", min: 0, max: 30, unit: "px" },
  { key: "border_size", label: "Border width", type: "int", min: 0, max: 12, unit: "px" },
  { key: "border_color", label: "Border color", type: "color" },
  { key: "float", label: "Float", type: "bool" },
  { key: "center", label: "Center (floating)", type: "bool" },
  { key: "size", label: "Size (floating)", type: "size", desc: "Width × height in px, or % of the monitor." },
  { key: "pin", label: "Pin on all workspaces", type: "bool", desc: "Floating windows only." },
  { key: "workspace", label: "Open on workspace", type: "text", desc: "e.g. 3, or 3 silent." },
  { key: "monitor", label: "Open on monitor", type: "text", desc: "e.g. DP-1 or 1." },
  { key: "fullscreen", label: "Open fullscreen", type: "bool" },
  { key: "maximize", label: "Open maximized", type: "bool" },
  { key: "animation", label: "Animation style", type: "enum", options: ["popin", "popin 80%", "slide", "slide top", "slide bottom", "slide left", "slide right", "gnomed"] },
  { key: "idle_inhibit", label: "Keep screen awake", type: "enum", options: ["none", "focus", "fullscreen", "always"] },
  { key: "keep_aspect_ratio", label: "Keep aspect ratio", type: "bool" },
  { key: "no_screen_share", label: "Hide from screen share", type: "bool" },
  { key: "no_focus", label: "Never focus", type: "bool" },
  { key: "stay_focused", label: "Stay focused", type: "bool" },
  { key: "dim_around", label: "Dim everything around", type: "bool" },
  { key: "xray", label: "Blur x-ray", type: "bool" },
  { key: "immediate", label: "Allow tearing", type: "bool", desc: "Needs 'Allow tearing' in Windows & Gaps." },
  { key: "render_unfocused", label: "Render when hidden", type: "bool" },
  { key: "scroll_mouse", label: "Mouse scroll factor", type: "float", min: 0.1, max: 3, step: 0.05, decimals: 2 },
  { key: "scroll_touchpad", label: "Touchpad scroll factor", type: "float", min: 0.1, max: 3, step: 0.05, decimals: 2 }
]

var MATCH_FIELDS = [
  { key: "class", label: "Class", type: "text" },
  { key: "title", label: "Title", type: "text" },
  { key: "initial_class", label: "Initial class", type: "text" },
  { key: "initial_title", label: "Initial title", type: "text" },
  { key: "float", label: "Only floating", type: "bool" },
  { key: "xwayland", label: "Only XWayland", type: "bool" }
]

function effectInfo(key) {
  for (var i = 0; i < RULE_EFFECTS.length; i++) if (RULE_EFFECTS[i].key === key) return RULE_EFFECTS[i]
  return null
}

function escapeRegex(s) {
  return String(s).replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
}

function classMatch(cls) {
  return "^(" + escapeRegex(cls) + ")$"
}

function ruleEffectLua(key, v) {
  var info = effectInfo(key)
  var type = info ? info.type : ""
  if (type === "opacity") {
    var a = Array.isArray(v) ? v : [v, v]
    return luaString(formatNumber(a[0]) + " " + formatNumber(a[1] === undefined ? a[0] : a[1]))
  }
  if (type === "size") {
    var s = Array.isArray(v) ? v : [800, 600]
    return "{ " + luaString(String(s[0])) + ", " + luaString(String(s[1])) + " }"
  }
  if (type === "color") return colorExpr(v, true)
  return luaValue("", v)
}

function renderRule(rule) {
  var match = []
  var keys = Object.keys(rule.match || {}).sort()
  for (var i = 0; i < keys.length; i++) {
    var mv = rule.match[keys[i]]
    if (mv === "" || mv === undefined || mv === null) continue
    match.push(luaKey(keys[i]) + " = " + luaValue("", mv))
  }
  if (match.length === 0) return ""
  var effects = []
  var ek = Object.keys(rule.effects || {})
  for (var j = 0; j < ek.length; j++) {
    var ev = rule.effects[ek[j]]
    if (ev === undefined || ev === null || ev === "") continue
    if (ek[j] === "size" || ek[j] === "border_color") continue
    effects.push(luaKey(ek[j]) + " = " + ruleEffectLua(ek[j], ev))
  }
  var out = []
  var id = String(rule.id || "rule").replace(/[^A-Za-z0-9_-]/g, "")
  var head = "{ name = " + luaString("hyprforge-" + id) + ", match = { " + match.join(", ") + " }"
  if (effects.length > 0) out.push("hl.window_rule(" + head + ", " + effects.join(", ") + " })")
  // Size/border_color render as separate rules: size only applies to floating
  // windows and border_color wants its own focus split.
  if (rule.effects && rule.effects.size) {
    out.push("hl.window_rule({ name = " + luaString("hyprforge-" + id + "-size") + ", match = { " + match.join(", ") + " }, size = " + ruleEffectLua("size", rule.effects.size) + " })")
  }
  if (rule.effects && isColorSpec(rule.effects.border_color)) {
    out.push("hl.window_rule({ name = " + luaString("hyprforge-" + id + "-border") + ", match = { " + match.join(", ") + ", focus = true }, border_color = " + ruleEffectLua("border_color", rule.effects.border_color) + " })")
  }
  return out.join("\n")
}

function renderRules(cfg) {
  var o = cfg.options
  var lines = []

  var baseA = o["hf:base_active"], baseI = o["hf:base_inactive"]
  if (baseA !== undefined || baseI !== undefined) {
    var a = baseA !== undefined ? baseA : 0.985
    var i = baseI !== undefined ? baseI : 0.96
    lines.push("-- Replaces Omarchy's blanket opacity rule (last matching rule wins).")
    lines.push("hl.window_rule({ name = \"hyprforge-base-opacity\", match = { tag = \"default-opacity\" }, opacity = " + luaString(formatNumber(a) + " " + formatNumber(i)) + " })")
  }

  if (o["hf:smart_gaps"] === true) {
    lines.push("-- Smart gaps: no gaps around a lone tiled window.")
    lines.push("hl.workspace_rule({ workspace = \"w[tv1]\", gaps_out = 0, gaps_in = 0 })")
    lines.push("hl.workspace_rule({ workspace = \"f[1]\", gaps_out = 0, gaps_in = 0 })")
  }
  if (o["hf:smart_borders"] === true) {
    lines.push("-- Smart borders: no border or rounding on a lone tiled window.")
    lines.push("hl.window_rule({ name = \"hyprforge-smart-border-single\", match = { float = false, workspace = \"w[tv1]\" }, border_size = 0, rounding = 0 })")
    lines.push("hl.window_rule({ name = \"hyprforge-smart-border-full\", match = { float = false, workspace = \"f[1]\" }, border_size = 0, rounding = 0 })")
  }
  if (o["hf:shell_blur"] === true) {
    var alpha = o["hf:shell_blur_alpha"] !== undefined ? o["hf:shell_blur_alpha"] : 0.2
    lines.push("-- Frosted glass behind Omarchy shell surfaces.")
    lines.push("hl.layer_rule({ name = \"hyprforge-shell-blur\", match = { namespace = \"^omarchy-(bar|menu|notifications|osd|clipboard|emojis|polkit|reminders|keyboard-panel)$\" }, blur = true, ignore_alpha = " + luaNumber(alpha) + " })")
  }

  var userRules = []
  for (var r = 0; r < cfg.rules.length; r++) {
    if (cfg.rules[r].enabled === false) continue
    var text = renderRule(cfg.rules[r])
    if (text) userRules.push((cfg.rules[r].name ? "-- " + String(cfg.rules[r].name).replace(/\n/g, " ") + "\n" : "") + text)
  }
  if (userRules.length > 0) {
    lines.push("-- App rules")
    lines.push(userRules.join("\n"))
  }
  return lines.join("\n")
}

// ------------------------------------------------------------ whole file

// ctx: { baseline, preview }
//   preview  omit rules and the base snapshot; that text goes to `hyprctl eval`,
//            where re-registering rules would stack duplicates until reload.
function render(cfgIn, ctx) {
  var cfg = normalize(cfgIn)
  ctx = ctx || {}
  var chunks = []
  var needsPalette = false
  for (var k in cfg.options) if (isColorSpec(cfg.options[k])) needsPalette = true
  for (var r = 0; r < cfg.rules.length; r++)
    if (cfg.rules[r].effects && isColorSpec(cfg.rules[r].effects.border_color)) needsPalette = true

  if (needsPalette) chunks.push(PRELUDE)
  if (!ctx.preview) {
    var keys = Object.keys(realOptions(cfg.options)).filter(function(key) { return !isColorSpec(cfg.options[key]) }).sort()
    var capture = renderBaseCapture(keys)
    if (capture) chunks.push(capture)
  }
  var config = renderConfig(cfg.options)
  if (config) chunks.push(config)
  var curves = renderCurves(cfg)
  if (curves) chunks.push(curves)
  var anims = renderAnimations(cfg, ctx.baseline)
  if (anims) chunks.push(anims)
  if (!ctx.preview) {
    var rules = renderRules(cfg)
    if (rules) chunks.push(rules)
  }
  return chunks.join("\n\n")
}

var HEADER = [
  "-- Hyprforge — generated by the aziz.hyprforge Omarchy plugin.",
  "--",
  "-- Rendered from ~/.config/hypr/hyprforge/state.json every time you change",
  "-- something in the panel (SUPER+SPACE › Hyprforge). Edits made here are",
  "-- overwritten; put hand-written config in looknfeel.lua instead.",
  "-- Delete this file, or its require line in hyprland.lua, to switch it off."
].join("\n")

function renderFile(cfg, ctx) {
  var body = render(cfg, ctx)
  return HEADER + "\n\n" + (body ? body + "\n" : "-- Nothing overridden: Omarchy defaults and your own files apply.\n")
}

// The single line Hyprforge adds to hyprland.lua. Optional-require, so
// removing the plugin and its file never breaks Hyprland.
var HOOK_LINE = "require(\"default.hypr.require_optional\").module(\"hypr.hyprforge\") -- Hyprforge (Omarchy plugin)"

function hasHook(text) {
  return String(text || "").indexOf("\"hypr.hyprforge\"") !== -1
}

// Insert the hook after the user's own modules and before Omarchy toggles, so
// Hyprforge beats looknfeel.lua/input.lua but toggles like "no gaps" still win.
function addHook(text) {
  var src = String(text || "")
  if (hasHook(src)) return src
  var lines = src.split("\n")
  var at = -1
  for (var i = 0; i < lines.length; i++) {
    if (/^\s*require\("hypr\.(autostart|looknfeel|bindings|input|monitors)"\)/.test(lines[i])) at = i
  }
  if (at === -1) {
    for (var j = 0; j < lines.length; j++) if (/require\("default\.hypr\.toggles"\)/.test(lines[j])) { at = j - 1; break }
  }
  if (at === -1) return src.replace(/\n*$/, "\n") + "\n" + HOOK_LINE + "\n"
  lines.splice(at + 1, 0, HOOK_LINE)
  return lines.join("\n")
}

function removeHook(text) {
  return String(text || "").split("\n").filter(function(l) { return l.indexOf("\"hypr.hyprforge\"") === -1 }).join("\n")
}

// --------------------------------------------------------------- presets

function spec(slots, alpha, angle) {
  var s = { slots: slots, alpha: alpha === undefined ? 238 : alpha }
  if (angle !== undefined) s.angle = angle
  return s
}

// Keys a "look" preset owns: applying one clears these first so looks don't
// bleed into each other. Layout, input and behaviour are never touched.
var LOOK_SECTIONS = ["windows", "borders", "corners", "opacity", "dimming", "blur", "shadow", "glow"]

var LOOKS = [
  {
    id: "stock", name: "Omarchy", desc: "Back to the shipped look.",
    options: {}
  },
  {
    id: "glass", name: "Frosted glass", desc: "Translucent windows over a soft, vibrant blur.",
    options: {
      "hf:base_active": 0.93, "hf:base_inactive": 0.85,
      "decoration:blur:enabled": true, "decoration:blur:size": 7, "decoration:blur:passes": 3,
      "decoration:blur:vibrancy": 0.25, "decoration:blur:noise": 0.02, "decoration:blur:popups": true,
      "hf:shell_blur": true, "decoration:rounding": 12, "decoration:rounding_power": 3,
      "decoration:shadow:enabled": true, "decoration:shadow:range": 22, "decoration:shadow:render_power": 3,
      "decoration:shadow:color": spec(["background"], 0x99),
      "general:col.active_border": spec(["accent", "foreground"], 0xcc, 45),
      "general:col.inactive_border": spec(["foreground"], 0x22)
    }
  },
  {
    id: "neon", name: "Neon", desc: "Spinning palette gradient with a colored glow.",
    options: {
      "general:border_size": 3, "decoration:rounding": 10,
      "general:col.active_border": spec(["accent", "magenta", "cyan", "accent"], 0xff, 45),
      "general:col.inactive_border": spec(["muted"], 0x88),
      "hf:border_rotate": true, "hf:border_rotate_speed": 5,
      "decoration:shadow:enabled": true, "decoration:shadow:range": 18, "decoration:shadow:render_power": 2,
      "decoration:shadow:color": spec(["accent"], 0x66), "decoration:shadow:color_inactive": spec(["background"], 0x00),
      "decoration:glow:enabled": true, "decoration:glow:range": 8, "decoration:glow:render_power": 3,
      "decoration:glow:color": spec(["accent"], 0x55), "decoration:glow:color_inactive": spec(["background"], 0x00)
    }
  },
  {
    id: "soft", name: "Soft & rounded", desc: "Squircle corners, roomy gaps, gentle shadow.",
    options: {
      "general:gaps_in": 8, "general:gaps_out": 16, "general:border_size": 2,
      "decoration:rounding": 16, "decoration:rounding_power": 4,
      "decoration:shadow:enabled": true, "decoration:shadow:range": 28, "decoration:shadow:render_power": 4,
      "decoration:shadow:offset": [0, 6], "decoration:shadow:color": spec(["darker_background"], 0x88),
      "general:col.active_border": spec(["accent"], 0xee),
      "general:col.inactive_border": spec(["lighter_background"], 0xaa)
    }
  },
  {
    id: "flat", name: "Flat & sharp", desc: "Square corners, hairline borders, no effects.",
    options: {
      "general:gaps_in": 3, "general:gaps_out": 6, "general:border_size": 1,
      "decoration:rounding": 0, "decoration:shadow:enabled": false, "decoration:blur:enabled": false,
      "hf:base_active": 1, "hf:base_inactive": 1,
      "general:col.active_border": spec(["accent"], 0xff),
      "general:col.inactive_border": spec(["selection"], 0xff)
    }
  },
  {
    id: "zen", name: "Zen focus", desc: "Everything but the focused window recedes.",
    options: {
      "decoration:dim_inactive": true, "decoration:dim_strength": 0.3,
      "decoration:inactive_opacity": 0.9, "general:border_size": 1,
      "general:col.active_border": spec(["accent"], 0xcc),
      "general:col.inactive_border": spec(["background"], 0x00),
      "decoration:rounding": 8, "hf:smart_gaps": true
    }
  },
  {
    id: "compact", name: "Compact", desc: "Maximum screen space for small displays.",
    options: {
      "general:gaps_in": 2, "general:gaps_out": 3, "general:border_size": 1,
      "decoration:rounding": 4, "hf:smart_gaps": true, "hf:smart_borders": true
    }
  },
  {
    id: "retro", name: "Retro", desc: "Thick square borders with a hard offset shadow.",
    options: {
      "general:gaps_in": 8, "general:gaps_out": 14, "general:border_size": 3,
      "decoration:rounding": 0, "hf:base_active": 1, "hf:base_inactive": 1,
      "decoration:shadow:enabled": true, "decoration:shadow:sharp": true, "decoration:shadow:range": 1,
      "decoration:shadow:offset": [8, 8], "decoration:shadow:color": spec(["accent"], 0xff),
      "decoration:shadow:color_inactive": spec(["muted"], 0xff),
      "general:col.active_border": spec(["foreground"], 0xff),
      "general:col.inactive_border": spec(["foreground"], 0x88)
    }
  },
  {
    id: "performance", name: "Performance", desc: "No blur, shadow or glow; opaque windows; snappy motion.",
    options: {
      "decoration:blur:enabled": false, "decoration:shadow:enabled": false, "decoration:glow:enabled": false,
      "hf:base_active": 1, "hf:base_inactive": 1, "decoration:dim_inactive": false
    },
    extra: { "hf:anim_speed": 1.6 }
  }
]

function lookById(id) {
  for (var i = 0; i < LOOKS.length; i++) if (LOOKS[i].id === id) return LOOKS[i]
  return null
}

// Animation presets rewrite cfg.anims + custom curves.
var MOTIONS = [
  { id: "omarchy", name: "Omarchy", desc: "The shipped motion.", curves: {}, anims: {} },
  {
    id: "snappy", name: "Snappy", desc: "Fast and decisive.",
    curves: { hf_snap: { type: "bezier", points: [0.16, 1, 0.3, 1] } },
    anims: {
      windows: { enabled: true, speed: 2.5, curve: "hf_snap", style: "" },
      windowsIn: { enabled: true, speed: 2.5, curve: "hf_snap", style: "popin 90%" },
      windowsOut: { enabled: true, speed: 1.4, curve: "hf_snap", style: "popin 90%" },
      windowsMove: { enabled: true, speed: 2.2, curve: "hf_snap", style: "" },
      fade: { enabled: true, speed: 2, curve: "hf_snap", style: "" },
      workspaces: { enabled: true, speed: 2.6, curve: "hf_snap", style: "slide" }
    }
  },
  {
    id: "smooth", name: "Smooth", desc: "Unhurried, cinematic easing.",
    curves: { hf_smooth: { type: "bezier", points: [0.45, 0, 0.2, 1] } },
    anims: {
      windows: { enabled: true, speed: 5, curve: "hf_smooth", style: "" },
      windowsIn: { enabled: true, speed: 5, curve: "hf_smooth", style: "popin 85%" },
      windowsOut: { enabled: true, speed: 3.5, curve: "hf_smooth", style: "popin 85%" },
      windowsMove: { enabled: true, speed: 5, curve: "hf_smooth", style: "" },
      fade: { enabled: true, speed: 4, curve: "hf_smooth", style: "" },
      workspaces: { enabled: true, speed: 6, curve: "hf_smooth", style: "slidefade 20%" },
      specialWorkspace: { enabled: true, speed: 5, curve: "hf_smooth", style: "slidefadevert 20%" }
    }
  },
  {
    id: "bouncy", name: "Bouncy", desc: "Springy windows with a little overshoot.",
    curves: {
      hf_spring: { type: "spring", mass: 1, stiffness: 120, dampening: 14 },
      hf_overshoot: { type: "bezier", points: [0.34, 1.56, 0.64, 1] }
    },
    anims: {
      windows: { enabled: true, speed: 4, curve: "hf_spring", style: "" },
      windowsIn: { enabled: true, speed: 4, curve: "hf_overshoot", style: "popin 70%" },
      windowsOut: { enabled: true, speed: 2, curve: "default", style: "popin 80%" },
      windowsMove: { enabled: true, speed: 4, curve: "hf_spring", style: "" },
      workspaces: { enabled: true, speed: 4, curve: "hf_overshoot", style: "slide" },
      layersIn: { enabled: true, speed: 3, curve: "hf_overshoot", style: "popin 90%" }
    }
  },
  {
    id: "slide", name: "Slide", desc: "Everything slides in from its edge.",
    curves: { hf_glide: { type: "bezier", points: [0.22, 1, 0.36, 1] } },
    anims: {
      windowsIn: { enabled: true, speed: 3.5, curve: "hf_glide", style: "slide" },
      windowsOut: { enabled: true, speed: 2.5, curve: "hf_glide", style: "slide" },
      windowsMove: { enabled: true, speed: 3.5, curve: "hf_glide", style: "" },
      layersIn: { enabled: true, speed: 3, curve: "hf_glide", style: "slide" },
      layersOut: { enabled: true, speed: 2, curve: "hf_glide", style: "slide" },
      workspaces: { enabled: true, speed: 4, curve: "hf_glide", style: "slide" }
    }
  },
  {
    id: "fade", name: "Fade", desc: "Calm cross-fades, no movement.",
    curves: {},
    anims: {
      windowsIn: { enabled: true, speed: 3, curve: "easeOutQuint", style: "popin 98%" },
      windowsOut: { enabled: true, speed: 2, curve: "linear", style: "popin 98%" },
      workspaces: { enabled: true, speed: 3.5, curve: "easeInOutCubic", style: "fade" },
      specialWorkspace: { enabled: true, speed: 3, curve: "easeInOutCubic", style: "fade" }
    }
  },
  {
    id: "minimal", name: "Minimal", desc: "Only quick fades; windows appear instantly.",
    curves: {},
    anims: {
      windows: { enabled: false }, windowsIn: { enabled: false }, windowsOut: { enabled: false },
      windowsMove: { enabled: false }, workspaces: { enabled: false }, specialWorkspace: { enabled: false },
      fade: { enabled: true, speed: 1.5, curve: "quick", style: "" }
    }
  }
]

function motionById(id) {
  for (var i = 0; i < MOTIONS.length; i++) if (MOTIONS[i].id === id) return MOTIONS[i]
  return null
}

// ------------------------------------------------------------- curve maths

// Cubic bezier y for a given x (0..1), anchored at (0,0) and (1,1).
function bezierAt(p, x) {
  var x1 = p[0], y1 = p[1], x2 = p[2], y2 = p[3]
  function bx(t) { var u = 1 - t; return 3 * u * u * t * x1 + 3 * u * t * t * x2 + t * t * t }
  function by(t) { var u = 1 - t; return 3 * u * u * t * y1 + 3 * u * t * t * y2 + t * t * t }
  var lo = 0, hi = 1, t = x
  for (var i = 0; i < 30; i++) {
    t = (lo + hi) / 2
    if (bx(t) < x) lo = t; else hi = t
  }
  return by(t)
}

// Damped spring from 0 to 1, sampled at `n` points over its settle time.
function springSamples(c, n) {
  var m = Math.max(0.01, Number(c.mass) || 1)
  var k = Math.max(0.01, Number(c.stiffness) || 100)
  var d = Math.max(0, Number(c.dampening) || 10)
  var dt = 1 / 240, x = 0, v = 0, out = []
  var steps = 0, settle = 0
  var trace = []
  while (steps < 240 * 4) {
    var a = (-k * (x - 1) - d * v) / m
    v += a * dt
    x += v * dt
    trace.push(x)
    steps++
    if (Math.abs(x - 1) < 0.001 && Math.abs(v) < 0.001) { settle = steps; break }
  }
  if (settle === 0) settle = steps
  for (var i = 0; i < n; i++) out.push(trace[Math.min(trace.length - 1, Math.round(i / (n - 1) * (settle - 1)))])
  return out
}

function curveSamples(curve, n) {
  if (!curve) return []
  if (curve.type === "spring") return springSamples(curve, n)
  var p = curve.points || [0.25, 0.1, 0.25, 1]
  var out = []
  for (var i = 0; i < n; i++) out.push(bezierAt(p, i / (n - 1)))
  return out
}

function curveByName(name, cfg, baseline) {
  var c = normalize(cfg)
  if (c.curves[name]) return c.curves[name]
  if (baseline && baseline.curves) for (var i = 0; i < baseline.curves.length; i++)
    if (baseline.curves[i].name === name) return baseline.curves[i]
  if (name === "default") return { type: "bezier", points: [0, 0.75, 0.15, 1] }
  return null
}

function curveNames(cfg, baseline) {
  var names = ["default"]
  if (baseline && baseline.curves) for (var i = 0; i < baseline.curves.length; i++)
    if (names.indexOf(baseline.curves[i].name) === -1) names.push(baseline.curves[i].name)
  var custom = Object.keys(normalize(cfg).curves).sort()
  for (var j = 0; j < custom.length; j++) if (names.indexOf(custom[j]) === -1) names.push(custom[j])
  return names
}

// ---------------------------------------------------------------- diffing

// Which catalogue keys differ between two configs (for history labels).
function diffKeys(a, b) {
  var x = normalize(a), y = normalize(b)
  var out = []
  var keys = {}
  for (var k in x.options) keys[k] = true
  for (var k2 in y.options) keys[k2] = true
  for (var key in keys) if (!valuesEqual(x.options[key], y.options[key])) out.push(key)
  if (!valuesEqual(x.anims, y.anims) || !valuesEqual(x.curves, y.curves)) out.push("animations")
  if (!valuesEqual(x.rules, y.rules)) out.push("rules")
  return out
}

function newId() {
  return Math.random().toString(36).slice(2, 8)
}
