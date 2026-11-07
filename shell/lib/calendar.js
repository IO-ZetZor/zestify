.pragma library

/**
 * Builds a Sunday-first month grid: array of weeks, each an array of 7 day numbers,
 * with 0 for padding days outside the month.
 */
function monthGrid(year, month) {
    const firstDay = new Date(year, month - 1, 1);
    const daysInMonth = new Date(year, month, 0).getDate();
    // JS getDay: 0=Sun, 1=Mon, ..., 6=Sat. Sunday-first means offset = getDay().
    const startOffset = firstDay.getDay();

    const grid = [];
    let week = [];
    for (let i = 0; i < startOffset; i++)
        week.push(0);

    let day = 1;
    while (day <= daysInMonth) {
        week.push(day);
        day++;
        if (week.length === 7) {
            grid.push(week);
            week = [];
        }
    }
    if (week.length > 0) {
        while (week.length < 7)
            week.push(0);
        grid.push(week);
    }
    return grid;
}

/**
 * Flattens an array of weeks into one array of day numbers.
 */
function flattenGrid(grid) {
    const flat = [];
    if (!Array.isArray(grid))
        return flat;
    for (let i = 0; i < grid.length; i++) {
        if (!Array.isArray(grid[i]))
            continue;
        for (let j = 0; j < grid[i].length; j++)
            flat.push(grid[i][j]);
    }
    return flat;
}

/**
 * Filters events to those whose date string matches exactly.
 * date is "YYYY-MM-DD".
 */
function eventsFor(date, events) {
    if (!Array.isArray(events))
        return [];
    return events.filter(function(e) { return e && e.date === date; });
}
