.pragma library

function progressAfter(progress, elapsedMs, holdMs) {
    if (!(holdMs > 0))
        return 1;
    const current = typeof progress === "number" && isFinite(progress) ? progress : 0;
    const elapsed = typeof elapsedMs === "number" && isFinite(elapsedMs) ? Math.max(0, elapsedMs) : 0;
    return Math.max(0, Math.min(1, current + elapsed / holdMs));
}

function completes(progress, elapsedMs, holdMs) {
    return progressAfter(progress, elapsedMs, holdMs) >= 1;
}

function fillGeometry(progress, availableHeight) {
    const amount = typeof progress === "number" && isFinite(progress) ? Math.max(0, Math.min(1, progress)) : 0;
    const total = typeof availableHeight === "number" && isFinite(availableHeight) ? Math.max(0, availableHeight) : 0;
    const height = total * amount;
    return { y: total - height, height: height };
}
