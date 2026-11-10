.pragma library

function parseMeminfo(text) {
    const values = {};
    const lines = String(text || "").split("\n");
    for (let i = 0; i < lines.length; i++) {
        const match = lines[i].match(/^([A-Za-z_]+):\s+(\d+)\s+kB/);
        if (!match)
            continue;
        values[match[1]] = Number(match[2]) * 1024;
    }
    const total = values.MemTotal || 0;
    const available = values.MemAvailable || 0;
    return {
        memTotal: total,
        memAvailable: available,
        memFree: values.MemFree || 0,
        swapTotal: values.SwapTotal || 0,
        swapFree: values.SwapFree || 0,
        swapUsed: (values.SwapTotal || 0) - (values.SwapFree || 0),
        used: Math.max(0, total - available)
    };
}

function parseCpu(text) {
    const line = String(text || "").split("\n").find(l => l.startsWith("cpu "));
    if (!line)
        return { idle: 0, total: 0 };
    const fields = line.trim().split(/\s+/).slice(1).map(Number);
    const idle = (fields[3] || 0) + (fields[4] || 0);
    // guest and guest_nice are already included in user and nice.
    const total = fields.slice(0, 8).reduce((sum, value) => sum + (Number.isFinite(value) ? value : 0), 0);
    return { idle: idle, total: total };
}

function parseCpuCores(text) {
    const cores = {};
    for (const line of String(text || "").split("\n")) {
        const match = line.match(/^(cpu\d+)\s+(.*)$/);
        if (match)
            cores[match[1]] = parseCpu("cpu " + match[2]);
    }
    return cores;
}

function corePercents(previous, current) {
    return Object.keys(current).sort((a, b) => Number(a.slice(3)) - Number(b.slice(3)))
        .map(name => ({ name: name, percent: cpuPercent(previous ? previous[name] : null, current[name]) }));
}

function networkRates(previous, current, seconds) {
    if (!previous || !current || !(seconds > 0))
        return { rx: 0, tx: 0 };
    return {
        rx: Math.max(0, (current.rx - previous.rx) / seconds),
        tx: Math.max(0, (current.tx - previous.tx) / seconds)
    };
}

function cpuPercent(previous, current) {
    if (!previous || !current)
        return 0;
    const total = current.total - previous.total;
    const idle = current.idle - previous.idle;
    if (total <= 0)
        return 0;
    return Math.max(0, Math.min(100, 100 * (1 - idle / total)));
}

function netRate(previous, current, seconds) {
    if (!previous || !current || !(seconds > 0))
        return 0;
    const delta = (current.rx + current.tx) - (previous.rx + previous.tx);
    return Math.max(0, delta / seconds);
}

function parseNetdev(text) {
    let rx = 0;
    let tx = 0;
    const lines = String(text || "").split("\n");
    for (let i = 0; i < lines.length; i++) {
        const match = lines[i].match(/^\s*([^:]+):\s*(.*)$/);
        if (!match || match[1].trim() === "lo")
            continue;
        const fields = match[2].trim().split(/\s+/).map(Number);
        if (fields.length < 16)
            continue;
        rx += fields[0] || 0;
        tx += fields[8] || 0;
    }
    return { rx: rx, tx: tx };
}

function historyCapacity(graphSeconds, pollInterval) {
    const seconds = Number(graphSeconds);
    const interval = Number(pollInterval);
    if (!Number.isFinite(seconds) || !Number.isFinite(interval)
            || seconds <= 0 || interval <= 0)
        return 60;
    return Math.max(8, Math.min(600, Math.round(seconds * 1000 / interval)));
}
