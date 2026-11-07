.pragma library

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
