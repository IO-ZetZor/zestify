import QtQuick
import QtTest
import "../../shell/lib/calendar.js" as Calendar

TestCase {
    name: "Calendar"

    function test_november_2026_grid() {
        const grid = Calendar.monthGrid(2026, 11);
        // Starts on Sunday (index 0), first week has 1 in position 0
        compare(grid[0][0], 1);
        // Nov 1, 2026 is a Sunday
        verify(grid.length >= 5);
        // Total days across all weeks = 30
        let count = 0;
        for (const week of grid)
            for (const day of week)
                if (day !== 0)
                    count++;
        compare(count, 30);
    }

    function test_flattens_month_grid() {
        const flat = Calendar.flattenGrid([[1, 2, 3], [4, 0, 6]]);
        compare(flat.length, 6);
        compare(flat[0], 1);
        compare(flat[4], 0);
        compare(flat[5], 6);
    }

    function test_events_for_date() {
        const events = [
            { date: "2026-11-15", title: "Meeting" },
            { date: "2026-11-15", title: "Lunch" },
            { date: "2026-11-20", title: "Dentist" }
        ];
        const matches = Calendar.eventsFor("2026-11-15", events);
        compare(matches.length, 2);
        compare(matches[0].title, "Meeting");
        const empty = Calendar.eventsFor("2026-11-16", events);
        compare(empty.length, 0);
    }
}
