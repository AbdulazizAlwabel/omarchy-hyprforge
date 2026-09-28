import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Schema.js" as Schema
import "Engine.js" as Engine
import "components"

// Hyprforge — the whole Hyprland look-and-feel (and then some) in one panel.
//
//   edit      cfg changes in memory; `hyprctl eval` previews it instantly
//   commit    cfg -> state.json + hyprforge.lua, then `hyprctl reload`
//   verify    `hyprctl configerrors`; a change Hyprland rejects is rolled back
//
// Colors are stored as theme palette names and resolved by the generated Lua
// on every reload, so `omarchy theme set` re-colors everything for free.
Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy"
  property var shell: null
  property var manifest: null

  // ------------------------------------------------------------- paths
  readonly property string home: Quickshell.env("HOME")
  readonly property string stateDir: home + "/.config/hypr/hyprforge"
  readonly property string statePath: stateDir + "/state.json"
  readonly property string historyPath: stateDir + "/history.json"
  readonly property string luaPath: home + "/.config/hypr/hyprforge.lua"
  readonly property string hyprlandPath: home + "/.config/hypr/hyprland.lua"
  readonly property string basePath: home + "/.cache/hyprforge/base.json"
  readonly property string themeDir: home + "/.local/state/omarchy/current/theme"
  readonly property string pluginDir: {
    var u = String(Qt.resolvedUrl("baseline.lua"))
    return decodeURIComponent(u.replace(/^file:\/\//, "")).replace(/\/baseline\.lua$/, "")
  }

  // ------------------------------------------------------------- theme
  readonly property color fg: Color.menu.text
  readonly property color bg: Color.menu.background
  readonly property color accent: Color.accent
  readonly property string font: Style.font.menuFamily
  readonly property real radius: Math.max(4, Math.min(Style.cornerRadius, 10))

  // ------------------------------------------------------------- state
  property bool opened: false
  property bool grabFocus: false
  Timer { id: releaseGrab; interval: 400; onTriggered: root.grabFocus = false }
  property var cfg: Engine.defaultConfig()
  property var lastGood: Engine.defaultConfig()
  property var profiles: ({})
  property string activeProfile: ""
  property var history: []
  property var live: ({})
  property var liveTypes: ({})
  property var base: ({})
  property var themePalette: []
  property var paletteMap: ({ accent: "#88c0d0", foreground: "#d8dee9", background: "#101315" })
  property string themeName: ""
  property string wallpaperUrl: "file://" + Quickshell.env("HOME") + "/.local/state/omarchy/current/background"
  property var animBaseline: ({ curves: [], animations: [] })
  property var descriptions: []
  property var allItemsCache: []
  property var clients: []
  property string monitorName: ""
  property real monitorWidth: 1920
  property real monitorHeight: 1080
  property bool hooked: true
  property bool stateLoaded: false

  property int sectionIndex: 0
  property int cursorIndex: 0
  property string searchQuery: ""
  property bool showAdvanced: false
  property string allFilter: ""
  property string allGroup: ""
  property bool peek: false
  property bool dockLeft: false

  property string errorText: ""
  property string statusText: ""
  property string errorsBefore: ""
  property var undoStack: []
  property var redoStack: []
  property bool editing: false
  property bool previewPending: false
  property string pendingLabel: ""

  readonly property var section: Schema.SECTIONS[Math.max(0, Math.min(Schema.SECTIONS.length - 1, sectionIndex))]
  readonly property bool listMode: searchQuery.trim() !== "" || !section.view || section.view === "all"

  // ============================================================= lifecycle

  function open(payloadJson) {
    var payload = {}
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) {}
    root.opened = true
    root.peek = false
    root.grabFocus = true
    releaseGrab.restart()
    mkdirProc.running = true
    stateFile.reload()
    historyFile.reload()
    hyprlandFile.reload()
    colorsFile.reload()
    themeNameFile.reload()
    baseFile.reload()
    baselineProc.running = true
    refreshLive()
    monitorsProc.running = true
    initialErrorsProc.running = true
    if (root.descriptions.length === 0) descProc.running = true
    root.wallpaperUrl = "file://" + root.home + "/.local/state/omarchy/current/background?" + Date.now()
    if (payload.section) {
      for (var i = 0; i < Schema.SECTIONS.length; i++) if (Schema.SECTIONS[i].id === payload.section) goSection(i)
    }
    Qt.callLater(refocus)
  }

  function close() {
    if (persistTimer.running) persistNow()
    root.opened = false
  }

  function dismiss() {
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "aziz.hyprforge")
    else close()
  }

  function toggle() { if (root.opened) dismiss(); else open("{}") }

  function refocus() { keyCatcher.forceActiveFocus() }

  // ============================================================= values

  function valueForKey(key) {
    if (root.cfg.options[key] !== undefined) return root.cfg.options[key]
    if (Schema.isSynthetic(key)) return Schema.SYNTHETIC[key]
    // Just un-overridden: Hyprland's live value still shows our old override
    // until the reload lands, but we already know what lies underneath.
    if (root.base[key] !== undefined && root.base[key] !== null) return root.base[key]
    var v = root.live[key]
    if (v !== undefined && !(v && v.gradient !== undefined)) return v
    return undefined
  }

  function valueFor(item) {
    if (!item) return undefined
    var v = root.cfg.options[item.key]
    if (v !== undefined) return v
    if (item.type === "color" || item.type === "gradient") return null
    v = valueForKey(item.key)
    if (v === undefined) {
      if (item.type === "bool") return false
      if (item.type === "enum") return item.options && item.options.length ? item.options[0].value : ""
      if (item.type === "text") return ""
      if (item.type === "vec2") return [0, 0]
      return item.min !== undefined ? item.min : 0
    }
    if (item.type === "enum" && item.options && item.options.length && typeof item.options[0].value === "number") return Number(v)
    return v
  }

  function isModified(key) { return root.cfg.options[key] !== undefined }

  function isAvailable(item) {
    if (!item || !item.needs || item.needsValue !== undefined) return true
    return valueForKey(item.needs) === true
  }

  // Resolved color for the preview: { stops: [{ hex, alpha }], angle }.
  function resolvedColor(key) {
    var spec = root.cfg.options[key]
    if (Engine.isColorSpec(spec)) {
      var out = []
      var a = spec.alpha === undefined ? 255 : spec.alpha
      for (var i = 0; i < spec.slots.length; i++) out.push({ hex: Engine.resolveSlot(spec.slots[i], root.paletteMap), alpha: a })
      return { stops: out, angle: spec.angle || 0 }
    }
    var v = root.live[key]
    if (v && v.gradient !== undefined) {
      var g = Engine.parseGradient(v.gradient)
      var st = []
      for (var j = 0; j < g.colors.length; j++) st.push({ hex: g.colors[j], alpha: g.alphas[j] })
      return { stops: st, angle: g.angle }
    }
    if (typeof v === "number") {
      var c = Engine.argbToHex(v)
      return { stops: [{ hex: c.hex, alpha: c.alpha }], angle: 0 }
    }
    return { stops: [], angle: 0 }
  }

  function stopsColor(res, i) {
    if (!res || !res.stops || res.stops.length === 0) return "transparent"
    var s = res.stops[Math.min(i, res.stops.length - 1)]
    var c = Qt.color(s.hex)
    return Qt.rgba(c.r, c.g, c.b, s.alpha / 255)
  }

  function slotForHex(hex) {
    var h = String(hex).toLowerCase()
    var prefer = ["accent", "foreground", "background", "selection", "muted"]
    for (var p = 0; p < prefer.length; p++) if (root.paletteMap[prefer[p]] === h) return prefer[p]
    for (var i = 0; i < root.themePalette.length; i++) if (root.themePalette[i].hex === h) return root.themePalette[i].name
    return h
  }

  // ============================================================= editing

  function copyCfg() { return Engine.normalize(root.cfg) }

  function pushUndo() {
    if (root.editing) return
    var u = root.undoStack.slice()
    u.push(JSON.stringify(root.cfg))
    if (u.length > 80) u.shift()
    root.undoStack = u
    root.redoStack = []
  }

  function setValue(item, value, commit) {
    if (!item) return
    pushUndo()
    root.editing = !commit
    var c = copyCfg()
    var q = Engine.quantize(item, value)
    if (item.type === "color" || item.type === "gradient") q = Engine.clone(value)
    c.options[item.key] = q
    root.cfg = c
    root.pendingLabel = (item.label || item.key) + " → " + Engine.describe(item, q)
    livePreview()
    if (commit) schedulePersist()
  }

  function resetKeys(keys) {
    pushUndo()
    var c = copyCfg()
    for (var i = 0; i < keys.length; i++) delete c.options[keys[i]]
    root.cfg = c
    root.pendingLabel = keys.length === 1 ? "Reset " + labelFor(keys[0]) : "Reset " + keys.length + " settings"
    persistNow()
  }

  function labelFor(key) {
    var it = Schema.itemFor(key)
    return it ? it.label : Schema.prettyKey(key)
  }

  function resetSection(id) {
    var sec = Schema.sectionById(id)
    if (!sec) return
    if (id === "animations") {
      pushUndo()
      var c = copyCfg()
      c.anims = {}
      for (var j = 0; j < (sec.items || []).length; j++) delete c.options[sec.items[j].key]
      root.cfg = c
      root.pendingLabel = "Reset animations"
      persistNow()
      return
    }
    if (id === "rules") { pushUndo(); var r = copyCfg(); r.rules = []; root.cfg = r; root.pendingLabel = "Removed all app rules"; persistNow(); return }
    var keys = []
    for (var i = 0; i < (sec.items || []).length; i++) if (isModified(sec.items[i].key)) keys.push(sec.items[i].key)
    if (id === "all") keys = Object.keys(root.cfg.options).filter(function(k) { return !Schema.itemFor(k) })
    if (keys.length) resetKeys(keys)
  }

  function sectionModified(sec) {
    if (!sec) return false
    if (sec.id === "animations" && Object.keys(root.cfg.anims).length > 0) return true
    if (sec.id === "rules") return root.cfg.rules.length > 0
    if (sec.id === "all") return Object.keys(root.cfg.options).some(function(k) { return !Schema.itemFor(k) })
    var items = sec.items || []
    for (var i = 0; i < items.length; i++) if (isModified(items[i].key)) return true
    return false
  }

  function resetAll() {
    pushUndo()
    root.cfg = Engine.defaultConfig()
    root.activeProfile = ""
    root.pendingLabel = "Reset everything"
    persistNow()
  }

  function canonical(o) {
    if (Array.isArray(o)) return "[" + o.map(canonical).join(",") + "]"
    if (o && typeof o === "object") return "{" + Object.keys(o).sort().map(function(k) { return JSON.stringify(k) + ":" + canonical(o[k]) }).join(",") + "}"
    return JSON.stringify(o)
  }

  function lookKeys() { return Schema.keysInSections(Engine.LOOK_SECTIONS) }

  readonly property string activeLook: {
    var keys = lookKeys()
    var mine = {}
    for (var k in root.cfg.options) if (keys[k]) mine[k] = root.cfg.options[k]
    var c = canonical(mine)
    for (var i = 0; i < Engine.LOOKS.length; i++) if (canonical(Engine.LOOKS[i].options) === c) return Engine.LOOKS[i].id
    return ""
  }

  readonly property string activeMotion: {
    var c = canonical(root.cfg.anims)
    for (var i = 0; i < Engine.MOTIONS.length; i++) if (canonical(Engine.MOTIONS[i].anims) === c) return Engine.MOTIONS[i].id
    return ""
  }

  function applyLook(id) {
    var look = Engine.lookById(id)
    if (!look) return
    pushUndo()
    var c = copyCfg()
    var keys = lookKeys()
    for (var k in keys) delete c.options[k]
    var o = Engine.clone(look.options)
    for (var k2 in o) c.options[k2] = o[k2]
    if (look.extra) for (var k3 in look.extra) c.options[k3] = look.extra[k3]
    root.cfg = c
    root.pendingLabel = "Look: " + look.name
    persistNow()
  }

  function applyMotion(id) {
    var m = Engine.motionById(id)
    if (!m) return
    pushUndo()
    var c = copyCfg()
    c.anims = Engine.clone(m.anims)
    var curves = Engine.clone(m.curves)
    for (var n in curves) c.curves[n] = curves[n]
    root.cfg = c
    root.pendingLabel = "Motion: " + m.name
    persistNow()
  }

  function setAnim(leaf, patch, commit) {
    pushUndo()
    root.editing = !commit
    var c = copyCfg()
    var cur = c.anims[leaf]
    if (!cur) {
      var e = Engine.effectiveAnim(leaf, root.animBaseline, {})
      cur = e ? { enabled: e.enabled, speed: e.speed, curve: e.curve, style: e.style } : { enabled: true, speed: 4, curve: "default", style: "" }
    }
    for (var k in patch) cur[k] = patch[k]
    c.anims[leaf] = cur
    root.cfg = c
    var info = Engine.leafInfo(leaf)
    root.pendingLabel = "Animation: " + (info ? info.label : leaf)
    livePreview()
    if (commit) schedulePersist()
  }

  function resetAnim(leaf) {
    pushUndo()
    var c = copyCfg()
    delete c.anims[leaf]
    root.cfg = c
    root.pendingLabel = "Reset animation " + leaf
    persistNow()
  }

  function setCurve(name, curve, commit) {
    pushUndo()
    root.editing = !commit
    var c = copyCfg()
    c.curves[name] = Engine.clone(curve)
    root.cfg = c
    root.pendingLabel = "Curve " + name
    livePreview()
    if (commit) schedulePersist()
  }

  function deleteCurve(name) {
    pushUndo()
    var c = copyCfg()
    delete c.curves[name]
    for (var leaf in c.anims) if (c.anims[leaf].curve === name) c.anims[leaf].curve = "default"
    root.cfg = c
    root.pendingLabel = "Deleted curve " + name
    persistNow()
  }

  function renameCurve(from, to) {
    pushUndo()
    var c = copyCfg()
    c.curves[to] = c.curves[from]
    delete c.curves[from]
    for (var leaf in c.anims) if (c.anims[leaf].curve === from) c.anims[leaf].curve = to
    root.cfg = c
    root.pendingLabel = "Renamed curve " + from + " → " + to
    persistNow()
  }

  function addRule(rule) {
    pushUndo()
    var c = copyCfg()
    c.rules.push(rule)
    root.cfg = c
    root.pendingLabel = "App rule: " + (rule.name || "new")
    persistNow()
  }

  function updateRule(id, patch, commit) {
    pushUndo()
    root.editing = !commit
    var c = copyCfg()
    for (var i = 0; i < c.rules.length; i++) if (c.rules[i].id === id) {
      for (var k in patch) c.rules[i][k] = Engine.clone(patch[k])
      root.pendingLabel = "App rule: " + (c.rules[i].name || id)
    }
    root.cfg = c
    if (commit) schedulePersist()
  }

  function deleteRule(id) {
    pushUndo()
    var c = copyCfg()
    c.rules = c.rules.filter(function(r) { return r.id !== id })
    root.cfg = c
    root.pendingLabel = "Deleted app rule"
    persistNow()
  }

  function moveRule(id, d) {
    var c = copyCfg()
    for (var i = 0; i < c.rules.length; i++) if (c.rules[i].id === id) {
      var j = i + d
      if (j < 0 || j >= c.rules.length) return
      pushUndo()
      var t = c.rules[i]; c.rules[i] = c.rules[j]; c.rules[j] = t
      root.cfg = c
      root.pendingLabel = "Reordered app rules"
      persistNow()
      return
    }
  }

  function undo() {
    if (root.undoStack.length === 0) return
    var u = root.undoStack.slice()
    var r = root.redoStack.slice()
    r.push(JSON.stringify(root.cfg))
    root.cfg = Engine.normalize(JSON.parse(u.pop()))
    root.undoStack = u
    root.redoStack = r
    root.editing = false
    root.pendingLabel = "Undo"
    persistNow()
  }

  function redo() {
    if (root.redoStack.length === 0) return
    var u = root.undoStack.slice()
    var r = root.redoStack.slice()
    u.push(JSON.stringify(root.cfg))
    root.cfg = Engine.normalize(JSON.parse(r.pop()))
    root.undoStack = u
    root.redoStack = r
    root.editing = false
    root.pendingLabel = "Redo"
    persistNow()
  }

  // ============================================================= profiles

  function saveProfile(name) {
    var p = Engine.clone(root.profiles)
    p[name] = { cfg: Engine.normalize(root.cfg), saved: Date.now() }
    root.profiles = p
    root.activeProfile = name
    saveState()
    flash("Saved profile “" + name + "”")
  }

  function applyProfile(name) {
    var p = root.profiles[name]
    if (!p) return
    pushUndo()
    root.cfg = Engine.normalize(p.cfg)
    root.activeProfile = name
    root.pendingLabel = "Profile: " + name
    persistNow()
  }

  function deleteProfile(name) {
    var p = Engine.clone(root.profiles)
    delete p[name]
    root.profiles = p
    if (root.activeProfile === name) root.activeProfile = ""
    saveState()
  }

  function copyProfile(name) {
    var p = root.profiles[name]
    if (!p) return
    Quickshell.execDetached(["wl-copy", "--", JSON.stringify({ hyprforgeProfile: name, version: Engine.VERSION, cfg: p.cfg }, null, 2)])
    flash("Copied “" + name + "” to the clipboard")
  }

  function importFromClipboard() { pasteProc.running = true }

  function importText(text) {
    try {
      var j = JSON.parse(String(text || ""))
      var cfg = j.cfg ? j.cfg : j
      var name = String(j.hyprforgeProfile || "Imported").trim() || "Imported"
      var n = name, i = 2
      while (root.profiles[n]) n = name + " " + i++
      var p = Engine.clone(root.profiles)
      p[n] = { cfg: Engine.normalize(cfg), saved: Date.now() }
      root.profiles = p
      saveState()
      flash("Imported profile “" + n + "”")
    } catch (e) {
      root.errorText = "The clipboard doesn't hold a Hyprforge profile."
    }
  }

  function restoreHistory(entry) {
    if (!entry || !entry.cfg) return
    pushUndo()
    root.cfg = Engine.normalize(entry.cfg)
    root.pendingLabel = "Restored “" + (entry.label || "change") + "”"
    persistNow()
  }

  function copyLua() {
    Quickshell.execDetached(["wl-copy", "--", Engine.renderFile(root.cfg, { baseline: root.animBaseline })])
    flash("Copied the generated Lua")
  }

  function openGenerated() {
    Quickshell.execDetached(["omarchy-launch-config-editor", root.luaPath])
    dismiss()
  }

  function flash(text) {
    root.statusText = text
    statusClear.restart()
  }

  // ============================================================= hook

  function connectHook() {
    var text = hyprlandFile.text()
    if (!text || Engine.hasHook(text)) { root.hooked = Engine.hasHook(text); return }
    Quickshell.execDetached(["cp", "-n", root.hyprlandPath, root.hyprlandPath + ".bak.hyprforge"])
    hyprlandFile.setText(Engine.addHook(text))
    root.pendingLabel = "Connected to hyprland.lua"
  }

  function disconnectHook() {
    var text = hyprlandFile.text()
    if (!text || !Engine.hasHook(text)) return
    hyprlandFile.setText(Engine.removeHook(text))
    root.pendingLabel = "Disconnected from hyprland.lua"
  }

  // ============================================================= preview / persist

  function livePreview() {
    if (Engine.validate(root.cfg, typeOf).length) return
    var body = Engine.render(root.cfg, { baseline: root.animBaseline, preview: true })
    if (!body) return
    root.previewDirty = true
    if (evalProc.running) { root.previewPending = true; return }
    evalProc.command = ["timeout", "3", "hyprctl", "eval", "local _hyprforge = true\n" + body]
    evalProc.running = true
  }

  function schedulePersist() { persistTimer.restart() }

  // What we last wrote to state.json. A change notification whose content
  // matches it is our own write arriving late and is ignored; anything else
  // (the service applying a profile from a keybinding) is adopted.
  property string lastStateText: ""

  function saveState(cfg) {
    var text = JSON.stringify({
      version: Engine.VERSION,
      cfg: Engine.normalize(cfg === undefined ? root.lastGood : cfg),
      profiles: root.profiles,
      activeProfile: root.activeProfile,
      ui: { dockLeft: root.dockLeft, showAdvanced: root.showAdvanced }
    }, null, 2) + "\n"
    root.lastStateText = text
    stateFile.setText(text)
  }

  // Type of any key, for validation: catalogue first, then what Hyprland
  // reported for it.
  function typeOf(key) {
    var it = Schema.itemFor(key)
    if (it) return it.type
    for (var i = 0; i < root.allItemsCache.length; i++) if (root.allItemsCache[i].key === key) return root.allItemsCache[i].type
    return root.liveTypes[key] || ""
  }

  // ---- commit pipeline --------------------------------------------------
  //
  //   persistNow   snapshot cfg -> validate -> `hyprctl eval` dry-run
  //   commit       write state.json, history, hyprforge.lua
  //   reload       `hyprctl reload`, then `hyprctl configerrors`
  //   settle       success, or roll back to the last good snapshot
  //
  // One commit runs at a time. Changes made meanwhile set `again`, and are
  // committed as soon as the current one settles, so a fast second click can
  // never be overwritten by the first click's slower commit.
  // Reload-time config errors can freeze Hyprland on some systems, which is
  // why nothing reaches the file before Hyprland accepted it through eval.
  property bool previewDirty: false
  property bool committing: false
  property bool again: false
  property var commitCfg: null
  property string commitLabel: ""
  property bool rejected: false
  property bool luaWriting: false
  property bool stateStale: false

  function persistNow() {
    persistTimer.stop()
    root.editing = false
    if (!root.stateLoaded) return
    if (root.committing) { root.again = true; return }
    dropRedundant()
    var problems = Engine.validate(root.cfg, typeOf)
    if (problems.length) {
      reject(problems.map(function(p) { return labelFor(p.key) + ": " + p.problem }).join("; "))
      return
    }
    root.committing = true
    root.commitCfg = Engine.normalize(root.cfg)
    root.commitLabel = root.pendingLabel
    root.pendingLabel = ""
    var next = Engine.renderFile(root.commitCfg, { baseline: root.animBaseline })
    if (next === luaFile.text()) {
      saveState(root.commitCfg)
      recordHistory(root.commitCfg, root.commitLabel)
      if (root.previewDirty) reloadProc.running = true
      else settle()
      return
    }
    root.statusText = "Checking with Hyprland…"
    var body = Engine.render(root.commitCfg, { baseline: root.animBaseline })
    if (!body) { commitChecked(); return }
    checkProc.command = ["timeout", "5", "hyprctl", "eval", "local _hyprforge_check = true\n" + body]
    checkProc.running = true
  }

  function commitChecked() {
    saveState(root.commitCfg)
    recordHistory(root.commitCfg, root.commitLabel)
    root.statusText = "Applying…"
    root.luaWriting = true
    luaFile.setText(Engine.renderFile(root.commitCfg, { baseline: root.animBaseline }))
  }

  function settle() {
    root.lastGood = root.commitCfg
    flash(root.commitLabel ? "Applied  ·  " + root.commitLabel : "Applied")
    root.committing = false
    if (root.again) { root.again = false; Qt.callLater(persistNow) }
    else if (root.stateStale) { root.stateStale = false; stateFile.reload() }
  }

  // An override equal to what Omarchy/your files already set is noise: drop it
  // so "N changes" and the modified dots only show real differences.
  function dropRedundant() {
    var c = null
    for (var k in root.cfg.options) {
      if (Schema.isSynthetic(k) || root.base[k] === undefined) continue
      var v = root.cfg.options[k], b = root.base[k]
      var same = Engine.valuesEqual(v, b)
      if (!same && typeof v === "number" && typeof b === "number") same = Math.abs(v - b) < 1e-4
      if (!same && typeof b === "number" && Engine.isGaps(v)) same = Engine.gapsUniform(v) && Engine.gapsFrom(v).top === b
      if (!same) continue
      if (!c) c = copyCfg()
      delete c.options[k]
    }
    if (c) root.cfg = c
  }

  function reject(why) {
    root.rejected = true
    root.committing = true
    root.again = false
    root.errorText = "Hyprland would reject that, so nothing was saved:\n" + why
    root.cfg = Engine.normalize(root.lastGood)
    root.pendingLabel = ""
    // Put the live session back to what's on disk (which is known-good).
    reloadProc.running = true
  }

  function recordHistory(cfg, label) {
    var h = root.history.slice()
    var last = h.length ? h[h.length - 1] : null
    if (last && Engine.valuesEqual(Engine.normalize(last.cfg), cfg)) return
    h.push({ time: Date.now(), label: label || "Change", cfg: cfg })
    while (h.length > 60) h.shift()
    root.history = h
    historyFile.setText(JSON.stringify(h) + "\n")
  }

  function afterReload(errors) {
    var out = String(errors || "").trim()
    if (out === "no errors") out = ""
    var fresh = out !== "" && out !== root.errorsBefore
    refreshLive()
    baseTimer.restart()
    if (root.rejected) {
      root.rejected = false
      root.committing = false
      root.statusText = ""
      return
    }
    if (fresh && out.indexOf("hyprforge") !== -1 && root.commitCfg && !Engine.valuesEqual(root.commitCfg, root.lastGood)) {
      // Rejected at reload despite the dry-run: put the last good file back.
      root.errorText = "Hyprland rejected that change, so it was rolled back:\n" + out.split("\n").slice(0, 3).join("\n")
      root.cfg = Engine.normalize(root.lastGood)
      root.commitCfg = Engine.normalize(root.lastGood)
      root.commitLabel = "Rolled back"
      saveState(root.lastGood)
      root.luaWriting = true
      luaFile.setText(Engine.renderFile(root.lastGood, { baseline: root.animBaseline }))
      return
    }
    if (root.commitLabel !== "Rolled back") root.errorText = fresh ? out : ""
    if (root.committing) settle()
  }

  function refreshLive() {
    var keys = root.descriptions.length ? root.descriptions.map(function(d) { return d.name }) : Schema.liveKeys()
    var batch = []
    for (var i = 0; i < keys.length; i++) batch.push("getoption " + keys[i])
    liveProc.command = ["timeout", "5", "hyprctl", "-j", "--batch", batch.join(" ; ")]
    liveProc.running = true
  }

  function refreshClients() { clientsProc.running = true }

  // ============================================================= catalogue

  function buildAllItems() {
    var out = []
    for (var i = 0; i < root.descriptions.length; i++) {
      var d = root.descriptions[i]
      var cur = Schema.itemFor(d.name)
      if (cur) { out.push(cur); continue }
      var it = Engine.itemFromDescription(d, root.liveTypes[d.name])
      out.push(it)
    }
    root.allItemsCache = out
  }

  readonly property var allGroups: {
    var seen = {}, out = []
    for (var i = 0; i < root.descriptions.length; i++) {
      var g = root.descriptions[i].name.split(":")[0]
      if (!seen[g]) { seen[g] = true; out.push(g) }
    }
    return out
  }

  readonly property var searchResults: {
    var q = root.searchQuery.trim()
    if (!q) return []
    var res = Schema.search(q, root.allItemsCache)
    return res.slice(0, 80).map(function(r) { return r.item })
  }

  // Rebuilt only when the *set* of rows changes, never on a value change, so a
  // slider being dragged is not destroyed under the pointer.
  property var rows: []
  property string rowsSig: ""
  function sectionAt(i) { return Schema.SECTIONS[Math.max(0, Math.min(Schema.SECTIONS.length - 1, i))] }

  // Deferred so every binding (section, searchResults, cfg) has settled first.
  function recomputeRows() { if (!rowsQueued) { rowsQueued = true; Qt.callLater(doRecomputeRows) } }
  property bool rowsQueued: false
  function doRecomputeRows() {
    root.rowsQueued = false
    var r = computeRows()
    var sig = r.map(function(i) { return i.key }).join("|")
    if (sig === root.rowsSig) return
    root.rowsSig = sig
    root.rows = r
    if (root.cursorIndex >= r.length) root.cursorIndex = Math.max(0, r.length - 1)
  }
  onCfgChanged: recomputeRows()
  onSectionIndexChanged: recomputeRows()
  onSearchQueryChanged: recomputeRows()
  onShowAdvancedChanged: recomputeRows()
  onAllFilterChanged: recomputeRows()
  onAllGroupChanged: recomputeRows()
  onAllItemsCacheChanged: recomputeRows()
  onLiveChanged: recomputeRows()

  function computeRows() {
    var q = root.searchQuery.trim()
    if (q !== "") return Schema.search(q, root.allItemsCache).slice(0, 80).map(function(r) { return r.item })
    var sec = sectionAt(root.sectionIndex)
    if (!sec) return []
    if (sec.view === "all") {
      var f = root.allFilter.toLowerCase().trim()
      return root.allItemsCache.filter(function(it) {
        if (root.allGroup && it.key.split(":")[0] !== root.allGroup) return false
        if (!f) return true
        return (it.key + " " + it.label + " " + (it.desc || "")).toLowerCase().indexOf(f) !== -1
      })
    }
    if (sec.view) return []
    var out = []
    var items = sec.items || []
    for (var i = 0; i < items.length; i++) {
      var it = items[i]
      if (it.advanced && !root.showAdvanced && !isModified(it.key)) continue
      if (it.needsValue !== undefined && String(valueForKey(it.needs)) !== String(it.needsValue)) continue
      out.push(it)
    }
    return out
  }

  readonly property int hiddenAdvanced: {
    var sec = root.section
    if (!sec || !sec.items || root.showAdvanced) return 0
    var n = 0
    for (var i = 0; i < sec.items.length; i++) if (sec.items[i].advanced && !isModified(sec.items[i].key)) n++
    return n
  }

  readonly property var changedItems: {
    var out = []
    var keys = Object.keys(root.cfg.options).sort()
    for (var i = 0; i < keys.length; i++) {
      var k = keys[i]
      var it = Schema.itemFor(k)
      var sec = it ? Schema.sectionById(it.section) : Schema.sectionById("all")
      out.push({
        kind: "option", key: k, section: sec ? sec.id : "all", icon: sec ? sec.icon : "",
        label: (sec ? sec.title + "  ›  " : "") + (it ? it.label : Schema.prettyKey(k)),
        value: Engine.describe(it, root.cfg.options[k]),
        order: sectionOrder(sec ? sec.id : "all") * 1000 + (it && sec && sec.items ? sec.items.indexOf(it) : 999)
      })
    }
    out.sort(function(a, b) { return a.order - b.order })
    var an = Object.keys(root.cfg.anims)
    if (an.length) out.push({ kind: "anims", key: "", section: "animations", icon: Schema.I.anim, label: "Animation overrides", value: an.join(", ") })
    var cv = Object.keys(root.cfg.curves)
    if (cv.length) out.push({ kind: "curves", key: "", section: "animations", icon: Schema.I.anim, label: "Custom curves", value: cv.join(", ") })
    if (root.cfg.rules.length) out.push({ kind: "rules", key: "", section: "rules", icon: Schema.I.rules, label: "App rules", value: root.cfg.rules.length + " rule(s)" })
    return out
  }

  function sectionOrder(id) {
    for (var i = 0; i < Schema.SECTIONS.length; i++) if (Schema.SECTIONS[i].id === id) return i
    return 99
  }

  function resetChange(entry) {
    if (entry.kind === "option") resetKeys([entry.key])
    else if (entry.kind === "anims") { pushUndo(); var c = copyCfg(); c.anims = {}; root.cfg = c; root.pendingLabel = "Reset animations"; persistNow() }
    else if (entry.kind === "curves") { pushUndo(); var d = copyCfg(); d.curves = {}; for (var l in d.anims) if (!Engine.curveByName(d.anims[l].curve, d, root.animBaseline)) d.anims[l].curve = "default"; root.cfg = d; root.pendingLabel = "Removed custom curves"; persistNow() }
    else if (entry.kind === "rules") resetSection("rules")
  }

  function jumpTo(key, sectionId) {
    for (var i = 0; i < Schema.SECTIONS.length; i++) if (Schema.SECTIONS[i].id === sectionId) root.sectionIndex = i
    root.searchQuery = ""
    var it = Schema.itemFor(key)
    if (it && it.advanced) root.showAdvanced = true
    Qt.callLater(function() {
      root.doRecomputeRows()
      for (var j = 0; j < root.rows.length; j++) if (root.rows[j].key === key) {
        root.cursorIndex = j
        if (contentLoader.item && contentLoader.item.positionViewAtIndex) contentLoader.item.positionViewAtIndex(j, ListView.Center)
      }
    })
  }

  // ============================================================= keyboard

  function goSection(i) {
    root.sectionIndex = (i + Schema.SECTIONS.length) % Schema.SECTIONS.length
    root.cursorIndex = 0
    root.searchQuery = ""
    searchField.text = ""
    Qt.callLater(function() { var it = contentLoader.item; if (!it) return; if (it.positionViewAtBeginning) it.positionViewAtBeginning(); else it.contentY = 0 })
  }

  function moveCursor(d) {
    var n = root.rows.length
    if (!root.listMode || n === 0) {
      if (contentLoader.item && contentLoader.item.flick) contentLoader.item.flick(0, -d * 1600)
      return
    }
    root.cursorIndex = (root.cursorIndex + d + n) % n
    if (contentLoader.item && contentLoader.item.positionViewAtIndex) contentLoader.item.positionViewAtIndex(root.cursorIndex, ListView.Contain)
  }

  function cursorItem() {
    if (!root.listMode || root.cursorIndex < 0 || root.cursorIndex >= root.rows.length) return null
    return root.rows[root.cursorIndex]
  }

  function nudge(dir, big) {
    var it = cursorItem()
    if (!it || !isAvailable(it)) return
    var v = valueFor(it)
    if (it.type === "bool") { setValue(it, dir > 0, true); return }
    if (it.type === "enum") {
      var o = it.options || []
      if (!o.length) return
      var at = 0
      for (var i = 0; i < o.length; i++) if (String(o[i].value) === String(v)) at = i
      setValue(it, o[(at + dir + o.length) % o.length].value, true)
      return
    }
    if (it.type === "int" || it.type === "float" || it.type === "gaps") {
      var cur = it.type === "gaps" ? Engine.gapsFrom(v).top : Number(v)
      var step = (it.step !== undefined ? it.step : 1) * (big ? 10 : 1)
      var lo = Math.min(it.min !== undefined ? it.min : -1e9, cur)
      var hi = Math.max(it.max !== undefined ? it.max : 1e9, cur)
      setValue(it, Math.max(lo, Math.min(hi, Math.round((cur + step * dir) / step) * step)), false)
      schedulePersist()
    }
  }

  function activateCursor() {
    var it = cursorItem()
    if (!it || !isAvailable(it)) return
    if (it.type === "bool") setValue(it, valueFor(it) !== true, true)
    else if (it.type === "enum") nudge(1, false)
  }

  function resetCursor() {
    var it = cursorItem()
    if (it && isModified(it.key)) resetKeys([it.key])
  }

  // ============================================================= processes

  Process { id: mkdirProc; command: ["mkdir", "-p", root.stateDir, root.home + "/.cache/hyprforge"] }

  Process {
    id: evalProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var t = String(text || "").trim()
        if (t !== "" && t !== "ok") root.statusText = "Preview: " + t.split("\n").pop()
      }
    }
    onExited: {
      if (typeof Style.scheduleRefresh === "function") Style.scheduleRefresh()
      if (!root.previewPending) return
      root.previewPending = false
      Qt.callLater(root.livePreview)
    }
  }

  Process {
    id: checkProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var t = String(text || "").trim()
        if (t === "ok") root.commitChecked()
        else root.reject(t === "" ? "Hyprland didn't answer the check." : t.split("\n").filter(function(l) { return l.trim() !== "" }).slice(-2).join("\n"))
      }
    }
  }

  Process {
    id: reloadProc
    command: ["timeout", "8", "hyprctl", "reload"]
    onExited: { root.previewDirty = false; errorsTimer.restart(); if (typeof Style.scheduleRefresh === "function") Style.scheduleRefresh() }
  }

  Timer { id: errorsTimer; interval: 250; onTriggered: errorsProc.running = true }

  Process {
    id: errorsProc
    command: ["timeout", "5", "hyprctl", "configerrors"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.afterReload(text) }
  }

  Process {
    id: initialErrorsProc
    command: ["timeout", "5", "hyprctl", "configerrors"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var t = String(text || "").trim()
        root.errorsBefore = t === "no errors" ? "" : t
      }
    }
  }

  Process {
    id: liveProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.live = Engine.parseGetoptions(text)
        root.liveTypes = Engine.parseLiveTypes(text)
        if (root.descriptions.length && root.allItemsCache.length === 0) root.buildAllItems()
      }
    }
  }

  Process {
    id: descProc
    command: ["timeout", "5", "hyprctl", "descriptions", "-j"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.descriptions = JSON.parse(text) } catch (e) { root.descriptions = [] }
        root.refreshLive()
      }
    }
  }

  Process {
    id: baselineProc
    command: ["lua", root.pluginDir + "/baseline.lua", root.omarchyPath + "/default/hypr/looknfeel.lua", root.home + "/.config/hypr/looknfeel.lua"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.animBaseline = JSON.parse(text) } catch (e) {}
      }
    }
  }

  Process {
    id: monitorsProc
    command: ["timeout", "5", "hyprctl", "monitors", "-j"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var m = JSON.parse(text)
          var f = m[0]
          for (var i = 0; i < m.length; i++) if (m[i].focused) f = m[i]
          if (f) {
            var sc = Number(f.scale) || 1
            var rot = (Number(f.transform) || 0) % 2 === 1
            root.monitorName = f.name
            root.monitorWidth = (rot ? f.height : f.width) / sc
            root.monitorHeight = (rot ? f.width : f.height) / sc
          }
        } catch (e) {}
      }
    }
  }

  Process {
    id: clientsProc
    command: ["timeout", "5", "hyprctl", "clients", "-j"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var c = JSON.parse(text)
          var seen = {}, out = []
          for (var i = 0; i < c.length; i++) {
            var cls = String(c[i]["class"] || "")
            if (!cls || seen[cls]) continue
            seen[cls] = true
            out.push({ "class": cls, title: String(c[i].title || "") })
          }
          out.sort(function(a, b) { return a["class"].toLowerCase().localeCompare(b["class"].toLowerCase()) })
          root.clients = out
        } catch (e) {}
      }
    }
  }

  Process {
    id: pasteProc
    command: ["wl-paste", "--no-newline"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.importText(text) }
  }

  Timer { id: persistTimer; interval: 420; onTriggered: root.persistNow() }
  Timer { id: statusClear; interval: 2600; onTriggered: root.statusText = "" }
  Timer { id: baseTimer; interval: 300; onTriggered: baseFile.reload() }

  // ============================================================= files

  FileView {
    id: stateFile
    path: root.statePath
    atomicWrites: true
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      var raw = text()
      if (raw === root.lastStateText) return
      if (root.stateLoaded && (root.committing || root.editing || persistTimer.running)) { root.stateStale = true; return }
      root.lastStateText = raw
      try {
        var j = JSON.parse(raw)
        root.cfg = Engine.normalize(j.cfg)
        root.profiles = j.profiles || {}
        root.activeProfile = j.activeProfile || ""
        if (j.ui) { root.dockLeft = j.ui.dockLeft === true; root.showAdvanced = j.ui.showAdvanced === true }
      } catch (e) {
        root.errorText = "state.json is not valid JSON; starting from a clean slate (the file is left untouched until you change something)."
      }
      root.lastGood = Engine.normalize(root.cfg)
      root.stateLoaded = true
    }
    onLoadFailed: { root.stateLoaded = true }
  }

  FileView {
    id: historyFile
    path: root.historyPath
    atomicWrites: true
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    onLoaded: { try { var h = JSON.parse(text()); root.history = Array.isArray(h) ? h : [] } catch (e) { root.history = [] } }
    onLoadFailed: root.history = []
  }

  FileView {
    id: luaFile
    path: root.luaPath
    atomicWrites: true
    printErrors: false
    blockLoading: true
    watchChanges: true
    onFileChanged: { if (!root.luaWriting) reload() }
    onSaved: { root.luaWriting = false; reloadProc.running = true }
    onSaveFailed: { root.luaWriting = false; root.committing = false; root.errorText = "Could not write " + root.luaPath }
  }

  FileView {
    id: hyprlandFile
    path: root.hyprlandPath
    atomicWrites: true
    printErrors: false
    watchChanges: true
    blockLoading: true
    onFileChanged: reload()
    onLoaded: root.hooked = Engine.hasHook(text())
    onSaved: { root.hooked = Engine.hasHook(text()); reloadProc.running = true }
  }

  FileView {
    id: colorsFile
    path: root.themeDir + "/colors.toml"
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      root.themePalette = Engine.parsePalette(text())
      root.paletteMap = Engine.paletteMap(root.themePalette)
    }
  }

  FileView {
    id: themeNameFile
    path: root.home + "/.local/state/omarchy/current/theme.name"
    printErrors: false
    watchChanges: true
    onFileChanged: {
      reload()
      root.wallpaperUrl = "file://" + root.home + "/.local/state/omarchy/current/background?" + Date.now()
      colorsFile.reload()
      if (root.opened) root.refreshLive()
    }
    onLoaded: root.themeName = String(text()).trim()
  }

  FileView {
    id: baseFile
    path: root.basePath
    printErrors: false
    onLoaded: {
      try {
        var b = JSON.parse(text())
        var out = {}
        for (var k in b) {
          var v = b[k]
          if (Array.isArray(v) && v.length === 4) v = (v[0] === v[1] && v[0] === v[2] && v[0] === v[3]) ? v[0] : { top: v[0], right: v[1], bottom: v[2], left: v[3] }
          else if (v && v.vec2) v = v.vec2
          out[k] = v
        }
        root.base = out
      } catch (e) {}
    }
  }

  // ============================================================= window

  PanelWindow {
    id: window
    visible: root.opened
    screen: {
      var list = Quickshell.screens
      for (var i = 0; i < list.length; i++) if (list[i].name === root.monitorName) return list[i]
      return list.length ? list[0] : null
    }
    anchors { top: true; bottom: true; left: root.dockLeft; right: !root.dockLeft }
    implicitWidth: card.width + Style.gapsOut * 2
    color: "transparent"
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 0
    WlrLayershell.namespace: "hyprforge"
    WlrLayershell.layer: WlrLayer.Overlay
    // Grab the keyboard when opened (so shortcuts work immediately), then
    // relax to on-demand: clicking any window hands the keyboard back, and
    // clicking the panel takes it again. Typing elsewhere never edits settings.
    WlrLayershell.keyboardFocus: !root.opened ? WlrKeyboardFocus.None : (root.grabFocus ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand)

    BorderSurface {
      id: card
      x: Style.gapsOut
      y: Style.gapsOut
      width: Math.min(Style.space(900), Math.max(Style.space(620), (window.screen ? window.screen.width : 1920) * 0.56))
      height: window.height - Style.gapsOut * 2
      radius: Style.cornerRadius
      color: root.bg
      borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
      padding: Style.spacing.panelPadding
      opacity: root.peek ? 0.12 : 1
      Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.onPressed: function(event) {
          var mods = event.modifiers
          var ctrl = mods & Qt.ControlModifier
          var plain = !(mods & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
          var k = event.key
          if (k === Qt.Key_Escape) {
            if (root.peek) root.peek = false
            else if (root.searchQuery !== "") { root.searchQuery = ""; searchField.text = "" }
            else root.dismiss()
          }
          else if (ctrl && k === Qt.Key_Z && (mods & Qt.ShiftModifier)) root.redo()
          else if (ctrl && k === Qt.Key_Z) root.undo()
          else if (ctrl && k === Qt.Key_Y) root.redo()
          else if (ctrl && k === Qt.Key_F || (plain && k === Qt.Key_Slash)) { searchField.forceActiveFocus(); searchField.selectAll() }
          else if (k === Qt.Key_Down || (plain && k === Qt.Key_J)) root.moveCursor(1)
          else if (k === Qt.Key_Up || (plain && k === Qt.Key_K)) root.moveCursor(-1)
          else if (k === Qt.Key_Right || (plain && k === Qt.Key_L) || (plain && event.text === "L")) root.nudge(1, mods & Qt.ShiftModifier)
          else if (k === Qt.Key_Left || (plain && k === Qt.Key_H) || (plain && event.text === "H")) root.nudge(-1, mods & Qt.ShiftModifier)
          else if (k === Qt.Key_Tab || k === Qt.Key_Backtab) root.goSection(root.sectionIndex + ((k === Qt.Key_Backtab || (mods & Qt.ShiftModifier)) ? -1 : 1))
          else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) root.activateCursor()
          else if (k === Qt.Key_Backspace || k === Qt.Key_Delete) root.resetCursor()
          else if (plain && k === Qt.Key_P) root.peek = !root.peek
          else if (plain && k === Qt.Key_A) { root.showAdvanced = !root.showAdvanced; root.saveState() }
          else if (plain && k >= Qt.Key_1 && k <= Qt.Key_9) root.goSection(k - Qt.Key_1)
          else return
          event.accepted = true
        }
      }

      MouseArea { anchors.fill: parent; onPressed: function(m) { root.refocus(); m.accepted = false } }

      ColumnLayout {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: Style.spacing.panelGap

        // ---------------------------------------------------- header
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.spacing.lg

          Rectangle {
            implicitWidth: Style.space(34); implicitHeight: implicitWidth
            radius: Math.min(root.radius + 2, implicitWidth / 2)
            gradient: Gradient {
              orientation: Gradient.Horizontal
              GradientStop { position: 0; color: root.accent }
              GradientStop { position: 1; color: root.paletteMap.cyan || root.paletteMap.magenta || Qt.lighter(root.accent, 1.3) }
            }
            Text {
              anchors.centerIn: parent
              text: Schema.I.forge
              color: root.bg
              font.family: root.font
              font.pixelSize: Style.font.iconLarge
            }
          }

          ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            Text {
              text: "Hyprforge"
              color: root.fg
              font.family: root.font
              font.pixelSize: Style.font.heading
              font.bold: true
            }
            Text {
              Layout.fillWidth: true
              text: {
                var n = root.changedItems.length
                var parts = [root.themeName ? "theme " + root.themeName : "", n === 0 ? "stock Omarchy" : n + (n === 1 ? " change" : " changes")]
                if (root.activeProfile) parts.push("profile " + root.activeProfile)
                return parts.filter(function(p) { return p }).join("  ·  ")
              }
              color: Util.alpha(root.fg, 0.55)
              font.family: root.font
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
          }

          PanelActionButton { iconText: Schema.I.undo; tooltipText: "Undo  ·  Ctrl+Z"; foreground: root.fg; enabled: root.undoStack.length > 0; opacity: enabled ? 1 : 0.35; onClicked: root.undo() }
          PanelActionButton { iconText: Schema.I.redo; tooltipText: "Redo  ·  Ctrl+Shift+Z"; foreground: root.fg; enabled: root.redoStack.length > 0; opacity: enabled ? 1 : 0.35; onClicked: root.redo() }
          PanelActionButton { iconText: Schema.I.eye; tooltipText: "Peek at the desktop  ·  P"; foreground: root.peek ? root.accent : root.fg; onClicked: root.peek = !root.peek }
          PanelActionButton {
            iconText: root.dockLeft ? "\u{F0142}" : "\u{F0141}"
            tooltipText: "Dock on the other side"
            foreground: root.fg
            onClicked: { root.dockLeft = !root.dockLeft; root.saveState() }
          }
          PanelActionButton { iconText: Schema.I.close; tooltipText: "Close  ·  Esc"; foreground: root.fg; onClicked: root.dismiss() }
        }

        // ---------------------------------------------------- banners
        Rectangle {
          visible: !root.hooked
          Layout.fillWidth: true
          implicitHeight: hookRow.implicitHeight + Style.spacing.lg * 2
          radius: root.radius
          color: Util.alpha(root.accent, 0.12)
          border.width: 1
          border.color: Util.alpha(root.accent, 0.5)
          RowLayout {
            id: hookRow
            anchors.fill: parent
            anchors.margins: Style.spacing.lg
            spacing: Style.spacing.lg
            Text {
              Layout.fillWidth: true
              text: "Hyprland isn't loading Hyprforge yet. Connecting adds one line to ~/.config/hypr/hyprland.lua (a backup is kept)."
              color: root.fg
              font.family: root.font
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }
            Button { text: "Connect"; iconText: Schema.I.link; bordered: true; foreground: root.fg; accent: root.accent; fontFamily: root.font; onClicked: root.connectHook() }
          }
        }

        Rectangle {
          visible: root.errorText !== ""
          Layout.fillWidth: true
          implicitHeight: errRow.implicitHeight + Style.spacing.lg * 2
          radius: root.radius
          color: Util.alpha(Color.urgent, 0.12)
          border.width: 1
          border.color: Util.alpha(Color.urgent, 0.6)
          RowLayout {
            id: errRow
            anchors.fill: parent
            anchors.margins: Style.spacing.lg
            spacing: Style.spacing.lg
            Text {
              text: Schema.I.warn
              color: Color.urgent
              font.family: root.font
              font.pixelSize: Style.font.icon
            }
            Text {
              Layout.fillWidth: true
              text: root.errorText
              color: root.fg
              font.family: root.font
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
              maximumLineCount: 5
              elide: Text.ElideRight
            }
            PanelActionButton { iconText: Schema.I.close; tooltipText: "Dismiss"; foreground: root.fg; onClicked: root.errorText = "" }
          }
        }

        // ---------------------------------------------------- body
        RowLayout {
          Layout.fillWidth: true
          Layout.fillHeight: true
          spacing: Style.spacing.panelGap

          // rail
          ColumnLayout {
            Layout.preferredWidth: Style.space(176)
            Layout.minimumWidth: Style.space(176)
            Layout.maximumWidth: Style.space(176)
            Layout.fillHeight: true
            spacing: Style.spacing.md

            TextField {
              id: searchField
              Layout.fillWidth: true
              placeholderText: Schema.I.search + "  Search 350+ options"
              foreground: root.fg
              accent: root.accent
              font.family: root.font
              font.pixelSize: Style.font.bodySmall
              onTextChanged: { root.searchQuery = text; root.cursorIndex = 0 }
              Keys.onEscapePressed: function(e) { text = ""; root.refocus(); e.accepted = true }
              Keys.onDownPressed: function(e) { root.refocus(); root.moveCursor(1); e.accepted = true }
              onAccepted: root.refocus()
            }

            ListView {
              id: rail
              Layout.fillWidth: true
              Layout.fillHeight: true
              clip: true
              spacing: Style.spacing.xxs
              model: Schema.SECTIONS
              boundsBehavior: Flickable.StopAtBounds
              delegate: Rectangle {
                id: railItem
                required property var modelData
                required property int index
                readonly property bool current: root.sectionIndex === index && root.searchQuery === ""
                readonly property bool touched: root.sectionModified(modelData)
                width: rail.width
                height: Style.space(29)
                radius: root.radius
                color: current ? Util.alpha(root.accent, 0.16) : (railHover.hovered ? Util.alpha(root.fg, 0.06) : "transparent")
                Behavior on color { ColorAnimation { duration: 90 } }

                Rectangle {
                  visible: railItem.current
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  width: Style.space(3); height: parent.height * 0.55; radius: width / 2
                  color: root.accent
                }
                RowLayout {
                  anchors.fill: parent
                  anchors.leftMargin: Style.spacing.lg
                  anchors.rightMargin: Style.spacing.lg
                  spacing: Style.spacing.md
                  Text {
                    Layout.preferredWidth: Style.space(18)
                    text: railItem.modelData.icon
                    color: railItem.current ? root.accent : Util.alpha(root.fg, 0.75)
                    font.family: root.font
                    font.pixelSize: Style.font.body
                  }
                  Text {
                    Layout.fillWidth: true
                    text: railItem.modelData.title
                    color: railItem.current ? root.fg : Util.alpha(root.fg, 0.8)
                    font.family: root.font
                    font.pixelSize: Style.font.bodySmall
                    font.bold: railItem.current
                    elide: Text.ElideRight
                  }
                  Rectangle {
                    visible: railItem.touched
                    implicitWidth: Style.space(6); implicitHeight: implicitWidth; radius: implicitWidth / 2
                    color: root.accent
                  }
                }
                HoverHandler { id: railHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { root.goSection(railItem.index); root.refocus() } }
              }
            }

          }

          Rectangle { Layout.preferredWidth: 1; Layout.fillHeight: true; color: Util.alpha(root.fg, 0.1) }

          // content
          ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Style.spacing.md

            RowLayout {
              Layout.fillWidth: true
              spacing: Style.spacing.lg
              Text {
                text: root.searchQuery ? Schema.I.search : root.section.icon
                color: root.accent
                font.family: root.font
                font.pixelSize: Style.font.iconLarge
              }
              ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Text {
                  text: root.searchQuery ? root.rows.length + " result" + (root.rows.length === 1 ? "" : "s") : root.section.title
                  color: root.fg
                  font.family: root.font
                  font.pixelSize: Style.font.title
                  font.bold: true
                }
                Text {
                  Layout.fillWidth: true
                  text: root.searchQuery ? "for “" + root.searchQuery + "”  ·  Esc clears" : root.section.blurb
                  color: Util.alpha(root.fg, 0.55)
                  font.family: root.font
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }
              }
              Button {
                visible: !root.searchQuery && (root.hiddenAdvanced > 0 || (root.showAdvanced && root.section.items && root.section.items.some(function(i) { return i.advanced })))
                text: root.showAdvanced ? "Hide advanced" : "Advanced (" + root.hiddenAdvanced + ")"
                bordered: true
                foreground: root.fg
                accent: root.accent
                fontFamily: root.font
                fontSize: Style.font.caption
                onClicked: { root.showAdvanced = !root.showAdvanced; root.saveState() }
              }
              PanelActionButton {
                visible: !root.searchQuery && root.sectionModified(root.section)
                iconText: Schema.I.reset
                tooltipText: "Reset this section"
                foreground: root.fg
                onClicked: root.resetSection(root.section.id)
              }
            }

            // "Every option" filter bar
            ColumnLayout {
              visible: !root.searchQuery && root.section.view === "all"
              Layout.fillWidth: true
              spacing: Style.spacing.sm
              Text {
                Layout.fillWidth: true
                text: "Raw Hyprland options. Every change is dry-run in Hyprland first, so invalid values never get saved — but debug, render and xwayland options can still do surprising things."
                color: Util.alpha(root.fg, 0.5)
                font.family: root.font
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
              TextField {
                Layout.fillWidth: true
                placeholderText: "Filter " + root.allItemsCache.length + " options by name, key or description"
                foreground: root.fg
                accent: root.accent
                font.family: root.font
                font.pixelSize: Style.font.bodySmall
                onTextChanged: { root.allFilter = text; root.cursorIndex = 0 }
                Keys.onEscapePressed: function(e) { text = ""; root.refocus(); e.accepted = true }
                onAccepted: root.refocus()
              }
              Flow {
                Layout.fillWidth: true
                spacing: Style.spacing.xs
                Repeater {
                  model: [""].concat(root.allGroups)
                  Button {
                    required property string modelData
                    text: modelData === "" ? "all" : modelData
                    selected: root.allGroup === modelData
                    bordered: true
                    foreground: root.fg
                    accent: root.accent
                    fontFamily: root.font
                    fontSize: Style.font.caption
                    horizontalPadding: Style.spacing.md
                    verticalPadding: Style.spacing.xxs
                    onClicked: { root.allGroup = modelData; root.cursorIndex = 0 }
                  }
                }
              }
            }

            Item {
              Layout.fillWidth: true
              Layout.fillHeight: true
              ScrollIndicator { flickable: contentLoader.item; panel: root; z: 5 }
            Loader {
              id: contentLoader
              anchors.fill: parent
              sourceComponent: {
                if (root.listMode) return listView
                var v = root.section.view
                if (v === "home") return homeView
                if (v === "animations") return animationsView
                if (v === "rules") return rulesView
                if (v === "profiles") return profilesView
                return listView
              }
            }
            }
          }
        }

        // ---------------------------------------------------- footer
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.spacing.lg
          Rectangle {
            implicitWidth: Style.space(7); implicitHeight: implicitWidth; radius: implicitWidth / 2
            color: root.errorText !== "" ? Color.urgent : (persistTimer.running || evalProc.running || checkProc.running || reloadProc.running ? Color.accent : Util.alpha(root.fg, 0.3))
            SequentialAnimation on opacity {
              running: persistTimer.running || reloadProc.running
              loops: Animation.Infinite
              NumberAnimation { to: 0.3; duration: 300 }
              NumberAnimation { to: 1; duration: 300 }
            }
          }
          Text {
            Layout.fillWidth: true
            text: root.statusText !== "" ? root.statusText
                  : (persistTimer.running ? "Previewing…" : "Tab section · j/k row · h/l adjust (⇧ ×10) · ⌫ reset · / search · P peek · A advanced · Ctrl+Z undo")
            color: Util.alpha(root.fg, 0.55)
            font.family: root.font
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }
      }
    }
  }

  // ============================================================= views

  Component {
    id: listView
    ListView {
      id: lv
      clip: true
      spacing: Style.spacing.xxs
      boundsBehavior: Flickable.StopAtBounds
      model: root.rows
      cacheBuffer: 600
      reuseItems: false
      header: Item {
        width: lv.width
        height: showPreview ? pv.implicitHeight + Style.spacing.lg : 0
        readonly property bool showPreview: !root.searchQuery && root.section.preview === true
        visible: showPreview
        PreviewCanvas {
          id: pv
          visible: parent.showPreview
          width: parent.width - Style.spacing.lg
          height: implicitHeight
          panel: root
        }
      }
      delegate: BoundRow {
        required property var modelData
        required property int index
        width: lv.width - Style.spacing.lg
        panel: root
        item: modelData
        hasCursor: root.cursorIndex === index
        sectionTag: root.searchQuery ? (modelData.section ? Schema.sectionById(modelData.section).title : (modelData.group || "")) : ""
        onFocusRequested: root.cursorIndex = index
      }
      footer: Item {
        width: lv.width
        height: emptyText.visible ? Style.space(80) : Style.spacing.xl
        Text {
          id: emptyText
          anchors.centerIn: parent
          visible: root.rows.length === 0
          text: root.section.view === "all" && root.allItemsCache.length === 0 ? "Asking Hyprland for its options…" : "Nothing matches."
          color: Util.alpha(root.fg, 0.45)
          font.family: root.font
          font.pixelSize: Style.font.body
        }
      }
    }
  }

  Component { id: homeView; HomeView { panel: root; section: root.section } }
  Component { id: animationsView; AnimationsView { panel: root; section: root.section } }
  Component { id: rulesView; RulesView { panel: root; section: root.section } }
  Component { id: profilesView; ProfilesView { panel: root; section: root.section } }
}
