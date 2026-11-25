import QtQuick
import QtTest
import "../../shell/components"

Item {
    id: fixture
    width: 1000
    height: 700

    Theme { id: fixtureTheme }
    QtObject { id: motion; property bool calm: false }
    PowerDrawer {
        id: drawer
        anchors.fill: parent
        theme: fixtureTheme
        PowerPortrait {
            id: portrait
            x: 200
            y: 40
            width: 92
            height: 92
            theme: fixtureTheme
            motion: motion
        }
    }

    TestCase {
        name: "PowerPortrait"
        when: windowShown

        function init() {
            drawer.enabled = true;
            drawer.reset();
            drawer.open();
            tryCompare(drawer, "settling", false, 1500);
            portrait.resetImmediately();
            portrait.s = 1;
            portrait.width = 92;
            portrait.height = 92;
            motion.calm = false;
            portrait.motion = motion;
            mouseMove(fixture, 900, 100);
        }

        function test_full_resolution_playback_and_scaled_texture() {
            const animation = findChild(portrait, "powerRemAnimation");
            tryCompare(animation, "status", Image.Ready);
            verify(animation.sourceSize.width >= 1280);
            verify(animation.sourceSize.height >= 716);
            verify(animation.frameCount > 1);
            verify(animation.playing);
            portrait.s = 1.25;
            portrait.width = 115;
            portrait.height = 115;
            verify(portrait.textureResolution >= 460);
            compare(animation.sourceSize.width, 1280);
            verify(animation.width >= portrait.textureResolution);
            verify(!animation.cache);
            motion.calm = true;
            verify(!animation.playing);
            // Reduced motion pauses playback without disabling manual rotation.
            portrait.forceActiveFocus();
            keyClick(Qt.Key_Right);
            compare(portrait.angle, 180);
            verify(!portrait.settling);
        }

        function test_optional_motion_service() {
            portrait.motion = undefined;
            verify(!portrait.calm);
            verify(findChild(portrait, "powerRemAnimation").playing);
            portrait.forceActiveFocus();
            keyClick(Qt.Key_Right);
            verify(portrait.settling);
            tryCompare(portrait, "settling", false, 1000);
            compare(portrait.angle, 180);
        }

        function test_closed_drawer_releases_animation_and_reopens() {
            const animation = findChild(portrait, "powerRemAnimation");
            tryCompare(animation, "status", Image.Ready);
            drawer.reset();
            compare(animation.source.toString(), "");
            compare(animation.status, Image.Null);
            verify(!animation.playing);
            drawer.open();
            tryCompare(animation, "status", Image.Ready);
            verify(animation.frameCount > 1);
            verify(animation.playing);
        }

        function test_side_to_side_full_turn_and_release_outside() {
            const grip = findChild(portrait, "powerRemGrip");
            const center = portrait.width / 2;
            mousePress(grip, center, center);
            verify(portrait.dragging);
            mouseMove(grip, portrait.width, center, 20, Qt.LeftButton);
            compare(portrait.angle, 90);
            mouseMove(grip, portrait.width * 2, center, 20, Qt.LeftButton);
            compare(portrait.angle, 270);
            mouseMove(grip, 0, center, 20, Qt.LeftButton);
            compare(portrait.angle, -90);
            mouseMove(grip, -center, center + 30, 20, Qt.LeftButton);
            compare(portrait.angle, -180);
            compare(drawer.pull, drawer.drawerHeight);
            verify(!drawer.dragging);
            mouseRelease(grip, -center, center + 30);
            verify(!portrait.dragging);
            tryCompare(portrait, "settling", false, 1000);
            compare(portrait.angle, 180);
            verify(drawer.opened);

            // The fixed input area can grab an edge-on portrait again.
            portrait.angle = 90;
            mousePress(grip, center, center);
            mouseMove(grip, 0, center, 20, Qt.LeftButton);
            mouseRelease(grip, 0, center);
            compare(portrait.angle, 0);
        }

        function test_release_snaps_to_nearest_face_data() {
            return [
                {tag: "front-right", angle: 60, face: 0},
                {tag: "back-right", angle: 120, face: 180},
                {tag: "past-back", angle: 245, face: 180},
                {tag: "full-turn-right", angle: 300, face: 0},
                {tag: "front-left", angle: -60, face: 0},
                {tag: "back-left", angle: -120, face: 180},
                {tag: "past-back-left", angle: -245, face: 180},
                {tag: "full-turn-left", angle: -300, face: 0},
                {tag: "beyond-full-turn", angle: 390, face: 0},
                {tag: "beyond-negative-turn", angle: -390, face: 0}
            ];
        }

        function test_release_snaps_to_nearest_face(data) {
            const grip = findChild(portrait, "powerRemGrip");
            const center = portrait.width / 2;
            const endX = center + portrait.width * data.angle / 180;
            mousePress(grip, center, center);
            mouseMove(grip, endX, center, 20, Qt.LeftButton);
            verify(Math.abs(portrait.angle - data.angle) < 2);
            mouseRelease(grip, endX, center);
            verify(portrait.settling, "An intermediate angle must animate toward a face");
            tryCompare(portrait, "settling", false, 1000);
            compare(portrait.angle, data.face);
            verify(drawer.opened && !drawer.dragging);
        }

        function test_grab_interrupts_flip_and_reduced_motion_finishes_it() {
            portrait.angle = 125;
            portrait.settleToFace();
            verify(portrait.settling);
            wait(50);
            const current = portrait.angle;
            const grip = findChild(portrait, "powerRemGrip");
            mousePress(grip, 46, 46);
            verify(!portrait.settling);
            compare(portrait.angle, current);
            mouseMove(grip, 20, 46, 20, Qt.LeftButton);
            mouseRelease(grip, 20, 46);
            verify(portrait.settling);
            motion.calm = true;
            verify(!portrait.settling);
            compare(portrait.angle, 180);
        }

        function test_rim_has_depth_when_edge_on() {
            portrait.angle = 90;
            const first = findChild(portrait, "powerRemRim0");
            const last = findChild(portrait, "powerRemRim12");
            const left = first.mapToItem(portrait, 0, first.height / 2);
            const right = last.mapToItem(portrait, last.width, last.height / 2);
            verify(right.x - left.x >= portrait.thickness,
                   "The side must retain thickness when the face is edge-on");
        }

        function test_keyboard_double_click_and_escape() {
            portrait.forceActiveFocus();
            keyClick(Qt.Key_Right);
            verify(portrait.settling);
            tryCompare(portrait, "settling", false, 1000);
            compare(portrait.angle, 180);
            keyClick(Qt.Key_Left);
            tryCompare(portrait, "settling", false, 1000);
            compare(portrait.angle, 0);
            portrait.angle = 105;
            keyClick(Qt.Key_Home);
            tryCompare(portrait, "settling", false, 1000);
            compare(portrait.angle, 0);
            portrait.angle = 180;
            mouseDoubleClickSequence(findChild(portrait, "powerRemGrip"));
            tryCompare(portrait, "settling", false, 1000);
            compare(portrait.angle, 0);
            keyClick(Qt.Key_Escape);
            verify(!drawer.opened);
            tryCompare(drawer, "active", false, 1500);
        }

        function test_hide_or_disable_cancels_grab_and_hidden_playback() {
            const grip = findChild(portrait, "powerRemGrip");
            mousePress(grip, 46, 46);
            mouseMove(grip, 70, 46, 20, Qt.LeftButton);
            verify(portrait.dragging);
            drawer.close();
            verify(!portrait.dragging);
            mouseRelease(grip, 70, 46);
            tryCompare(drawer, "active", false, 1500);
            compare(portrait.angle, 0);
            verify(!findChild(portrait, "powerRemAnimation").playing);
            drawer.open();
            tryCompare(drawer, "settling", false, 1500);
            mousePress(grip, 46, 46);
            drawer.enabled = false;
            verify(!portrait.dragging);
            compare(portrait.angle, 0);
            mouseRelease(grip, 46, 46);
        }

        function test_hidden_flip_stops_and_does_not_return_on_reopen() {
            portrait.angle = 125;
            portrait.settleToFace();
            verify(portrait.settling);
            drawer.close();
            verify(!portrait.settling);
            tryCompare(drawer, "active", false, 1500);
            compare(portrait.angle, 0);
            drawer.open();
            tryCompare(drawer, "settling", false, 1500);
            wait(500);
            compare(portrait.angle, 0);
        }
    }
}
