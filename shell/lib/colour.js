.pragma library

function normalizeHex(value) {
    if (value === undefined || value === null)
        return "#000000";

    let hex = String(value).trim().replace(/\s+/g, "").replace(/^#/, "").toLowerCase();
    if (hex.length === 8)
        hex = hex.slice(2);
    if (hex.length !== 6 || !/^[0-9a-f]{6}$/.test(hex))
        return "#000000";
    return "#" + hex;
}

function withAlpha(hex, alpha) {
    const base = normalizeHex(hex).slice(1);
    const clamped = Math.max(0, Math.min(1, Number(alpha)));
    const a = Math.round(clamped * 255).toString(16).padStart(2, "0");
    return "#" + a + base;
}

function isLight(mode) {
    return String(mode).toLowerCase() === "light";
}
