.pragma library

function icon(level, charging) {
    if (charging)
        return "󰂄";
    if (level < 0)
        return "󰂑";
    if (level <= 10)
        return "󰁺";
    if (level <= 20)
        return "󰁻";
    if (level <= 30)
        return "󰁼";
    if (level <= 40)
        return "󰁽";
    if (level <= 50)
        return "󰁾";
    if (level <= 60)
        return "󰁿";
    if (level <= 70)
        return "󰂀";
    if (level <= 80)
        return "󰂁";
    if (level <= 90)
        return "󰂂";
    return "󰁹";
}

function tone(level, charging) {
    if (charging)
        return "charging";
    if (level < 0)
        return "unknown";
    if (level <= 20)
        return "danger";
    if (level <= 40)
        return "warning";
    return "healthy";
}
