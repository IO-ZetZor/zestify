pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

Item {
    id: root

    required property var theme
    required property var session
    property real s: 1
    property real backgroundOpacity: 1
    property string defaultMode: "countdown"
    property int defaultMinutes: 25
    property bool defaultDnd: false
    property bool editorOpen: false
    property bool hovered: false
    property string taskDraft: ""
    property string modeDraft: "countdown"
    property string minutesDraft: "25"
    property bool quietDraft: false

    readonly property real restHeight: 54 * s
    readonly property bool editingExisting: session.active || session.status === "finished"
    readonly property bool showControls: !editorOpen && hovered
        && (session.active || session.status === "finished")
    readonly property bool expanded: editorOpen || showControls
    readonly property bool validMinutes: /^\d+$/.test(minutesDraft)
        && Number(minutesDraft) >= 1 && Number(minutesDraft) <= 240
    readonly property bool canCommit: taskDraft.trim().length > 0
        && (editingExisting || modeDraft === "stopwatch" || validMinutes)

    implicitWidth: 360 * s
    implicitHeight: restHeight
    height: editorOpen ? editor.y + editor.implicitHeight + 14 * s
        : showControls ? restHeight + controls.implicitHeight + 12 * s : restHeight
    clip: true

    Behavior on height {
        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
    }

    function beginEdit() {
        taskDraft = session.task;
        modeDraft = session.active || session.status === "finished" ? session.mode : defaultMode;
        minutesDraft = String(session.active ? session.durationMinutes : defaultMinutes);
        quietDraft = defaultDnd;
        editorOpen = true;
        Qt.callLater(() => {
            if (root.editorOpen) {
                taskInput.forceActiveFocus();
                taskInput.selectAll();
            }
        });
    }

    function closeEditor() {
        editorOpen = false;
        taskInput.focus = false;
        minutesInput.focus = false;
    }

    function commitEditor() {
        if (!canCommit)
            return;
        const committed = editingExisting ? session.editTask(taskDraft)
            : session.start(taskDraft, modeDraft, modeDraft === "stopwatch" ? defaultMinutes : Number(minutesDraft), quietDraft);
        if (committed)
            closeEditor();
    }

    function dismiss() {
        closeEditor();
        hovered = false;
        leaveTimer.stop();
    }

    onEnabledChanged: { if (!enabled) dismiss(); }
    Keys.onEscapePressed: event => { root.dismiss(); event.accepted = true; }

    HoverHandler {
        id: cardHover
        onHoveredChanged: {
            if (hovered) {
                leaveTimer.stop();
                root.hovered = true;
            } else {
                leaveTimer.restart();
            }
        }
    }
    Timer {
        id: leaveTimer
        interval: 180
        onTriggered: root.hovered = false
    }

    PillBody {
        anchors.fill: parent
        theme: root.theme
        cornerRadius: 12 * root.s
        backgroundOpacity: root.backgroundOpacity
    }

    Item {
        id: header
        width: parent.width
        height: root.restHeight

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.editorOpen ? root.closeEditor() : root.beginEdit()
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.leftMargin: 14 * root.s
            anchors.rightMargin: 14 * root.s
            anchors.topMargin: 8 * root.s
            anchors.bottomMargin: 8 * root.s
            spacing: 4 * root.s

            RowLayout {
                Layout.fillWidth: true
                spacing: 12 * root.s

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1 * root.s

                    Text {
                        text: root.session.onBreak ? "Break" : root.session.status === "paused" ? "Focus · Paused"
                            : root.session.status === "finished" ? "Focus · Finished"
                            : root.session.active && root.session.mode === "stopwatch" ? "Focus · Stopwatch" : "Focus"
                        color: root.theme.dim
                        font.family: root.theme.fontFamily
                        font.pixelSize: root.theme.fs.label * root.s
                    }
                    Text {
                        objectName: "focusTaskLabel"
                        Layout.fillWidth: true
                        text: root.session.onBreak ? "Take a breath" : root.session.task || "What are you working on?"
                        elide: Text.ElideRight
                        color: root.theme.cream
                        font.family: root.theme.fontFamily
                        font.pixelSize: root.theme.fs.body * root.s
                        font.weight: Font.Medium
                    }
                }

                Text {
                    objectName: "focusTimeLabel"
                    text: root.session.status === "idle" ? "Start" : root.session.timeText
                    color: root.session.status === "paused" ? root.theme.dim : root.theme.accent
                    font.family: root.session.status === "idle" ? root.theme.fontFamily : root.theme.monoFont
                    font.pixelSize: root.theme.fs.title * root.s
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 2 * root.s
                radius: height / 2
                color: root.theme.withAlpha(root.theme.outline, 0.22)
                Rectangle {
                    width: parent.width * root.session.progress
                    height: parent.height
                    radius: parent.radius
                    color: root.session.status === "paused" ? root.theme.dim : root.theme.accent
                    Behavior on width { NumberAnimation { duration: 180 } }
                }
            }
        }
    }

    component Action: Rectangle {
        id: action
        property string text: ""
        property bool primary: false
        property bool selected: false
        signal clicked()
        implicitWidth: label.implicitWidth + 18 * root.s
        implicitHeight: 27 * root.s
        radius: 7 * root.s
        color: primary || selected ? root.theme.accent
            : root.theme.withAlpha(root.theme.outline, actionHover.hovered ? 0.28 : 0.14)
        opacity: enabled ? 1 : 0.4
        activeFocusOnTab: true
        border.width: activeFocus ? 1 : 0
        border.color: root.theme.accent
        Text {
            id: label
            anchors.centerIn: parent
            text: action.text
            color: action.primary || action.selected ? root.theme.onAccent : root.theme.cream
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.fs.meta * root.s
        }
        HoverHandler { id: actionHover; cursorShape: Qt.PointingHandCursor }
        MouseArea { anchors.fill: parent; onClicked: action.clicked() }
        Keys.onSpacePressed: action.clicked()
        Keys.onReturnPressed: action.clicked()
        Keys.onEnterPressed: action.clicked()
    }

    RowLayout {
        id: controls
        x: 14 * root.s
        y: root.restHeight
        width: parent.width - 28 * root.s
        visible: root.showControls
        spacing: 6 * root.s

        Action {
            objectName: "focusPause"
            visible: root.session.active
            text: root.session.status === "paused" ? "Resume" : "Pause"
            onClicked: root.session.status === "paused" ? root.session.resume() : root.session.pause()
        }
        Action {
            objectName: "focusBreak"
            visible: root.session.status === "finished" && !root.session.onBreak
            text: "Take a break"
            onClicked: root.session.takeBreak()
        }
        Action {
            objectName: "focusContinue"
            visible: root.session.status === "finished"
            text: root.session.onBreak ? "Start focus" : "Keep going"
            primary: true
            onClicked: root.session.keepGoing()
        }
        Action {
            objectName: "focusEdit"
            text: "Edit"
            onClicked: root.beginEdit()
        }
        Item { Layout.fillWidth: true }
        Action {
            objectName: "focusEnd"
            text: "End"
            onClicked: { root.session.end(); root.dismiss(); }
        }
    }

    ColumnLayout {
        id: editor
        x: 14 * root.s
        y: root.restHeight + 4 * root.s
        width: parent.width - 28 * root.s
        visible: root.editorOpen
        spacing: 10 * root.s

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 34 * root.s
            radius: 7 * root.s
            color: root.theme.withAlpha(root.theme.surfaceHighest, 0.65)
            border.width: taskInput.activeFocus ? 1 : 0
            border.color: root.theme.accent
            Text {
                anchors.fill: parent
                anchors.margins: 8 * root.s
                verticalAlignment: Text.AlignVCenter
                visible: !taskInput.text.length
                text: "One thing to focus on…"
                color: root.theme.faint
                font.family: root.theme.fontFamily
                font.pixelSize: root.theme.fs.body * root.s
            }
            TextInput {
                id: taskInput
                objectName: "focusTaskInput"
                anchors.fill: parent
                anchors.margins: 8 * root.s
                verticalAlignment: TextInput.AlignVCenter
                text: root.taskDraft
                maximumLength: 200
                selectByMouse: true
                clip: true
                color: root.theme.cream
                selectionColor: root.theme.accent
                selectedTextColor: root.theme.onAccent
                font.family: root.theme.fontFamily
                font.pixelSize: root.theme.fs.body * root.s
                onTextEdited: root.taskDraft = text
                onAccepted: root.commitEditor()
            }
        }

        RowLayout {
            visible: !root.editingExisting
            spacing: 6 * root.s
            Action {
                objectName: "focusCountdown"
                text: "Countdown"
                selected: root.modeDraft === "countdown"
                onClicked: root.modeDraft = "countdown"
            }
            Action {
                objectName: "focusStopwatch"
                text: "Stopwatch"
                selected: root.modeDraft === "stopwatch"
                onClicked: root.modeDraft = "stopwatch"
            }
        }

        RowLayout {
            visible: !root.editingExisting && root.modeDraft === "countdown"
            spacing: 6 * root.s
            Action {
                objectName: "focus25"
                text: "25 min"
                selected: root.minutesDraft === "25"
                onClicked: root.minutesDraft = "25"
            }
            Action {
                objectName: "focus50"
                text: "50 min"
                selected: root.minutesDraft === "50"
                onClicked: root.minutesDraft = "50"
            }
            Rectangle {
                Layout.preferredWidth: 46 * root.s
                Layout.preferredHeight: 27 * root.s
                radius: 7 * root.s
                color: root.theme.withAlpha(root.theme.outline, 0.14)
                border.width: minutesInput.activeFocus || !root.validMinutes ? 1 : 0
                border.color: root.validMinutes ? root.theme.accent : root.theme.danger
                TextInput {
                    id: minutesInput
                    objectName: "focusMinutesInput"
                    anchors.fill: parent
                    anchors.margins: 5 * root.s
                    verticalAlignment: TextInput.AlignVCenter
                    horizontalAlignment: TextInput.AlignHCenter
                    text: root.minutesDraft
                    maximumLength: 3
                    validator: IntValidator { bottom: 1; top: 240 }
                    selectByMouse: true
                    color: root.theme.cream
                    font.family: root.theme.monoFont
                    font.pixelSize: root.theme.fs.meta * root.s
                    onTextEdited: root.minutesDraft = text
                    onAccepted: root.commitEditor()
                }
            }
            Text {
                text: "min"
                color: root.theme.dim
                font.family: root.theme.fontFamily
                font.pixelSize: root.theme.fs.meta * root.s
            }
        }

        Action {
            objectName: "focusQuiet"
            visible: !root.editingExisting
            text: (root.quietDraft ? "✓ " : "") + "Do not disturb during focus"
            selected: root.quietDraft
            onClicked: root.quietDraft = !root.quietDraft
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6 * root.s
            Action {
                objectName: "focusCancel"
                text: "Cancel"
                onClicked: root.closeEditor()
            }
            Item { Layout.fillWidth: true }
            Action {
                objectName: "focusStart"
                text: root.editingExisting ? "Save task" : "Start focus"
                primary: true
                enabled: root.canCommit
                onClicked: root.commitEditor()
            }
        }
    }
}
