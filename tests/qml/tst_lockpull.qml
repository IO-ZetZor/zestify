import QtQuick
import QtTest
import "../../shell/components"

Item {
    width: 500
    height: 500

    LockPull {
        id: gesture
        anchors.fill: parent
        wallpaper: Component { Rectangle { color: "#334455" } }
    }

    Image {
        id: handoffPreview
        width: 500
        height: 500
        visible: false
        asynchronous: false
    }

    TestCase {
        name: "LockPull"
        when: windowShown

        SignalSpy {
            id: lockSpy
            target: gesture
            signalName: "lockRequested"
        }

        SignalSpy {
            id: timeoutSpy
            target: gesture
            signalName: "lockTimedOut"
        }

        function init() {
            gesture.enabled = true;
            gesture.lockTimeout = 40000;
            gesture.reset();
            handoffPreview.source = "";
            handoffPreview.visible = false;
            lockSpy.clear();
            timeoutSpy.clear();
        }

        function pullTo(y) {
            mousePress(gesture, 250, 1, Qt.LeftButton);
            mouseMove(gesture, 250, y, 10, Qt.LeftButton);
        }

        function test_movement_without_press_does_not_start() {
            mouseMove(gesture, 250, 1);
            mouseMove(gesture, 250, 490);
            verify(!gesture.active);
            compare(lockSpy.count, 0);
        }

        function test_wallpaper_exists_only_during_the_gesture() {
            const loader = findChild(gesture, "lockPullWallpaper");
            const blur = findChild(gesture, "lockPullBlur");
            verify(!blur.active);
            compare(blur.item, null);
            verify(!loader.active);
            compare(loader.item, null);
            pullTo(80);
            verify(loader.active);
            verify(loader.item !== null);
            verify(blur.item !== null);
            mouseRelease(gesture, 250, 80, Qt.LeftButton);
            tryCompare(gesture, "active", false);
            compare(loader.item, null);
            compare(blur.item, null);
        }

        function test_press_away_from_edge_does_not_start() {
            mousePress(gesture, 250, 40, Qt.LeftButton);
            mouseMove(gesture, 250, 490, 10, Qt.LeftButton);
            mouseRelease(gesture, 250, 490, Qt.LeftButton);
            verify(!gesture.active);
            compare(lockSpy.count, 0);
        }

        function test_right_button_does_not_start() {
            mousePress(gesture, 250, 1, Qt.RightButton);
            mouseMove(gesture, 250, 490, 10, Qt.RightButton);
            mouseRelease(gesture, 250, 490, Qt.RightButton);
            verify(!gesture.active);
            compare(lockSpy.count, 0);
        }

        function test_short_pull_follows_pointer_and_returns() {
            pullTo(80);
            verify(gesture.dragging);
            compare(gesture.pull, 79);
            compare(lockSpy.count, 0);
            mouseRelease(gesture, 250, 80, Qt.LeftButton);
            tryCompare(gesture, "active", false);
            compare(gesture.pull, 0);
            compare(lockSpy.count, 0);
        }

        function test_threshold_pull_drops_on_release_then_locks_once() {
            pullTo(gesture.triggerDistance + 1);
            verify(gesture.ready);
            compare(lockSpy.count, 0);
            mouseRelease(gesture, 250, gesture.triggerDistance + 1, Qt.LeftButton);
            compare(lockSpy.count, 0);
            verify(gesture.requestingLock);
            verify(gesture.pull < gesture.height);
            verify(gesture.handoffProgress < 1);
            wait(100);
            verify(gesture.handoffProgress > 0 && gesture.handoffProgress < 1);
            tryCompare(lockSpy, "count", 1);
            tryCompare(gesture, "pull", 500);
            compare(gesture.handoffProgress, 1);
            mouseClick(gesture, 250, 1, Qt.LeftButton);
            compare(lockSpy.count, 1);
        }

        function test_drag_keeps_following_beyond_threshold_without_dropping() {
            pullTo(gesture.triggerDistance + 1);
            wait(500);
            compare(gesture.pull, gesture.triggerDistance);
            verify(!gesture.requestingLock);
            mouseMove(gesture, 250, 400, 10, Qt.LeftButton);
            compare(gesture.pull, 399);
            compare(gesture.handoffProgress, 0);
            wait(500);
            compare(gesture.pull, 399);
            compare(lockSpy.count, 0);
            mouseRelease(gesture, 250, 400, Qt.LeftButton);
            tryCompare(lockSpy, "count", 1);
        }

        function test_handoff_retains_background_after_curtain_is_reset() {
            pullTo(490);
            mouseRelease(gesture, 250, 490, Qt.LeftButton);
            tryCompare(lockSpy, "count", 1);
            const frame = lockSpy.signalArguments[0][0];
            verify(frame !== null);
            handoffPreview.source = frame.url;
            compare(handoffPreview.status, Image.Ready);
            handoffPreview.visible = true;
            verify(waitForRendering(handoffPreview));
            const background = grabImage(handoffPreview);
            gesture.reset();
            verify(waitForRendering(handoffPreview));
            const retained = grabImage(handoffPreview);
            for (let y = 20; y < 500; y += 40)
                for (let x = 20; x < 500; x += 40) {
                    compare(retained.red(x, y), background.red(x, y));
                    compare(retained.green(x, y), background.green(x, y));
                    compare(retained.blue(x, y), background.blue(x, y));
                }
        }

        function test_reset_discards_pending_handoff() {
            pullTo(490);
            gesture.requestingLock = true;
            gesture.pull = gesture.height;
            gesture.handoffProgress = 1;
            gesture.handOff();
            gesture.reset();
            wait(100);
            compare(lockSpy.count, 0);
        }

        function test_pulling_back_up_cancels_even_after_bottom() {
            pullTo(490);
            mouseMove(gesture, 250, 80, 10, Qt.LeftButton);
            verify(!gesture.ready);
            mouseRelease(gesture, 250, 80, Qt.LeftButton);
            tryCompare(gesture, "active", false);
            compare(lockSpy.count, 0);
        }

        function test_escape_cancels_while_button_held() {
            pullTo(490);
            keyClick(Qt.Key_Escape);
            verify(!gesture.dragging);
            mouseRelease(gesture, 250, 490, Qt.LeftButton);
            tryCompare(gesture, "active", false);
            compare(lockSpy.count, 0);
        }

        function test_external_lock_or_dpms_cancels_drag() {
            pullTo(490);
            gesture.enabled = false;
            mouseRelease(gesture, 250, 490, Qt.LeftButton);
            verify(!gesture.active);
            compare(lockSpy.count, 0);
        }

        function test_unavailable_locker_restores_input() {
            gesture.lockTimeout = 100;
            pullTo(490);
            mouseRelease(gesture, 250, 490, Qt.LeftButton);
            tryCompare(lockSpy, "count", 1);
            tryCompare(timeoutSpy, "count", 1);
            verify(!gesture.active);
            verify(!gesture.requestingLock);
            compare(gesture.pull, 0);
            compare(gesture.handoffProgress, 0);
        }
    }
}
