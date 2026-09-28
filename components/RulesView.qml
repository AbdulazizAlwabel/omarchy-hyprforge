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

  readonly property color fg: panel.fg
  readonly property color accent: panel.accent
  readonly property string fontFamily: panel.font

  contentWidth: width
  contentHeight: col.implicitHeight + Style.spacing.huge
  clip: true
  boundsBehavior: Flickable.StopAtBounds

  Component.onCompleted: panel.refreshClients()

  function defaultEffect(info) {
    if (info.type === "bool") return true
    if (info.type === "opacity") return [0.92, 0.85]
    if (info.type === "size") return ["60%", "70%"]
    if (info.type === "color") return { slots: ["accent"], alpha: 255 }
    if (info.type === "enum") return info.options[0]
    if (info.type === "text") return ""
    if (info.type === "float") return 1
    return info.min !== undefined ? Math.round((info.min + info.max) / 3) : 0
  }

  function ruleFor(cls) {
    var m = Engine.classMatch(cls)
    for (var i = 0; i < panel.cfg.rules.length; i++)
      if (panel.cfg.rules[i].match && panel.cfg.rules[i].match["class"] === m) return panel.cfg.rules[i]
    return null
  }

  ColumnLayout {
    id: col
    width: view.width - Style.spacing.lg
    spacing: Style.spacing.md

    SectionCard {
      panel: view.panel
      title: "Open windows"
      subtitle: "Click an app to create a rule for it. Rules apply when you release a control."
      Flow {
        Layout.fillWidth: true
        spacing: Style.spacing.xs
        Repeater {
          model: panel.clients
          Button {
            required property var modelData
            readonly property var existing: view.ruleFor(modelData["class"])
            text: modelData["class"]
            tooltipText: modelData.title
            iconText: existing ? Schema.I.check : Schema.I.plus
            selected: !!existing
            bordered: true
            foreground: view.fg
            accent: view.accent
            fontFamily: view.fontFamily
            fontSize: Style.font.caption
            onClicked: {
              if (existing) return
              panel.addRule({ id: Engine.newId(), enabled: true, name: modelData["class"], match: { "class": Engine.classMatch(modelData["class"]) }, effects: { opacity: [1, 0.9] } })
            }
          }
        }
        PanelActionButton {
          iconText: Schema.I.reset
          tooltipText: "Refresh the list"
          foreground: view.fg
          onClicked: panel.refreshClients()
        }
      }
      Button {
        text: "Empty rule"
        iconText: Schema.I.plus
        bordered: true
        foreground: view.fg
        accent: view.accent
        fontFamily: view.fontFamily
        fontSize: Style.font.bodySmall
        onClicked: panel.addRule({ id: Engine.newId(), enabled: true, name: "", match: { "class": "" }, effects: {} })
      }
    }

    Text {
      visible: panel.cfg.rules.length === 0
      Layout.fillWidth: true
      Layout.topMargin: Style.spacing.xl
      horizontalAlignment: Text.AlignHCenter
      text: "No app rules yet."
      color: Util.alpha(view.fg, 0.45)
      font.family: view.fontFamily
      font.pixelSize: Style.font.body
    }

    Repeater {
      model: panel.cfg.rules
      Rectangle {
        id: card
        required property var modelData
        required property int index
        // Deep plain-JS copy: model data arrives as Qt list/map wrappers, for
        // which Array.isArray() is false and edits would fall back to defaults.
        readonly property var rule: JSON.parse(JSON.stringify(modelData))
        readonly property var effectKeys: Object.keys(rule.effects || {})
        Layout.fillWidth: true
        implicitHeight: cardCol.implicitHeight + Style.spacing.xl * 2
        radius: panel.radius
        color: Util.alpha(view.fg, 0.035)
        border.width: 1
        border.color: Util.alpha(view.fg, 0.08)
        opacity: rule.enabled === false ? 0.55 : 1

        ColumnLayout {
          id: cardCol
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: Style.spacing.xl
          spacing: Style.spacing.md

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.spacing.md
            TextField {
              Layout.fillWidth: true
              text: card.rule.name || ""
              placeholderText: "Rule name"
              foreground: view.fg
              accent: view.accent
              font.family: view.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
              onAccepted: { panel.updateRule(card.rule.id, { name: text }, true); panel.refocus() }
            }
            ToggleSwitch {
              checked: card.rule.enabled !== false
              foreground: view.fg
              accent: view.accent
              cursorRing: false
              onToggled: panel.updateRule(card.rule.id, { enabled: card.rule.enabled === false }, true)
            }
            PanelActionButton { iconText: Schema.I.up; tooltipText: "Earlier (later rules win)"; foreground: view.fg; onClicked: panel.moveRule(card.rule.id, -1) }
            PanelActionButton { iconText: Schema.I.down; tooltipText: "Later"; foreground: view.fg; onClicked: panel.moveRule(card.rule.id, 1) }
            PanelActionButton { iconText: Schema.I.trash; tooltipText: "Delete rule"; foreground: view.fg; onClicked: panel.deleteRule(card.rule.id) }
          }

          // match
          Repeater {
            model: [{ key: "class", label: "Class" }, { key: "title", label: "Title" }]
            RowLayout {
              required property var modelData
              Layout.fillWidth: true
              spacing: Style.spacing.lg
              Text {
                Layout.preferredWidth: Style.space(60)
                text: modelData.label
                color: Util.alpha(view.fg, 0.6)
                font.family: view.fontFamily
                font.pixelSize: Style.font.bodySmall
              }
              TextField {
                Layout.fillWidth: true
                text: (card.rule.match && card.rule.match[modelData.key]) || ""
                placeholderText: modelData.key === "class" ? "regex, e.g. ^(firefox)$" : "optional regex"
                foreground: view.fg
                accent: view.accent
                font.family: view.fontFamily
                font.pixelSize: Style.font.bodySmall
                onAccepted: {
                  var m = JSON.parse(JSON.stringify(card.rule.match || {}))
                  if (text === "") delete m[modelData.key]; else m[modelData.key] = text
                  panel.updateRule(card.rule.id, { match: m }, true)
                  panel.refocus()
                }
              }
            }
          }
          RowLayout {
            spacing: Style.spacing.lg
            Text {
              Layout.preferredWidth: Style.space(60)
              text: "Only"
              color: Util.alpha(view.fg, 0.6)
              font.family: view.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
            Repeater {
              model: [{ key: "", label: "All" }, { key: "float", label: "Floating" }, { key: "tiled", label: "Tiled" }]
              Button {
                required property var modelData
                readonly property var f: card.rule.match ? card.rule.match["float"] : undefined
                text: modelData.label
                selected: modelData.key === "" ? f === undefined : (modelData.key === "float" ? f === true : f === false)
                bordered: true
                foreground: view.fg
                accent: view.accent
                fontFamily: view.fontFamily
                fontSize: Style.font.caption
                onClicked: {
                  var m = JSON.parse(JSON.stringify(card.rule.match || {}))
                  if (modelData.key === "") delete m["float"]; else m["float"] = modelData.key === "float"
                  panel.updateRule(card.rule.id, { match: m }, true)
                }
              }
            }
          }

          Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Util.alpha(view.fg, 0.08) }

          // effects
          Repeater {
            model: card.effectKeys
            RowLayout {
              id: eff
              required property var modelData
              readonly property var info: Engine.effectInfo(modelData) || { key: modelData, label: modelData, type: "text" }
              readonly property var val: card.rule.effects[modelData]
              Layout.fillWidth: true
              spacing: Style.spacing.lg

              function set(v, commit) {
                var e = JSON.parse(JSON.stringify(card.rule.effects || {}))
                e[eff.modelData] = v
                panel.updateRule(card.rule.id, { effects: e }, commit)
              }

              ColumnLayout {
                Layout.preferredWidth: Style.space(140)
                Layout.alignment: Qt.AlignTop
                spacing: 0
                Text {
                  text: eff.info.label
                  color: view.fg
                  font.family: view.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }
                Text {
                  Layout.fillWidth: true
                  visible: !!eff.info.desc
                  text: eff.info.desc || ""
                  color: Util.alpha(view.fg, 0.45)
                  font.family: view.fontFamily
                  font.pixelSize: Style.font.caption
                  wrapMode: Text.WordWrap
                }
              }

              Loader {
                Layout.fillWidth: true
                sourceComponent: {
                  var t = eff.info.type
                  if (t === "bool") return bEd
                  if (t === "int" || t === "float") return nEd
                  if (t === "opacity") return oEd
                  if (t === "size") return sEd
                  if (t === "enum") return eEd
                  if (t === "color") return cEd
                  return tEd
                }
                Component {
                  id: bEd
                  Item {
                    implicitHeight: sw.implicitHeight
                    ToggleSwitch { id: sw; checked: eff.val === true; foreground: view.fg; accent: view.accent; cursorRing: false; onToggled: eff.set(!(eff.val === true), true) }
                  }
                }
                Component {
                  id: nEd
                  RowLayout {
                    spacing: Style.spacing.lg
                    Slider {
                      Layout.fillWidth: true
                      minimum: eff.info.min; maximum: eff.info.max; step: eff.info.step || 1
                      integer: eff.info.type === "int"
                      value: Number(eff.val)
                      trackColor: Util.alpha(view.fg, 0.14); fillColor: view.accent; knobColor: view.fg
                      onReleased: function(v) { eff.set(eff.info.type === "int" ? Math.round(v) : Math.round(v * 100) / 100, true) }
                    }
                    Text {
                      text: Engine.formatNumber(eff.val, eff.info.decimals) + (eff.info.unit || "")
                      color: view.fg; font.family: view.fontFamily; font.pixelSize: Style.font.caption
                    }
                  }
                }
                Component {
                  id: oEd
                  ColumnLayout {
                    spacing: Style.spacing.xs
                    Repeater {
                      model: ["Focused", "Unfocused"]
                      RowLayout {
                        required property string modelData
                        required property int index
                        spacing: Style.spacing.lg
                        Text { Layout.preferredWidth: Style.space(66); text: modelData; color: Util.alpha(view.fg, 0.6); font.family: view.fontFamily; font.pixelSize: Style.font.caption }
                        Slider {
                          Layout.fillWidth: true
                          minimum: 0.2; maximum: 1; step: 0.01
                          value: Number((Array.isArray(eff.val) ? eff.val : [1, 1])[index])
                          trackColor: Util.alpha(view.fg, 0.14); fillColor: view.accent; knobColor: view.fg
                          onReleased: function(v) { var a = (Array.isArray(eff.val) ? eff.val : [1, 1]).slice(); a[index] = Math.round(v * 100) / 100; eff.set(a, true) }
                        }
                        Text { text: Engine.formatNumber((Array.isArray(eff.val) ? eff.val : [1, 1])[index], 2); color: view.fg; font.family: view.fontFamily; font.pixelSize: Style.font.caption }
                      }
                    }
                  }
                }
                Component {
                  id: sEd
                  RowLayout {
                    spacing: Style.spacing.md
                    Repeater {
                      model: 2
                      TextField {
                        required property int index
                        implicitWidth: Style.space(80)
                        text: String((Array.isArray(eff.val) ? eff.val : ["", ""])[index])
                        placeholderText: index === 0 ? "width" : "height"
                        foreground: view.fg; accent: view.accent; font.family: view.fontFamily; font.pixelSize: Style.font.bodySmall
                        onAccepted: { var a = (Array.isArray(eff.val) ? eff.val : ["60%", "70%"]).slice(); a[index] = String(text).trim(); eff.set(a, true); panel.refocus() }
                      }
                    }
                    Text { text: "px or %"; color: Util.alpha(view.fg, 0.45); font.family: view.fontFamily; font.pixelSize: Style.font.caption }
                  }
                }
                Component {
                  id: eEd
                  Choice {
                    showLabel: false
                    value: String(eff.val)
                    options: eff.info.options.map(function(o) { return { value: o, label: o } })
                    foreground: view.fg; accent: view.accent; fontFamily: view.fontFamily
                    onChanged: function(v) { eff.set(v, true) }
                  }
                }
                Component {
                  id: cEd
                  PaletteEditor {
                    panel: view.panel
                    spec: Engine.isColorSpec(eff.val) ? eff.val : null
                    gradient: true
                    onEdited: function(s) { eff.set(s, false) }
                    onCommitted: function(s) { eff.set(s, true) }
                  }
                }
                Component {
                  id: tEd
                  TextField {
                    text: String(eff.val || "")
                    foreground: view.fg; accent: view.accent; font.family: view.fontFamily; font.pixelSize: Style.font.bodySmall
                    onAccepted: { eff.set(String(text), true); panel.refocus() }
                  }
                }
              }

              PanelActionButton {
                Layout.alignment: Qt.AlignTop
                iconText: Schema.I.close
                tooltipText: "Remove effect"
                foreground: view.fg
                onClicked: {
                  var e = JSON.parse(JSON.stringify(card.rule.effects || {}))
                  delete e[eff.modelData]
                  panel.updateRule(card.rule.id, { effects: e }, true)
                }
              }
            }
          }

          Choice {
            implicitWidth: Style.space(220)
            showLabel: false
            value: ""
            options: [{ value: "", label: "+ Add effect…" }].concat(Engine.RULE_EFFECTS.filter(function(e) {
              return card.effectKeys.indexOf(e.key) === -1
            }).map(function(e) { return { value: e.key, label: e.label } }))
            foreground: view.fg
            accent: view.accent
            fontFamily: view.fontFamily
            onChanged: function(v) {
              if (!v) return
              var info = Engine.effectInfo(v)
              var e = JSON.parse(JSON.stringify(card.rule.effects || {}))
              e[v] = view.defaultEffect(info)
              panel.updateRule(card.rule.id, { effects: e }, true)
            }
          }
        }
      }
    }
  }
}
