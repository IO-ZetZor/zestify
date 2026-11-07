import QtQuick
import QtTest
import "../../shell/lib/time.js" as Time

TestCase {
    name: "Time"

    function test_formats_durations() {
        compare(Time.formatDuration(0), "0:00");
        compare(Time.formatDuration(75), "1:15");
    }

    function test_joins_artists() {
        compare(Time.joinArtists(["A", "B"]), "A, B");
    }
}
