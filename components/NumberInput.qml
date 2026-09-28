import QtQuick
import qs.Commons

// Compact editable value readout next to a slider: click, type, Enter.
Rectangle {
  id: box

  property var panel: null
  property string text: ""
  property bool wideField: false

  signal submitted(string text)

  readonly property color fg: panel ? panel.fg : Color.foreground

  implicitWidth: wideField ? Style.space(110) : Math.max(Style.space(58), input.contentWidth + Style.spacing.lg * 2)
  implicitHeight: Style.space(24)
  radius: Style.space(5)
  color: input.activeFocus ? Util.alpha(fg, 0.08) : (hover.hovered ? Util.alpha(fg, 0.05) : "transparent")
  border.width: input.activeFocus ? 1 : 0
  border.color: panel ? panel.accent : Color.accent

  HoverHandler { id: hover; cursorShape: Qt.IBeamCursor }

  TextInput {
    id: input
    anchors.fill: parent
    anchors.leftMargin: Style.spacing.md
    anchors.rightMargin: Style.spacing.md
    verticalAlignment: TextInput.AlignVCenter
    horizontalAlignment: TextInput.AlignRight
    text: box.text
    color: box.fg
    selectionColor: Util.alpha(panel ? panel.accent : Color.accent, 0.4)
    font.family: panel ? panel.font : Style.font.family
    font.pixelSize: Style.font.bodySmall
    font.features: { "tnum": 1 }
    selectByMouse: true
    onActiveFocusChanged: if (activeFocus) selectAll()
    onAccepted: { box.submitted(text); if (box.panel) box.panel.refocus() }
    Keys.onEscapePressed: function(e) { text = box.text; if (box.panel) box.panel.refocus(); e.accepted = true }
  }

  onTextChanged: if (!input.activeFocus) input.text = text
}
