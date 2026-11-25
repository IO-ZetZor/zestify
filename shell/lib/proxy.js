.pragma library

function accepts(source, path, width, height, expectedSource, expectedWidth, expectedHeight) {
    return typeof path === "string" && path.length > 0
        && source === expectedSource
        && width === expectedWidth
        && height === expectedHeight;
}

function needsRequest(source, requestedSource, path, failed, requestedWidth, requestedHeight, width, height) {
    if (typeof source !== "string" || source.length === 0)
        return false;
    if (source !== requestedSource || failed || typeof path !== "string" || path.length === 0)
        return true;
    return requestedWidth !== width || requestedHeight !== height;
}

function resolutionSize(resolution, width, height) {
    const fallback = {
        width: Number.isFinite(Number(width)) && Number(width) > 0 ? Math.round(Number(width)) : 0,
        height: Number.isFinite(Number(height)) && Number(height) > 0 ? Math.round(Number(height)) : 0
    };
    const setting = String(resolution || "").trim();
    if ((setting === "1080p" || setting === "720p") && fallback.width > 0 && fallback.height > 0) {
        const longEdge = setting === "1080p" ? 1920 : 1280;
        const shortEdge = setting === "1080p" ? 1080 : 720;
        const landscape = fallback.width >= fallback.height;
        const scale = Math.min(1, (landscape ? longEdge : shortEdge) / fallback.width,
            (landscape ? shortEdge : longEdge) / fallback.height);
        return {
            width: Math.max(2, Math.floor(fallback.width * scale / 2) * 2),
            height: Math.max(2, Math.floor(fallback.height * scale / 2) * 2)
        };
    }
    const match = setting.match(/^(\d+)x(\d+)$/);
    if (!match)
        return fallback;
    const fixedWidth = Number(match[1]);
    const fixedHeight = Number(match[2]);
    if (fixedWidth <= 0 || fixedHeight <= 0)
        return fallback;
    return { width: fixedWidth, height: fixedHeight };
}
