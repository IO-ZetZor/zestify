import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Zestify.Login 1.0

ColumnLayout {
    id: root
    required property string fieldKey
    required property string selectedFamily
    readonly property var families: Array.from(Theme.fontFamilies)
    readonly property var matches: families.filter(family => family.toLowerCase().includes(search.text.toLowerCase()))
    spacing: 6

    TextField {
        id: search
        objectName: "fontSearch-" + root.fieldKey
        Layout.fillWidth: true
        placeholderText: "Search installed fonts"
        selectByMouse: true
    }
    ComboBox {
        id: picker
        objectName: "theme-" + root.fieldKey
        Layout.fillWidth: true
        model: root.matches
        editable: false
        currentIndex: root.matches.indexOf(root.selectedFamily)
        displayText: root.selectedFamily
        onActivated: Theme.selectFont(root.fieldKey, currentText)
        delegate: ItemDelegate {
            required property var modelData
            required property int index
            width: picker.width
            text: modelData
            highlighted: picker.highlightedIndex === index
            contentItem: Label {
                text: parent.text
                textFormat: Text.PlainText
                font.family: parent.text
                font.pixelSize: 15
                elide: Text.ElideRight
            }
        }
        popup: Popup {
            y: picker.height + 4
            width: picker.width
            padding: 4
            implicitHeight: Math.min(contentItem.implicitHeight + 8, 300)
            contentItem: ListView {
                clip: true
                implicitHeight: contentHeight
                model: picker.popup.visible ? picker.delegateModel : null
                currentIndex: picker.highlightedIndex
                ScrollBar.vertical: ScrollBar {}
            }
        }
    }
    Label {
        text: root.matches.length + " of " + root.families.length + " installed font families"
        color: "#abaab5"
        font.pixelSize: 11
    }
}
