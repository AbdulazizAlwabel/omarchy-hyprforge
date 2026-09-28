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
  readonly property var changed: panel.changedItems

  contentWidth: width
  contentHeight: col.implicitHeight + Style.spacing.huge
  clip: true
  boundsBehavior: Flickable.StopAtBounds

  function lookColors(look) {
    var o = look.options
    var out = []
    var b = o["general:col.active_border"]
    if (b && b.slots) for (var i = 0; i < b.slots.length && out.length < 4; i++) out.push(Engine.resolveSlot(b.slots[i], panel.paletteMap))
    if (out.length === 0) out.push(panel.paletteMap.accent)
    return out
  }

  ColumnLayout {
    id: col
    width: view.width - Style.spacing.lg
    spacing: Style.spacing.lg

    PreviewCanvas {
      id: preview
      Layout.fillWidth: true
      Layout.preferredHeight: implicitHeight
      panel: view.panel
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.spacing.lg
      Text {
        Layout.fillWidth: true
        text: "Live model of " + panel.monitorName + "  ·  click a window to focus it"
        color: Util.alpha(view.fg, 0.5)
        font.family: view.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
      Text {
        text: panel.themeName + "  ·  " + String(panel.valueForKey("general:layout"))
        color: Util.alpha(view.fg, 0.5)
        font.family: view.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    SectionCard {
      panel: view.panel
      title: "Looks"
      subtitle: "One click restyles windows, borders, corners, blur, shadow and glow. Layout, input and animations stay as they are. Colors come from your current theme."

      GridLayout {
        Layout.fillWidth: true
        columns: Math.max(2, Math.floor(col.width / Style.space(210)))
        rowSpacing: Style.spacing.md
        columnSpacing: Style.spacing.md

        Repeater {
          model: Engine.LOOKS
          Rectangle {
            id: lcard
            required property var modelData
            readonly property bool active: panel.activeLook === modelData.id
            Layout.fillWidth: true
            implicitHeight: lcol.implicitHeight + Style.spacing.lg * 2
            radius: panel.radius
            color: active ? Util.alpha(view.accent, 0.12) : Util.alpha(view.fg, lhover.hovered ? 0.07 : 0.035)
            border.width: 1
            border.color: active ? view.accent : Util.alpha(view.fg, 0.08)
            Behavior on color { ColorAnimation { duration: 100 } }

            ColumnLayout {
              id: lcol
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: Style.spacing.lg
              spacing: Style.spacing.sm

              RowLayout {
                spacing: Style.spacing.md
                // mini window swatch: rounding + border colors of the look
                Rectangle {
                  readonly property var o: lcard.modelData.options
                  implicitWidth: Style.space(34); implicitHeight: Style.space(24)
                  radius: Math.min(8, Number(o["decoration:rounding"] !== undefined ? o["decoration:rounding"] : 0) / 2)
                  color: panel.paletteMap.background
                  border.width: Math.max(1, Math.min(3, Number(o["general:border_size"] || 2)))
                  border.color: view.lookColors(lcard.modelData)[0]
                  Rectangle {
                    anchors.bottom: parent.bottom; anchors.right: parent.right; anchors.margins: 4
                    width: 8; height: 4; radius: 2
                    color: view.lookColors(lcard.modelData)[view.lookColors(lcard.modelData).length - 1]
                  }
                }
                Text {
                  Layout.fillWidth: true
                  text: lcard.modelData.name
                  color: view.fg
                  font.family: view.fontFamily
                  font.pixelSize: Style.font.subtitle
                  font.bold: true
                  elide: Text.ElideRight
                }
              }
              Text {
                Layout.fillWidth: true
                text: lcard.modelData.desc
                color: Util.alpha(view.fg, 0.55)
                font.family: view.fontFamily
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }
            }
            HoverHandler { id: lhover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: panel.applyLook(lcard.modelData.id) }
          }
        }
      }
    }

    SectionCard {
      panel: view.panel
      title: "Motion"
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

    SectionCard {
      panel: view.panel
      title: view.changed.length === 0 ? "Everything is stock" : view.changed.length + (view.changed.length === 1 ? " change" : " changes")
      subtitle: view.changed.length === 0 ? "Nothing overridden yet: Omarchy's defaults and your own files apply." : "Click one to jump to it."

      Repeater {
        model: view.changed
        Rectangle {
          id: crow
          required property var modelData
          Layout.fillWidth: true
          implicitHeight: crowRow.implicitHeight + Style.spacing.md * 2
          radius: panel.radius
          color: chover.hovered ? Util.alpha(view.fg, 0.05) : "transparent"
          HoverHandler { id: chover; cursorShape: Qt.PointingHandCursor }
          TapHandler { onTapped: panel.jumpTo(crow.modelData.key, crow.modelData.section) }
          RowLayout {
            id: crowRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.spacing.lg
            anchors.rightMargin: Style.spacing.sm
            spacing: Style.spacing.md
            Text {
              text: crow.modelData.icon || ""
              color: view.accent
              font.family: view.fontFamily
              font.pixelSize: Style.font.body
            }
            Text {
              Layout.fillWidth: true
              text: crow.modelData.label
              color: view.fg
              font.family: view.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }
            Text {
              Layout.maximumWidth: Style.space(200)
              text: crow.modelData.value
              color: Util.alpha(view.fg, 0.6)
              font.family: view.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }
            PanelActionButton {
              iconText: Schema.I.reset
              tooltipText: "Reset"
              foreground: view.fg
              onClicked: panel.resetChange(crow.modelData)
            }
          }
        }
      }
    }
  }
}
