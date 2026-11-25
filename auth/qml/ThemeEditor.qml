import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Zestify.Login 1.0

Drawer {
    id: root
    edge: Qt.RightEdge
    width: Math.min(440, parent.width)
    height: parent.height
    modal: false
    interactive: Theme.editable
    enabled: Theme.editable
    property string wallpaperError: ""
    function browseAsset(key) {
        if (!assetPicker.item) return;
        assetPicker.item.fieldKey = key;
        const current = Theme.assetUrl(Theme.value(key)).toString();
        if (current.length > 0) assetPicker.item.currentFolder = current.substring(0, current.lastIndexOf("/") + 1);
        assetPicker.item.open();
    }
    Loader {
        id: assetPicker
        objectName: "assetPickerLoader"
        // The real login screen does not need a desktop file dialog module.
        active: root.opened && Theme.editable
        source: active ? "AssetPicker.qml" : ""
    }
    // Keep the editor legible while previewing arbitrary fonts and colors.
    font.family: "sans-serif"
    font.pixelSize: 14
    palette.window: "#171923"
    palette.windowText: "#eeeeff"
    palette.text: "#eeeeff"
    palette.buttonText: "#eeeeff"
    palette.base: "#0d0e15"
    palette.button: "#292c3d"
    palette.highlight: "#bfc4ee"
    background: Rectangle { color: "#171923"; border.color: "#363846" }
    readonly property var groups: ["fonts", "colors", "layout", "brand", "welcome", "clock", "form", "hint", "icons", "background"]
    readonly property var visibleFields: Array.from(Theme.fields).filter(field => field.path.startsWith(groups[section.currentIndex] + "."))

    ColumnLayout {
        anchors { fill: parent; margins: 20 }
        spacing: 12
        RowLayout {
            Layout.fillWidth: true
            Label { text: "Login appearance"; color: "#eeeeff"; font.pixelSize: 22; Layout.fillWidth: true }
            Button { text: "Close"; onClicked: root.close() }
        }
        Label { text: "Changes appear immediately. Save to keep your theme."; color: "#abaab5"; wrapMode: Text.WordWrap; Layout.fillWidth: true }
        ComboBox { id: section; objectName: "themeSection"; model: root.groups; Layout.fillWidth: true }
        ListView {
            id: list
            objectName: "themeFields"
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 14
            model: root.visibleFields
            ScrollBar.vertical: ScrollBar {}
            delegate: Column {
                id: field
                required property var modelData
                readonly property var currentValue: {
                    const settings = Theme.data;
                    return Theme.value(modelData.path);
                }
                width: list.width - 12
                spacing: 5
                Label { text: field.modelData.label; textFormat: Text.PlainText; color: "#eeeeff" }
                Label { text: field.modelData.path; color: "#abaab5"; font.pixelSize: 10 }
                Loader {
                    width: parent.width
                    sourceComponent: field.modelData.type === "boolean" ? toggle
                        : field.modelData.type === "choice" ? selection
                        : field.modelData.type === "font" ? fontSelection
                        : field.modelData.type === "number" ? number : entry
                }
                Component {
                    id: fontSelection
                    FontPicker { fieldKey: field.modelData.path; selectedFamily: field.currentValue }
                }
                Component {
                    id: toggle
                    Switch { checked: field.currentValue; onToggled: Theme.setValue(field.modelData.path, checked) }
                }
                Component {
                    id: selection
                    ComboBox {
                        model: field.modelData.choices
                        currentIndex: model.indexOf(field.currentValue)
                        onActivated: Theme.setValue(field.modelData.path, currentText)
                    }
                }
                Component {
                    id: number
                    RowLayout {
                        Slider {
                            Layout.fillWidth: true
                            from: field.modelData.min
                            to: field.modelData.max
                            value: field.currentValue
                            onMoved: Theme.setValue(field.modelData.path, Math.round(value * 100) / 100)
                        }
                        TextField {
                            Layout.preferredWidth: 82
                            text: Number(field.currentValue).toFixed(2).replace(/\.?0+$/, "")
                            selectByMouse: true
                            onEditingFinished: Theme.setValue(field.modelData.path, Number(text))
                        }
                    }
                }
                Component {
                    id: entry
                    RowLayout {
                        Rectangle {
                            visible: field.modelData.type === "color"
                            width: 24; height: 24
                            color: visible ? field.currentValue : "transparent"
                            border.color: "#eeeeff"
                            radius: 4
                        }
                        TextField {
                            objectName: "theme-" + field.modelData.path
                            Layout.fillWidth: true
                            text: field.currentValue
                            selectByMouse: true
                            placeholderText: field.modelData.type === "asset" ? "Local file path (optional)" : ""
                            onEditingFinished: Theme.setValue(field.modelData.path, text)
                        }
                        Button {
                            objectName: "browse-" + field.modelData.path
                            visible: field.modelData.type === "asset"
                            text: "Browse…"
                            onClicked: root.browseAsset(field.modelData.path)
                        }
                    }
                }
            }
        }
        Label {
            Layout.fillWidth: true
            visible: root.wallpaperError.length > 0
            text: root.wallpaperError
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            color: "#f97386"
            font.pixelSize: 12
        }
        Label {
            Layout.fillWidth: true
            visible: Theme.status.length > 0
            text: Theme.status
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            color: Theme.error ? "#f97386" : "#abaab5"
            font.pixelSize: 12
        }
        TextField { id: filename; objectName: "themeFilename"; Layout.fillWidth: true; text: Theme.path; selectByMouse: true }
        RowLayout {
            Layout.fillWidth: true
            Button { text: "Defaults"; onClicked: Theme.reset() }
            Button { text: "Reload"; onClicked: Theme.reload() }
            Item { Layout.fillWidth: true }
            Button { objectName: "saveTheme"; text: "Save theme"; onClicked: Theme.save(filename.text) }
        }
    }
}
