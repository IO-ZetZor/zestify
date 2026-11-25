import QtQuick
import QtTest
import "../../shell/lib/proxy.js" as ProxyLib

TestCase {
    name: "Proxy"

    function test_accepts_only_matching_monitor_size() {
        verify(ProxyLib.accepts("/wallpapers/10006.mp4", "/cache/1920x1200.mp4", 1920, 1200,
            "/wallpapers/10006.mp4", 1920, 1200));
        verify(!ProxyLib.accepts("/wallpapers/10006.mp4", "/cache/768x1366.mp4", 768, 1366,
            "/wallpapers/10006.mp4", 1920, 1200));
    }

    function test_rejects_stale_source_and_empty_path() {
        verify(!ProxyLib.accepts("/old.mp4", "/cache/1920x1200.mp4", 1920, 1200,
            "/new.mp4", 1920, 1200));
        verify(!ProxyLib.accepts("/new.mp4", "", 1920, 1200,
            "/new.mp4", 1920, 1200));
    }

    function test_requests_when_source_or_target_size_changes() {
        verify(ProxyLib.needsRequest("/a.mp4", "", "", false, 0, 0, 1920, 1200));
        verify(!ProxyLib.needsRequest("/a.mp4", "/a.mp4", "/cache/a.mp4", false, 1920, 1200, 1920, 1200));
        verify(ProxyLib.needsRequest("/a.mp4", "/a.mp4", "/cache/a.mp4", false, 768, 1366, 1366, 768));
        verify(ProxyLib.needsRequest("/b.mp4", "/a.mp4", "/cache/a.mp4", false, 1920, 1200, 1920, 1200));
        verify(ProxyLib.needsRequest("/a.mp4", "/a.mp4", "", true, 1920, 1200, 1920, 1200));
    }

    function test_resolution_setting_overrides_monitor_size() {
        const monitor = ProxyLib.resolutionSize("monitor", 1920, 1200);
        compare(monitor.width, 1920);
        compare(monitor.height, 1200);

        const fixed = ProxyLib.resolutionSize("1280x720", 1920, 1200);
        compare(fixed.width, 1280);
        compare(fixed.height, 720);

        const fallback = ProxyLib.resolutionSize("invalid", 1920, 1200);
        compare(fallback.width, 1920);
        compare(fallback.height, 1200);
    }

    function test_resolution_presets_preserve_orientation_and_do_not_upscale() {
        compare(ProxyLib.resolutionSize("1080p", 3840, 2160), {width: 1920, height: 1080});
        compare(ProxyLib.resolutionSize("1080p", 2160, 3840), {width: 1080, height: 1920});
        compare(ProxyLib.resolutionSize("1080p", 1920, 1200), {width: 1728, height: 1080});
        compare(ProxyLib.resolutionSize("720p", 1920, 1200), {width: 1152, height: 720});
        compare(ProxyLib.resolutionSize("1080p", 1280, 720), {width: 1280, height: 720});
        compare(ProxyLib.resolutionSize("720p", 768, 1366), {width: 718, height: 1280});
        compare(ProxyLib.resolutionSize("1080p", 0, 0), {width: 0, height: 0});
    }
}
