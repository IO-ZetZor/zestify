pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

SurfaceFrame {
    id: root

    property var apps
    property var screen
    property var motion
    property alias query: search.text

    readonly property var filtered: {
        const source = apps && apps.items ? apps.items : [];
        const needle = String(query).trim().toLowerCase();
        if (needle.length === 0)
            return source;
        return source.filter(function(app) {
            if (app.name.toLowerCase().indexOf(needle) >= 0)
                return true;
            if (app.comment && app.comment.toLowerCase().indexOf(needle) >= 0)
                return true;
            for (let i = 0; i < app.categories.length; i++) {
                if (app.categories[i].toLowerCase().indexOf(needle) >= 0)
                    return true;
            }
            return false;
        });
    }

    property int selectedIndex: 0

    function iconFor(app) {
        if (app && app.icon && Quickshell.hasThemeIcon(app.icon))
            return Quickshell.iconPath(app.icon);
        if (Quickshell.hasThemeIcon("application-x-executable"))
            return Quickshell.iconPath("application-x-executable");
        return "";
    }

    function launchSelected() {
        const list = root.filtered;
        if (root.selectedIndex < 0 || root.selectedIndex >= list.length)
            return;
        const app = list[root.selectedIndex];
        root.closeRequested();
        if (root.apps)
            root.apps.launch(app);
    }

    function moveSelection(delta) {
        if (root.filtered.length === 0)
            return;
        root.selectedIndex = Math.max(0, Math.min(root.filtered.length - 1, root.selectedIndex + delta));
        appList.positionViewAtIndex(root.selectedIndex, ListView.Contain);
    }

    title: "Launcher"

    onFilteredChanged: {
        if (root.selectedIndex >= root.filtered.length)
            root.selectedIndex = Math.max(0, root.filtered.length - 1);
    }

    Component.onCompleted: {
        if (root.apps)
            root.apps.refresh();
        search.forceActiveFocus();
    }

    Timer {
        interval: 80
        running: true
        onTriggered: search.forceActiveFocus()
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: root.theme.sp.m * root.s

        TextField {
            id: search
            Layout.fillWidth: true
            Layout.preferredHeight: 32 * root.s
            placeholderText: "Search applications"
            placeholderTextColor: root.theme.faint
            color: root.theme.cream
            selectionColor: root.theme.accent
            selectedTextColor: root.theme.onAccent
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.fs.body * root.s
            leftPadding: 10 * root.s
            rightPadding: 10 * root.s
            verticalAlignment: TextInput.AlignVCenter
            selectByMouse: true
            background: Rectangle {
                radius: root.theme.r.s * root.s
                color: root.theme.withAlpha(root.theme.surfaceHigh, 0.6)
                border.width: 1
                border.color: root.theme.withAlpha(root.theme.outline, 0.5)
            }

            Keys.onPressed: (event) => {
                if (event.key === Qt.Key_Down) {
                    root.moveSelection(1);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Up) {
                    root.moveSelection(-1);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Escape) {
                    root.closeRequested();
                    event.accepted = true;
                }
            }
            onAccepted: root.launchSelected()
        }

        ListView {
            id: appList
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: root.filtered
            currentIndex: root.selectedIndex
            boundsBehavior: Flickable.StopAtBounds
            spacing: 2 * root.s

            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
            }

            delegate: Item {
                id: row
                required property var modelData
                required property int index

                width: appList.width
                height: 38 * root.s

                Rectangle {
                    anchors.fill: parent
                    radius: root.theme.r.s * root.s
                    color: row.index === root.selectedIndex
                        ? root.theme.withAlpha(root.theme.accent, 0.16)
                        : "transparent"
                }

                TapHandler {
                    onTapped: {
                        root.selectedIndex = row.index;
                        root.launchSelected();
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8 * root.s
                    anchors.rightMargin: 8 * root.s
                    spacing: root.theme.sp.m * root.s

                    Item {
                        Layout.preferredWidth: 24 * root.s
                        Layout.preferredHeight: 24 * root.s

                        Image {
                            id: appIcon
                            anchors.fill: parent
                            source: root.iconFor(row.modelData)
                            visible: source.toString().length > 0
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: !appIcon.visible
                            text: "󰀻"
                            color: root.theme.iconDim
                            font.family: root.theme.iconFont
                            font.pixelSize: 22 * root.s
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1 * root.s

                        Text {
                            Layout.fillWidth: true
                            text: row.modelData.name
                            color: root.theme.cream
                            elide: Text.ElideRight
                            font.family: root.theme.fontFamily
                            font.pixelSize: root.theme.fs.body * root.s
                        }

                        Text {
                            Layout.fillWidth: true
                            text: row.modelData.comment || row.modelData.categories.join(" · ")
                            color: root.theme.faint
                            elide: Text.ElideRight
                            visible: text.length > 0
                            font.family: root.theme.fontFamily
                            font.pixelSize: root.theme.fs.meta * root.s
                        }
                    }
                }
            }
        }

        Text {
            Layout.fillWidth: true
            visible: root.filtered.length === 0
            text: "No applications found"
            color: root.theme.faint
            horizontalAlignment: Text.AlignHCenter
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.fs.meta * root.s
        }

        Text {
            Layout.fillWidth: true
            text: "Enter to launch  ·  Esc to close"
            color: root.theme.faint
            horizontalAlignment: Text.AlignRight
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.fs.label * root.s
        }
    }
}
