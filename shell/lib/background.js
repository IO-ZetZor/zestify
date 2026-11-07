.pragma library

function isFullscreen(workspace) {
    return !!(workspace && workspace.hasFullscreen);
}
