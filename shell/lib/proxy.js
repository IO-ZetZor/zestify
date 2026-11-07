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
