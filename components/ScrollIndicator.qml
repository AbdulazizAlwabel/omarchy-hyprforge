import QtQuick
import qs.Commons

// Thin scroll thumb for any Flickable, drawn over its right edge.
Rectangle {
  id: bar
  property var flickable: null
  property var panel: null

  readonly property real contentH: flickable ? flickable.contentHeight : 0
  readonly property real viewH: flickable ? flickable.height : 0

  anchors.right: parent ? parent.right : undefined
  width: Style.space(3)
  radius: width / 2
  color: Util.alpha(panel ? panel.fg : Color.foreground, 0.28)
  visible: flickable !== null && contentH > viewH + 1
  height: Math.max(Style.space(24), viewH * (viewH / Math.max(1, contentH)))
  y: flickable ? (viewH - height) * Math.max(0, Math.min(1, (flickable.contentY - (flickable.originY || 0)) / Math.max(1, contentH - viewH))) : 0
}
