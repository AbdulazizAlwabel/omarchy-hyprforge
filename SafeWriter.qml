import QtQuick
import Quickshell.Io

// Writes files without ever following a symlink. The content is piped to a
// fixed shell snippet that creates a fresh mktemp file (exclusive, random name)
// in the destination directory and renames it over the path. A rename replaces
// a symlink at the path instead of writing through it, so a planted link can't
// redirect the write into another file. Writes are queued and run one at a time;
// `written(path, ok)` reports each result in order.
Item {
  id: writer

  signal written(string path, bool ok)

  property var queue: []
  // Own flag: Process.running doesn't flip synchronously, so back-to-back
  // write() calls must not rely on it.
  property bool active: false
  readonly property bool busy: active || queue.length > 0

  readonly property string script: [
    'set -eu',
    'd=$(dirname -- "$1")',
    'mkdir -p -- "$d"',
    't=$(mktemp -- "$d/.$(basename -- "$1").XXXXXX")',
    'trap \'rm -f -- "$t"\' EXIT',
    'cat > "$t"',
    'chmod 644 -- "$t"',
    'mv -fT -- "$t" "$1"',
    'trap - EXIT'
  ].join("\n")

  function write(path, text) {
    queue = queue.concat([{ path: String(path), text: String(text) }])
    if (!active) next()
  }

  function next() {
    if (queue.length === 0) { active = false; return }
    active = true
    var job = queue[0]
    queue = queue.slice(1)
    proc.job = job
    proc.command = ["sh", "-c", script, "sh", job.path]
    proc.running = true
  }

  Process {
    id: proc
    property var job: null
    stdinEnabled: true
    onStarted: {
      write(job.text)
      stdinEnabled = false          // closes stdin so `cat` finishes
    }
    onExited: function(code) {
      var j = job
      stdinEnabled = true
      writer.written(j.path, code === 0)
      writer.next()
    }
  }
}
