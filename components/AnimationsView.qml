import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "../Engine.js" as Engine
import "../Schema.js" as Schema

Flickable {
  id: view
  property var panel: null
  property var section: null
  property string selectedCurve: "easeOutQuint"
  property string renameText: ""

  readonly property color fg: panel.fg
  readonly property color accent: panel.accent
  readonly property string fontFamily: panel.font
  readonly property real mul: {
    var m = Number(panel.valueForKey("hf:anim_speed"))
    return isFinite(m) && m > 0 ? m : 1
  }
  readonly property var curveNames: Engine.curveNames(panel.cfg, panel.animBaseline)
  readonly property var curveOptions: curveNames.map(function(n) { return { value: n, label: n } })
  readonly property bool selectedCustom: panel.cfg.curves[selectedCurve] !== undefined

  contentWidth: width
  contentHeight: col.implicitHeight + Style.spacing.huge
  clip: true
  boundsBehavior: Flickable.StopAtBounds

  function usedBy(name) {
    var out = []
    for (var i = 0; i < Engine.ANIM_LEAVES.length; i++) {
      var e = Engine.effectiveAnim(Engine.ANIM_LEAVES[i].leaf, panel.animBaseline, panel.cfg.anims)
      if (e && e.curve === name) out.push(Engine.ANIM_LEAVES[i].label)
    }
    return out
  }

  function uniqueName(base) {
    var n = base, i = 2
    while (curveNames.indexOf(n) !== -1) n = base + i++
    return n
  }

  function styleBase(style) { return String(style || "").split(" ")[0] }
  function stylePercent(style) {
    var m = String(style || "").match(/(\d+)%/)
    return m ? Number(m[1]) : -1
  }

  ColumnLayout {
    id: col
    width: view.width - Style.spacing.lg
    spacing: Style.spacing.xs

    Repeater {
      model: view.section ? view.section.items : []
      BoundRow {
        required property var modelData
        Layout.fillWidth: true
        panel: view.panel
        item: modelData
      }
    }

    // ------------------------------------------------------------ presets
    SectionCard {
      panel: view.panel
      title: "Motion presets"
      subtitle: "Replaces the per-animation overrides below. Undo with Ctrl+Z."
      Flow {
        Layout.fillWidth: true
        spacing: Style.spacing.md
        Repeater {
          model: Engine.MOTIONS
          Button {
            required property var modelData
            text: modelData.name
            tooltipText: modelData.desc
            selected: panel.activeMotion === modelData.id
            bordered: true
            foreground: view.fg
            accent: view.accent
            fontFamily: view.fontFamily
            onClicked: panel.applyMotion(modelData.id)
          }
        }
      }
    }

    // ---------------------------------------------------------- per leaf
    SectionCard {
      panel: view.panel
      title: "Each animation"
      subtitle: "Duration is shown after the global speed. Unset rows inherit from their parent."

      Repeater {
        model: Engine.ANIM_LEAVES
        Rectangle {
          id: leafRow
          required property var modelData
          readonly property var eff: Engine.effectiveAnim(modelData.leaf, panel.animBaseline, panel.cfg.anims)
          readonly property bool over: panel.cfg.anims[modelData.leaf] !== undefined
          Layout.fillWidth: true
          implicitHeight: leafCol.implicitHeight + Style.spacing.lg * 2
          radius: panel.radius
          color: leafHover.hovered ? Util.alpha(view.fg, 0.035) : "transparent"
          HoverHandler { id: leafHover }

          ColumnLayout {
            id: leafCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.spacing.rowPaddingX
            anchors.rightMargin: Style.spacing.rowPaddingX
            spacing: Style.spacing.sm

            RowLayout {
              Layout.fillWidth: true
              spacing: Style.spacing.lg

              Rectangle {
                implicitWidth: Style.space(6); implicitHeight: implicitWidth; radius: implicitWidth / 2
                color: leafRow.over ? view.accent : "transparent"
                border.width: leafRow.over ? 0 : 1
                border.color: Util.alpha(view.fg, 0.18)
              }
              ColumnLayout {
                spacing: 0
                Text {
                  text: leafRow.modelData.label
                  color: view.fg
                  font.family: view.fontFamily
                  font.pixelSize: Style.font.subtitle
                  font.bold: leafRow.over
                }
                Text {
                  text: leafRow.modelData.leaf + (leafRow.eff ? (leafRow.eff.enabled
                        ? "  ·  " + Math.round(leafRow.eff.speed * 100 / view.mul) + " ms  ·  " + leafRow.eff.curve + (leafRow.eff.style ? "  ·  " + leafRow.eff.style : "")
                        : "  ·  off") : "  ·  inherits")
                  color: Util.alpha(view.fg, 0.5)
                  font.family: view.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }
              Item { Layout.fillWidth: true }
              Button {
                visible: !leafRow.eff
                text: "Customize"
                bordered: true
                foreground: view.fg
                accent: view.accent
                fontFamily: view.fontFamily
                fontSize: Style.font.caption
                onClicked: panel.setAnim(leafRow.modelData.leaf, { enabled: true, speed: 4, curve: "easeOutQuint", style: "" }, true)
              }
              ToggleSwitch {
                visible: !!leafRow.eff
                checked: leafRow.eff ? leafRow.eff.enabled : false
                foreground: view.fg
                accent: view.accent
                cursorRing: false
                onToggled: panel.setAnim(leafRow.modelData.leaf, { enabled: !leafRow.eff.enabled }, true)
              }
              PanelActionButton {
                iconText: Schema.I.reset
                tooltipText: "Back to Omarchy"
                foreground: view.fg
                opacity: leafRow.over ? 1 : 0
                enabled: leafRow.over
                onClicked: panel.resetAnim(leafRow.modelData.leaf)
              }
            }

            RowLayout {
              visible: !!leafRow.eff && leafRow.eff.enabled
              Layout.fillWidth: true
              Layout.leftMargin: Style.space(6) + Style.spacing.lg
              spacing: Style.spacing.lg

              Slider {
                Layout.fillWidth: true
                Layout.minimumWidth: Style.space(90)
                minimum: 0.5; maximum: Math.max(15, leafRow.eff ? leafRow.eff.speed : 0); step: 0.1
                value: leafRow.eff ? leafRow.eff.speed : 1
                trackColor: Util.alpha(view.fg, 0.14)
                fillColor: view.accent
                knobColor: view.fg
                onMoved: function(v) { panel.setAnim(leafRow.modelData.leaf, { speed: Math.round(v * 10) / 10 }, false) }
                onReleased: function(v) { panel.setAnim(leafRow.modelData.leaf, { speed: Math.round(v * 10) / 10 }, true) }
              }
              Choice {
                implicitWidth: Style.space(130)
                showLabel: false
                value: leafRow.eff ? leafRow.eff.curve : "default"
                options: view.curveOptions
                foreground: view.fg
                accent: view.accent
                fontFamily: view.fontFamily
                onChanged: function(v) { panel.setAnim(leafRow.modelData.leaf, { curve: v }, true); view.selectedCurve = v }
              }
              Choice {
                visible: leafRow.modelData.styles.length > 0
                implicitWidth: Style.space(120)
                showLabel: false
                value: view.styleBase(leafRow.eff ? leafRow.eff.style : "")
                options: [{ value: "", label: "default" }].concat(leafRow.modelData.styles.map(function(s) { return { value: s, label: s } }))
                foreground: view.fg
                accent: view.accent
                fontFamily: view.fontFamily
                onChanged: function(v) {
                  var pct = view.stylePercent(leafRow.eff ? leafRow.eff.style : "")
                  var ws = leafRow.modelData.leaf.toLowerCase().indexOf("workspace") >= 0
                  var withPct = (v === "popin" || (ws && v.indexOf("slide") === 0)) && pct > 0
                  panel.setAnim(leafRow.modelData.leaf, { style: v + (withPct ? " " + pct + "%" : "") }, true)
                }
              }
            }

            RowLayout {
              readonly property string base: view.styleBase(leafRow.eff ? leafRow.eff.style : "")
              readonly property bool isWorkspace: leafRow.modelData.leaf.toLowerCase().indexOf("workspace") >= 0
              readonly property int fallback: base === "popin" ? 80 : 100
              visible: !!leafRow.eff && leafRow.eff.enabled && (base === "popin" || (isWorkspace && base.indexOf("slide") === 0))
              Layout.fillWidth: true
              Layout.leftMargin: Style.space(6) + Style.spacing.lg
              spacing: Style.spacing.lg
              Text {
                text: parent.base === "popin" ? "Start size" : "Travel"
                color: Util.alpha(view.fg, 0.6)
                font.family: view.fontFamily
                font.pixelSize: Style.font.caption
              }
              Slider {
                Layout.fillWidth: true
                minimum: 10; maximum: 100; integer: true; step: 5
                value: { var p = view.stylePercent(leafRow.eff ? leafRow.eff.style : ""); return p > 0 ? p : parent.fallback }
                trackColor: Util.alpha(view.fg, 0.14)
                fillColor: view.accent
                knobColor: view.fg
                onMoved: function(v) { panel.setAnim(leafRow.modelData.leaf, { style: parent.base + " " + Math.round(v) + "%" }, false) }
                onReleased: function(v) { panel.setAnim(leafRow.modelData.leaf, { style: parent.base + " " + Math.round(v) + "%" }, true) }
              }
              Text {
                text: { var p = view.stylePercent(leafRow.eff ? leafRow.eff.style : ""); return (p > 0 ? p : parent.fallback) + "%" }
                color: view.fg
                font.family: view.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }
        }
      }
    }

    // ------------------------------------------------------------ curves
    SectionCard {
      panel: view.panel
      title: "Curve studio"
      subtitle: "Drag the handles, or build a physical spring. Custom curves are saved with your config."

      Flow {
        Layout.fillWidth: true
        spacing: Style.spacing.xs
        Repeater {
          model: view.curveNames
          Button {
            required property var modelData
            text: modelData
            selected: view.selectedCurve === modelData
            bordered: true
            foreground: view.fg
            accent: view.accent
            fontFamily: view.fontFamily
            fontSize: Style.font.caption
            onClicked: view.selectedCurve = modelData
          }
        }
      }

      RowLayout {
        spacing: Style.spacing.md
        Button {
          text: "New bezier"; iconText: Schema.I.plus; bordered: true
          foreground: view.fg; accent: view.accent; fontFamily: view.fontFamily; fontSize: Style.font.caption
          onClicked: { var n = view.uniqueName("hf_curve"); panel.setCurve(n, { type: "bezier", points: [0.3, 1.2, 0.5, 1] }, true); view.selectedCurve = n }
        }
        Button {
          text: "New spring"; iconText: Schema.I.plus; bordered: true
          foreground: view.fg; accent: view.accent; fontFamily: view.fontFamily; fontSize: Style.font.caption
          onClicked: { var n = view.uniqueName("hf_spring"); panel.setCurve(n, { type: "spring", mass: 1, stiffness: 120, dampening: 12 }, true); view.selectedCurve = n }
        }
        Button {
          text: "Duplicate"; iconText: Schema.I.copy; bordered: true
          foreground: view.fg; accent: view.accent; fontFamily: view.fontFamily; fontSize: Style.font.caption
          onClicked: {
            var c = Engine.curveByName(view.selectedCurve, panel.cfg, panel.animBaseline)
            if (!c) return
            var copy = c.type === "spring" ? { type: "spring", mass: c.mass, stiffness: c.stiffness, dampening: c.dampening } : { type: "bezier", points: c.points.slice() }
            var n = view.uniqueName("hf_" + view.selectedCurve.replace(/^hf_/, ""))
            panel.setCurve(n, copy, true); view.selectedCurve = n
          }
        }
        Button {
          visible: view.selectedCustom
          text: "Delete"; iconText: Schema.I.trash; bordered: true
          foreground: view.fg; accent: view.accent; fontFamily: view.fontFamily; fontSize: Style.font.caption
          onClicked: { panel.deleteCurve(view.selectedCurve); view.selectedCurve = "easeOutQuint" }
        }
      }

      RowLayout {
        visible: view.selectedCustom
        spacing: Style.spacing.md
        Text {
          text: "Rename"
          color: Util.alpha(view.fg, 0.6)
          font.family: view.fontFamily
          font.pixelSize: Style.font.caption
        }
        TextField {
          implicitWidth: Style.space(160)
          text: view.selectedCurve
          foreground: view.fg
          accent: view.accent
          font.family: view.fontFamily
          font.pixelSize: Style.font.bodySmall
          onAccepted: {
            var n = String(text).trim().replace(/[^A-Za-z0-9_]/g, "_")
            if (n && n !== view.selectedCurve && view.curveNames.indexOf(n) === -1) {
              panel.renameCurve(view.selectedCurve, n); view.selectedCurve = n
            }
            panel.refocus()
          }
        }
      }

      CurveEditor {
        Layout.fillWidth: true
        panel: view.panel
        name: view.selectedCurve
        source: Engine.curveByName(view.selectedCurve, panel.cfg, panel.animBaseline)
        editable: view.selectedCustom
        durationMs: {
          var e = Engine.effectiveAnim("windows", panel.animBaseline, panel.cfg.anims)
          return (e ? e.speed : 4) * 100 / view.mul
        }
        onEdited: function(c) { panel.setCurve(view.selectedCurve, c, false) }
        onCommitted: function(c) { panel.setCurve(view.selectedCurve, c, true) }
      }

      Text {
        Layout.fillWidth: true
        text: { var u = view.usedBy(view.selectedCurve); return u.length ? "Used by: " + u.join(", ") : "Not used yet. Pick it in a row above." }
        color: Util.alpha(view.fg, 0.5)
        font.family: view.fontFamily
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }
    }
  }
}
