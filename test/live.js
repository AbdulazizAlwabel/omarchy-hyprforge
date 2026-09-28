// node test/live.js — evals every rendered preset in the running Hyprland,
// reports errors, then reloads the real config. Briefly changes the look.
const fs = require("fs"), path = require("path"), vm = require("vm")
const { execFileSync } = require("child_process")
const root = path.join(__dirname, "..")
function load(f) { const c = {}; vm.createContext(c); vm.runInContext(fs.readFileSync(path.join(root, f), "utf8").replace(/^\.pragma library\s*/, ""), c); return c }
const Engine = load("Engine.js")
const baseline = JSON.parse(execFileSync("lua", [path.join(root, "baseline.lua"), "/usr/share/omarchy/default/hypr/looknfeel.lua"]).toString())
const cases = []
for (const l of Engine.LOOKS) { const c = Engine.defaultConfig(); Object.assign(c.options, l.options, l.extra || {}); cases.push(["look " + l.id, c]) }
for (const m of Engine.MOTIONS) { const c = Engine.defaultConfig(); c.curves = m.curves; c.anims = m.anims; c.options["hf:anim_speed"] = 1.3; cases.push(["motion " + m.id, c]) }
const sink = Engine.defaultConfig()
sink.options = { "general:gaps_out": { top: 4, right: 10, bottom: 10, left: 10 }, "decoration:shadow:offset": [2, 4], "input:touchpad:tap-to-click": true,
  "group:groupbar:text_color": { slots: ["foreground"], alpha: 255 }, "group:groupbar:col.active": { slots: ["accent"], alpha: 0x66 },
  "hf:smart_gaps": true, "hf:smart_borders": true, "hf:shell_blur": true, "hf:border_rotate": true, "hf:base_active": 1, "input:accel_profile": "", "layout:single_window_aspect_ratio": [0, 0] }
const effects = {}
for (const e of Engine.RULE_EFFECTS) effects[e.key] = e.type === "bool" ? true : e.type === "opacity" ? [0.9, 0.8] : e.type === "size" ? ["60%", "70%"] : e.type === "color" ? { slots: ["red"], alpha: 255 } : e.type === "enum" ? e.options[1] : e.type === "text" ? (e.key === "monitor" ? "1" : "3 silent") : (e.min || 1)
sink.rules = [{ id: "live1", enabled: true, match: { class: "^(hyprforge-nonexistent)$" }, effects }]
cases.push(["kitchen sink", sink])
let bad = 0
for (const [label, cfg] of cases) {
  const src = Engine.render(cfg, { baseline })
  let out = ""
  try { out = execFileSync("hyprctl", ["eval", "local _hf_guard = 0\n" + src]).toString().trim() } catch (e) { out = String(e.stdout || e) }
  if (out !== "ok") { bad++; console.log("FAIL", label, "\n", out.split("\n").filter(l => /error|:\d+:/.test(l)).slice(-6).join("\n")) } else console.log("ok  ", label)
}
execFileSync("hyprctl", ["reload"])
execFileSync("sleep", ["0.6"])
console.log("configerrors after reload:", execFileSync("hyprctl", ["configerrors"]).toString().trim() || "(none)")
process.exit(bad ? 1 : 0)
