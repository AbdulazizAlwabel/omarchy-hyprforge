import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "../Engine.js" as Engine
import "../Schema.js" as Schema

// Edits one curve. Bezier: drag the two handles. Spring: mass, stiffness and
// dampening sliders. "Play" runs a demo using the real sampled curve for the
// given duration, next to a linear reference.
ColumnLayout {
  id: ce

  property var panel: null
  property var source: null          // { type, points } | { type, mass, stiffness, dampening }
  property var curve: null           // working copy while dragging
  onSourceChanged: curve = source ? JSON.parse(JSON.stringify(source)) : null
  Component.onCompleted: curve = source ? JSON.parse(JSON.stringify(source)) : null
  property string name: ""
  property bool editable: true
  property real durationMs: 500

  signal edited(var curve)
  signal committed(var curve)

  readonly property color fg: panel ? panel.fg : Color.foreground
  readonly property color accent: panel ? panel.accent : Color.accent
  readonly property string fontFamily: panel ? panel.font : Style.font.family
  readonly property bool isSpring: curve && curve.type === "spring"
  readonly property var samples: Engine.curveSamples(curve, 90)

  spacing: Style.spacing.lg

  onSamplesChanged: plot.requestPaint()

  RowLayout {
    Layout.fillWidth: true
    spacing: Style.spacing.xl

    // ------------------------------------------------------------ plot
    Item {
      id: plotBox
      Layout.preferredWidth: Style.space(210)
      Layout.preferredHeight: Style.space(210)

      readonly property real pad: Style.space(8)
      readonly property real yMin: -0.5
      readonly property real yMax: 1.5
      function toX(x) { return pad + x * (width - pad * 2) }
      function toY(y) { return pad + (1 - (y - yMin) / (yMax - yMin)) * (height - pad * 2) }
      function fromX(px) { return Math.max(0, Math.min(1, (px - pad) / (width - pad * 2))) }
      function fromY(py) { return Math.max(yMin, Math.min(yMax, yMin + (1 - (py - pad) / (height - pad * 2)) * (yMax - yMin))) }

      Rectangle {
        anchors.fill: parent
        radius: panel ? panel.radius : 6
        color: Util.alpha(ce.fg, 0.035)
        border.width: 1
        border.color: Util.alpha(ce.fg, 0.08)
      }

      Canvas {
        id: plot
        anchors.fill: parent
        onPaint: {
          var ctx = getContext("2d")
          ctx.reset()
          var b = plotBox
          // guides at 0 and 1
          ctx.strokeStyle = Util.alpha(ce.fg, 0.12)
          ctx.lineWidth = 1
          ctx.setLineDash([3, 3])
          ctx.beginPath()
          ctx.moveTo(b.toX(0), b.toY(0)); ctx.lineTo(b.toX(1), b.toY(0))
          ctx.moveTo(b.toX(0), b.toY(1)); ctx.lineTo(b.toX(1), b.toY(1))
          ctx.stroke()
          ctx.setLineDash([])
          // linear reference
          ctx.strokeStyle = Util.alpha(ce.fg, 0.15)
          ctx.beginPath(); ctx.moveTo(b.toX(0), b.toY(0)); ctx.lineTo(b.toX(1), b.toY(1)); ctx.stroke()
          if (!ce.curve) return
          // bezier handles
          if (!ce.isSpring) {
            var p = ce.curve.points
            ctx.strokeStyle = Util.alpha(ce.accent, 0.5)
            ctx.beginPath()
            ctx.moveTo(b.toX(0), b.toY(0)); ctx.lineTo(b.toX(p[0]), b.toY(p[1]))
            ctx.moveTo(b.toX(1), b.toY(1)); ctx.lineTo(b.toX(p[2]), b.toY(p[3]))
            ctx.stroke()
          }
          // curve
          var s = ce.samples
          ctx.strokeStyle = ce.accent
          ctx.lineWidth = 2.5
          ctx.beginPath()
          for (var i = 0; i < s.length; i++) {
            var x = b.toX(i / (s.length - 1)), y = b.toY(s[i])
            if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
          }
          ctx.stroke()
        }
      }

      Repeater {
        model: ce.isSpring || !ce.curve ? 0 : 2
        Rectangle {
          id: handle
          required property int index
          readonly property real hx: ce.curve.points[index * 2]
          readonly property real hy: ce.curve.points[index * 2 + 1]
          width: Style.space(14); height: width; radius: width / 2
          x: plotBox.toX(hx) - width / 2
          y: plotBox.toY(hy) - height / 2
          color: drag.active || hh.hovered ? ce.accent : ce.fg
          border.width: 2
          border.color: panel ? panel.bg : Color.background
          visible: ce.editable
          HoverHandler { id: hh; cursorShape: Qt.SizeAllCursor }
          DragHandler {
            id: drag
            target: null
            onActiveChanged: if (!active) ce.committed(ce.curve)
            onCentroidChanged: {
              if (!active) return
              var pt = handle.mapToItem(plotBox, centroid.position.x, centroid.position.y)
              var p = ce.curve.points.slice()
              p[handle.index * 2] = Math.round(plotBox.fromX(pt.x) * 100) / 100
              p[handle.index * 2 + 1] = Math.round(plotBox.fromY(pt.y) * 100) / 100
              ce.curve = { type: "bezier", points: p }
              ce.edited(ce.curve)
            }
          }
        }
      }
    }

    // ------------------------------------------------------------ demo
    ColumnLayout {
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignTop
      spacing: Style.spacing.lg

      Text {
        text: ce.name === "" ? "" : ce.name + (ce.isSpring ? "  ·  spring" : "  ·  bezier")
        color: ce.fg
        font.family: ce.fontFamily
        font.pixelSize: Style.font.subtitle
        font.bold: true
      }
      Text {
        visible: !ce.isSpring && ce.curve
        text: ce.curve && !ce.isSpring ? "cubic-bezier(" + ce.curve.points.join(", ") + ")" : ""
        color: Util.alpha(ce.fg, 0.55)
        font.family: ce.fontFamily
        font.pixelSize: Style.font.caption
      }

      Repeater {
        model: [{ label: "curve", useCurve: true }, { label: "linear", useCurve: false }]
        Item {
          required property var modelData
          Layout.fillWidth: true
          Layout.preferredHeight: Style.space(26)
          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width; height: 2
            color: Util.alpha(ce.fg, 0.1)
          }
          Rectangle {
            width: Style.space(22); height: width; radius: Style.space(6)
            anchors.verticalCenter: parent.verticalCenter
            color: modelData.useCurve ? ce.accent : Util.alpha(ce.fg, 0.3)
            x: (parent.width - width) * (modelData.useCurve ? ce.sampleAt(demo.t) : demo.t)
          }
        }
      }

      Item {
        id: demo
        property real t: 0
        NumberAnimation on t {
          id: player
          running: false
          from: 0; to: 1
          duration: Math.max(80, ce.durationMs)
        }
      }

      RowLayout {
        spacing: Style.spacing.md
        Button {
          text: "Play"
          iconText: Schema.I.play
          bordered: true
          foreground: ce.fg
          accent: ce.accent
          fontFamily: ce.fontFamily
          fontSize: Style.font.bodySmall
          onClicked: { player.stop(); demo.t = 0; player.start() }
        }
        Text {
          text: Math.round(ce.durationMs) + " ms"
          color: Util.alpha(ce.fg, 0.55)
          font.family: ce.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      Text {
        Layout.fillWidth: true
        visible: !ce.editable
        text: "Built-in curve. Duplicate it to edit."
        color: Util.alpha(ce.fg, 0.5)
        font.family: ce.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }
    }
  }

  // spring parameters
  Repeater {
    model: ce.isSpring ? [
      { key: "mass", label: "Mass", min: 0.1, max: 5, step: 0.1 },
      { key: "stiffness", label: "Stiffness", min: 10, max: 400, step: 5 },
      { key: "dampening", label: "Dampening", min: 1, max: 60, step: 0.5 }
    ] : []
    RowLayout {
      required property var modelData
      Layout.fillWidth: true
      spacing: Style.spacing.lg
      Text {
        Layout.preferredWidth: Style.space(72)
        text: modelData.label
        color: Util.alpha(ce.fg, 0.7)
        font.family: ce.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
      Slider {
        Layout.fillWidth: true
        enabled: ce.editable
        minimum: modelData.min; maximum: modelData.max; step: modelData.step
        value: Number(ce.curve[modelData.key])
        trackColor: Util.alpha(ce.fg, 0.14)
        fillColor: ce.accent
        knobColor: ce.fg
        onMoved: function(v) { ce.curve = ce.withParam(modelData.key, v, modelData.step); ce.edited(ce.curve) }
        onReleased: function(v) { ce.curve = ce.withParam(modelData.key, v, modelData.step); ce.committed(ce.curve) }
      }
      Text {
        Layout.preferredWidth: Style.space(40)
        horizontalAlignment: Text.AlignRight
        text: Engine.formatNumber(ce.curve[modelData.key])
        color: ce.fg
        font.family: ce.fontFamily
        font.pixelSize: Style.font.bodySmall
      }
    }
  }

  function withParam(key, v, step) {
    var c = JSON.parse(JSON.stringify(curve))
    c[key] = Math.round(v / step) * step
    c[key] = Math.round(c[key] * 100) / 100
    return c
  }

  function sampleAt(t) {
    var s = samples
    if (!s || s.length === 0) return t
    var f = t * (s.length - 1)
    var i = Math.floor(f)
    if (i >= s.length - 1) return s[s.length - 1]
    return s[i] + (s[i + 1] - s[i]) * (f - i)
  }
}
