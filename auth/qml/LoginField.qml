import QtQuick
import QtQuick.Controls
import Zestify.Login 1.0

TextField {
    id: root
    required property var iconSpec
    property string iconFamily: Theme.data.fonts.iconFamily
    implicitHeight: Theme.data.form.controlHeight
    color: Theme.data.colors.text
    placeholderTextColor: Theme.data.colors.muted
    selectionColor: Theme.data.colors.selection
    selectedTextColor: Theme.data.colors.accentText
    font.pixelSize: Theme.data.form.textSize
    leftPadding: icon.hasIcon ? Theme.data.form.iconSize + Theme.data.form.iconSpacing + 14 : 14
    rightPadding: 14
    ThemeIcon {
        id: icon
        x: 12
        anchors.verticalCenter: parent.verticalCenter
        spec: root.iconSpec
        family: root.iconFamily
        color: root.activeFocus ? Theme.data.colors.accent : Theme.data.colors.muted
    }
    background: Rectangle {
        objectName: "loginFieldBackground"
        opacity: 1 - Theme.data.layout.transparency
        radius: Theme.data.form.controlRadius
        color: Theme.data.colors.input
        border.width: root.activeFocus ? Math.max(2, Theme.data.form.borderWidth) : Theme.data.form.borderWidth
        border.color: root.activeFocus ? Theme.data.colors.accent : Theme.data.colors.border
    }
}
