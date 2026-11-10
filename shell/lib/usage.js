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
