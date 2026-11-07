import QtQuick

Row {
    id: root

    property var theme
    property var stats
    property real s: 1

    signal clicked()

    spacing: 8 * s

    Text {
        text: "CPU " + (root.stats ? Math.round(root.stats.cpuPercent) + "%" : "--")
        color: root.theme.dim
        font.family: root.theme.monoFont
        font.pixelSize: root.theme.fs.meta * root.s
    }

    Text {
        text: root.stats && root.stats.ramTotal > 0
            ? (root.stats.ramUsed / 1073741824).toFixed(1) + "G"
            : "--"
        color: root.theme.faint
        font.family: root.theme.monoFont
        font.pixelSize: root.theme.fs.meta * root.s
    }

    TapHandler {
        onTapped: root.clicked()
    }
}
