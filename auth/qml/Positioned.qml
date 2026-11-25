import QtQuick
import Zestify.Login 1.0

// Positions are fractions of the available screen; offsets are logical pixels.
// Clamp the scaled bounds to a safe margin, including on small displays.
Item {
    id: root
    required property var position
    readonly property real uiScale: Theme.data.layout.scale
    readonly property real margin: Math.min(Theme.data.layout.margin, parent.width / 4, parent.height / 4)
    transformOrigin: Item.TopLeft
    scale: uiScale
    x: Math.max(margin, Math.min(parent.width - margin - width * uiScale,
        parent.width * position.x - width * uiScale * position.anchorX + position.offsetX * uiScale))
    y: Math.max(margin, Math.min(parent.height - margin - height * uiScale,
        parent.height * position.y - height * uiScale * position.anchorY + position.offsetY * uiScale))
}
