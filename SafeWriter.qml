import QtQuick
import Quickshell.Io

// Writes files without ever following a symlink. The content is piped to a
// fixed shell snippet that creates a fresh mktemp file (exclusive, random name)
// in the destination directory and renames it over the path. A rename replaces
// a symlink at the path instead of writing through it, so a planted link can't
// redirect the write into another file. Writes are queued and run one at a time;
// `written(path, ok)` reports each result in order.
// write(path, text, true) first copies the current file to <path>.bak the
// same way (mktemp + rename) inside the same job, and writes only if that
// succeeded. Each job is an immutable {path, text, backup} record run by its
// own process invocation, so a finishing backup can never be attributed to a
// different write.
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
    'if [ "$2" = 1 ] && [ -f "$1" ] && [ ! -L "$1" ]; then',
    '  b=$(mktemp -- "$d/.$(basename -- "$1").bak.XXXXXX")',
    '  cat -- "$1" > "$b" || { rm -f -- "$b"; exit 1; }',
    '  mv -fT -- "$b" "$1.bak"',
    'fi',
    't=$(mktemp -- "$d/.$(basename -- "$1").XXXXXX")',
    'trap \'rm -f -- "$t"\' EXIT',
    'cat > "$t"',
    'chmod 644 -- "$t"',
    'mv -fT -- "$t" "$1"',
    'trap - EXIT'
  ].join("\n")

  function write(path, text, backup) {
    queue = queue.concat([{ path: String(path), text: String(text), backup: backup === true }])
    if (!active) next()
  }

  function next() {
    if (queue.length === 0) { active = false; return }
    active = true
    var job = queue[0]
    queue = queue.slice(1)
    proc.job = job
    proc.command = ["sh", "-c", script, "sh", job.path, job.backup ? "1" : "0"]
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
