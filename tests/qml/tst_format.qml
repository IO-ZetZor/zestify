import QtQuick
import QtTest
import "../../shell/lib/format.js" as Format

TestCase {
    name: "Format"

    function test_signal_percent_accepts_fraction_or_percent() {
        compare(Format.signalPercent(0.72), 72);
        compare(Format.signalPercent(45), 45);
        compare(Format.signalPercent(150), 100);
        compare(Format.signalPercent(-0.2), 0);
    }

    function test_security_labels_are_short() {
        compare(Format.securityLabel("Open"), "Open");
        compare(Format.securityLabel("Owe"), "OWE");
        compare(Format.securityLabel("Wpa2Psk"), "WPA2");
        compare(Format.securityLabel("Wpa3SuiteB192"), "WPA3");
        compare(Format.securityLabel("Sae"), "WPA3");
        compare(Format.securityLabel("StaticWep"), "WEP");
        compare(Format.securityLabel("Unknown"), "");
    }

    function test_failure_labels_are_human_readable() {
        compare(Format.failureLabel("NoSecrets"), "Password required");
        compare(Format.failureLabel("WifiAuthTimeout"), "Authentication timed out");
        compare(Format.failureLabel("WifiNetworkLost"), "Network lost");
        compare(Format.failureLabel("SomethingElse"), "Connection failed");
    }

    function test_duration_formats_hours_and_minutes() {
        compare(Format.duration(0), "");
        compare(Format.duration(300), "5m");
        compare(Format.duration(3660), "1h 1m");
        compare(Format.duration(5400), "1h 30m");
    }

    function test_power_and_energy_labels() {
        compare(Format.watts(12.34), "12.3 W");
        compare(Format.watts(-3.2), "3.2 W");
        compare(Format.energy(42.05), "42.1 Wh");
    }
}
