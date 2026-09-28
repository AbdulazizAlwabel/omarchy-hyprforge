import QtQuick
import Quickshell
import Quickshell.Io
import "Engine.js" as Engine
import "Schema.js" as Schema

// Headless half of Hyprforge.
//
// * Installs the SUPER+SPACE launcher entry (only a file carrying the
//   X-Hyprforge-Managed marker is ever written or removed).
// * Exposes `omarchy-shell hyprforge <method>` so keybindings and scripts can
//   switch profiles, looks and motion presets without opening the panel:
//
//     omarchy-shell hyprforge toggle
//     omarchy-shell hyprforge profile "Gaming"
//     omarchy-shell hyprforge cycleProfile
//     omarchy-shell hyprforge look glass        (stock glass neon soft flat zen compact retro performance)
//     omarchy-shell hyprforge motion bouncy     (omarchy snappy smooth bouncy slide fade minimal)
//     omarchy-shell hyprforge listProfiles
//     omarchy-shell hyprforge saveProfile "Work"
//     omarchy-shell hyprforge set decoration:rounding 12      (unset <key> to drop it)
QtObject {
  id: svc

  property string omarchyPath: Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy"
  property var shell: null
  property var manifest: null

  readonly property string home: Quickshell.env("HOME")
  readonly property string statePath: home + "/.config/hypr/hyprforge/state.json"
  readonly property string luaPath: home + "/.config/hypr/hyprforge.lua"
  readonly property string pluginDir: {
    var u = String(Qt.resolvedUrl("baseline.lua"))
    return decodeURIComponent(u.replace(/^file:\/\//, "")).replace(/\/baseline\.lua$/, "")
  }
  readonly property string pluginId: (manifest && manifest.id) || "aziz.hyprforge"

  // ------------------------------------------------------------ launcher
  readonly property string desktopDest: home + "/.local/share/applications/hyprforge.desktop"
  readonly property string desktopText: [
    "[Desktop Entry]",
    "Type=Application",
    "Name=Hyprforge",
    "GenericName=Hyprland Studio",
    "Comment=Customize Hyprland: gaps, borders, colors, blur, shadows, animations, app rules and profiles",
    "Exec=omarchy-shell shell toggle " + pluginId + " {}",
    "TryExec=omarchy-shell",
    "Icon=" + pluginDir + "/icon.svg",
    "Terminal=false",
    "StartupNotify=false",
    "Categories=Settings;DesktopSettings;",
    "Keywords=hyprland;omarchy;gaps;blur;opacity;animations;rounding;shadow;border;theme;window;rules;",
    "X-Hyprforge-Managed=true",
    ""
  ].join("\n")

  readonly property string installScript:
      'if [ -e "$1" ] && ! grep -q "^X-Hyprforge-Managed=true$" "$1"; then exit 0; fi\n'
    + 'mkdir -p "${1%/*}" || exit 0\n'
    + 'tmp="$1.hyprforge.new"\n'
    + 'printf "%s" "$2" > "$tmp" || exit 0\n'
    + 'if cmp -s "$tmp" "$1"; then rm -f "$tmp"; else mv -f "$tmp" "$1"; fi\n'

  property bool installed: false

  Component.onCompleted: {
    installed = true
    Quickshell.execDetached(["sh", "-c", installScript, "sh", desktopDest, desktopText])
    Quickshell.execDetached(["mkdir", "-p", home + "/.config/hypr/hyprforge", home + "/.cache/hyprforge"])
  }

  Component.onDestruction: {
    if (!installed) return
    Quickshell.execDetached(["sh", "-c", 'grep -q "^X-Hyprforge-Managed=true$" "$1" 2>/dev/null && rm -f "$1"', "sh", desktopDest])
  }

  // ------------------------------------------------------------ headless apply
  property var pending: null

  // Watched so the cached text always matches disk: the panel writes this
  // file too, and acting on a stale copy would undo its changes.
  property FileView stateFile: FileView {
    path: svc.statePath
    blockLoading: true
    printErrors: false
    atomicWrites: true
    watchChanges: true
    onFileChanged: reload()
  }

  property FileView luaFile: FileView {
    path: svc.luaPath
    blockLoading: true
    printErrors: false
    atomicWrites: true
    watchChanges: true
    onFileChanged: reload()
    onSaved: svc.reloadProc.running = true
  }

  property Process baselineProc: Process {
    command: ["lua", svc.pluginDir + "/baseline.lua", svc.omarchyPath + "/default/hypr/looknfeel.lua", svc.home + "/.config/hypr/looknfeel.lua"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var baseline = { curves: [], animations: [] }
        try { baseline = JSON.parse(text) } catch (e) {}
        svc.finish(baseline)
      }
    }
  }

  property Process reloadProc: Process { command: ["timeout", "8", "hyprctl", "reload"] }

  property var pendingSet: null
  property Process checkProc: Process {
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var p = svc.pendingSet
        svc.pendingSet = null
        if (!p) return
        var entry = null
        try { entry = JSON.parse(String(text).match(/\{[^{}]*\}/)[0]) } catch (e) {}
        if (!entry || !entry.option) { svc.notify("Unknown Hyprland option: " + p.key, true); return }
        var t = Engine.liveType(entry)
        var why = (t === "int" && Engine.isColorSpec(p.value)) ? "" : Engine.checkValue(t === "text" ? "any" : t, p.value)
        if (why) { svc.notify(p.key + " " + why + " — not applied", true); return }
        svc.run(function(state) { state.cfg = Engine.normalize(state.cfg); state.cfg.options[p.key] = p.value; return p.key + " = " + p.text })
      }
    }
  }

  // null when state.json exists but can't be parsed: never overwrite it then.
  function readState() {
    stateFile.reload()
    var raw = stateFile.text()
    if (!raw || raw.trim() === "") return { version: Engine.VERSION, cfg: Engine.defaultConfig(), profiles: {} }
    try { return JSON.parse(raw) } catch (e) { return null }
  }

  // mutate(state) edits the parsed state in place and returns a label, or ""
  // to abort.
  function run(mutate) {
    var state = readState()
    if (!state) { notify("state.json is unreadable; nothing was changed", true); return "error" }
    var label = mutate(state)
    if (!label) return "unknown"
    pending = { state: state, label: label }
    baselineProc.running = true
    return "ok"
  }

  // Catalogue type when known; anything else must at least be a sane shape,
  // and the eval dry-run below catches type mismatches.
  function typeOf(key) {
    var it = Schema.itemFor(key)
    return it ? it.type : "any"
  }

  function notify(text, critical) {
    Quickshell.execDetached(["notify-send", "-a", "Hyprforge", "-t", critical ? "6000" : "1800"].concat(critical ? ["-u", "critical"] : []).concat(["Hyprforge", text]))
  }

  // validate -> `hyprctl eval` dry-run -> write state + lua -> reload
  function finish(baseline) {
    if (!pending) return
    var p = pending
    pending = null
    p.state.cfg = Engine.normalize(p.state.cfg)
    var problems = Engine.validate(p.state.cfg, typeOf)
    if (problems.length) { notify("Not applied: " + problems[0].key + " " + problems[0].problem, true); return }
    p.lua = Engine.renderFile(p.state.cfg, { baseline: baseline })
    var body = Engine.render(p.state.cfg, { baseline: baseline })
    checked = p
    if (!body) { commit(); return }
    evalCheck.command = ["timeout", "5", "hyprctl", "eval", "local _hyprforge_check = true\n" + body]
    evalCheck.running = true
  }

  property var checked: null

  function commit() {
    var p = checked
    checked = null
    if (!p) return
    stateFile.setText(JSON.stringify(p.state, null, 2) + "\n")
    appendHistory(p.label, p.state.cfg)
    luaFile.setText(p.lua)
    notify(p.label, false)
  }

  property Process evalCheck: Process {
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var t = String(text || "").trim()
        if (t === "ok") { svc.commit(); return }
        svc.checked = null
        svc.notify("Hyprland rejected that, nothing was saved: " + t.split("\n").pop(), true)
        svc.reloadProc.running = true
      }
    }
  }

  property FileView historyFile: FileView {
    path: svc.home + "/.config/hypr/hyprforge/history.json"
    blockLoading: true
    printErrors: false
    atomicWrites: true
    watchChanges: true
    onFileChanged: reload()
  }

  function appendHistory(label, cfg) {
    historyFile.reload()
    var h = []
    try { h = JSON.parse(historyFile.text()) } catch (e) {}
    if (!Array.isArray(h)) h = []
    h.push({ time: Date.now(), label: label, cfg: Engine.normalize(cfg) })
    while (h.length > 60) h.shift()
    historyFile.setText(JSON.stringify(h) + "\n")
  }

  function applyProfileTo(state, name) {
    var prof = state.profiles && state.profiles[name]
    if (!prof) return ""
    state.cfg = Engine.normalize(prof.cfg)
    state.activeProfile = name
    return "Profile: " + name
  }

  property IpcHandler ipc: IpcHandler {
    target: "hyprforge"

    function open(): void { Quickshell.execDetached(["omarchy-shell", "shell", "summon", svc.pluginId, "{}"]) }
    function close(): void { Quickshell.execDetached(["omarchy-shell", "shell", "hide", svc.pluginId]) }
    function toggle(): void { Quickshell.execDetached(["omarchy-shell", "shell", "toggle", svc.pluginId, "{}"]) }
    function section(id: string): void { Quickshell.execDetached(["omarchy-shell", "shell", "summon", svc.pluginId, JSON.stringify({ section: id })]) }

    function profile(name: string): string {
      return svc.run(function(state) { return svc.applyProfileTo(state, name) })
    }

    function cycleProfile(): string {
      return svc.run(function(state) {
        var names = Object.keys(state.profiles || {}).sort(function(a, b) { return a.toLowerCase().localeCompare(b.toLowerCase()) })
        if (names.length === 0) return ""
        var at = names.indexOf(state.activeProfile || "")
        return svc.applyProfileTo(state, names[(at + 1) % names.length])
      })
    }

    function listProfiles(): string {
      var state = svc.readState()
      return state ? Object.keys(state.profiles || {}).sort().join("\n") : "error"
    }

    function look(id: string): string {
      return svc.run(function(state) {
        var l = Engine.lookById(id)
        if (!l) return ""
        var cfg = Engine.normalize(state.cfg)
        var drop = Schema.keysInSections(Engine.LOOK_SECTIONS)
        for (var key in drop) delete cfg.options[key]
        var o = Engine.clone(l.options)
        for (var k in o) cfg.options[k] = o[k]
        if (l.extra) for (var k2 in l.extra) cfg.options[k2] = l.extra[k2]
        state.cfg = cfg
        return "Look: " + l.name
      })
    }

    function motion(id: string): string {
      return svc.run(function(state) {
        var m = Engine.motionById(id)
        if (!m) return ""
        var cfg = Engine.normalize(state.cfg)
        cfg.anims = Engine.clone(m.anims)
        var c = Engine.clone(m.curves)
        for (var n in c) cfg.curves[n] = c[n]
        state.cfg = cfg
        return "Motion: " + m.name
      })
    }

    function saveProfile(name: string): string {
      var n = String(name || "").trim()
      if (!n) return "unknown"
      var state = svc.readState()
      if (!state) return "error"
      if (!state.profiles) state.profiles = {}
      state.profiles[n] = { cfg: Engine.normalize(state.cfg), saved: Date.now() }
      state.activeProfile = n
      svc.stateFile.setText(JSON.stringify(state, null, 2) + "\n")
      return "ok"
    }

    // omarchy-shell hyprforge set decoration:rounding 12
    // Values are JSON when they parse (true, 0.8, [0,4], {"slots":["accent"],"alpha":255})
    // and plain strings otherwise. The key is checked with Hyprland first.
    function set(key: string, value: string): string {
      var v
      try { v = JSON.parse(value) } catch (e) { v = String(value) }
      if (String(key).indexOf("hf:") === 0) {
        return svc.run(function(state) { state.cfg = Engine.normalize(state.cfg); state.cfg.options[key] = v; return key + " = " + value })
      }
      svc.pendingSet = { key: key, value: v, text: value }
      svc.checkProc.command = ["timeout", "5", "hyprctl", "getoption", key, "-j"]
      svc.checkProc.running = true
      return "ok"
    }

    function unset(key: string): string {
      return svc.run(function(state) {
        state.cfg = Engine.normalize(state.cfg)
        if (state.cfg.options[key] === undefined) return ""
        delete state.cfg.options[key]
        return "Reset " + key
      })
    }

    function reset(): string {
      return svc.run(function(state) { state.cfg = Engine.defaultConfig(); state.activeProfile = ""; return "Back to stock Omarchy" })
    }
  }
}
