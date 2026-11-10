import QtQuick
import "../lib/colour.js" as Colour
import "../lib/scheme.js" as Scheme

QtObject {
    id: root

    property var scheme: null
    property string mode: "dark"
    readonly property var fallback: Scheme.fallbackScheme(mode)
    readonly property var c: Scheme.coloursFor(scheme, mode)

    function pick(key, fallbackHex) {
        const value = c[key] !== undefined
            ? c[key]
            : (fallback.colours[key] !== undefined ? fallback.colours[key] : fallbackHex);
        return Colour.normalizeHex(value);
    }

    function withAlpha(color, alpha) {
        return Colour.withAlpha(String(color), alpha);
    }

    readonly property color cream: pick("onSurface", "#e6e4f0")
    readonly property color bright: pick("onSurface", "#e6e4f0")
    readonly property color dim: pick("onSurfaceVariant", "#abaab5")
    readonly property color faint: pick("outline", "#74757f")
    readonly property color iconDim: pick("onSurfaceVariant", "#abaab5")
    readonly property color accent: pick("primary", "#bfc4ee")
    property color shellAccent: accent
    readonly property color accentDim: pick("primaryDim", "#b1b6e0")
    readonly property color onAccent: pick("onPrimary", "#383e61")
    readonly property color danger: pick("error", "#f97386")
    readonly property color onDanger: pick("onError", "#490013")
    readonly property color surface: pick("surface", "#020305")
    readonly property color surfaceLow: pick("surfaceContainerLow", "#040407")
    readonly property color surfaceHigh: pick("surfaceContainerHigh", "#08090d")
    readonly property color surfaceHighest: pick("surfaceContainerHighest", "#0a0b10")
    readonly property color outline: pick("outline", "#74757f")
    readonly property color hairline: withAlpha(outline, 0.35)
    readonly property color cardTop: pick("surfaceContainerHigh", "#08090d")
    readonly property color cardBot: pick("surfaceContainerLow", "#040407")
    readonly property color tileBg: pick("surfaceContainer", "#06060b")
    readonly property color border: withAlpha(outline, 0.25)
    readonly property color shadow: withAlpha("#000000", 0.55)

    readonly property var fs: ({
        label: 9,
        meta: 10.5,
        body: 12.5,
        title: 15,
        display: 30
    })
    readonly property var sp: ({
        s: 4,
        m: 8,
        l: 12
    })
    readonly property var r: ({
        s: 7,
        tile: 13,
        pill: 18
    })
    readonly property var inset: ({
        top: 8,
        side: 10,
        bottom: 8
    })

    property string fontFamily: "SF Pro"
    property string monoFont: "SF Mono"
    property string iconFont: "CaskaydiaCove Nerd Font"
    property real transparency: 1.0
}
