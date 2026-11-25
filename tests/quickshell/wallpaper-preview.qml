import QtQuick
import QtTest
import "../../shell/backgrounds"

Rectangle {
    id: fixture
    width: 160
    height: 90
    color: "#ff00ff"
    readonly property var red: ({path: "__RED__", thumb: "__RED__"})
    readonly property var blue: ({path: "__BLUE__", thumb: "__BLUE__"})
    readonly property var greenVideo: ({path: "__GREEN_VIDEO__", thumb: "__BLUE__"})
    readonly property var blueVideo: ({path: "__BLUE_VIDEO__", thumb: "__RED__"})
    readonly property var slowVideo: ({path: "__SLOW_VIDEO__", thumb: "__BLUE__"})
    readonly property var failedVideo: ({path: "__MISSING_VIDEO__", thumb: "__BLUE__"})

    WallpaperPreview {
        id: preview
        anchors.fill: parent
        motion: ({standard: 400, calm: false})
    }

    TestCase {
        name: "WallpaperPreview"
        when: windowShown

        function init() {
            preview.active = false;
            preview.item = null;
            preview.active = true;
        }

        function cleanup() {
            preview.active = false;
            preview.item = null;
        }

        function settled(item) {
            tryVerify(() => preview.displayedLayer !== null
                && preview.displayedLayer.wallpaper.path === item.path
                && preview.incomingLayer === null && !preview.transitioning, 5000);
            verify(preview.currentFrame.ready);
            wait(30);
        }

        function show(item) {
            preview.item = item;
            settled(item);
        }

        function midpoint(layer) {
            tryVerify(() => preview.transitioning && layer.opacity > 0.25 && layer.opacity < 0.75, 5000);
        }

        function test_crossfade_data() {
            return [
                {tag: "static-static", from: fixture.red, to: fixture.blue, channels: ["red", "blue"]},
                {tag: "static-live", from: fixture.red, to: fixture.greenVideo, channels: ["red", "green"]},
                {tag: "live-static", from: fixture.greenVideo, to: fixture.blue, channels: ["green", "blue"]},
                {tag: "live-live", from: fixture.greenVideo, to: fixture.blueVideo, channels: ["green", "blue"]}
            ];
        }

        function test_crossfade(data) {
            show(data.from);
            const outgoing = preview.displayedLayer;
            preview.item = data.to;
            const incoming = preview.incomingLayer;
            verify(incoming !== null);
            midpoint(incoming);
            compare(outgoing.opacity, 1, "Outgoing wallpaper must remain opaque under the blend");
            compare(outgoing.wallpaper.path, data.from.path);
            const frame = grabImage(fixture);
            for (const channel of data.channels)
                verify(frame[channel](80, 45) > 25, "Both wallpapers must contribute to the rendered midpoint");
            const absent = ["red", "green", "blue"].find(channel => !data.channels.includes(channel));
            verify(frame[absent](80, 45) < 15, "Desktop leaked through the crossfade");
            frame.save("__OUTPUT_DIR__/" + data.tag + ".png");
            settled(data.to);
            compare(outgoing.wallpaper, null, "Finished transition retained outgoing media");
            compare(outgoing.frame, null, "Finished transition retained outgoing decoder");
        }

        function test_slow_video_retains_outgoing_until_a_frame_is_ready() {
            show(fixture.red);
            const outgoing = preview.displayedLayer;
            preview.item = fixture.slowVideo;
            wait(150);
            verify(!preview.transitioning, "A thumbnail must not start the live crossfade before its first frame");
            compare(preview.displayedLayer, outgoing);
            compare(outgoing.opacity, 1);
            const frame = grabImage(fixture);
            verify(frame.red(80, 45) > 240 && frame.blue(80, 45) < 15);
            settled(fixture.slowVideo);
        }
        function test_entering_preview_fades_over_the_saved_wallpaper() {
            preview.item = fixture.red;
            midpoint(preview.incomingLayer);
            compare(preview.displayedLayer, null);
            const frame = grabImage(fixture);
            verify(frame.red(80, 45) > 240 && frame.blue(80, 45) > 25,
                "Entering preview must blend with the saved wallpaper");
            settled(fixture.red);
        }
        function test_failed_video_crossfades_to_its_thumbnail() {
            show(fixture.red);
            preview.item = fixture.failedVideo;
            settled(fixture.failedVideo);
            verify(preview.video.failed);
            const frame = grabImage(fixture);
            verify(frame.blue(80, 45) > 240 && frame.red(80, 45) < 15,
                "A failed video should retain its thumbnail fallback");
        }
        function test_replacing_a_loading_video_discards_stale_media() {
            show(fixture.red);
            preview.item = fixture.slowVideo;
            wait(100);
            verify(!preview.transitioning);
            preview.item = fixture.blue;
            settled(fixture.blue);
            compare(preview.video, null);
            wait(1100);
            compare(preview.displayedLayer.wallpaper.path, fixture.blue.path);
            compare(preview.incomingLayer, null);
        }

        function test_rapid_selection_keeps_the_blend_and_displays_only_the_latest_request() {
            show(fixture.red);
            preview.item = fixture.blue;
            const incoming = preview.incomingLayer;
            midpoint(incoming);
            preview.item = fixture.greenVideo;
            preview.item = fixture.red;
            preview.item = fixture.blueVideo;
            compare(preview.incomingLayer, incoming);
            compare(incoming.wallpaper.path, fixture.blue.path, "Rapid selection interrupted the visible blend");
            settled(fixture.blueVideo);
            verify(preview.video !== null && !preview.video.failed);
            const spare = preview.children.find(child => child.wallpaper !== undefined && child !== preview.displayedLayer);
            compare(spare.wallpaper, null, "Rapid selection retained extra media");
        }

        function test_cancel_loading_and_fade_back_to_the_saved_wallpaper() {
            show(fixture.red);
            preview.item = fixture.slowVideo;
            wait(100);
            preview.item = null;
            compare(preview.incomingLayer, null, "Cancelling retained the loading video");
            const outgoing = preview.displayedLayer;
            midpoint(outgoing);
            const frame = grabImage(fixture);
            verify(frame.red(80, 45) > 240 && frame.blue(80, 45) > 25,
                "Return to the saved wallpaper must blend instead of cutting");
            tryCompare(preview, "displayedLayer", null);
            compare(preview.video, null);
            compare(preview.image, null);
            verify(!preview.visible);
        }

        function test_inactive_immediately_releases_both_live_decoders() {
            show(fixture.greenVideo);
            preview.item = fixture.blueVideo;
            midpoint(preview.incomingLayer);
            preview.active = false;
            compare(preview.video, null);
            compare(preview.displayedLayer, null);
            compare(preview.incomingLayer, null);
            verify(!preview.transitioning);
            for (const child of preview.children) {
                if (child.wallpaper !== undefined) {
                    compare(child.wallpaper, null);
                    compare(child.frame, null);
                }
            }
            preview.active = true;
            settled(fixture.blueVideo);
        }
    }
}
