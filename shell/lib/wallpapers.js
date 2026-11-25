.pragma library

function localUrl(path) {
    const value = String(path || "");
    return value.startsWith("/") ? "file://" + value.split("/").map(encodeURIComponent).join("/") : value;
}

function pick(globalPath, monitorPaths, screenName) {
    if (monitorPaths && monitorPaths[screenName])
        return monitorPaths[screenName];
    return globalPath || "";
}

function isVideoPath(path) {
    return /\.(mp4|webm|mkv|mov|m4v)$/i.test(path || "");
}

function videoSource(isVideo, proxyPath, wallpaperPath) {
    if (!isVideo)
        return "";
    return proxyPath && proxyPath.length > 0 ? proxyPath : (wallpaperPath || "");
}

function filterItems(items, query, kind) {
    const needle = String(query || "").trim().toLowerCase();
    return (items || []).filter(item => {
        if (kind === "images" && item.isVideo)
            return false;
        if (kind === "animated" && !item.isVideo)
            return false;
        return !needle.length || String(item.name || "").toLowerCase().indexOf(needle) !== -1;
    });
}

function monitorSlug(name) {
    const raw = String(name || "").trim().toLowerCase();
    let out = "";
    let prevSep = false;
    for (const ch of raw) {
        if (/[a-z0-9]/.test(ch)) {
            out += ch;
            prevSep = false;
        } else {
            if (!prevSep || (out.length > 0 && out[out.length - 1] !== "-"))
                out += "-";
            prevSep = true;
        }
    }
    return out.replace(/^-+|-+$/g, "") || "_";
}
