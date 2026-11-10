.pragma library

function isFullscreen(workspace) {
    return !!(workspace && workspace.hasFullscreen);
}

function shouldPauseForObscured(mode, fullscreen, anyWindow) {
    switch (String(mode || "fullscreen")) {
    case "never":
        return false;
    case "any-window":
        return !!anyWindow;
    default:
        return !!fullscreen;
    }
}
