import QtQuick
import QtTest
import "../../shell/lib/layout.js" as Layout

TestCase {
    name: "Layout"

    function test_pill_scale_uses_short_edge() {
        verify(Math.abs(Layout.pillScale(1920, 1200) - 1.111) < 0.001);
        verify(Math.abs(Layout.pillScale(768, 1366) - 0.711) < 0.001);
        verify(Math.abs(Layout.pillScale(3840, 2160) - 1.25) < 0.001);
        verify(Math.abs(Layout.pillScale(640, 480) - 0.70) < 0.001);
    }

    function test_surface_width_fits_screen() {
        verify(Layout.surfaceWidth(768, 0.711) <= 768);
        verify(Layout.surfaceWidth(1920, 1.111) > 0);
    }

    function test_osd_placement_follows_configured_position() {
        const topCenter = Layout.osdPlacement("top-center");
        compare(topCenter.top, true);
        compare(topCenter.right, false);

        const bottomRight = Layout.osdPlacement("bottom-right");
        compare(bottomRight.top, false);
        compare(bottomRight.right, true);

        const fallback = Layout.osdPlacement("unknown");
        compare(fallback.top, false);
        compare(fallback.right, false);
    }
}
