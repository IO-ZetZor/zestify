import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import "../../shell/components"
import "../../shell/singletons"

ShellRoot {
    Window {
        visible: true
        width: 400
        height: 400
        color: fixtureTheme.surface
        Theme { id: fixtureTheme }
        ShortcutDrawer {
            id: drawer
            anchors.fill: parent
            theme: fixtureTheme
            recording: Capture.recording
            ShortcutActions {
                id: icons
                anchors.fill: parent
                theme: fixtureTheme
                recording: Capture.recording
            }
        }
        Process {
            id: externalStop
            command: [Session.cli, "test-stop-recording"]
        }
        TestCase {
            id: tests
            name: "CaptureUI"
            when: false
            optional: true
            function exercise() {
                Notifications.clear();
                if (Quickshell.env("CAPTURE_MISSING_BACKEND") === "1") {
                    verify(Capture.run("screenshot"));
                    tryCompare(Capture, "busy", false, 3000);
                    tryVerify(() => Notifications.history.length > 0, 3000);
                    compare(Notifications.history[0].summary, "Capture failed");
                    verify(Notifications.history[0].body.includes("Could not start"));
                    savePreview();
                    return;
                }
                externalStop.command = [Session.cli, "test-start-recording"];
                externalStop.running = true;
                tryCompare(externalStop, "running", false, 3000);
                tryCompare(Capture, "recording", true, 3000);
                compare(Notifications.history[0].summary, "Recording started");
                verify(Capture.run("record"));
                tryCompare(Capture, "busy", false, 3000);
                tryCompare(Capture, "recording", false, 3000);
                verify(Capture.run("screenshot"));
                verify(!Capture.run("record"), "Capture commands must be serialized");
                tryCompare(Capture, "busy", false, 3000);
                compare(Notifications.history[0].summary, "Screenshot taken");
                verify(Notifications.history[0].body.includes("clipboard"));
                const successCount = Notifications.history.length;
                verify(Capture.run("screenshot"));
                tryCompare(Capture, "busy", false, 3000);
                compare(Notifications.history.length, successCount, "Cancellation must not announce success");
                verify(Capture.run("screenshot"));
                tryCompare(Capture, "busy", false, 3000);
                compare(Notifications.history[0].summary, "Capture failed");
                verify(Notifications.history[0].body.includes("synthetic failure"));
                verify(Capture.run("record"));
                tryCompare(Capture, "busy", false, 3000);
                tryCompare(Capture, "recording", true, 3000);
                compare(Notifications.history[0].summary, "Recording started");
                verify(findChild(drawer, "shortcutRecordingIndicator").visible);
                drawer.open();
                tryCompare(drawer, "settling", false, 1500);
                const record = findChild(icons, "shortcut-record");
                verify(record.recordingAction);
                compare(record.Accessible.name, "Stop screen recording");
                verify(Capture.run("record"));
                tryCompare(Capture, "busy", false, 3000);
                tryCompare(Capture, "recording", false, 3000);
                compare(Notifications.history[0].summary, "Recording stopped");
                verify(Notifications.history[0].body.includes("recording.mp4"));
                verify(!record.recordingAction);
                verify(Capture.run("record"));
                tryCompare(Capture, "recording", true, 3000);
                tryCompare(Capture, "busy", false, 3000);
                externalStop.command = [Session.cli, "test-stop-recording"];
                externalStop.running = true;
                tryCompare(externalStop, "running", false, 3000);
                tryCompare(Capture, "recording", false, 3000);
                compare(Notifications.history[0].summary, "Recording stopped");
                verify(Notifications.history[0].body.includes("unexpectedly"));
                verify(Capture.run("record"));
                tryCompare(Capture, "recording", true, 3000);
                tryCompare(Capture, "busy", false, 3000);
                externalStop.command = [Session.cli, "test-fail-next-stop"];
                externalStop.running = true;
                tryCompare(externalStop, "running", false, 3000);
                const beforeFailure = Notifications.history.length;
                verify(Capture.run("record"));
                tryCompare(Capture, "busy", false, 3000);
                tryCompare(Capture, "recording", false, 3000);
                const newMessages = Notifications.history.slice(0, Notifications.history.length - beforeFailure);
                verify(newMessages.some(entry => entry.summary === "Capture failed"));
                verify(newMessages.every(entry => !entry.body.includes("Video saved")),
                    "An unsuccessful stop must not claim the video was saved");
                verify(Capture.run("record"));
                tryCompare(Capture, "recording", true, 3000);
                tryCompare(Capture, "busy", false, 3000);
                savePreview();
            }
            function savePreview() {
                drawer.grabToImage(result => {
                    if (!result.saveToFile(Quickshell.env("CAPTURE_UI_PREVIEW"))) {
                        console.error("CAPTURE UI FAIL: preview was not saved");
                        Qt.exit(1);
                    } else {
                        console.log("CAPTURE UI PASS: screenshot feedback, recording state and capture failures");
                        Qt.quit();
                    }
                });
            }
        }
        Timer {
            interval: 200
            running: true
            onTriggered: {
                try { tests.exercise(); }
                catch (error) { console.error("CAPTURE UI FAIL:", error); Qt.exit(1); }
            }
        }
    }
}
