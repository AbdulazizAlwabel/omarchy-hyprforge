import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "../Engine.js" as Engine
import "../Schema.js" as Schema

// One option: label and description on the left, its editor on the right (or
// underneath for wide editors). Emits `edited` while dragging (live preview)
// and `committed` when a change should be saved.
Item {
  id: row

  property var panel: null
  property var item: ({})
  property var value
  property var wasValue
  property var liveRaw
  property bool modified: false
  property bool available: true
  property bool hasCursor: false
  property string sectionTag: ""

  signal edited(var v)
  signal committed(var v)
  signal reset()
  signal focusRequested()

  readonly property string type: item && item.type ? item.type : "text"
  readonly property bool wide: type === "gradient" || type === "color" || (type === "gaps" && gapsExpanded) || type === "vec2" || (type === "text" && !!item.wideText)
  readonly property color fg: panel ? panel.fg : Color.foreground
  readonly property color accent: panel ? panel.accent : Color.accent
  readonly property string fontFamily: panel ? panel.font : Style.font.family
  property bool gapsExpanded: type === "gaps" && Engine.isGaps(value) && !Engine.gapsUniform(value)

  implicitHeight: body.implicitHeight + Style.spacing.lg * 2
  opacity: available ? 1 : 0.4

  Behavior on opacity { NumberAnimation { duration: 120 } }

  Rectangle {
    anchors.fill: parent
    radius: panel ? panel.radius : 6
    color: row.hasCursor ? Util.alpha(row.fg, 0.07) : (hover.hovered ? Util.alpha(row.fg, 0.035) : "transparent")
    border.width: row.hasCursor ? 1 : 0
    border.color: Util.alpha(row.accent, 0.55)
    Behavior on color { ColorAnimation { duration: 90 } }
  }

  HoverHandler { id: hover }
  TapHandler { onTapped: row.focusRequested() }

  ColumnLayout {
    id: body
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: Style.spacing.rowPaddingX
    anchors.rightMargin: Style.spacing.rowPaddingX
    spacing: Style.spacing.md

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.spacing.lg

      // modified marker
      Rectangle {
        Layout.alignment: Qt.AlignTop
        Layout.topMargin: Style.space(6)
        implicitWidth: Style.space(6)
        implicitHeight: Style.space(6)
        radius: width / 2
        color: row.modified ? row.accent : "transparent"
        border.width: row.modified ? 0 : 1
        border.color: Util.alpha(row.fg, 0.18)
      }

      ColumnLayout {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        Layout.alignment: Qt.AlignVCenter
        spacing: Style.spacing.xxs

        // Always-present stretcher: a layout can only grow if a child can.
        Item { Layout.fillWidth: true; implicitHeight: 0 }

        RowLayout {
          Layout.fillWidth: true
          Layout.minimumWidth: 0
          spacing: Style.spacing.md
          TextMetrics {
            id: titleMetrics
            text: row.item.label || ""
            font.family: row.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: row.modified
          }
          Text {
            // natural width when there's room, elides only when squeezed
            Layout.preferredWidth: Math.ceil(titleMetrics.advanceWidth) + 2
            Layout.minimumWidth: 0
            elide: Text.ElideRight
            text: row.item.label || ""
            color: row.fg
            font.family: row.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: row.modified
          }
          Text {
            visible: row.sectionTag !== ""
            text: row.sectionTag
            color: Util.alpha(row.fg, 0.45)
            font.family: row.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
        Text {
          Layout.fillWidth: true
          visible: text !== ""
          text: row.item.desc || ""
          color: Util.alpha(row.fg, 0.55)
          font.family: row.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
          maximumLineCount: 3
          elide: Text.ElideRight
        }
        Text {
          visible: row.modified && row.wasValue !== undefined && row.wasValue !== null && !Engine.isColorSpec(row.value)
          Layout.fillWidth: true
          elide: Text.ElideMiddle
          text: "was " + Engine.describe(row.item, row.wasValue) + "  ·  " + (row.item.key || "")
          color: Util.alpha(row.fg, 0.4)
          font.family: row.fontFamily
          font.pixelSize: Style.font.caption
        }
        Text {
          Layout.fillWidth: true
          elide: Text.ElideMiddle
          visible: !row.modified && (row.item.generated === true)
          text: row.item.key || ""
          color: Util.alpha(row.fg, 0.35)
          font.family: row.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      // inline editors
      Loader {
        Layout.alignment: Qt.AlignVCenter
        active: !row.wide
        visible: active
        sourceComponent: {
          if (row.type === "bool") return boolEditor
          if (row.type === "enum") return (row.item.options || []).length <= 4 && row.chipsFit() ? chipsEditor : dropdownEditor
          if (row.type === "int" || row.type === "float") return row.item.freeform ? numberEditor : sliderEditor
          if (row.type === "gaps") return sliderEditor
          return textEditor
        }
      }

      PanelActionButton {
        Layout.alignment: Qt.AlignVCenter
        iconText: Schema.I.reset
        tooltipText: "Reset to Omarchy  ·  Backspace"
        foreground: row.fg
        opacity: row.modified ? 1 : 0
        enabled: row.modified
        onClicked: row.reset()
      }
    }

    // wide editors live under the title
    Loader {
      Layout.fillWidth: true
      Layout.leftMargin: Style.space(6) + Style.spacing.lg
      active: row.wide
      visible: active
      sourceComponent: {
        if (row.type === "gradient" || row.type === "color") return paletteEditor
        if (row.type === "gaps") return gapsEditor
        if (row.type === "vec2") return vecEditor
        return textEditor
      }
    }
  }

  function chipsFit() {
    var total = 0
    var o = item.options || []
    for (var i = 0; i < o.length; i++) total += String(o[i].label).length
    return total <= 26
  }

  function num(v, fallback) {
    var n = Number(v)
    return isFinite(n) ? n : fallback
  }

  function displayNumber(v) {
    var n = num(v, 0)
    var d = item.decimals !== undefined ? item.decimals : (type === "float" ? 2 : 0)
    return n.toFixed(d)
  }

  // ------------------------------------------------------------- editors

  Component {
    id: boolEditor
    ToggleSwitch {
      checked: row.value === true
      foreground: row.fg
      accent: row.accent
      cursorRing: false
      interactive: row.available
      onToggled: { row.focusRequested(); row.committed(!(row.value === true)) }
    }
  }

  Component {
    id: chipsEditor
    Row {
      spacing: Style.spacing.xs
      Repeater {
        model: row.item.options || []
        Button {
          required property var modelData
          text: modelData.label
          selected: String(modelData.value) === String(row.value)
          bordered: true
          foreground: row.fg
          accent: row.accent
          fontFamily: row.fontFamily
          fontSize: Style.font.bodySmall
          horizontalPadding: Style.spacing.lg
          verticalPadding: Style.spacing.xs
          enabled: row.available
          onClicked: { row.focusRequested(); row.committed(modelData.value) }
        }
      }
    }
  }

  Component {
    id: dropdownEditor
    Choice {
      implicitWidth: Style.space(170)
      showLabel: false
      value: String(row.value)
      options: (row.item.options || []).map(function(o) { return { value: String(o.value), label: o.label } })
      foreground: row.fg
      accent: row.accent
      fontFamily: row.fontFamily
      enabled: row.available
      onChanged: function(v) {
        row.focusRequested()
        var opts = row.item.options || []
        for (var i = 0; i < opts.length; i++) if (String(opts[i].value) === v) { row.committed(opts[i].value); return }
        row.committed(v)
      }
    }
  }

  Component {
    id: sliderEditor
    RowLayout {
      spacing: Style.spacing.lg
      readonly property real current: row.type === "gaps" ? Engine.gapsFrom(row.value).top : row.num(row.value, 0)

      PanelActionButton {
        visible: row.type === "gaps"
        iconText: Schema.I.expand
        tooltipText: "Set each side separately"
        foreground: row.fg
        onClicked: row.gapsExpanded = true
      }

      Slider {
        id: slider
        Layout.preferredWidth: Style.space(140)
        minimum: Math.min(row.item.min !== undefined ? row.item.min : 0, parent.current)
        maximum: Math.max(row.item.max !== undefined ? row.item.max : 100, parent.current)
        step: row.item.step !== undefined ? row.item.step : 1
        integer: row.type === "int" || row.type === "gaps"
        value: parent.current
        trackColor: Util.alpha(row.fg, 0.14)
        fillColor: row.accent
        knobColor: row.fg
        tickColor: row.panel ? row.panel.bg : Color.background
        enabled: row.available
        onMoved: function(v) { row.focusRequested(); row.edited(row.snap(v)) }
        onReleased: function(v) { row.committed(row.snap(v)) }
      }

      NumberInput {
        panel: row.panel
        text: row.displayNumber(parent.current) + (row.item.unit || "")
        onSubmitted: function(t) {
          var n = parseFloat(String(t).replace(/[^0-9.+-]/g, ""))
          if (isFinite(n)) row.committed(row.snap(n))
        }
      }
    }
  }

  Component {
    id: numberEditor
    NumberInput {
      panel: row.panel
      wideField: true
      text: row.displayNumber(row.value)
      onSubmitted: function(t) {
        var n = parseFloat(t)
        if (isFinite(n)) row.committed(row.snap(n))
      }
    }
  }

  Component {
    id: textEditor
    TextField {
      implicitWidth: row.wide ? 0 : Style.space(200)
      text: String(row.value === undefined || row.value === null ? "" : row.value)
      placeholderText: "(empty)"
      foreground: row.fg
      accent: row.accent
      font.family: row.fontFamily
      font.pixelSize: Style.font.body
      selectByMouse: true
      enabled: row.available
      onActiveFocusChanged: if (activeFocus) row.focusRequested()
      onAccepted: { row.committed(text); if (row.panel) row.panel.refocus() }
      Keys.onEscapePressed: function(e) { text = String(row.value || ""); if (row.panel) row.panel.refocus(); e.accepted = true }
    }
  }

  Component {
    id: gapsEditor
    ColumnLayout {
      spacing: Style.spacing.sm
      readonly property var g: Engine.gapsFrom(row.value)
      Repeater {
        model: [["top", "Top"], ["right", "Right"], ["bottom", "Bottom"], ["left", "Left"]]
        RowLayout {
          required property var modelData
          Layout.fillWidth: true
          spacing: Style.spacing.lg
          Text {
            Layout.preferredWidth: Style.space(52)
            text: modelData[1]
            color: Util.alpha(row.fg, 0.7)
            font.family: row.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
          Slider {
            Layout.fillWidth: true
            minimum: 0
            maximum: Math.max(row.item.max || 80, g[modelData[0]])
            integer: true
            step: 1
            value: g[modelData[0]]
            trackColor: Util.alpha(row.fg, 0.14)
            fillColor: row.accent
            knobColor: row.fg
            onMoved: function(v) { row.edited(row.withSide(modelData[0], v)) }
            onReleased: function(v) { row.committed(row.withSide(modelData[0], v)) }
          }
          Text {
            Layout.preferredWidth: Style.space(40)
            horizontalAlignment: Text.AlignRight
            text: g[modelData[0]] + "px"
            color: row.fg
            font.family: row.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }
      }
      Button {
        text: "Same on every side"
        bordered: true
        foreground: row.fg
        accent: row.accent
        fontFamily: row.fontFamily
        fontSize: Style.font.caption
        onClicked: { row.gapsExpanded = false; row.committed(g.top) }
      }
    }
  }

  Component {
    id: vecEditor
    ColumnLayout {
      spacing: Style.spacing.sm
      readonly property var v: Array.isArray(row.value) ? row.value : [0, 0]
      Repeater {
        model: 2
        RowLayout {
          required property int index
          Layout.fillWidth: true
          spacing: Style.spacing.lg
          Text {
            Layout.preferredWidth: Style.space(52)
            text: row.item.key === "layout:single_window_aspect_ratio" ? (index === 0 ? "Width" : "Height") : (index === 0 ? "X" : "Y")
            color: Util.alpha(row.fg, 0.7)
            font.family: row.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
          Slider {
            Layout.fillWidth: true
            minimum: Math.min(row.item.min !== undefined ? row.item.min : -50, v[index])
            maximum: Math.max(row.item.max !== undefined ? row.item.max : 50, v[index])
            integer: true
            step: 1
            value: v[index]
            trackColor: Util.alpha(row.fg, 0.14)
            fillColor: row.accent
            knobColor: row.fg
            enabled: row.available
            onMoved: function(x) { var n = v.slice(); n[index] = Math.round(x); row.edited(n) }
            onReleased: function(x) { var n = v.slice(); n[index] = Math.round(x); row.committed(n) }
          }
          Text {
            Layout.preferredWidth: Style.space(40)
            horizontalAlignment: Text.AlignRight
            text: v[index] + (row.item.unit || "")
            color: row.fg
            font.family: row.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }
      }
    }
  }

  Component {
    id: paletteEditor
    PaletteEditor {
      panel: row.panel
      spec: Engine.isColorSpec(row.value) ? row.value : null
      liveValue: row.liveRaw
      gradient: row.type === "gradient"
      enabled: row.available
      onEdited: function(s) { row.focusRequested(); row.edited(s) }
      onCommitted: function(s) { row.focusRequested(); row.committed(s) }
    }
  }

  function snap(v) {
    var n = Number(v)
    if (type === "int" || type === "gaps") return Math.round(n)
    var step = item.step !== undefined ? item.step : 0.01
    return Math.round(n / step) * step
  }

  function withSide(side, v) {
    var g = Engine.gapsFrom(value)
    g[side] = Math.round(v)
    return g
  }
}
