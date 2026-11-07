.pragma library

function shouldInhibitAudio(isPlaying, inhibitWhenAudio) {
    return Boolean(isPlaying && inhibitWhenAudio);
}

function shouldInhibitCharging(isCharging, inhibitWhenCharging) {
    return Boolean(isCharging && inhibitWhenCharging);
}

function shouldLock(idleSeconds, lockAfter) {
    if (!(lockAfter > 0))
        return false;
    return Number(idleSeconds) >= Number(lockAfter);
}

function nextBatteryWarning(percent, lastWarned, warnings) {
    if (!Array.isArray(warnings))
        return null;
    const value = Number(percent);
    const previous = Number(lastWarned);
    if (!Number.isFinite(value) || !Number.isFinite(previous))
        return null;
    let next = null;
    for (let i = 0; i < warnings.length; i++) {
        const threshold = Number(warnings[i]);
        if (!Number.isFinite(threshold))
            continue;
        if (threshold < previous && (next === null || threshold > next))
            next = threshold;
    }
    return next;
}
