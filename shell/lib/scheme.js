.pragma library

function fallbackScheme() {
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

function pick(global, monitors, screenName) {
    if (isObject(monitors) && isObject(monitors[screenName]))
        return monitors[screenName];
    if (isObject(global))
        return global;
    return fallbackScheme();
}
