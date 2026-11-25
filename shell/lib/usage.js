.pragma library

function percent(used, total) {
    return total > 0 ? Math.max(0, Math.min(100, 100 * used / total)) : 0;
}

function peak(values) {
    return (values || []).reduce((max, value) => Number.isFinite(value) ? Math.max(max, value) : max, 0);
}

function scaleFor(first, second) {
    const value = Math.max(1024, peak(first), peak(second));
    return Math.pow(2, Math.ceil(Math.log(value) / Math.LN2));
}

function points(values, capacity, maximum, width, height) {
    const samples = (values || []).slice(-capacity);
    const start = Math.max(0, capacity - samples.length);
    return samples.map((value, index) => ({
        x: (start + index) * width / Math.max(1, capacity - 1),
        y: height * (1 - Math.max(0, Math.min(1, (Number(value) || 0) / Math.max(1, maximum))))
    }));
}

function sampleAt(values, capacity, fraction) {
    const samples = (values || []).slice(-capacity);
    const index = Math.round(Math.max(0, Math.min(1, fraction)) * Math.max(1, capacity - 1))
        - (capacity - samples.length);
    return index >= 0 && index < samples.length ? samples[index] : null;
}

// Include adjacent segments and the endpoint dot when samples change. Rolling
// histories may move every point; their damage must cover the entire plot.
function dirtySpan(before, after, width, padding) {
    let left = width;
    let right = 0;
    let changed = false;
    const count = Math.max(before.length, after.length);
    for (let i = 0; i < count; i++) {
        const a = before[i];
        const b = after[i];
        if (a && b && a.x === b.x && a.y === b.y)
            continue;
        changed = true;
        for (let j = Math.max(0, i - 1); j <= Math.min(count - 1, i + 1); j++) {
            for (const point of [before[j], after[j]]) {
                if (!point) continue;
                left = Math.min(left, point.x);
                right = Math.max(right, point.x);
            }
        }
    }
    return changed ? { x: Math.max(0, Math.floor(left - padding)),
        right: Math.min(width, Math.ceil(right + padding)) } : null;
}
