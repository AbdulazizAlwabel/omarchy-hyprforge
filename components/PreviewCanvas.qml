import QtQuick
import QtQuick.Effects
import qs.Commons
import "../Engine.js" as Engine

// A scale model of your desktop drawn from the values being edited: your real
// wallpaper, the bar, the active layout, gaps, borders (palette gradient and
// angle, rotating if enabled), rounding, shadow, glow, blur, opacity and dim.
// Click a window to move focus.
Item {
  id: pv

  property var panel: null
  property int focusedIndex: 0
  property bool showLabels: false

  readonly property real monW: panel && panel.monitorWidth > 0 ? panel.monitorWidth : 1920
  readonly property real monH: panel && panel.monitorHeight > 0 ? panel.monitorHeight : 1080
  readonly property real s: width / monW
  implicitHeight: width * monH / monW

  function v(key, fallback) {
    if (!panel) return fallback
    var x = panel.valueForKey(key)
    return x === undefined || x === null ? fallback : x
  }
  function px(n) { var p = Number(n) * s; return n > 0 ? Math.max(1, p) : 0 }

  readonly property var gOut: Engine.gapsFrom(v("general:gaps_out", 10))
  readonly property real gIn: Engine.gapsFrom(v("general:gaps_in", 5)).top
  readonly property real borderW: Number(v("general:border_size", 2))
  readonly property bool borderInside: v("decoration:border_part_of_window", true) === true
  readonly property real rounding: Number(v("decoration:rounding", 0))
  readonly property string layoutName: String(v("general:layout", "dwindle"))
  readonly property real barH: 26

  readonly property bool shadowOn: v("decoration:shadow:enabled", false) === true
  readonly property bool glowOn: v("decoration:glow:enabled", false) === true
  readonly property bool blurOn: v("decoration:blur:enabled", false) === true
  readonly property bool dimOn: v("decoration:dim_inactive", false) === true
  readonly property real dimStrength: Number(v("decoration:dim_strength", 0.5))

  readonly property real opActive: Number(v("hf:base_active", 0.985)) * Number(v("decoration:active_opacity", 1))
  readonly property real opInactive: Number(v("hf:base_inactive", 0.96)) * Number(v("decoration:inactive_opacity", 1))

  readonly property var activeBorder: panel ? panel.resolvedColor("general:col.active_border") : ({ stops: [], angle: 0 })
  readonly property var inactiveBorder: panel ? panel.resolvedColor("general:col.inactive_border") : ({ stops: [], angle: 0 })
  readonly property var shadowColor: panel ? panel.resolvedColor("decoration:shadow:color") : ({ stops: [], angle: 0 })
  readonly property var shadowInactive: panel ? panel.resolvedColor("decoration:shadow:color_inactive") : ({ stops: [], angle: 0 })
  readonly property var glowColor: panel ? panel.resolvedColor("decoration:glow:color") : ({ stops: [], angle: 0 })
  readonly property var glowInactive: panel ? panel.resolvedColor("decoration:glow:color_inactive") : ({ stops: [], angle: 0 })

  property real spin: 0
  NumberAnimation on spin {
    running: pv.visible && pv.v("hf:border_rotate", false) === true
    from: 0; to: 360
    loops: Animation.Infinite
    duration: Math.max(500, Number(pv.v("hf:border_rotate_speed", 6)) * 1000)
  }

  // Work area in monitor pixels.
  readonly property var area: ({
    x: gOut.left, y: barH + gOut.top,
    w: monW - gOut.left - gOut.right, h: monH - barH - gOut.top - gOut.bottom
  })

  readonly property var tiles: {
    var a = area, g = gIn * 2, out = []
    if (layoutName === "master") {
      var mf = Number(v("master:mfact", 0.55))
      var mw = (a.w - g) * mf
      out.push({ x: a.x, y: a.y, w: mw, h: a.h })
      var sh = (a.h - g) / 2
      out.push({ x: a.x + mw + g, y: a.y, w: a.w - mw - g, h: sh })
      out.push({ x: a.x + mw + g, y: a.y + sh + g, w: a.w - mw - g, h: sh })
    } else if (layoutName === "scrolling") {
      var cw = a.w * Number(v("scrolling:column_width", 0.5))
      out.push({ x: a.x, y: a.y, w: cw - gIn, h: a.h })
      var h2 = (a.h - g) / 2
      out.push({ x: a.x + cw + gIn, y: a.y, w: cw - gIn, h: h2 })
      out.push({ x: a.x + cw + gIn, y: a.y + h2 + g, w: cw - gIn, h: h2 })
    } else if (layoutName === "monocle") {
      out.push({ x: a.x, y: a.y, w: a.w, h: a.h })
    } else {
      var half = (a.w - g) / 2
      out.push({ x: a.x, y: a.y, w: half, h: a.h })
      var hh = (a.h - g) / 2
      out.push({ x: a.x + half + g, y: a.y, w: half, h: hh })
      out.push({ x: a.x + half + g, y: a.y + hh + g, w: half, h: hh })
    }
    out.push({ x: monW * 0.36, y: monH * 0.42, w: monW * 0.3, h: monH * 0.36, floating: true })
    return out
  }

  // ---------------------------------------------------------- wallpaper

  Item {
    id: wall
    anchors.fill: parent
    layer.enabled: true

    Rectangle {
      anchors.fill: parent
      gradient: Gradient {
        GradientStop { position: 0; color: panel ? panel.paletteMap.lighter_background || panel.paletteMap.background : "#222" }
        GradientStop { position: 1; color: panel ? panel.paletteMap.background : "#111" }
      }
    }
    Image {
      anchors.fill: parent
      source: panel ? panel.wallpaperUrl : ""
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      cache: false
      sourceSize.width: 960
    }
  }

  // clip everything to a rounded "screen"
  layer.enabled: true
  layer.effect: MultiEffect {
    maskEnabled: true
    maskSource: screenMask
    maskThresholdMin: 0.5
    maskSpreadAtMin: 1
  }
  Item {
    id: screenMask
    anchors.fill: parent
    visible: false
    layer.enabled: true
    Rectangle { anchors.fill: parent; radius: Style.space(10); color: "black" }
  }

  // bar
  Rectangle {
    x: 0; y: 0; width: parent.width; height: Math.max(3, pv.barH * pv.s)
    color: Color.bar.background
    Row {
      anchors.verticalCenter: parent.verticalCenter
      x: parent.height * 0.6
      spacing: parent.height * 0.35
      Repeater {
        model: 5
        Rectangle {
          required property int index
          width: parent.parent.height * 0.32; height: width; radius: width / 2
          color: index === 0 ? Color.accent : Util.alpha(Color.bar.text, 0.4)
        }
      }
    }
    Rectangle {
      anchors.centerIn: parent
      width: parent.height * 2.2; height: parent.height * 0.3; radius: height / 2
      color: Util.alpha(Color.bar.text, 0.55)
    }
  }

  // ------------------------------------------------------------ windows

  Repeater {
    model: pv.tiles
    delegate: Item {
      id: win
      required property var modelData
      required property int index
      readonly property bool focused: pv.focusedIndex === index
      readonly property real bw: pv.borderW > 0 ? Math.max(1, pv.borderW * pv.s) : 0
      readonly property real outset: pv.borderInside ? 0 : bw
      readonly property real r: Math.max(0, pv.rounding * pv.s)
      readonly property var border: focused ? pv.activeBorder : pv.inactiveBorder

      x: modelData.x * pv.s - outset
      y: modelData.y * pv.s - outset
      width: modelData.w * pv.s + outset * 2
      height: modelData.h * pv.s + outset * 2
      z: modelData.floating ? 10 : (focused ? 5 : 1)

      Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
      Behavior on y { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
      Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
      Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

      // shadow
      Rectangle {
        id: caster
        visible: false
        width: win.width; height: win.height
        radius: win.r + win.outset
        color: pv.panel ? pv.panel.stopsColor(win.focused ? pv.shadowColor : (pv.shadowInactive.stops.length ? pv.shadowInactive : pv.shadowColor), 0) : "black"
        layer.enabled: true
      }
      MultiEffect {
        visible: pv.shadowOn
        source: caster
        x: Number(pv.v("decoration:shadow:offset", [0, 0])[0]) * pv.s
        y: Number(pv.v("decoration:shadow:offset", [0, 0])[1]) * pv.s
        width: win.width; height: win.height
        scale: Number(pv.v("decoration:shadow:scale", 1))
        autoPaddingEnabled: true
        blurEnabled: pv.v("decoration:shadow:sharp", false) !== true
        blurMax: Math.max(1, Math.round(Number(pv.v("decoration:shadow:range", 4)) * pv.s * 2))
        blur: 1.0
      }

      // blur of what's behind (wallpaper only in the model)
      ShaderEffectSource {
        id: behind
        visible: false
        sourceItem: wall
        sourceRect: Qt.rect(win.x, win.y, win.width, win.height)
        live: true
      }
      Item {
        id: bodyMask
        visible: false
        anchors.fill: parent
        layer.enabled: true
        Rectangle { anchors.fill: parent; radius: win.r + win.outset; color: "black" }
      }
      MultiEffect {
        visible: pv.blurOn
        anchors.fill: parent
        source: behind
        autoPaddingEnabled: false
        blurEnabled: true
        blurMax: Math.max(4, Number(pv.v("decoration:blur:size", 8)) * Number(pv.v("decoration:blur:passes", 1)) * pv.s * 3)
        blur: 1.0
        saturation: Number(pv.v("decoration:blur:vibrancy", 0.17)) * 0.8
        brightness: Number(pv.v("decoration:blur:brightness", 1)) - 1
        contrast: Number(pv.v("decoration:blur:contrast", 0.9)) - 1
        maskEnabled: true
        maskSource: bodyMask
      }

      // body
      Rectangle {
        id: body
        anchors.fill: parent
        anchors.margins: win.outset
        radius: win.r
        readonly property real op: win.focused ? pv.opActive : pv.opInactive
        color: Util.alpha(pv.panel ? pv.panel.paletteMap.background : "#101315", pv.blurOn ? op * 0.82 : op)

        Column {
          x: parent.width * 0.08
          y: parent.height * 0.12
          spacing: Math.max(2, parent.height * 0.06)
          Repeater {
            model: win.modelData.floating ? 3 : 4 + (win.index % 2)
            Rectangle {
              required property int index
              width: body.width * (0.35 + ((index * 37 + win.index * 13) % 40) / 100)
              height: Math.max(2, body.height * 0.035)
              radius: height / 2
              color: index === 0
                ? (pv.panel ? pv.panel.accent : Color.accent)
                : Util.alpha(pv.panel ? pv.panel.fg : Color.foreground, 0.28 - index * 0.03)
            }
          }
        }
      }

      // border + glow
      Canvas {
        id: frame
        anchors.fill: parent
        readonly property var stops: win.border.stops
        readonly property real angle: (win.border.angle || 0) + (win.focused ? pv.spin : 0)
        readonly property var glow: pv.glowOn ? (win.focused ? pv.glowColor : (pv.glowInactive.stops.length ? pv.glowInactive : pv.glowColor)) : null
        onStopsChanged: requestPaint()
        onAngleChanged: requestPaint()
        onGlowChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Connections {
          target: pv
          function onBorderWChanged() { frame.requestPaint() }
          function onRoundingChanged() { frame.requestPaint() }
        }

        function roundRect(ctx, x, y, w, h, r) {
          r = Math.max(0, Math.min(r, w / 2, h / 2))
          ctx.beginPath()
          ctx.moveTo(x + r, y)
          ctx.arcTo(x + w, y, x + w, y + h, r)
          ctx.arcTo(x + w, y + h, x, y + h, r)
          ctx.arcTo(x, y + h, x, y, r)
          ctx.arcTo(x, y, x + w, y, r)
          ctx.closePath()
        }

        onPaint: {
          var ctx = getContext("2d")
          ctx.reset()
          var w = width, h = height
          if (glow && glow.stops.length) {
            ctx.save()
            roundRect(ctx, 0, 0, w, h, win.r + win.outset)
            ctx.clip()
            var gr = Math.max(1, Number(pv.v("decoration:glow:range", 10)) * pv.s * 1.6)
            ctx.shadowColor = pv.panel.stopsColor(glow, 0)
            ctx.shadowBlur = gr
            ctx.lineWidth = gr
            ctx.strokeStyle = pv.panel.stopsColor(glow, 0)
            roundRect(ctx, -gr / 2, -gr / 2, w + gr, h + gr, win.r + win.outset + gr / 2)
            ctx.stroke()
            ctx.restore()
          }
          if (win.bw <= 0 || stops.length === 0) return
          var rad = angle * Math.PI / 180
          var cx = w / 2, cy = h / 2
          var dx = Math.cos(rad) * w / 2, dy = Math.sin(rad) * h / 2
          var grad = ctx.createLinearGradient(cx - dx, cy + dy, cx + dx, cy - dy)
          for (var i = 0; i < stops.length; i++) {
            var pos = stops.length === 1 ? 0 : i / (stops.length - 1)
            grad.addColorStop(pos, pv.panel.stopsColor({ stops: stops }, i))
            if (stops.length === 1) grad.addColorStop(1, pv.panel.stopsColor({ stops: stops }, i))
          }
          ctx.lineWidth = win.bw
          ctx.strokeStyle = grad
          roundRect(ctx, win.bw / 2, win.bw / 2, w - win.bw, h - win.bw, Math.max(0, win.r + win.outset - win.bw / 2))
          ctx.stroke()
        }
      }

      // dim
      Rectangle {
        anchors.fill: parent
        radius: win.r + win.outset
        color: "black"
        opacity: pv.dimOn && !win.focused ? pv.dimStrength : 0
        Behavior on opacity { NumberAnimation { duration: 180 } }
      }

      TapHandler { onTapped: pv.focusedIndex = win.index }
      HoverHandler { cursorShape: Qt.PointingHandCursor }
    }
  }
}
