import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Zestify.Login 1.0

ComboBox {
    id: root
    required property var iconSpec
    property string iconFamily: Theme.data.fonts.iconFamily
    property bool showAccountId: false
    textRole: "name"
    valueRole: "id"
    editable: false
    implicitHeight: Theme.data.form.controlHeight
    font.pixelSize: Theme.data.form.textSize
    leftPadding: 14
    rightPadding: 28
    contentItem: RowLayout {
        spacing: Theme.data.form.iconSpacing
        ThemeIcon { objectName: "choiceIcon"; spec: root.iconSpec; family: root.iconFamily; color: Theme.data.colors.muted }
        Label {
            Layout.fillWidth: true
            text: root.showAccountId && root.currentValue && root.displayText !== root.currentValue
                ? root.displayText + " (" + root.currentValue + ")" : root.displayText
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: Theme.data.colors.text
            font: root.font
        }
    }
    indicator: ThemeIcon {
        x: root.width - width - 12
        anchors.verticalCenter: parent.verticalCenter
        spec: Theme.data.icons.dropdown
        family: root.iconFamily
        color: Theme.data.colors.muted
    }
    background: Rectangle {
        objectName: "loginChoiceBackground"
        opacity: 1 - Theme.data.layout.transparency
        radius: Theme.data.form.controlRadius
        color: Theme.data.colors.input
        border.width: root.activeFocus ? Math.max(2, Theme.data.form.borderWidth) : Theme.data.form.borderWidth
        border.color: root.activeFocus ? Theme.data.colors.accent : Theme.data.colors.border
    }
    delegate: ItemDelegate {
        required property var modelData
        required property int index
        width: root.width
        implicitHeight: Theme.data.form.controlHeight
        text: root.showAccountId && modelData.name !== modelData.id ? modelData.name + " (" + modelData.id + ")" : modelData.name
        font: root.font
        highlighted: root.highlightedIndex === index
        contentItem: Label { text: parent.text; textFormat: Text.PlainText; font: root.font; color: Theme.data.colors.text }
        background: Rectangle { color: parent.highlighted ? Theme.data.colors.button : Theme.data.colors.panel; opacity: 1 - Theme.data.layout.transparency }
    }
    popup: Popup {
        y: root.height + 4
        width: root.width
        padding: 4
        implicitHeight: Math.min(contentItem.implicitHeight + 8, 280)
        contentItem: ListView {
            clip: true
            implicitHeight: contentHeight
            model: root.popup.visible ? root.delegateModel : null
            currentIndex: root.highlightedIndex
            ScrollIndicator.vertical: ScrollIndicator {}
        }
        background: Rectangle { color: Theme.data.colors.panel; radius: Theme.data.form.controlRadius; border.color: Theme.data.colors.border; opacity: 1 - Theme.data.layout.transparency }
    }
}
