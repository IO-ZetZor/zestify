pragma Singleton

import Quickshell
import QtQuick
import "../components"
import "."

Singleton {
    readonly property alias session: focusSession
    readonly property bool suppressNotifications: focusSession.suppressNotifications

    FocusSession {
        id: focusSession
        Component.onCompleted: task = Config.focus.task
        onTaskSaved: text => Config.setValue("focus.task", text)
        onFinished: wasBreak => Notifications.notify(
            wasBreak ? "Break finished" : "Focus session finished",
            wasBreak ? "Ready when you are: " + task : task + " — take a break or keep going.",
            "normal", "Zestify Focus", 8000)
    }

    Connections {
        target: Config
        function onRevisionChanged() {
            focusSession.task = Config.focus.task;
        }
    }
}
