import QtQuick
import QtTest
import "../../shell/lib/wallpapers.js" as WallpapersLib

TestCase {
    name: "Wallpapers"

    function test_filter_by_name_and_media_type() {
        const items = [
            {name: "Mountain Dawn.jpg", isVideo: false},
            {name: "Mountain Rain.mp4", isVideo: true},
            {name: "Ocean.png", isVideo: false}
        ];
        compare(WallpapersLib.filterItems(items, "  MOUNTAIN  ", "all").length, 2);
        compare(WallpapersLib.filterItems(items, "mountain", "images")[0], items[0]);
        compare(WallpapersLib.filterItems(items, "mountain", "animated")[0], items[1]);
        compare(WallpapersLib.filterItems(items, "ocean", "animated").length, 0);
        compare(WallpapersLib.filterItems(items, "", "all").length, 3);
        compare(WallpapersLib.filterItems(null, "", "all").length, 0);
    }

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

    function test_monitor_slug_matches_cli_state_files() {
        compare(WallpapersLib.monitorSlug("eDP-1"), "edp-1");
        compare(WallpapersLib.monitorSlug("HDMI-A-1"), "hdmi-a-1");
        compare(WallpapersLib.monitorSlug("DP--1"), "dp-1");
        compare(WallpapersLib.monitorSlug(".."), "_");
        var escaped = WallpapersLib.monitorSlug("../../../etc/passwd");
        verify(escaped.length > 0);
        verify(escaped.indexOf("/") === -1);
        verify(escaped.indexOf("\\") === -1);
    }
}
