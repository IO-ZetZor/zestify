.pragma library

function pillScale(width, height, base, minimum, maximum) {
    const b = base === undefined ? 1080 : base;
    const lo = minimum === undefined ? 0.70 : minimum;
    const hi = maximum === undefined ? 1.25 : maximum;
    const shortEdge = Math.min(width, height);
    return Math.max(lo, Math.min(hi, shortEdge / b));
}

function surfaceWidth(screenWidth, scale, margin) {
    const m = margin === undefined ? 12 : margin;
    const available = Math.max(1, screenWidth - m * 2);
    return Math.min(available, Math.max(280, 460 * scale));
}
