import QtQuick
import QtTest
import "../../shell/lib/session.js" as SessionLib

TestCase {
    name: "Session"

    function test_inhibits_audio_only_when_enabled_and_playing() {
        compare(SessionLib.shouldInhibitAudio(true, true), true);
        compare(SessionLib.shouldInhibitAudio(true, false), false);
        compare(SessionLib.shouldInhibitAudio(false, true), false);
    }

    function test_inhibits_charging_only_when_enabled_and_charging() {
        compare(SessionLib.shouldInhibitCharging(true, true), true);
        compare(SessionLib.shouldInhibitCharging(true, false), false);
        compare(SessionLib.shouldInhibitCharging(false, true), false);
    }

    function test_locks_at_threshold() {
        compare(SessionLib.shouldLock(179, 180), false);
        compare(SessionLib.shouldLock(180, 180), true);
        compare(SessionLib.shouldLock(181, 180), true);
        compare(SessionLib.shouldLock(0, 0), false);
    }

    function test_returns_next_battery_warning() {
        compare(SessionLib.nextBatteryWarning(19, 20, [20, 10, 5]), 10);
        compare(SessionLib.nextBatteryWarning(9, 10, [20, 10, 5]), 5);
        compare(SessionLib.nextBatteryWarning(4, 5, [20, 10, 5]), null);
        compare(SessionLib.nextBatteryWarning(19, 100, [20, 10, 5]), 20);
    }
}
