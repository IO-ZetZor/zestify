.pragma library

// Exponential interpolation used by the pill visualiser.
//
// Caelestia drives its bars with alpha = 1 - exp(-dt / tau) where
// tau = animationDuration / 3. That gives a fast attack and a natural,
// non-overshooting decay instead of the bouncy spring it used before.
function advance(current, target, dtMs, durationMs) {
    const tau = durationMs / 3.0;
    const alpha = 1.0 - Math.exp(-dtMs / tau);
    const count = Math.max(current.length, target.length);
    const values = [];
    let settled = true;

    for (let i = 0; i < count; i++) {
        const from = i < current.length ? Number(current[i]) || 0 : 0;
        const to = i < target.length ? Number(target[i]) || 0 : 0;
        const diff = to - from;

        if (Math.abs(diff) > 0.001) {
            values.push(from + diff * alpha);
            settled = false;
        } else {
            values.push(to);
        }
    }

    return { values: values, settled: settled };
}

// Monstercat smoothing: carry energy into neighbouring bars so a peak
// decays gradually across the spectrum instead of snapping to zero.
function monstercat(raw) {
    const inv = 1.0 / 1.5;
    const smoothed = [];
    let carry = 0.0;

    for (let i = 0; i < raw.length; i++) {
        carry = Math.max(raw[i], carry * inv);
        smoothed[i] = carry;
    }

    carry = 0.0;
    for (let i = raw.length - 1; i >= 0; i--) {
        carry = Math.max(raw[i], carry * inv);
        smoothed[i] = Math.max(smoothed[i], carry);
    }

    return smoothed;
}

// Stereo raw output is [left bars..., right bars...]. Smoothing each half
// separately keeps a peak on one channel from bleeding into the other.
function monstercatSides(raw) {
    const half = Math.floor(raw.length / 2);

    if (raw.length < 2)
        return raw.slice();

    return monstercat(raw.slice(0, half)).concat(monstercat(raw.slice(half)));
}
