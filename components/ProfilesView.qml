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
  property string confirmDelete: ""

  readonly property color fg: panel.fg
  readonly property color accent: panel.accent
  readonly property string fontFamily: panel.font
  readonly property var names: Object.keys(panel.profiles).sort(function(a, b) { return a.toLowerCase().localeCompare(b.toLowerCase()) })

  contentWidth: width
  contentHeight: col.implicitHeight + Style.spacing.huge
  clip: true
  boundsBehavior: Flickable.StopAtBounds

  function when(ts) {
    if (!ts) return ""
    var d = new Date(ts)
    var now = new Date()
    var sec = Math.round((now - d) / 1000)
    if (sec < 60) return "just now"
    if (sec < 3600) return Math.round(sec / 60) + " min ago"
    if (d.toDateString() === now.toDateString()) return Qt.formatTime(d, "HH:mm")
    return Qt.formatDateTime(d, "d MMM HH:mm")
  }

  function changeCount(cfg) {
    var c = Engine.normalize(cfg)
    return Object.keys(c.options).length + Object.keys(c.anims).length + c.rules.length
  }

  ColumnLayout {
    id: col
    width: view.width - Style.spacing.lg
    spacing: Style.spacing.md

    SectionCard {
      panel: view.panel
      title: "Save this look"
      subtitle: "A profile stores every Hyprforge setting: options, colors, animations, curves and app rules."
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.spacing.md
        TextField {
          id: nameField
          Layout.fillWidth: true
          placeholderText: "Profile name, e.g. Work, Gaming, Cozy night"
          foreground: view.fg
          accent: view.accent
          font.family: view.fontFamily
          font.pixelSize: Style.font.body
          onAccepted: save()
          function save() {
            var n = String(text).trim()
            if (!n) return
            panel.saveProfile(n)
            text = ""
            panel.refocus()
          }
        }
        Button {
          text: "Save"
          iconText: Schema.I.profiles
          bordered: true
          foreground: view.fg
          accent: view.accent
          fontFamily: view.fontFamily
          onClicked: nameField.save()
        }
        Button {
          text: "Import"
          iconText: Schema.I.export
          tooltipText: "Paste a profile someone copied with the Copy button"
          bordered: true
          foreground: view.fg
          accent: view.accent
          fontFamily: view.fontFamily
          onClicked: panel.importFromClipboard()
        }
      }
    }

    SectionCard {
      panel: view.panel
      title: "Profiles"
      subtitle: view.names.length === 0 ? "None saved yet." : "Switch from a keybinding or script with:  omarchy-shell hyprforge profile \"<name>\"  (or cycleProfile)."

      Repeater {
        model: view.names
        Rectangle {
          id: pcard
          required property string modelData
          readonly property var prof: panel.profiles[modelData]
          readonly property bool active: panel.activeProfile === modelData
          Layout.fillWidth: true
          implicitHeight: prow.implicitHeight + Style.spacing.lg * 2
          radius: panel.radius
          color: active ? Util.alpha(view.accent, 0.1) : Util.alpha(view.fg, 0.035)
          border.width: 1
          border.color: active ? Util.alpha(view.accent, 0.6) : Util.alpha(view.fg, 0.08)

          RowLayout {
            id: prow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Style.spacing.lg
            spacing: Style.spacing.md

            ColumnLayout {
              Layout.fillWidth: true
              spacing: 0
              Text {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: pcard.modelData + (pcard.active ? "  ·  active" : "")
                color: view.fg
                font.family: view.fontFamily
                font.pixelSize: Style.font.subtitle
                font.bold: true
              }
              Text {
                text: view.changeCount(pcard.prof.cfg) + " settings  ·  saved " + view.when(pcard.prof.saved)
                color: Util.alpha(view.fg, 0.5)
                font.family: view.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
            Button {
              text: "Apply"; iconText: Schema.I.check; bordered: true
              foreground: view.fg; accent: view.accent; fontFamily: view.fontFamily; fontSize: Style.font.bodySmall
              onClicked: panel.applyProfile(pcard.modelData)
            }
            PanelActionButton { iconText: Schema.I.profiles; tooltipText: "Overwrite with current settings"; foreground: view.fg; onClicked: panel.saveProfile(pcard.modelData) }
            PanelActionButton { iconText: Schema.I.copy; tooltipText: "Copy as shareable JSON"; foreground: view.fg; onClicked: panel.copyProfile(pcard.modelData) }
            PanelActionButton {
              iconText: view.confirmDelete === pcard.modelData ? Schema.I.check : Schema.I.trash
              tooltipText: view.confirmDelete === pcard.modelData ? "Click again to delete" : "Delete"
              foreground: view.confirmDelete === pcard.modelData ? Color.urgent : view.fg
              onClicked: {
                if (view.confirmDelete === pcard.modelData) { var n = pcard.modelData; view.confirmDelete = ""; panel.deleteProfile(n) }
                else view.confirmDelete = pcard.modelData
              }
            }
          }
        }
      }
    }

    SectionCard {
      panel: view.panel
      title: "History"
      subtitle: "Every applied change, newest first. Restoring is itself undoable."

      Repeater {
        model: panel.history.slice().reverse()
        RowLayout {
          required property var modelData
          required property int index
          Layout.fillWidth: true
          spacing: Style.spacing.md
          Text {
            Layout.preferredWidth: Style.space(78)
            text: view.when(modelData.time)
            color: Util.alpha(view.fg, 0.5)
            font.family: view.fontFamily
            font.pixelSize: Style.font.caption
          }
          Text {
            Layout.fillWidth: true
            text: modelData.label || "change"
            color: view.fg
            font.family: view.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
          }
          Button {
            text: index === 0 ? "Current" : "Restore"
            enabled: index !== 0
            opacity: enabled ? 1 : 0.45
            bordered: true
            foreground: view.fg; accent: view.accent; fontFamily: view.fontFamily; fontSize: Style.font.caption
            onClicked: panel.restoreHistory(modelData)
          }
        }
      }
      Text {
        visible: panel.history.length === 0
        text: "Nothing applied yet."
        color: Util.alpha(view.fg, 0.45)
        font.family: view.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    SectionCard {
      panel: view.panel
      title: "Files & safety"
      subtitle: "Hyprforge writes ~/.config/hypr/hyprforge.lua and loads it with one line in hyprland.lua. If Hyprland ever rejects a change, it is rolled back automatically."
      Flow {
        Layout.fillWidth: true
        spacing: Style.spacing.md
        Button {
          text: "Copy generated Lua"; iconText: Schema.I.copy; bordered: true
          foreground: view.fg; accent: view.accent; fontFamily: view.fontFamily; fontSize: Style.font.bodySmall
          onClicked: panel.copyLua()
        }
        Button {
          text: "Open hyprforge.lua"; iconText: Schema.I.eye; bordered: true
          foreground: view.fg; accent: view.accent; fontFamily: view.fontFamily; fontSize: Style.font.bodySmall
          onClicked: panel.openGenerated()
        }
        Button {
          text: panel.hooked ? "Disconnect from Hyprland" : "Connect to Hyprland"
          iconText: Schema.I.link
          bordered: true
          foreground: view.fg; accent: view.accent; fontFamily: view.fontFamily; fontSize: Style.font.bodySmall
          onClicked: panel.hooked ? panel.disconnectHook() : panel.connectHook()
        }
        Button {
          text: "Reset everything"; iconText: Schema.I.reset; bordered: true
          foreground: Color.urgent; accent: view.accent; fontFamily: view.fontFamily; fontSize: Style.font.bodySmall
          onClicked: panel.resetAll()
        }
      }
    }
  }
}
