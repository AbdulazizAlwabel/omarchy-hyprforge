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

  // Never writes through a symlink or to a predictable path: the temp file
  // comes from mktemp (exclusive create, random name) in the same directory and
  // is renamed over the entry, which replaces a link instead of following it.
  // An existing entry is only replaced when it carries our marker.
  readonly property string installScript: [
    'dest=$1',
    'dir=${dest%/*}',
    'mkdir -p -- "$dir" || exit 0',
    '[ -L "$dest" ] && exit 0',
    'if [ -e "$dest" ] && ! grep -q "^X-Hyprforge-Managed=true$" -- "$dest"; then exit 0; fi',
    'tmp=$(mktemp -- "$dir/.hyprforge-desktop.XXXXXX") || exit 0',
    'printf "%s" "$2" > "$tmp" || { rm -f -- "$tmp"; exit 0; }',
    'chmod 644 -- "$tmp"',
    'if cmp -s -- "$tmp" "$dest"; then rm -f -- "$tmp"; else mv -fT -- "$tmp" "$dest"; fi'
  ].join("\n")

  // Removes only our own regular file, never a symlink or someone else's entry.
  readonly property string removeScript:
    '[ -L "$1" ] || { grep -q "^X-Hyprforge-Managed=true$" -- "$1" 2>/dev/null && rm -f -- "$1"; }'

  property bool installed: false

  Component.onCompleted: {
    installed = true
    withState(function(state) { svc.opDone() })
    Quickshell.execDetached(["sh", "-c", installScript, "sh", desktopDest, desktopText])
    Quickshell.execDetached(["mkdir", "-p", home + "/.config/hypr/hyprforge", home + "/.cache/hyprforge"])
  }

  Component.onDestruction: {
    if (!installed) return
    Quickshell.execDetached(["sh", "-c", removeScript, "sh", desktopDest])
  }

  // ------------------------------------------------------------ headless apply
  //
  // Script commands run one at a time through a small queue. Each operation
  // reads state.json fresh (size-capped, see BoundedRead.qml), changes it, and
  // finishes only after its writes have landed, so the next one never sees
  // stale data. The panel is told afterwards (stateWritten) and re-reads.
  signal stateWritten()

  property var pending: null
  property var ops: []
  property var currentOp: null
  property bool opBusy: false
  property var cachedProfiles: []

  function withState(fn) {
    ops = ops.concat([fn])
    if (!opBusy) nextOp()
  }

  function nextOp() {
    if (ops.length === 0) { opBusy = false; return }
    opBusy = true
    currentOp = ops[0]
    ops = ops.slice(1)
    stateReader.read()
  }

  function opDone() {
    currentOp = null
    Qt.callLater(nextOp)
  }

  // null when state.json exists but can't be read or parsed: never overwrite it then.
  property BoundedRead stateReader: BoundedRead {
    path: svc.statePath
    limit: 4 * 1024 * 1024
    onDone: function(raw, status) {
      var state = null
      if (status === "missing" || (status === "ok" && String(raw).trim() === ""))
        state = { version: Engine.VERSION, cfg: Engine.defaultConfig(), profiles: {} }
      else if (status === "ok") { try { state = JSON.parse(raw) } catch (e) { state = null } }
      if (state) svc.cachedProfiles = Object.keys(state.profiles || {}).sort()
      var fn = svc.currentOp
      if (fn) fn(state)
      else svc.opDone()
    }
  }

  property BoundedRead historyReader: BoundedRead {
    path: svc.home + "/.config/hypr/hyprforge/history.json"
    limit: 8 * 1024 * 1024
    onDone: function(raw, status) {
      var h = []
      if (status === "ok") { try { h = JSON.parse(raw) } catch (e) { h = [] } }
      else if (status !== "missing") { svc.notify("history.json could not be read; history not updated", true); h = null }
      svc.historyReady(h)
    }
  }

  property Process baselineProc: Process {
    command: svc.capped(["lua", svc.pluginDir + "/baseline.lua", svc.omarchyPath + "/default/hypr/looknfeel.lua", svc.home + "/.config/hypr/looknfeel.lua"], 1024 * 1024)
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var baseline = { curves: [], animations: [] }
        try { baseline = JSON.parse(text) } catch (e) {}
        svc.finish(baseline)
      }
    }
  }

  // All writes: mktemp + rename, never through a symlink (see SafeWriter.qml).
  // The Lua file is always the last write of an operation.
  property SafeWriter writer: SafeWriter {
    onWritten: function(path, ok) {
      if (!ok) svc.notify("Could not write " + path, true)
      if (path === svc.luaPath) {
        if (ok) svc.reloadProc.running = true
        svc.stateWritten()
        svc.opDone()
      } else if (path === svc.statePath && svc.stateOnlyOp) {
        svc.stateOnlyOp = false
        svc.stateWritten()
        svc.opDone()
      }
    }
  }
  property bool stateOnlyOp: false

  property Process reloadProc: Process { command: ["timeout", "8", "hyprctl", "reload"] }

  // Cap a command's stdout before it reaches QML (StdioCollector keeps all of it).
  function capped(cmd, bytes) {
    return ["sh", "-c", '"$@" | head -c ' + Math.floor(bytes), "sh"].concat(cmd)
  }

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

  // mutate(state) edits the parsed state in place and returns a label, or ""
  // to change nothing. Queued; returns immediately.
  function run(mutate) {
    withState(function(state) {
      if (!state) { svc.notify("state.json is unreadable; nothing was changed", true); svc.opDone(); return }
      var label = mutate(state)
      if (!label) { svc.opDone(); return }
      svc.pending = { state: state, label: label }
      svc.baselineProc.running = true
    })
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

  // validate -> `hyprctl eval` dry-run -> write state + history + lua -> reload
  function finish(baseline) {
    if (!pending) return
    var p = pending
    pending = null
    p.state.cfg = Engine.normalize(p.state.cfg)
    var problems = Engine.validate(p.state.cfg, typeOf)
    if (problems.length) { notify("Not applied: " + problems[0].key + " " + problems[0].problem, true); opDone(); return }
    p.lua = Engine.renderFile(p.state.cfg, { baseline: baseline })
    var body = Engine.render(p.state.cfg, { baseline: baseline })
    checked = p
    if (!body) { commit(); return }
    evalCheck.command = capped(["timeout", "5", "hyprctl", "eval", "local _hyprforge_check = true\n" + body], 64 * 1024)
    evalCheck.running = true
  }

  property var checked: null

  // History is read (bounded) before it's appended to; the writes follow in
  // order: state, history, then the Lua file (which ends the operation).
  function commit() {
    if (!checked) { opDone(); return }
    historyReader.read()
  }

  function historyReady(h) {
    var p = checked
    checked = null
    if (!p) { opDone(); return }
    writer.write(svc.statePath, JSON.stringify(p.state, null, 2) + "\n")
    if (h !== null) {
      if (!Array.isArray(h)) h = []
      h.push({ time: Date.now(), label: p.label, cfg: Engine.normalize(p.state.cfg) })
      while (h.length > 60) h.shift()
      writer.write(svc.home + "/.config/hypr/hyprforge/history.json", JSON.stringify(h) + "\n")
    }
    writer.write(svc.luaPath, p.lua)
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
        svc.opDone()
      }
    }
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

    // Answers from the last read and refreshes the cache for next time.
    function listProfiles(): string {
      svc.withState(function(state) { svc.opDone() })
      return svc.cachedProfiles.join("\n")
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
      svc.withState(function(state) {
        if (!state) { svc.notify("state.json is unreadable; profile not saved", true); svc.opDone(); return }
        if (!state.profiles) state.profiles = {}
        state.profiles[n] = { cfg: Engine.normalize(state.cfg), saved: Date.now() }
        state.activeProfile = n
        svc.cachedProfiles = Object.keys(state.profiles).sort()
        svc.stateOnlyOp = true
        svc.writer.write(svc.statePath, JSON.stringify(state, null, 2) + "\n")
      })
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
      svc.checkProc.command = svc.capped(["timeout", "5", "hyprctl", "getoption", key, "-j"], 64 * 1024)
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
