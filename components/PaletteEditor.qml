import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "../Engine.js" as Engine
import "../Schema.js" as Schema

// Color / gradient editor built on palette *names*. Picking "accent" stores
// "accent", not its hex, so the color follows every theme change. A literal
// hex is still possible for people who want a fixed color.
ColumnLayout {
  id: ed

  property var panel: null
  property var spec: null          // null = theme default
  property var liveValue           // what Hyprland reports right now
  property bool gradient: false

  signal edited(var spec)
  signal committed(var spec)

  property int selected: 0
  property bool pickerOpen: false

  readonly property color fg: panel ? panel.fg : Color.foreground
  readonly property color accent: panel ? panel.accent : Color.accent
  readonly property string fontFamily: panel ? panel.font : Style.font.family
  readonly property var slots: spec ? spec.slots : []
  readonly property int alpha: spec && spec.alpha !== undefined ? spec.alpha : 255
  readonly property int angle: spec && spec.angle !== undefined ? spec.angle : 45

  spacing: Style.spacing.md

  function hexOf(slot) { return panel ? Engine.resolveSlot(slot, panel.paletteMap) : "#888888" }

  function colorOf(slot, a) {
    var c = Qt.color(hexOf(slot))
    return Qt.rgba(c.r, c.g, c.b, (a === undefined ? alpha : a) / 255)
  }

  // Current look when following the theme, as [{ color, alpha }].
  function liveStops() {
    var v = liveValue
    if (v && v.gradient !== undefined) {
      var g = Engine.parseGradient(v.gradient)
      var out = []
      for (var i = 0; i < g.colors.length; i++) out.push({ hex: g.colors[i], alpha: g.alphas[i] })
      return { stops: out, angle: g.angle }
    }
    if (typeof v === "number") {
      var c = Engine.argbToHex(v)
      return { stops: [{ hex: c.hex, alpha: c.alpha }], angle: 0 }
    }
    return { stops: [{ hex: panel ? panel.paletteMap.accent : "#888888", alpha: 255 }], angle: 0 }
  }

  function customizeFromLive() {
    var l = liveStops()
    var s = { slots: [], alpha: l.stops.length ? l.stops[0].alpha : 238 }
    for (var i = 0; i < l.stops.length; i++) s.slots.push(panel ? panel.slotForHex(l.stops[i].hex) : l.stops[i].hex)
    if (s.slots.length === 0) s.slots = ["accent"]
    if (!gradient) s.slots = [s.slots[0]]
    if (gradient) s.angle = l.angle || 45
    selected = 0
    pickerOpen = true
    committed(s)
  }

  function withSlots(next) {
    var s = { slots: next, alpha: alpha }
    if (gradient) s.angle = angle
    return s
  }

  function setSlot(i, name) {
    var next = slots.slice()
    if (i >= next.length) next.push(name); else next[i] = name
    committed(withSlots(next))
  }

  function removeSlot(i) {
    if (slots.length <= 1) return
    var next = slots.slice()
    next.splice(i, 1)
    selected = Math.max(0, Math.min(selected, next.length - 1))
    committed(withSlots(next))
  }

  function moveSlot(i, d) {
    var j = i + d
    if (j < 0 || j >= slots.length) return
    var next = slots.slice()
    var t = next[i]; next[i] = next[j]; next[j] = t
    selected = j
    committed(withSlots(next))
  }

  // ------------------------------------------------------------ preview bar

  RowLayout {
    Layout.fillWidth: true
    spacing: Style.spacing.lg

    Rectangle {
      id: bar
      Layout.preferredWidth: Style.space(120)
      Layout.preferredHeight: Style.space(22)
      radius: height / 2
      border.width: 1
      border.color: Util.alpha(ed.fg, 0.15)
      // checkerboard hint for transparency
      color: Util.alpha(ed.fg, 0.08)
      clip: true

      Rectangle {
        anchors.fill: parent
        anchors.margins: 1
        radius: height / 2
        gradient: Gradient {
          orientation: Gradient.Horizontal
          GradientStop { position: 0; color: ed.stopColor(0) }
          GradientStop { position: 0.5; color: ed.stopColor(0.5) }
          GradientStop { position: 1; color: ed.stopColor(1) }
        }
      }
    }

    Text {
      visible: ed.spec === null
      Layout.fillWidth: true
      text: "Following your theme"
      color: Util.alpha(ed.fg, 0.6)
      font.family: ed.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    Button {
      visible: ed.spec === null
      text: "Customize"
      iconText: Schema.I.palette
      bordered: true
      foreground: ed.fg
      accent: ed.accent
      fontFamily: ed.fontFamily
      fontSize: Style.font.bodySmall
      onClicked: ed.customizeFromLive()
    }

    // slot chips
    Flow {
      visible: ed.spec !== null
      Layout.fillWidth: true
      spacing: Style.spacing.xs

      Repeater {
        model: ed.slots
        Rectangle {
          id: chip
          required property var modelData
          required property int index
          readonly property bool isSel: ed.pickerOpen && ed.selected === index
          height: Style.space(24)
          width: chipRow.implicitWidth + Style.spacing.lg * 2
          radius: height / 2
          color: isSel ? Util.alpha(ed.accent, 0.18) : Util.alpha(ed.fg, chipHover.hovered ? 0.09 : 0.05)
          border.width: isSel ? 1 : 0
          border.color: ed.accent

          Row {
            id: chipRow
            anchors.centerIn: parent
            spacing: Style.spacing.sm
            Rectangle {
              width: Style.space(12); height: width; radius: width / 2
              anchors.verticalCenter: parent.verticalCenter
              color: ed.hexOf(chip.modelData)
              border.width: 1
              border.color: Util.alpha(ed.fg, 0.25)
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: String(chip.modelData).replace(/_/g, " ")
              color: ed.fg
              font.family: ed.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
          HoverHandler { id: chipHover; cursorShape: Qt.PointingHandCursor }
          TapHandler {
            onTapped: {
              if (ed.pickerOpen && ed.selected === chip.index) ed.pickerOpen = false
              else { ed.selected = chip.index; ed.pickerOpen = true }
            }
          }
        }
      }

      Rectangle {
        visible: ed.gradient && ed.slots.length < 6
        height: Style.space(24); width: height; radius: height / 2
        color: Util.alpha(ed.fg, addHover.hovered ? 0.12 : 0.06)
        Text {
          anchors.centerIn: parent
          text: Schema.I.plus
          color: ed.fg
          font.family: ed.fontFamily
          font.pixelSize: Style.font.body
        }
        HoverHandler { id: addHover; cursorShape: Qt.PointingHandCursor }
        TapHandler {
          onTapped: {
            var at = ed.slots.length
            ed.setSlot(at, at ? ed.slots[at - 1] : "accent")
            ed.selected = at
            ed.pickerOpen = true
          }
        }
      }

      PanelActionButton {
        visible: ed.pickerOpen && ed.gradient && ed.slots.length > 1
        iconText: "\u{F0141}"
        tooltipText: "Move left"
        foreground: ed.fg
        onClicked: ed.moveSlot(ed.selected, -1)
      }
      PanelActionButton {
        visible: ed.pickerOpen && ed.gradient && ed.slots.length > 1
        iconText: "\u{F0142}"
        tooltipText: "Move right"
        foreground: ed.fg
        onClicked: ed.moveSlot(ed.selected, 1)
      }
      PanelActionButton {
        visible: ed.pickerOpen && ed.slots.length > 1
        iconText: Schema.I.trash
        tooltipText: "Remove this color"
        foreground: ed.fg
        onClicked: ed.removeSlot(ed.selected)
      }
    }
  }

  function stopColor(pos) {
    if (spec === null) {
      var l = liveStops().stops
      if (l.length === 0) return "transparent"
      var i = Math.min(l.length - 1, Math.round(pos * (l.length - 1)))
      var c = Qt.color(l[i].hex)
      return Qt.rgba(c.r, c.g, c.b, l[i].alpha / 255)
    }
    if (slots.length === 0) return "transparent"
    var j = Math.min(slots.length - 1, Math.round(pos * (slots.length - 1)))
    return colorOf(slots[j])
  }

  // ------------------------------------------------------------ swatch picker

  Rectangle {
    visible: ed.spec !== null && ed.pickerOpen
    Layout.fillWidth: true
    implicitHeight: pickCol.implicitHeight + Style.spacing.lg * 2
    radius: panel ? panel.radius : 6
    color: Util.alpha(ed.fg, 0.035)
    border.width: 1
    border.color: Util.alpha(ed.fg, 0.08)

    ColumnLayout {
      id: pickCol
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Style.spacing.lg
      spacing: Style.spacing.md

      Text {
        text: "Theme palette  ·  " + (panel ? panel.themeName : "")
        color: Util.alpha(ed.fg, 0.55)
        font.family: ed.fontFamily
        font.pixelSize: Style.font.caption
      }

      Flow {
        Layout.fillWidth: true
        spacing: Style.spacing.xs
        Repeater {
          model: panel ? panel.themePalette : []
          Rectangle {
            id: sw
            required property var modelData
            readonly property bool current: ed.slots[ed.selected] === modelData.name
            width: Style.space(26); height: width; radius: width / 2
            color: modelData.hex
            border.width: current ? 2 : 1
            border.color: current ? ed.fg : Util.alpha(ed.fg, 0.2)
            scale: swHover.hovered ? 1.15 : 1
            Behavior on scale { NumberAnimation { duration: 90 } }
            HoverHandler { id: swHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: ed.setSlot(ed.selected, sw.modelData.name) }
            PanelToolTip {
              visible: swHover.hovered
              text: sw.modelData.name.replace(/_/g, " ") + "  " + sw.modelData.hex
            }
          }
        }
      }

      RowLayout {
        spacing: Style.spacing.lg
        Text {
          text: "Fixed hex"
          color: Util.alpha(ed.fg, 0.55)
          font.family: ed.fontFamily
          font.pixelSize: Style.font.caption
        }
        TextField {
          implicitWidth: Style.space(110)
          placeholderText: "#rrggbb"
          text: String(ed.slots[ed.selected] || "").charAt(0) === "#" ? ed.slots[ed.selected] : ""
          foreground: ed.fg
          accent: ed.accent
          font.family: ed.fontFamily
          font.pixelSize: Style.font.bodySmall
          selectByMouse: true
          onAccepted: {
            var m = String(text).trim().match(/^#?([0-9a-fA-F]{6})$/)
            if (m) ed.setSlot(ed.selected, "#" + m[1].toLowerCase())
            if (panel) panel.refocus()
          }
        }
        Text {
          Layout.fillWidth: true
          text: "Doesn't follow theme changes"
          color: Util.alpha(ed.fg, 0.4)
          font.family: ed.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }
  }

  // ---------------------------------------------------------- alpha / angle

  RowLayout {
    visible: ed.spec !== null
    Layout.fillWidth: true
    spacing: Style.spacing.lg
    Text {
      Layout.preferredWidth: Style.space(52)
      text: "Opacity"
      color: Util.alpha(ed.fg, 0.7)
      font.family: ed.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
    Slider {
      Layout.fillWidth: true
      minimum: 0; maximum: 255; integer: true; step: 5
      value: ed.alpha
      trackColor: Util.alpha(ed.fg, 0.14)
      fillColor: ed.accent
      knobColor: ed.fg
      onMoved: function(v) { var s = ed.withSlots(ed.slots); s.alpha = Math.round(v); ed.edited(s) }
      onReleased: function(v) { var s = ed.withSlots(ed.slots); s.alpha = Math.round(v); ed.committed(s) }
    }
    Text {
      Layout.preferredWidth: Style.space(40)
      horizontalAlignment: Text.AlignRight
      text: Math.round(ed.alpha / 2.55) + "%"
      color: ed.fg
      font.family: ed.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }

  RowLayout {
    visible: ed.spec !== null && ed.gradient && ed.slots.length > 1
    Layout.fillWidth: true
    spacing: Style.spacing.lg
    Text {
      Layout.preferredWidth: Style.space(52)
      text: "Angle"
      color: Util.alpha(ed.fg, 0.7)
      font.family: ed.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
    Slider {
      Layout.fillWidth: true
      minimum: 0; maximum: 360; integer: true; step: 15
      value: ed.angle
      trackColor: Util.alpha(ed.fg, 0.14)
      fillColor: ed.accent
      knobColor: ed.fg
      onMoved: function(v) { var s = ed.withSlots(ed.slots); s.angle = Math.round(v); ed.edited(s) }
      onReleased: function(v) { var s = ed.withSlots(ed.slots); s.angle = Math.round(v); ed.committed(s) }
    }
    Text {
      Layout.preferredWidth: Style.space(40)
      horizontalAlignment: Text.AlignRight
      text: ed.angle + "°"
      color: ed.fg
      font.family: ed.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }
}
