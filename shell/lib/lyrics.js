.pragma library

// Shared by the hover card and expanded player. Keep the cache bounded.
var cache = {};
var keys = [];

function remember(key, value) {
    if (keys.indexOf(key) < 0) keys.push(key);
    cache[key] = value;
    if (keys.length > 32) delete cache[keys.shift()];
}

function parse(synced, plain) {
    const lines = [];
    let offset = 0;
    const text = String(synced || "");
    const offsetMatch = text.match(/\[offset:([+-]?\d+)\]/i);
    if (offsetMatch) offset = Number(offsetMatch[1]) / 1000;
    for (const row of text.split(/\r?\n/)) {
        const stamps = row.match(/\[\d+:\d{2}(?:[.:]\d+)?\]/g) || [];
        const body = row.replace(/\[[^\]]*\]/g, "").trim();
        for (const stamp of stamps) {
            const match = stamp.match(/\[(\d+):(\d{2})(?:[.:](\d+))?\]/);
            const fraction = match[3] ? Number("0." + match[3]) : 0;
            lines.push({time: Math.max(0, Number(match[1]) * 60 + Number(match[2]) + fraction + offset), text: body});
        }
    }
    lines.sort((a, b) => a.time - b.time);
    if (lines.length) return {synced: true, lines: lines};
    return {synced: false, lines: String(plain || "").split(/\r?\n/)
        .filter(line => line.trim().length > 0).map(line => ({time: -1, text: line.trim()}))};
}

function indexAt(lines, position) {
    let index = -1;
    for (let i = 0; i < lines.length && lines[i].time <= position; i++) index = i;
    return index;
}
