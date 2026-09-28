// node test/run.js
//
// Loads Schema.js and Engine.js outside QML, checks every catalogue key
// against a `hyprctl descriptions -j` fixture, renders every preset, rule
// effect and motion, and runs the generated Lua through `luac -p` plus a stub
// harness that records what hl.* received.

const fs = require("fs")
const path = require("path")
const vm = require("vm")
const { execFileSync } = require("child_process")
const os = require("os")

const root = path.join(__dirname, "..")
function load(file) {
  const src = fs.readFileSync(path.join(root, file), "utf8").replace(/^\.pragma library\s*/, "")
  const ctx = {}
  vm.createContext(ctx)
  vm.runInContext(src, ctx, { filename: file })
  return ctx
}

const Schema = load("Schema.js")
const Engine = load("Engine.js")
const desc = JSON.parse(fs.readFileSync(path.join(__dirname, "descriptions.fixture.json"), "utf8"))
const known = new Set(desc.map(d => d.name))

let failures = 0
function check(cond, msg) {
  if (!cond) { failures++; console.log("FAIL", msg) }
}

// 1. catalogue keys exist
const items = Schema.allItems()
for (const it of items) {
  if (Schema.isSynthetic(it.key)) { check(it.key in Schema.SYNTHETIC, "synthetic default missing: " + it.key); continue }
  check(known.has(it.key), "unknown hyprland key: " + it.key)
  if (it.needs) check(!!Schema.itemFor(it.needs), `needs ${it.needs} (from ${it.key}) not in catalogue`)
  if (it.type === "enum") check(Array.isArray(it.options) && it.options.length > 1, "enum without options: " + it.key)
}
// enum maps agree with Hyprland's
for (const it of items) {
  const d = desc.find(x => x.name === it.key)
  if (!d || !d.map || it.type !== "enum") continue
  const values = new Set(d.map.map(m => Object.values(m)[0]))
  for (const o of it.options) check(values.has(Number(o.value)), `enum ${it.key} value ${o.value} not in hyprland map`)
}
console.log(`catalogue: ${items.length} items, ${Schema.SECTIONS.length} sections`)

// 1b. every option's Lua path exists in Hyprland's own API stubs
{
  const stubPath = "/usr/share/hypr/stubs/hl.meta.lua"
  if (fs.existsSync(stubPath)) {
    const stub = fs.readFileSync(stubPath, "utf8")
    const luaKeys = new Set([...stub.matchAll(/---@field \['([^']+)'\]/g)].map(m => m[1]))
    for (const d of desc) check(luaKeys.has(Engine.keyPath(d.name).join(".")), "no Lua path for " + d.name)
  }
}

// 2. generated catalogue for every description
let generated = 0
for (const d of desc) { const it = Engine.itemFromDescription(d, undefined); if (it.type) generated++ }
check(generated === desc.length, "itemFromDescription failed for some")

// 3. render: presets + motions + rules + synthetics
const baseline = JSON.parse(execFileSync("lua", [path.join(root, "baseline.lua"), "/usr/share/omarchy/default/hypr/looknfeel.lua"]).toString())
check(baseline.animations.length > 10, "baseline animations parsed")

function renderAll(cfg, label) {
  const text = Engine.renderFile(cfg, { baseline })
  const prev = Engine.render(cfg, { baseline, preview: true })
  const tmp = path.join(os.tmpdir(), "hyprforge-test.lua")
  for (const [name, src] of [["file", text], ["preview", prev]]) {
    fs.writeFileSync(tmp, src)
    try { execFileSync("luac", ["-p", tmp], { stdio: "pipe" }) }
    catch (e) { check(false, `${label}/${name}: luac: ${e.stderr}`); console.log(src); return null }
  }
  fs.writeFileSync(tmp, text)
  try {
    return execFileSync("lua", [path.join(__dirname, "harness.lua"), tmp], { stdio: "pipe" }).toString()
  } catch (e) { check(false, `${label}: harness: ${e.stderr}`); console.log(text); return null }
}

for (const look of Engine.LOOKS) {
  const cfg = Engine.defaultConfig()
  Object.assign(cfg.options, JSON.parse(JSON.stringify(look.options)), look.extra || {})
  const out = renderAll(cfg, "look " + look.id)
  if (out === null) continue
  for (const k of Object.keys(look.options)) {
    if (k.startsWith("hf:")) continue
    check(out.includes("k\t" + k.replace(/[.]/g, ":")), `look ${look.id}: ${k} not emitted`)
  }
}

for (const m of Engine.MOTIONS) {
  const cfg = Engine.defaultConfig()
  cfg.curves = JSON.parse(JSON.stringify(m.curves)); cfg.anims = JSON.parse(JSON.stringify(m.anims))
  cfg.options["hf:anim_speed"] = 1.5
  const out = renderAll(cfg, "motion " + m.id)
  if (out === null) continue
  for (const leaf of Object.keys(m.anims)) check(out.includes("a\t" + leaf + "\t"), `motion ${m.id}: ${leaf} missing`)
  for (const c of Object.keys(m.curves)) check(out.includes("c\t" + c + "\t"), `motion ${m.id}: curve ${c} missing`)
}

{
  const cfg = Engine.defaultConfig()
  cfg.options = {
    "general:gaps_out": { top: 4, right: 10, bottom: 10, left: 10 }, "general:gaps_in": 5,
    "decoration:shadow:offset": [2, 4], "input:touchpad:tap-to-click": false,
    "general:col.active_border": { slots: ["accent", "#ff00aa"], alpha: 200, angle: 90 },
    "general:col.inactive_border": { slots: ["muted"], alpha: 170 },
    "hf:smart_gaps": true, "hf:smart_borders": true, "hf:shell_blur": true, "hf:border_rotate": true,
    "hf:base_active": 1, "misc:swallow_regex": "^(Alacritty|kitty)$", "input:accel_profile": "flat"
  }
  const effects = {}
  for (const e of Engine.RULE_EFFECTS) {
    effects[e.key] = e.type === "bool" ? true : e.type === "opacity" ? [0.9, 0.8] : e.type === "size" ? ["60%", "70%"]
      : e.type === "color" ? { slots: ["red"], alpha: 255 } : e.type === "enum" ? e.options[1] : e.type === "text" ? "3 silent" : (e.min || 1)
  }
  cfg.rules = [{ id: "abc123", enabled: true, name: "Firefox \"test\"", match: { class: Engine.classMatch("org.mozilla.firefox") }, effects }]
  const out = renderAll(cfg, "kitchen sink")
  if (out !== null) {
    check(out.includes("k\tgeneral:gaps_out\ttable"), "css gaps table")
    check(out.includes("k\tinput:touchpad:tap_to_click\tboolean\tfalse"), "hyphenated key")
    check(/k\tgeneral:col:active_border:colors:1\tstring\trgba\([0-9a-f]{6}c8\)/.test(out), "palette gradient resolved")
    check(out.includes("k\tgeneral:col:active_border:colors:2\tstring\trgba(ff00aac8)"), "custom hex slot")
    check(out.includes("w\thyprforge-abc123\t"), "app rule emitted")
    check(out.includes("w\thyprforge-abc123-size\t"), "size rule emitted")
    check(out.includes("s\tw[tv1]"), "smart gaps rule")
    check(out.includes("l\thyprforge-shell-blur"), "shell blur rule")
    check(out.includes("w\thyprforge-base-opacity"), "base opacity rule")
    check(out.includes("a\tborderangle\t"), "border rotate")
  }
}

// 4. hook insertion
{
  const src = fs.readFileSync(path.join(os.homedir(), ".config/hypr/hyprland.lua"), "utf8")
  const hooked = Engine.addHook(Engine.removeHook(src))
  const lines = hooked.split("\n")
  const hook = lines.findIndex(l => l.includes('"hypr.hyprforge"'))
  const autostart = lines.findIndex(l => l.includes('require("hypr.autostart")'))
  const toggles = lines.findIndex(l => l.includes('require("default.hypr.toggles")'))
  check(hook > autostart && hook < toggles, "hook placed between user modules and toggles")
  check(Engine.addHook(hooked) === hooked, "hook idempotent")
  check(Engine.removeHook(hooked) === Engine.removeHook(src), "hook removal restores")
}

// 5. value helpers
check(Engine.quantize({ type: "gaps" }, { top: 3, right: 3, bottom: 3, left: 3 }) === 3, "uniform gaps collapse")
check(Math.abs(Engine.bezierAt([0.42, 0, 0.58, 1], 0.5) - 0.5) < 0.01, "bezier midpoint")
const spring = Engine.curveSamples({ type: "spring", mass: 1, stiffness: 120, dampening: 8 }, 60)
check(Math.max(...spring) > 1.01 && Math.abs(spring[59] - 1) < 0.02, "spring overshoots and settles")
const live = Engine.parseGetoptions('{"option": "general:gaps_out", "css": "10 10 10 10", "set": true }\n{"option": "decoration:shadow:offset", "vec2": [0,3], "set": false }')
check(live["general:gaps_out"] === 10 && live["decoration:shadow:offset"][1] === 3, "getoption parse")
check(Engine.parsePalette('accent = "#a88bff"\nred = "#ff6f91"').length === 2, "palette parse")

// 6. validation
{
  const types = { "general:border_size": "int", "general:gaps_out": "gaps", "general:col.active_border": "gradient", "hf:smart_gaps": "bool", "decoration:shadow:offset": "vec2" }
  const t = k => types[k] || ""
  const bad = Engine.validate({ options: { "general:border_size": "thick", "general:gaps_out": -3, "general:col.active_border": { slots: ["acc ent"] }, "nope:x": 1, "decoration:shadow:offset": [1] } }, t)
  check(bad.length === 5, "validation catches 5 problems, got " + JSON.stringify(bad))
  const good = Engine.validate({ options: { "general:border_size": 2, "general:gaps_out": { top: 1, right: 2, bottom: 3, left: 4 }, "general:col.active_border": { slots: ["accent", "#ff00aa"], alpha: 200, angle: 45 }, "hf:smart_gaps": true } }, t)
  check(good.length === 0, "valid config passes: " + JSON.stringify(good))
  for (const look of Engine.LOOKS) {
    const cfg = { options: Object.assign({}, look.options, look.extra || {}) }
    const typeOf = k => { const it = Schema.itemFor(k); return it ? (it.type === "enum" ? "enum" : it.type) : "" }
    const probs = Engine.validate(cfg, typeOf)
    check(probs.length === 0, `look ${look.id} validates: ${JSON.stringify(probs)}`)
  }
}

if (failures) { console.log(`\n${failures} failure(s)`); process.exit(1) }
console.log("all good")
