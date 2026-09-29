import QtQuick
import Quickshell.Io

// Reads a file into QML with a hard size limit, so an oversized or swapped-in
// file can never exhaust the shell's memory. The size is checked before any
// byte is read, and `head -c` caps the stream regardless. Only regular files
// are read; symlinks are refused unless `followLinks` is set (for user config
// that may legitimately live in a dotfiles repo).
//
//   done(text, status)   status: "ok" | "missing" | "too-large" | "refused" | "error"
//
// Every read() gets a token; a result is reported only for the newest request.
Item {
  id: reader

  property string path: ""
  property int limit: 1048576
  property bool followLinks: false

  signal done(string text, string status)

  property int token: 0
  property bool again: false

  readonly property string script: [
    'f=$1; n=$2; follow=$3',
    '[ -e "$f" ] || [ -L "$f" ] || exit 10',
    '[ "$follow" = 1 ] || [ ! -L "$f" ] || exit 12',
    '[ -f "$f" ] || exit 12',
    's=$(stat -Lc %s -- "$f") || exit 13',
    '[ "$s" -le "$n" ] || exit 11',
    'head -c "$n" -- "$f"'
  ].join("\n")

  function read() {
    token++
    if (proc.running) { again = true; return }
    start()
  }

  function start() {
    proc.token = token
    proc.command = ["sh", "-c", script, "sh", path, String(limit), followLinks ? "1" : "0"]
    proc.running = true
  }

  Process {
    id: proc
    property int token: 0
    stdout: StdioCollector { id: out; waitForEnd: true }
    onExited: function(code) {
      if (reader.again) { reader.again = false; reader.start(); return }
      if (proc.token !== reader.token) return
      var status = code === 0 ? "ok" : code === 10 ? "missing" : code === 11 ? "too-large" : code === 12 ? "refused" : "error"
      reader.done(code === 0 ? String(out.text) : "", status)
    }
  }
}
