import QtQuick
import QtQuick.Layouts
import qs.Commons

// Titled group inside a view.
ColumnLayout {
  id: card
  property var panel: null
  property string title: ""
  property string subtitle: ""
  default property alias content: inner.data

  Layout.fillWidth: true
  spacing: Style.spacing.md

  ColumnLayout {
    Layout.fillWidth: true
    Layout.topMargin: Style.spacing.lg
    spacing: Style.spacing.xxs
    visible: card.title !== ""
    Text {
      text: card.title
      color: panel ? panel.fg : Color.foreground
      font.family: panel ? panel.font : Style.font.family
      font.pixelSize: Style.font.title
      font.bold: true
    }
    Text {
      Layout.fillWidth: true
      visible: text !== ""
      text: card.subtitle
      color: Util.alpha(panel ? panel.fg : Color.foreground, 0.55)
      font.family: panel ? panel.font : Style.font.family
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }
  }

  ColumnLayout {
    id: inner
    Layout.fillWidth: true
    spacing: Style.spacing.xs
  }
}
