import QtQuick
import Quickshell
import "../../shell/components"
import "../../shell/singletons"

ShellRoot {
    id: root
    property double now: 100000
    property int phase: 0
    property int completions: 0
    readonly property string previewPath: Quickshell.env("FOCUS_PREVIEW_DIR")

    Theme { id: theme }
    FloatingWindow {
        id: preview
        visible: true
        implicitWidth: 768
        implicitHeight: 400
        color: "#262331"
        FocusCard {
            id: card
            anchors.top: parent.top
            anchors.topMargin: 16
            anchors.horizontalCenter: parent.horizontalCenter
            width: implicitWidth
            theme: theme
            session: Focus.session
        }
    }

    Connections {
        target: Focus.session
        function onFinished(wasBreak) { root.completions++; }
    }
    function check(condition, message) {
        if (!condition) throw new Error(message);
    }
    function snapshot(label) {
        if (!previewPath.length) return;
        preview.contentItem.grabToImage(result => {
            root.check(result.saveToFile(root.previewPath + "/focus-" + label + ".png"), "Preview failed");
        });
    }
    function run() {
        try {
            const session = Focus.session;
            if (phase === 0) {
                session.clock = () => root.now;
                Config.setValue("notifications.dnd", false);
                root.snapshot("idle");
            } else if (phase === 1) {
                card.beginEdit();
                card.taskDraft = "Review driver patch";
                card.quietDraft = true;
            } else if (phase === 2) {
                root.snapshot("editor");
            } else if (phase === 3) {
                card.commitEditor();
                root.check(session.status === "running", "Card did not start session");
                root.check(Config.focus.task === session.task, "Task was not saved");
                root.check(Notifications.dnd && !Config.notifications.dnd, "Focus changed saved DND setting");
                Notifications.notify("Suppressed", "Focus test");
                root.check(Notifications.popups.length === 0, "Focus did not suppress popup");
                root.check(Notifications.history.length === 1, "Focus lost notification history");
                Config.setValue("focus.task", "Live task edit");
                root.check(session.task === "Live task edit", "Live task setting stopped updating after start");
                Config.setValue("focus.task", "Review driver patch");
                root.now += 83456;
                session.update();
                card.hovered = true;
            } else if (phase === 4) {
                root.snapshot("running");
                card.enabled = false;
                root.now += 1500000;
                session.update();
                root.check(session.status === "finished" && completions === 1, "Hidden timer did not finish once");
                root.check(!Notifications.dnd, "DND was not restored at completion");
                root.check(Notifications.popups.length === 1, "Completion notification was not shown");
                root.check(Notifications.popups[0].summary === "Focus session finished", "Wrong completion notification");
                card.enabled = true;
                card.hovered = true;
            } else if (phase === 5) {
                root.snapshot("finished");
                session.takeBreak();
                root.check(!Notifications.dnd && session.timeText === "05:00", "Break should allow notifications");
                root.now += 300000;
                session.update();
                session.keepGoing();
                root.check(Notifications.dnd && !Config.notifications.dnd, "Continuation lost chosen quiet option");
                session.end();
                root.check(!Notifications.dnd, "End did not restore DND");
                Config.setValue("notifications.dnd", true);
                session.start("Already quiet", "stopwatch", 25, true);
                session.end();
                root.check(Notifications.dnd && Config.notifications.dnd, "Preexisting DND was lost");
                Config.setValue("notifications.dnd", false);
                session.start("Manual DND", "stopwatch", 25, true);
                Notifications.toggleDnd();
                root.check(!Notifications.dnd && !session.muteNotifications, "Manual DND off was ignored");
                session.end();
                console.log("FOCUS PASS: task persistence/live edits, card startup, hidden timer, completion, DND/history/restoration/continuation/manual override");
                Qt.quit();
            }
            phase++;
        } catch (error) {
            console.error("FOCUS FAIL: " + error);
            Qt.quit();
        }
    }
    Timer { interval: 350; repeat: true; running: true; onTriggered: root.run() }
}
