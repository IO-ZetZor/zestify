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
}
