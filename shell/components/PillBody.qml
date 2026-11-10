import QtQuick

Rectangle {
    id: root

    property var theme
    property real cornerRadius: 18
    property real transparency: root.theme ? root.theme.transparency : 1.0
    property real backgroundOpacity: 1.0
    property bool animateCornerRadius: true

    Behavior on cornerRadius {
        enabled: root.animateCornerRadius
        NumberAnimation {
            duration: 300
            easing.type: Easing.OutCubic
        }
    }

    radius: cornerRadius
    border.width: 0
    border.color: theme.border
    gradient: Gradient {
        GradientStop { position: 0.0; color: root.theme.withAlpha(root.theme.cardTop, root.transparency * root.backgroundOpacity) }
        GradientStop { position: 1.0; color: root.theme.withAlpha(root.theme.cardBot, root.transparency * root.backgroundOpacity) }
    }
}
