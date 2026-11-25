import QtQuick
import QtTest
import "../../shell/components"

Item {
    width: 500
    height: 500
    Rectangle { id: backdrop; anchors.fill: parent; color: "#557799" }
    QtObject {
        id: motion
        property bool calm: false
    }
    UnlockFade { id: curtain; anchors.fill: parent; motion: motion; duration: 200 }

    TestCase {
        name: "UnlockFade"
        when: windowShown
        SignalSpy { id: done; target: curtain; signalName: "finished" }
        function init() { curtain.reset(); motion.calm = false; done.clear(); }
        function prepare() {
            verify(backdrop.grabToImage(result => curtain.prepare(result, 7)));
            tryCompare(curtain, "ready", true);
            verify(curtain.active);
            compare(curtain.serial, 7);
        }
        function test_prepared_frame_stays_still_until_release() {
            prepare();
            wait(100);
            compare(curtain.progress, 0);
            compare(findChild(curtain, "unlockFadeImage").y, 0);
            compare(done.count, 0);
        }
        function test_fades_to_desktop_and_releases_capture() {
            prepare();
            curtain.reveal();
            wait(60);
            verify(curtain.progress > 0 && curtain.progress < 1);
            const image = findChild(curtain, "unlockFadeImage");
            compare(image.y, 0);
            verify(image.opacity > 0 && image.opacity < 1);
            tryCompare(done, "count", 1);
            verify(!curtain.active);
            compare(curtain.frame, null);
            compare(curtain.progress, 0);
        }
        function test_relock_cancels_reveal_without_completion() {
            prepare();
            curtain.reveal();
            wait(60);
            curtain.reset();
            wait(200);
            compare(done.count, 0);
            verify(!curtain.active);
        }
        function test_calm_motion_finishes_immediately() {
            prepare();
            motion.calm = true;
            curtain.reveal();
            tryCompare(done, "count", 1);
            verify(!curtain.active);
        }
    }
}
