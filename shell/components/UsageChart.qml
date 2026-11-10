import QtQuick
import "../lib/usage.js" as Usage

Item {
    id: root

    property var theme
    property real s: 1
    property var values: []
    property var secondaryValues: []
    property color colour: theme.accent
    property color secondaryColour: theme.dim
    property string seriesName: ""
    property string secondaryName: ""
    property real maximum: 100
    property int capacity: 60
    property int sampleInterval: 1000
    property string topLabel: "100%"
    property string bottomLabel: "0%"
    property var formatter: null

    readonly property real fraction: Math.max(0, Math.min(1, (hover.point.position.x - plot.x) / Math.max(1, plot.width)))
    readonly property var hoveredValue: Usage.sampleAt(values, capacity, fraction)
    readonly property var hoveredSecondary: Usage.sampleAt(secondaryValues, capacity, fraction)
    readonly property bool inspecting: hover.hovered && hoveredValue !== null && hover.point.position.x >= plot.x
    readonly property int secondsAgo: Math.round((1 - fraction) * (capacity - 1) * sampleInterval / 1000)

    implicitHeight: 92 * s

    function formatted(value) {
        return formatter ? formatter(value) : Math.round(value) + "%";
    }

    onValuesChanged: plot.requestPaint()
    onSecondaryValuesChanged: plot.requestPaint()
    onMaximumChanged: plot.requestPaint()
    onCapacityChanged: plot.requestPaint()
    onColourChanged: plot.requestPaint()
    onSecondaryColourChanged: plot.requestPaint()
    onThemeChanged: plot.requestPaint()

    Text {
        id: scaleLabel
        x: 0; y: 0
        text: root.topLabel
        color: root.theme.faint
        font.family: root.theme.monoFont
        font.pixelSize: 8 * root.s
    }

    Text {
        x: 0; anchors.bottom: plot.bottom
        text: root.bottomLabel
        color: root.theme.faint
        font.family: root.theme.monoFont
        font.pixelSize: 8 * root.s
    }

    Canvas {
        id: plot
        anchors.fill: parent
        anchors.leftMargin: Math.max(28 * root.s, scaleLabel.implicitWidth + 8 * root.s)
        anchors.topMargin: 4 * root.s
        anchors.bottomMargin: 16 * root.s
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        onPaint: {
            if (!root.theme || width <= 0 || height <= 0)
                return;
            const ctx = getContext("2d");
            ctx.reset();
            ctx.lineWidth = 1;
            ctx.strokeStyle = String(root.theme.withAlpha(root.theme.outline, 0.18));
            for (let i = 0; i < 3; i++) {
                const y = Math.max(0.5, Math.min(height - 0.5, height * i / 2));
                ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(width, y); ctx.stroke();
            }
            function trace(values, colour, filled) {
                const points = Usage.points(values, root.capacity, root.maximum, width, height - 2 * root.s);
                if (points.length === 0)
                    return;
                if (filled && points.length > 1) {
                    const gradient = ctx.createLinearGradient(0, 0, 0, height);
                    gradient.addColorStop(0, String(root.theme.withAlpha(colour, 0.28)));
                    gradient.addColorStop(1, String(root.theme.withAlpha(colour, 0.02)));
                    ctx.fillStyle = gradient;
                    ctx.beginPath(); ctx.moveTo(points[0].x, height);
                    for (const point of points) ctx.lineTo(point.x, point.y + root.s);
                    ctx.lineTo(points[points.length - 1].x, height); ctx.closePath(); ctx.fill();
                }
                ctx.strokeStyle = String(colour);
                ctx.lineWidth = 1.8 * root.s;
                ctx.lineJoin = "round";
                ctx.lineCap = "round";
                ctx.beginPath();
                ctx.moveTo(points[0].x, points[0].y + root.s);
                for (let i = 1; i < points.length; i++) ctx.lineTo(points[i].x, points[i].y + root.s);
                ctx.stroke();
                const last = points[points.length - 1];
                ctx.beginPath(); ctx.arc(last.x, last.y + root.s, 2.5 * root.s, 0, Math.PI * 2); ctx.fillStyle = String(colour); ctx.fill();
            }
            trace(root.values, root.colour, true);
            trace(root.secondaryValues, root.secondaryColour, false);
        }
    }

    Text {
        anchors.left: plot.left; anchors.bottom: parent.bottom
        text: Math.round((root.capacity - 1) * root.sampleInterval / 1000) + "s ago"
        color: root.theme.faint
        font.family: root.theme.monoFont
        font.pixelSize: 8 * root.s
    }

    Text {
        anchors.right: parent.right; anchors.bottom: parent.bottom
        text: "now"
        color: root.theme.faint
        font.family: root.theme.monoFont
        font.pixelSize: 8 * root.s
    }

    Rectangle {
        visible: root.inspecting
        x: plot.x + root.fraction * plot.width
        y: plot.y
        width: root.s
        height: plot.height
        color: root.theme.withAlpha(root.theme.cream, 0.35)
    }

    Rectangle {
        visible: root.inspecting
        z: 2
        x: Math.max(0, Math.min(root.width - width, hover.point.position.x - width / 2))
        y: -8 * root.s
        width: tooltip.implicitWidth + 16 * root.s
        height: tooltip.implicitHeight + 10 * root.s
        radius: 6 * root.s
        color: root.theme.surfaceHighest
        border.width: 1
        border.color: root.theme.border
        Text {
            id: tooltip
            anchors.centerIn: parent
            text: root.seriesName + " " + root.formatted(root.hoveredValue || 0)
                + (root.hoveredSecondary !== null ? " · " + root.secondaryName + " " + root.formatted(root.hoveredSecondary) : "")
                + " · " + root.secondsAgo + "s ago"
            color: root.theme.cream
            font.family: root.theme.monoFont
            font.pixelSize: 9 * root.s
        }
    }

    HoverHandler { id: hover }
}
