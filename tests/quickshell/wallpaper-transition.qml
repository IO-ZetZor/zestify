import QtQuick
import QtTest
import QtMultimedia
import "../../shell/backgrounds"

Rectangle {
    id: fixture
    width: 320
    height: 180
    color: "#ff00ff"
    readonly property var red: ({path: "__RED__", thumb: "__RED__"})
    readonly property var blue: ({path: "__BLUE__", thumb: "__BLUE__"})
    readonly property var subject: ({path: "__SUBJECT__", thumb: "__SUBJECT__"})
    readonly property var greenVideo: ({path: "__GREEN_VIDEO__", thumb: "__BLUE__"})
    readonly property var blueVideo: ({path: "__BLUE_VIDEO__", thumb: "__RED__"})
    readonly property var slowVideo: ({path: "__SLOW_VIDEO__", thumb: "__BLUE__"})
    readonly property var failedVideo: ({path: "__MISSING_VIDEO__", thumb: "__BLUE__"})
    QtObject {
        id: mapService
        signal ready(string source, var maps)
        signal failed(string source, string error)
        function prepare(source) {
            Qt.callLater(() => ready(source, source === fixture.subject.path
                ? ({kind: "perfil", field: "__SUBJECT_FIELD__", line: "__SUBJECT_LINE__"})
                : ({kind: "contagio", field: "__COLONY_FIELD__", line: "__COLONY_LINE__"})));
        }
    }
    WallpaperTransition {
        id: scene
        anchors.fill: parent
        duration: 1000
        effects: mapService
    }
    TestCase {
        name: "WallpaperTransition"
        when: windowShown
        function init() {
            scene.reset();
            scene.item = null;
            scene.active = true;
            scene.shouldDecode = true;
            scene.motion = null;
        }
        function cleanup() { scene.item = null; }
        function settled(item) {
            tryVerify(() => scene.displayedLayer !== null
                && scene.displayedLayer.wallpaper.path === item.path
                && scene.incomingLayer === null && !scene.transitioning, 7000);
            verify(scene.currentFrame.ready);
            wait(30);
        }
        function show(item) { scene.item = item; settled(item); }
        function test_initial_wallpaper_is_displayed_without_animation() {
            show(fixture.red);
            const frame = grabImage(fixture);
            verify(frame.red(160, 90) > 240 && frame.blue(160, 90) < 15);
        }
        function test_scene_change_data() {
            return [
                {tag: "static-static", from: fixture.red, to: fixture.blue, channels: ["red", "blue"]},
                {tag: "static-live", from: fixture.red, to: fixture.greenVideo, channels: ["red", "green"]},
                {tag: "live-static", from: fixture.greenVideo, to: fixture.blue, channels: ["green", "blue"]},
                {tag: "live-live", from: fixture.greenVideo, to: fixture.blueVideo, channels: ["green", "blue"]}
            ];
        }
        function test_scene_change(data) {
            scene.ember = data.channels[1] === "green" ? "lime" : "blue";
            show(data.from);
            const outgoing = scene.displayedLayer;
            scene.item = data.to;
            tryVerify(() => scene.transitioning && scene.progress > 0.44 && scene.progress < 0.64, 5000);
            compare(outgoing.wallpaper.path, data.from.path);
            const frame = grabImage(fixture);
            let oldPixels = 0, newPixels = 0;
            const oldChannel = data.channels[0], newChannel = data.channels[1];
            for (let y = 10; y < fixture.height; y += 10) {
                for (let x = 10; x < fixture.width; x += 10) {
                    if (frame[oldChannel](x, y) > frame[newChannel](x, y) + 80) oldPixels++;
                    if (frame[newChannel](x, y) > frame[oldChannel](x, y) + 80) newPixels++;
                    const absent = ["red", "green", "blue"].find(c => !data.channels.includes(c));
                    verify(frame[absent](x, y) < 45, "Desktop leaked through the transition");
                }
            }
            verify(oldPixels > 0 && newPixels > 0, "Transition must reveal regions of both wallpapers");
            frame.save("__OUTPUT_DIR__/" + data.tag + ".png");
            settled(data.to);
            compare(outgoing.wallpaper, null);
            compare(outgoing.frame, null, "The outgoing decoder must be released");
        }
        function test_contour_precedes_the_reveal() {
            show(fixture.red);
            scene.item = fixture.subject;
            tryVerify(() => scene.transitioning && scene.progress > 0.17 && scene.progress < 0.26, 5000);
            const frame = grabImage(fixture);
            let lit = 0;
            for (let y = 60; y <= 120; y++)
                for (let x = 100; x <= 220; x++)
                    if (frame.green(x, y) > 90 && frame.blue(x, y) > 90) lit++;
            verify(lit > 20, "The incoming subject contour must be drawn before the background arrives");
            frame.save("__OUTPUT_DIR__/contour.png");
            settled(fixture.subject);
        }
        function test_rapid_requests_finish_visible_transition_then_use_latest() {
            show(fixture.red);
            scene.item = fixture.blue;
            tryVerify(() => scene.transitioning && scene.progress > 0.15, 5000);
            const incoming = scene.incomingLayer;
            scene.item = fixture.subject;
            scene.item = fixture.greenVideo;
            compare(scene.incomingLayer, incoming);
            compare(incoming.wallpaper.path, fixture.blue.path);
            settled(fixture.greenVideo);
        }
        function test_loading_retains_outgoing_and_replacement_discards_stale_video() {
            show(fixture.red);
            const outgoing = scene.displayedLayer;
            scene.item = fixture.slowVideo;
            wait(150);
            verify(!scene.transitioning, "Video thumbnails cannot start a transition before the first frame");
            compare(scene.displayedLayer, outgoing);
            const frame = grabImage(fixture);
            verify(frame.red(160, 90) > 240 && frame.blue(160, 90) < 15);
            scene.item = fixture.blue;
            settled(fixture.blue);
            compare(scene.video, null);
            wait(1100);
            compare(scene.displayedLayer.wallpaper.path, fixture.blue.path);
        }
        function test_failed_video_uses_thumbnail() {
            show(fixture.red);
            scene.item = fixture.failedVideo;
            settled(fixture.failedVideo);
            verify(scene.video.failed);
            const frame = grabImage(fixture);
            verify(frame.blue(160, 90) > 240 && frame.red(160, 90) < 15);
        }
        function test_pause_and_mute_are_forwarded() {
            show(fixture.greenVideo);
            verify(scene.video.muted);
            scene.shouldDecode = false;
            tryCompare(scene.video.player, "playbackState", MediaPlayer.PausedState);
            scene.shouldDecode = true;
            tryCompare(scene.video.player, "playbackState", MediaPlayer.PlayingState);
            scene.muted = false;
            verify(!scene.video.muted);
            scene.muted = true;
        }
        function test_cancel_and_inactive_release_every_media_slot() {
            show(fixture.greenVideo);
            const outgoing = scene.displayedLayer;
            scene.item = fixture.blueVideo;
            const incoming = scene.incomingLayer;
            scene.item = null;
            verify(!scene.transitioning && !scene.visible);
            compare(outgoing.frame, null);
            compare(incoming.frame, null);
            show(fixture.greenVideo);
            scene.active = false;
            compare(scene.currentFrame, null);
        }
        function test_calm_motion_skips_scene_animation() {
            show(fixture.red);
            scene.motion = ({calm: true});
            scene.item = fixture.blue;
            settled(fixture.blue);
            verify(!scene.transitioning);
        }
    }
}
