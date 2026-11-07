pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../lib/calendar.js" as Calendar

SurfaceFrame {
    id: root

    property var screen
    property var motion
    property var events: []
    property date now: new Date()

    property int viewYear: now.getFullYear()
    property int viewMonth: now.getMonth() + 1
    property string selectedDate: root.isoFromDate(root.now)

    readonly property string eventsPath: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/zestify/events.json"
    readonly property var grid: Calendar.monthGrid(viewYear, viewMonth)
    readonly property var cells: Calendar.flattenGrid(grid)
    readonly property var dayEvents: Calendar.eventsFor(selectedDate, events)

    title: "Calendar"

    function pad(value) {
        return value < 10 ? "0" + value : "" + value;
    }

    function iso(year, month, day) {
        return year + "-" + pad(month) + "-" + pad(day);
    }

    function isoFromDate(date) {
        return iso(date.getFullYear(), date.getMonth() + 1, date.getDate());
    }

    function isToday(day) {
        return root.selectedDate === root.iso(root.viewYear, root.viewMonth, day);
    }

    function isActualToday(day) {
        return root.isoFromDate(root.now) === root.iso(root.viewYear, root.viewMonth, day);
    }

    function previousMonth() {
        if (root.viewMonth === 1) {
            root.viewMonth = 12;
            root.viewYear -= 1;
        } else {
            root.viewMonth -= 1;
        }
        root.selectedDate = root.iso(root.viewYear, root.viewMonth, 1);
    }

    function nextMonth() {
        if (root.viewMonth === 12) {
            root.viewMonth = 1;
            root.viewYear += 1;
        } else {
            root.viewMonth += 1;
        }
        root.selectedDate = root.iso(root.viewYear, root.viewMonth, 1);
    }

    function goToday() {
        root.now = new Date();
        root.viewYear = root.now.getFullYear();
        root.viewMonth = root.now.getMonth() + 1;
        root.selectedDate = root.isoFromDate(root.now);
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8 * root.s

        RowLayout {
            Layout.fillWidth: true
            spacing: 4 * root.s

            Rectangle {
                Layout.preferredWidth: 26 * root.s
                Layout.preferredHeight: 26 * root.s
                radius: 7 * root.s
                color: previousArea.containsMouse ? root.theme.withAlpha(root.theme.cream, 0.06) : "transparent"

                Text {
                    anchors.centerIn: parent
                    text: "󰁍"
                    color: root.theme.dim
                    font.family: root.theme.iconFont
                    font.pixelSize: 13 * root.s
                }

                MouseArea {
                    id: previousArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.previousMonth()
                }
            }

            Text {
                Layout.fillWidth: true
                text: Qt.formatDate(new Date(root.viewYear, root.viewMonth - 1, 1), "MMMM yyyy")
                color: root.theme.cream
                font.family: root.theme.fontFamily
                font.pixelSize: root.theme.fs.title * root.s
                font.weight: Font.Medium
                horizontalAlignment: Text.AlignHCenter
            }

            Rectangle {
                Layout.preferredWidth: 26 * root.s
                Layout.preferredHeight: 26 * root.s
                radius: 7 * root.s
                color: nextArea.containsMouse ? root.theme.withAlpha(root.theme.cream, 0.06) : "transparent"

                Text {
                    anchors.centerIn: parent
                    text: "󰁔"
                    color: root.theme.dim
                    font.family: root.theme.iconFont
                    font.pixelSize: 13 * root.s
                }

                MouseArea {
                    id: nextArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.nextMonth()
                }
            }

            Rectangle {
                Layout.preferredWidth: todayLabel.implicitWidth + 14 * root.s
                Layout.preferredHeight: 26 * root.s
                radius: 7 * root.s
                color: todayArea.containsMouse ? root.theme.withAlpha(root.theme.accent, 0.18) : "transparent"
                border.width: 1
                border.color: root.theme.hairline

                Text {
                    id: todayLabel
                    anchors.centerIn: parent
                    text: "Today"
                    color: root.theme.dim
                    font.family: root.theme.fontFamily
                    font.pixelSize: root.theme.fs.meta * root.s
                }

                MouseArea {
                    id: todayArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.goToday()
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 0

            Repeater {
                model: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

                delegate: Text {
                    required property string modelData
                    Layout.fillWidth: true
                    text: modelData
                    color: root.theme.faint
                    font.family: root.theme.fontFamily
                    font.pixelSize: root.theme.fs.label * root.s
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 7
            rowSpacing: 2 * root.s
            columnSpacing: 2 * root.s

            Repeater {
                model: root.cells

                delegate: Rectangle {
                    required property var modelData

                    Layout.fillWidth: true
                    Layout.preferredHeight: 29 * root.s
                    radius: 6 * root.s
                    color: {
                        if (modelData === 0)
                            return "transparent";
                        if (root.isToday(modelData))
                            return root.theme.accent;
                        if (root.isActualToday(modelData))
                            return root.theme.withAlpha(root.theme.accent, 0.14);
                        return dayArea.containsMouse ? root.theme.withAlpha(root.theme.cream, 0.06) : "transparent";
                    }
                    border.width: modelData !== 0 && root.isActualToday(modelData) && !root.isToday(modelData) ? 1 : 0
                    border.color: root.theme.withAlpha(root.theme.accent, 0.5)

                    Text {
                        anchors.centerIn: parent
                        visible: modelData !== 0
                        text: modelData
                        color: root.isToday(modelData)
                            ? root.theme.onAccent
                            : (root.isActualToday(modelData) ? root.theme.accent : root.theme.cream)
                        font.family: root.theme.monoFont
                        font.pixelSize: root.theme.fs.meta * root.s
                    }

                    MouseArea {
                        id: dayArea
                        anchors.fill: parent
                        enabled: modelData !== 0
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.selectedDate = root.iso(root.viewYear, root.viewMonth, modelData)
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: root.theme.hairline
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6 * root.s

            Text {
                Layout.fillWidth: true
                text: root.selectedDate
                color: root.theme.cream
                font.family: root.theme.fontFamily
                font.pixelSize: root.theme.fs.title * root.s
                font.weight: Font.Medium
            }

            Text {
                text: root.dayEvents.length + (root.dayEvents.length === 1 ? " event" : " events")
                color: root.theme.faint
                font.family: root.theme.fontFamily
                font.pixelSize: root.theme.fs.meta * root.s
            }
        }

        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 3 * root.s
            clip: true
            model: root.dayEvents

            delegate: Rectangle {
                required property var modelData

                width: ListView.view.width
                height: 28 * root.s
                radius: 6 * root.s
                color: root.theme.tileBg

                Text {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: root.theme.sp.m * root.s
                    anchors.rightMargin: root.theme.sp.m * root.s
                    text: modelData.title || "Untitled event"
                    color: root.theme.cream
                    font.family: root.theme.fontFamily
                    font.pixelSize: root.theme.fs.meta * root.s
                    elide: Text.ElideRight
                }
            }

            Text {
                anchors.centerIn: parent
                visible: root.dayEvents.length === 0
                text: "No events"
                color: root.theme.faint
                font.family: root.theme.fontFamily
                font.pixelSize: root.theme.fs.body * root.s
            }
        }
    }

    FileView {
        id: eventsFile
        path: root.eventsPath
        watchChanges: true
        blockLoading: true
        printErrors: false
        onLoaded: {
            try {
                const data = JSON.parse(text());
                root.events = Array.isArray(data)
                    ? data
                    : (data && Array.isArray(data.events) ? data.events : []);
            } catch (error) {
                root.events = [];
            }
        }
        onLoadFailed: root.events = []
        onFileChanged: reload()
    }

    Timer {
        interval: 60000
        repeat: true
        running: true
        onTriggered: root.now = new Date()
    }
}
