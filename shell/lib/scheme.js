.pragma library

function fallbackScheme(mode) {
    if (mode === "light") {
        return {
            name: "zestify-fallback", mode: "light", variant: "light",
            colours: {
                background: "f9f8ff", onBackground: "1b1b21",
                surface: "f9f8ff", onSurface: "1b1b21",
                surfaceContainerLow: "f3f2fa", surfaceContainer: "ededf4",
                surfaceContainerHigh: "e7e7ee", surfaceContainerHighest: "e2e1e9",
                onSurfaceVariant: "454650", outline: "757680",
                primary: "555b86", primaryDim: "474d78", onPrimary: "ffffff",
                error: "ba1a1a", onError: "ffffff"
            }
        };
    }
    return {
        name: "zestify-fallback",
        flavour: "hard",
        mode: "dark",
        variant: "dark",
        colours: {
            background: "020305",
            onBackground: "e6e4f0",
            surface: "020305",
            surfaceDim: "020305",
            surfaceBright: "0c0c11",
            surfaceContainerLowest: "000000",
            surfaceContainerLow: "040407",
            surfaceContainer: "06060b",
            surfaceContainerHigh: "08090d",
            surfaceContainerHighest: "0a0b10",
            onSurface: "e6e4f0",
            surfaceVariant: "0a0b10",
            onSurfaceVariant: "abaab5",
            outline: "74757f",
            outlineVariant: "474750",
            primary: "bfc4ee",
            primaryDim: "b1b6e0",
            onPrimary: "383e61",
            primaryContainer: "4a5074",
            onPrimaryContainer: "dfe1ff",
            secondary: "c3c5dd",
            secondaryDim: "b5b7cf",
            onSecondary: "3c3f52",
            secondaryContainer: "373a4d",
            onSecondaryContainer: "bcbed5",
            tertiary: "f9e0ff",
            tertiaryDim: "f1cefc",
            onTertiary: "664b72",
            tertiaryContainer: "f1cefc",
            onTertiaryContainer: "5d4369",
            error: "f97386",
            errorDim: "c44b5f",
            onError: "490013",
            errorContainer: "871c34",
            onErrorContainer: "ff97a3"
        }
    };
}

function isObject(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value);
}

function coloursFor(scheme, mode) {
    if (!isObject(scheme))
        return fallbackScheme(mode).colours;
    if (isObject(scheme.palettes) && isObject(scheme.palettes[mode]))
        return scheme.palettes[mode];
    // Older CLI versions stored the generated dual-mode payload directly.
    if (isObject(scheme.colors)) {
        const colours = {};
        for (const role in scheme.colors) {
            const entry = scheme.colors[role];
            const selected = isObject(entry) ? entry[mode] : null;
            if (isObject(selected) && typeof selected.color === "string") {
                const key = role.replace(/_([a-z])/g, (_, letter) => letter.toUpperCase());
                colours[key] = selected.color;
            }
        }
        return colours;
    }
    if (isObject(scheme.colours))
        return scheme.colours;
    return fallbackScheme(mode).colours;
}

function pick(global, monitors, screenName) {
    if (isObject(monitors) && isObject(monitors[screenName]))
        return monitors[screenName];
    if (isObject(global))
        return global;
    return fallbackScheme();
}
