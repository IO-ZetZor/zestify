.pragma library

function primaryName(screens, configured) {
    for (let i = 0; i < screens.length; i++) {
        if (screens[i].name === configured)
            return configured;
    }
    return screens.length > 0 ? screens[0].name : "";
}

function widgetMode(name, primary, secondaryMode, overrides) {
    // Always keep the main shell controls on an attached display.
    if (name === primary)
        return "pill";
    const mode = overrides && typeof overrides === "object" && !Array.isArray(overrides)
        && Object.prototype.hasOwnProperty.call(overrides, name) ? overrides[name] : secondaryMode;
    return ["focus", "pill", "none"].indexOf(mode) >= 0 ? mode : "focus";
}
