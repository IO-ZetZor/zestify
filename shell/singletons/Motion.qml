pragma Singleton

import QtQuick
import Quickshell

Singleton {
    readonly property bool calm: false
    readonly property int fast: 140
    readonly property int standard: 300
    readonly property int morph: 420
    readonly property int shapeshift: 520
    readonly property int glide: 260
    readonly property int heat: 1100
    readonly property int easeStandard: Easing.OutCubic
    readonly property int easeMorph: Easing.BezierSpline
    readonly property var morphCurve: [0.16, 1, 0.3, 1, 1, 1]

    function reveal(p) {
        const t = Math.max(0, Math.min(1, (p - 0.35) / 0.5));
        return t * t * (3 - 2 * t);
    }
}
