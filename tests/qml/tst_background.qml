import QtQuick
import QtTest
import "../../shell/lib/background.js" as BackgroundLib

TestCase {
    name: "Background"

    function test_missing_workspace_is_not_fullscreen() {
        verify(!BackgroundLib.isFullscreen(null));
        verify(!BackgroundLib.isFullscreen(undefined));
    }

    function test_workspace_fullscreen_state_is_reported() {
        verify(BackgroundLib.isFullscreen({ hasFullscreen: true }));
        verify(!BackgroundLib.isFullscreen({ hasFullscreen: false }));
    }

    function test_obscured_mode_controls_pause() {
        verify(BackgroundLib.shouldPauseForObscured("fullscreen", true, false));
        verify(!BackgroundLib.shouldPauseForObscured("fullscreen", false, true));
        verify(BackgroundLib.shouldPauseForObscured("any-window", false, true));
        verify(!BackgroundLib.shouldPauseForObscured("any-window", true, false));
        verify(!BackgroundLib.shouldPauseForObscured("never", true, true));
    }
}
