import QtQuick
import QtTest
import "../../shell/components"

Item {
    id: fixture
    width: 320
    height: 320
    property bool renderShaders: GraphicsInfo.api !== GraphicsInfo.Software

    Theme { id: fixtureTheme }

    AlbumCover {
        id: cover
        x: 70
        y: 70
        width: 180
        height: 180
        theme: fixtureTheme
        playing: false
        active: false
    }

    TestCase {
        name: "AlbumCover"
        when: windowShown

        function init() {
            cover.fillContainer = false;
            cover.width = 180;
            cover.height = 180;
            cover.source = "";
            findChild(cover, "albumArtwork").rotation = 0;
            cover.longPressDuration = 550;
            cover.interactive = true;
            mouseMove(cover, cover.width / 2, cover.height / 2, 10);
        }

        function test_ring_and_mask_are_antialiased() {
            const ring = findChild(cover, "albumRing");
            verify(ring !== null, "album ring should exist");
            compare(ring.antialiasing, true, "ring border must be antialiased");

            const mask = findChild(cover, "coverMask");
            verify(mask !== null, "cover mask effect should exist");
            const origin = mask.mapToItem(fixture, 0, 0);
            const before = grabImage(fixture);
            cover.source = Qt.resolvedUrl("../fixtures/album-cover.svg");
            tryCompare(findChild(cover, "albumArtwork"), "status", Image.Ready);
            wait(50);
            const image = grabImage(fixture);
            compare(image.pixel(Math.floor(origin.x + 1), Math.floor(origin.y + 1)),
                    before.pixel(Math.floor(origin.x + 1), Math.floor(origin.y + 1)),
                    "circle corner must leave the background unchanged");
        }

        function test_crop_rotation_and_capsule_use_the_same_source() {
            cover.source = Qt.resolvedUrl("../fixtures/album-cover.svg");
            const art = findChild(cover, "albumArtwork");
            const mask = findChild(cover, "coverMask");
            tryCompare(art, "status", Image.Ready);
            compare(mask.cropScale, Qt.vector2d(0.5, 1));
            if (!fixture.renderShaders)
                skip("Pixel coverage runs with the native shader backend; offscreen uses software rendering");
            wait(50);
            let origin = mask.mapToItem(fixture, 0, 0);
            let image = grabImage(fixture);

            verify(image.green(Math.floor(origin.x + mask.width / 4), Math.floor(origin.y + mask.height / 2)) > 242,
                   "landscape source must crop to its center, not stretch");
            verify(image.blue(Math.floor(origin.x + mask.width * 3 / 4), Math.floor(origin.y + mask.height / 2)) > 242);
            art.rotation = 90;
            wait(50);
            image = grabImage(fixture);
            verify(image.green(Math.floor(origin.x + mask.width / 2), Math.floor(origin.y + mask.height / 4)) > 242);
            verify(image.blue(Math.floor(origin.x + mask.width / 2), Math.floor(origin.y + mask.height * 3 / 4)) > 242);
            cover.fillContainer = true;
            cover.width = 280;
            cover.height = 100;
            art.rotation = 0;
            wait(50);
            origin = mask.mapToItem(fixture, 0, 0);
            image = grabImage(fixture);
            verify(image.red(Math.floor(origin.x + 1), Math.floor(origin.y + 1)) > 242,
                   "capsule corner must leave the white background visible");
            verify(image.green(Math.floor(origin.x + mask.width / 4), Math.floor(origin.y + mask.height / 2)) > 242);
            verify(image.blue(Math.floor(origin.x + mask.width * 3 / 4), Math.floor(origin.y + mask.height / 2)) > 242);
        }

        function test_portrait_decode_preserves_aspect_and_crop() {
            cover.source = Qt.resolvedUrl("../fixtures/album-cover-portrait.svg");
            const art = findChild(cover, "albumArtwork");
            const mask = findChild(cover, "coverMask");
            tryCompare(art, "status", Image.Ready);
            compare(art.sourceSize.width, cover.textureResolution);
            compare(art.sourceSize.height, cover.textureResolution);
            compare(mask.cropScale, Qt.vector2d(1, 0.5));
            if (!fixture.renderShaders)
                skip("Pixel coverage runs with the native shader backend");
            wait(50);
            const origin = mask.mapToItem(fixture, 0, 0);
            const image = grabImage(fixture);
            verify(image.green(Math.floor(origin.x + mask.width / 2), Math.floor(origin.y + mask.height / 4)) > 242);
            verify(image.blue(Math.floor(origin.x + mask.width / 2), Math.floor(origin.y + mask.height * 3 / 4)) > 242);
        }

        function test_short_click_emits_clicked_not_long_pressed() {
            let clicks = 0;
            let holds = 0;
            const onClick = () => clicks++;
            const onHold = () => holds++;
            cover.clicked.connect(onClick);
            cover.longPressed.connect(onHold);

            mousePress(cover, cover.width / 2, cover.height / 2, Qt.LeftButton);
            wait(100);
            mouseRelease(cover, cover.width / 2, cover.height / 2, Qt.LeftButton);
            wait(20);

            compare(clicks, 1, "a short press should still count as a click");
            compare(holds, 0);

            cover.clicked.disconnect(onClick);
            cover.longPressed.disconnect(onHold);
        }

        function test_hold_fires_long_press_once_and_suppresses_click() {
            let clicks = 0;
            let holds = 0;
            const onClick = () => clicks++;
            const onHold = () => holds++;
            cover.clicked.connect(onClick);
            cover.longPressed.connect(onHold);

            mousePress(cover, cover.width / 2, cover.height / 2, Qt.LeftButton);
            wait(cover.longPressDuration + 120);
            compare(holds, 1, "holding past the threshold should fire once");
            mouseRelease(cover, cover.width / 2, cover.height / 2, Qt.LeftButton);
            wait(20);

            compare(clicks, 0, "a long press must not also emit a click");
            compare(holds, 1, "long press must only fire once");

            cover.clicked.disconnect(onClick);
            cover.longPressed.disconnect(onHold);
        }

        function test_release_outside_does_not_click() {
            let clicks = 0;
            const onClick = () => clicks++;
            cover.clicked.connect(onClick);

            mousePress(cover, cover.width / 2, cover.height / 2, Qt.LeftButton);
            wait(80);
            mouseMove(cover, cover.width + 60, cover.height / 2, 16);
            mouseRelease(cover, cover.width + 60, cover.height / 2, Qt.LeftButton);
            wait(20);

            compare(clicks, 0, "releasing off the cover must not activate it");

            cover.clicked.disconnect(onClick);
        }

        function test_hold_dragged_off_does_not_fire() {
            let holds = 0;
            const onHold = () => holds++;
            cover.longPressed.connect(onHold);

            mousePress(cover, cover.width / 2, cover.height / 2, Qt.LeftButton);
            mouseMove(cover, cover.width + 60, cover.height / 2, 16);
            wait(cover.longPressDuration + 120);
            compare(holds, 0, "dragging off the cover must cancel the hold");
            mouseRelease(cover, cover.width + 60, cover.height / 2, Qt.LeftButton);
            wait(20);
            compare(holds, 0);

            cover.longPressed.disconnect(onHold);
        }

        function test_cancelled_hold_does_not_fire() {            let holds = 0;
            const onHold = () => holds++;
            cover.longPressed.connect(onHold);

            mousePress(cover, cover.width / 2, cover.height / 2, Qt.LeftButton);
            wait(120);
            mouseRelease(cover, cover.width / 2, cover.height / 2, Qt.LeftButton);
            wait(20);

            compare(holds, 0);

            cover.longPressed.disconnect(onHold);
        }

        function test_non_interactive_cover_ignores_presses() {
            cover.interactive = false;
            let clicks = 0;
            const onClick = () => clicks++;
            cover.clicked.connect(onClick);

            mouseClick(cover, cover.width / 2, cover.height / 2);
            wait(20);

            compare(clicks, 0);

            cover.clicked.disconnect(onClick);
        }
    }
}
