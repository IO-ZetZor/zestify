import QtQuick
import QtTest
import "../../shell/lib/wallpapers.js" as WallpapersLib

TestCase {
    name: "Wallpapers"

    function test_prefers_monitor_override() {
        compare(WallpapersLib.pick("/global.mp4", { "HDMI-A-1": "/secondary.mp4" }, "HDMI-A-1"), "/secondary.mp4");
    }

    function test_falls_back_to_global() {
        compare(WallpapersLib.pick("/global.mp4", { "HDMI-A-1": "/secondary.mp4" }, "eDP-1"), "/global.mp4");
    }

    function test_empty_when_nothing_is_known() {
        compare(WallpapersLib.pick("", {}, "eDP-1"), "");
    }

    function test_detects_video_extensions() {
        verify(WallpapersLib.isVideoPath("/wallpapers/10006.mp4"));
        verify(WallpapersLib.isVideoPath("/wallpapers/10006.MKV"));
        verify(!WallpapersLib.isVideoPath("/wallpapers/10006.png"));
        verify(!WallpapersLib.isVideoPath(""));
    }

    function test_video_source_only_loads_videos() {
        compare(WallpapersLib.videoSource(false, "/proxy.mp4", "/image.png"), "");
        compare(WallpapersLib.videoSource(true, "/proxy.mp4", "/source.mp4"), "/proxy.mp4");
        compare(WallpapersLib.videoSource(true, "", "/source.mp4"), "/source.mp4");
    }
}
