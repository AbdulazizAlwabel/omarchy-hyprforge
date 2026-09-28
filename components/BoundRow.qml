import QtQuick

// OptionRow wired to the panel's state for one catalogue item.
OptionRow {
  id: bound
  value: panel ? panel.valueFor(item) : undefined
  wasValue: panel ? panel.base[item.key] : undefined
  liveRaw: panel ? panel.live[item.key] : undefined
  modified: panel ? panel.isModified(item.key) : false
  available: panel ? panel.isAvailable(item) : true
  onEdited: function(v) { if (panel) panel.setValue(item, v, false) }
  onCommitted: function(v) { if (panel) panel.setValue(item, v, true) }
  onReset: if (panel) panel.resetKeys([item.key])
}
