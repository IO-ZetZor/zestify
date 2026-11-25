import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Zestify.Login 1.0

Button {
    id: root
    required property var iconSpec
    property string iconFamily: Theme.data.fonts.iconFamily
    property bool primary: false
    implicitHeight: Theme.data.form.buttonHeight
    implicitWidth: contents.implicitWidth + 28
    font.pixelSize: Theme.data.form.buttonSize
    contentItem: RowLayout {
        id: contents
        spacing: Theme.data.form.iconSpacing
        ThemeIcon {
            spec: root.iconSpec
            family: root.iconFamily
            color: root.primary ? Theme.data.colors.accentText : Theme.data.colors.text
        }
        Label {
            text: root.text
            textFormat: Text.PlainText
            font: root.font
            color: root.primary ? Theme.data.colors.accentText : Theme.data.colors.text
        }
    }
    background: Rectangle {
        radius: Theme.data.form.buttonRadius
        color: root.primary ? Theme.data.colors.accent : Theme.data.colors.button
        opacity: (1 - Theme.data.layout.transparency) * (!root.enabled ? 0.45 : root.down ? 0.65 : root.hovered ? 0.85 : 1)
        border.width: root.activeFocus ? 2 : 0
        border.color: Theme.data.colors.text
    }
}
