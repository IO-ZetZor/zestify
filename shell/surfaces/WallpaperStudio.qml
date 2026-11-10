pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../lib/wallpapers.js" as WallpapersLib

Item {
    id: root

    property var theme
    property var screen
    property var wallpapers
    property var motion
    property real s: 1
    property string folder: ""
    property bool allMonitors: false
    property string selectedPath: ""
    property string query: ""
    property string mediaFilter: "all"

    readonly property string monitorName: screen ? screen.name : ""
    readonly property int columns: width >= 600 * s ? 3 : (width >= 350 * s ? 2 : 1)
    readonly property var items: wallpapers ? wallpapers.items : []
    readonly property var filteredItems: WallpapersLib.filterItems(items, query, mediaFilter)
    readonly property string currentPath: wallpapers ? wallpapers.currentFor(monitorName) : ""
    readonly property var selectedItem: items.find(item => item.path === selectedPath) || null
    readonly property var previewItem: selectedItem || items.find(item => item.path === currentPath) || null
    readonly property bool busy: wallpapers ? wallpapers.busy : false
    readonly property bool listing: wallpapers ? wallpapers.listing : false
    readonly property string error: wallpapers ? wallpapers.lastError : ""
    readonly property bool canApply: selectedItem !== null && !busy
    readonly property bool compact: width < 500 * s

    function applySelected(all) {
        if (!root.canApply)
            return;
        if (all)
            root.wallpapers.applyAll(root.selectedPath);
        else
            root.wallpapers.apply(root.selectedPath, root.monitorName);
    }

    function moveSelection(delta) {
        if (root.busy || !root.filteredItems.length)
            return;
        const previous = root.filteredItems.findIndex(item => item.path === root.selectedPath);
        grid.currentIndex = previous < 0 ? 0 : Math.max(0, Math.min(grid.count - 1, previous + delta));
        root.selectedPath = root.filteredItems[grid.currentIndex].path;
        grid.positionViewAtIndex(grid.currentIndex, GridView.Contain);
    }

    component ActionButton: Rectangle {
        id: button
        property string label
        property string glyph: ""
        property bool primary: false
        property bool selected: false
        signal clicked()

        implicitWidth: buttonRow.implicitWidth + 22 * root.s
        implicitHeight: 32 * root.s
        radius: 9 * root.s
        activeFocusOnTab: true
        opacity: enabled ? 1 : 0.45
        color: button.primary && button.enabled ? root.theme.accent
            : (button.selected ? root.theme.withAlpha(root.theme.accent, 0.14)
                : (buttonArea.containsMouse ? root.theme.withAlpha(root.theme.cream, 0.07) : "transparent"))
        border.width: button.activeFocus ? 2 : 1
        border.color: button.activeFocus || button.selected ? root.theme.accent : root.theme.border
        Behavior on color { ColorAnimation { duration: root.motion ? root.motion.fast : 140 } }
        Accessible.role: Accessible.Button
        Accessible.name: button.label
        Accessible.onPressAction: if (button.enabled) button.clicked()
        Keys.onReturnPressed: event => { if (!event.isAutoRepeat) button.clicked(); }
        Keys.onEnterPressed: event => { if (!event.isAutoRepeat) button.clicked(); }
        Keys.onSpacePressed: event => { if (!event.isAutoRepeat) button.clicked(); }

        Row {
            id: buttonRow
            anchors.centerIn: parent
            spacing: 6 * root.s
            Text {
                visible: button.glyph.length > 0
                text: button.glyph
                color: button.primary && button.enabled ? root.theme.onAccent : root.theme.accent
                font.family: root.theme.iconFont
                font.pixelSize: root.theme.fs.body * root.s
            }
            Text {
                text: button.label
                color: button.primary && button.enabled ? root.theme.onAccent
                    : (button.selected ? root.theme.accent : root.theme.cream)
                font.family: root.theme.fontFamily
                font.pixelSize: root.theme.fs.meta * root.s
                font.weight: button.primary ? Font.Medium : Font.Normal
            }
        }
        MouseArea {
            id: buttonArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                button.forceActiveFocus(Qt.MouseFocusReason);
                button.clicked();
            }
        }
    }

    component Thumbnail: Rectangle {
        id: thumbnail
        property var item: null
        color: root.theme.withAlpha(root.theme.cream, 0.035)
        clip: true
        Image {
            id: image
            anchors.fill: parent
            source: thumbnail.item ? thumbnail.item.thumb || "" : ""
            asynchronous: true
            cache: true
            smooth: true
            mipmap: true
            fillMode: Image.PreserveAspectCrop
            sourceSize.width: Math.max(1, Math.round(width * 2))
            sourceSize.height: Math.max(1, Math.round(height * 2))
        }
        Text {
            anchors.centerIn: parent
            visible: image.status !== Image.Ready
            text: image.status === Image.Loading ? "…" : "󰸉"
            color: root.theme.faint
            font.family: root.theme.iconFont
            font.pixelSize: 24 * root.s
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 10 * root.s

        RowLayout {
            Layout.fillWidth: true
            spacing: 8 * root.s
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3 * root.s
                Text {
                    Layout.fillWidth: true
                    text: "Your collection"
                    color: root.theme.cream
                    font.family: root.theme.fontFamily
                    font.pixelSize: root.theme.fs.body * root.s
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    text: root.folder
                    color: root.theme.faint
                    elide: Text.ElideMiddle
                    font.family: root.theme.monoFont
                    font.pixelSize: root.theme.fs.label * root.s
                }
            }
            Text {
                text: root.listing ? "Scanning…" : root.items.length + (root.items.length === 1 ? " wallpaper" : " wallpapers")
                color: root.theme.dim
                font.family: root.theme.fontFamily
                font.pixelSize: root.theme.fs.meta * root.s
            }
            ActionButton {
                objectName: "refreshWallpapers"
                label: "Refresh"
                glyph: "󰜉"
                enabled: root.wallpapers !== null && root.wallpapers !== undefined && !root.listing && !root.busy
                onClicked: root.wallpapers.refresh()
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 36 * root.s
            radius: 10 * root.s
            color: root.theme.tileBg
            border.width: 1
            border.color: search.activeFocus ? root.theme.accent : root.theme.border
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12 * root.s
                anchors.rightMargin: 10 * root.s
                spacing: 8 * root.s
                Text {
                    text: "󰍉"
                    color: search.activeFocus ? root.theme.accent : root.theme.faint
                    font.family: root.theme.iconFont
                    font.pixelSize: 16 * root.s
                }
                TextInput {
                    id: search
                    objectName: "wallpaperSearch"
                    Layout.fillWidth: true
                    text: root.query
                    onTextEdited: root.query = text
                    color: root.theme.cream
                    selectionColor: root.theme.accent
                    selectedTextColor: root.theme.onAccent
                    font.family: root.theme.fontFamily
                    font.pixelSize: root.theme.fs.body * root.s
                    clip: true
                    selectByMouse: true
                    activeFocusOnTab: true
                    Accessible.name: "Search wallpapers"
                    Keys.onDownPressed: {
                        grid.forceActiveFocus(Qt.TabFocusReason);
                        root.moveSelection(0);
                    }
                    Text {
                        anchors.fill: parent
                        visible: !search.text.length
                        text: "Search wallpapers…"
                        color: root.theme.faint
                        font: search.font
                    }
                }
                ActionButton {
                    label: "Clear"
                    visible: root.query.length > 0
                    implicitHeight: 26 * root.s
                    onClicked: {
                        root.query = "";
                        search.forceActiveFocus();
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6 * root.s
            Repeater {
                model: [{label: "All", kind: "all"}, {label: "Images", kind: "images"}, {label: "Animated", kind: "animated"}]
                delegate: ActionButton {
                    required property var modelData
                    label: modelData.label
                    selected: root.mediaFilter === modelData.kind
                    onClicked: root.mediaFilter = modelData.kind
                }
            }
            Item { Layout.fillWidth: true }
            Text {
                visible: !root.compact
                text: "Select to preview · Double-click to apply"
                color: root.theme.faint
                font.family: root.theme.fontFamily
                font.pixelSize: root.theme.fs.label * root.s
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            GridView {
                id: grid
                objectName: "wallpaperGrid"
                anchors.fill: parent
                anchors.rightMargin: 10 * root.s
                clip: true
                cellWidth: width / root.columns
                cellHeight: (cellWidth - 10 * root.s) * 0.5625 + 48 * root.s
                model: root.filteredItems
                activeFocusOnTab: true
                keyNavigationEnabled: false
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar {
                    visible: grid.contentHeight > grid.height + 1
                    parent: grid.parent
                    width: 5 * root.s
                    anchors.right: parent.right
                    anchors.top: grid.top
                    anchors.bottom: grid.bottom
                    policy: ScrollBar.AsNeeded
                    contentItem: Rectangle {
                        implicitWidth: 5 * root.s
                        radius: width / 2
                        color: root.theme.withAlpha(root.theme.accent, 0.45)
                    }
                    background: Rectangle { color: "transparent" }
                }
                Keys.onLeftPressed: root.moveSelection(-1)
                Keys.onRightPressed: root.moveSelection(1)
                Keys.onUpPressed: root.moveSelection(-root.columns)
                Keys.onDownPressed: root.moveSelection(root.columns)
                Keys.onReturnPressed: event => { if (!event.isAutoRepeat) root.applySelected(root.allMonitors); }
                Keys.onEnterPressed: event => { if (!event.isAutoRepeat) root.applySelected(root.allMonitors); }

                delegate: Item {
                    id: delegateRoot
                    required property var modelData
                    required property int index
                    width: grid.cellWidth
                    height: grid.cellHeight
                    readonly property bool selected: root.selectedPath === modelData.path
                    readonly property bool current: root.currentPath === modelData.path
                    Rectangle {
                        id: card
                        objectName: "wallpaperCard" + delegateRoot.index
                        anchors.fill: parent
                        anchors.rightMargin: 8 * root.s
                        anchors.bottomMargin: 8 * root.s
                        radius: root.theme.r.tile * root.s
                        color: cardArea.containsMouse ? root.theme.withAlpha(root.theme.accent, 0.18)
                            : (delegateRoot.selected ? root.theme.withAlpha(root.theme.accent, 0.08)
                                : root.theme.withAlpha(root.theme.cream, 0.035))
                        border.width: delegateRoot.selected ? 2 * root.s : 1
                        border.color: delegateRoot.selected ? root.theme.accent
                            : (cardArea.containsMouse ? root.theme.withAlpha(root.theme.accent, 0.5) : root.theme.border)
                        Behavior on color { ColorAnimation { duration: root.motion ? root.motion.fast : 140 } }
                        Behavior on border.color { ColorAnimation { duration: root.motion ? root.motion.fast : 140 } }
                        Thumbnail {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 6 * root.s
                            height: Math.max(0, card.height - 42 * root.s)
                            item: delegateRoot.modelData
                            Rectangle {
                                visible: delegateRoot.modelData.isVideo
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.margins: 6 * root.s
                                width: animatedLabel.implicitWidth + 12 * root.s
                                height: 20 * root.s
                                radius: 6 * root.s
                                color: root.theme.withAlpha(root.theme.surface, 0.88)
                                Text {
                                    id: animatedLabel
                                    anchors.centerIn: parent
                                    text: "󰐊  Animated"
                                    color: root.theme.cream
                                    font.family: root.theme.iconFont
                                    font.pixelSize: root.theme.fs.label * root.s
                                }
                            }
                            Rectangle {
                                visible: delegateRoot.current
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 6 * root.s
                                width: 22 * root.s
                                height: width
                                radius: width / 2
                                color: root.theme.accent
                                Text {
                                    anchors.centerIn: parent
                                    text: "󰄬"
                                    color: root.theme.onAccent
                                    font.family: root.theme.iconFont
                                    font.pixelSize: 12 * root.s
                                }
                            }
                        }
                        Text {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: 10 * root.s
                            text: delegateRoot.modelData.name
                            color: delegateRoot.selected || cardArea.containsMouse ? root.theme.accent : root.theme.cream
                            elide: Text.ElideMiddle
                            font.family: root.theme.fontFamily
                            font.pixelSize: root.theme.fs.meta * root.s
                        }
                        MouseArea {
                            id: cardArea
                            anchors.fill: parent
                            enabled: !root.busy
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                grid.forceActiveFocus(Qt.MouseFocusReason);
                                grid.currentIndex = delegateRoot.index;
                                root.selectedPath = delegateRoot.modelData.path;
                            }
                            onDoubleClicked: {
                                root.selectedPath = delegateRoot.modelData.path;
                                root.applySelected(root.allMonitors);
                            }
                        }
                    }
                }
            }
            ColumnLayout {
                anchors.centerIn: parent
                width: Math.max(0, parent.width - 32 * root.s)
                spacing: 8 * root.s
                visible: !root.filteredItems.length
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.listing ? "󰜉" : "󰸉"
                    color: root.theme.accent
                    font.family: root.theme.iconFont
                    font.pixelSize: 32 * root.s
                }
                Text {
                    Layout.fillWidth: true
                    text: root.listing ? "Finding your wallpapers…"
                        : (root.items.length ? "No matching wallpapers" : (root.error.length ? "Couldn't load wallpapers" : "Your collection is empty"))
                    color: root.theme.cream
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    font.family: root.theme.fontFamily
                    font.pixelSize: root.theme.fs.body * root.s
                }
                Text {
                    Layout.fillWidth: true
                    text: root.listing ? "Thumbnails will appear here"
                        : (root.items.length ? "Try another search or choose a different type" : "Add images or videos to your wallpaper folder, then refresh")
                    color: root.theme.dim
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    font.family: root.theme.fontFamily
                    font.pixelSize: root.theme.fs.meta * root.s
                }
                ActionButton {
                    Layout.alignment: Qt.AlignHCenter
                    visible: root.items.length > 0
                    label: "Reset filters"
                    onClicked: {
                        root.query = "";
                        root.mediaFilter = "all";
                    }
                }
            }
        }

        Text {
            Layout.fillWidth: true
            visible: root.error.length > 0
            text: root.error
            color: root.theme.danger
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.fs.meta * root.s
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: selectionDock.implicitHeight + 20 * root.s
            radius: root.theme.r.tile * root.s
            color: root.theme.tileBg
            border.width: 1
            border.color: root.theme.border
            ColumnLayout {
                id: selectionDock
                anchors.fill: parent
                anchors.margins: 10 * root.s
                spacing: 10 * root.s
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10 * root.s
                    Thumbnail {
                        Layout.preferredWidth: 68 * root.s
                        Layout.preferredHeight: 40 * root.s
                        item: root.previewItem
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 3 * root.s
                        Text {
                            Layout.fillWidth: true
                            text: root.previewItem ? root.previewItem.name : "Choose a wallpaper"
                            color: root.theme.cream
                            elide: Text.ElideMiddle
                            font.family: root.theme.fontFamily
                            font.pixelSize: root.theme.fs.body * root.s
                            font.weight: Font.Medium
                        }
                        Text {
                            Layout.fillWidth: true
                            text: root.busy ? "Applying wallpaper…" : (root.previewItem
                                ? ((root.previewItem.path === root.currentPath ? "Current wallpaper" : "Ready to apply")
                                    + " · " + (root.previewItem.isVideo ? "Animated" : "Image"))
                                : "Select a thumbnail above")
                            color: root.busy ? root.theme.accent : root.theme.dim
                            elide: Text.ElideRight
                            font.family: root.theme.fontFamily
                            font.pixelSize: root.theme.fs.meta * root.s
                        }
                    }
                    ActionButton {
                        objectName: "randomWallpaper"
                        label: "Random"
                        glyph: "󰒟"
                        enabled: root.items.length > 0 && !root.busy
                        onClicked: root.wallpapers.random(root.allMonitors ? "" : root.monitorName)
                    }
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: root.theme.border
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6 * root.s
                    ActionButton {
                        objectName: "thisMonitor"
                        label: root.compact ? "This display" : (root.monitorName || "This display")
                        selected: !root.allMonitors
                        enabled: !root.busy
                        onClicked: root.allMonitors = false
                    }
                    ActionButton {
                        objectName: "allMonitors"
                        label: "All displays"
                        selected: root.allMonitors
                        enabled: !root.busy
                        onClicked: root.allMonitors = true
                    }
                    Item { Layout.fillWidth: true }
                    ActionButton {
                        objectName: "applyWallpaper"
                        label: root.busy ? "Applying…" : (root.allMonitors && !root.compact ? "Apply to all" : "Apply")
                        glyph: "󰄬"
                        primary: true
                        enabled: root.canApply
                        onClicked: root.applySelected(root.allMonitors)
                    }
                }
            }
        }
    }
    Component.onCompleted: if (root.wallpapers) root.wallpapers.refresh()
}
