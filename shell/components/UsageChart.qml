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

    property var primaryPoints: []
    property var secondaryPoints: []

    function updateSeries(secondary) {
        const before = secondary ? secondaryPoints : primaryPoints;
        const after = Usage.points(secondary ? secondaryValues : values,
            capacity, maximum, plot.width, plot.height - 2 * s);
        const span = Usage.dirtySpan(before, after, plot.width, 3.5 * s + 1);
        if (secondary) secondaryPoints = after;
        else primaryPoints = after;
        if (span && plot.available)
            plot.markDirty(Qt.rect(span.x, 0, span.right - span.x, plot.height));
    }
    function rebuild() {
        primaryPoints = Usage.points(values, capacity, maximum, plot.width, plot.height - 2 * s);
        secondaryPoints = Usage.points(secondaryValues, capacity, maximum, plot.width, plot.height - 2 * s);
        plot.requestPaint();
    }
    onValuesChanged: updateSeries(false)
    onSecondaryValuesChanged: updateSeries(true)
    onMaximumChanged: rebuild()
    onCapacityChanged: rebuild()
    onSChanged: rebuild()
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

    // Retained scene-graph nodes do not repaint when the histories advance.
    Repeater {
        model: 3
        delegate: Rectangle {
            required property int index
            x: plot.x
            y: plot.y + Math.max(0, Math.min(plot.height - 1, plot.height * index / 2 - 0.5))
            width: plot.width
            height: 1
            color: root.theme.withAlpha(root.theme.outline, 0.18)
        }
    }

    Canvas {
        id: plot
        objectName: "usagePlot"
        anchors.fill: parent
        anchors.leftMargin: Math.max(28 * root.s, scaleLabel.implicitWidth + 8 * root.s)
        anchors.topMargin: 4 * root.s
        anchors.bottomMargin: 16 * root.s
        onWidthChanged: root.rebuild()
        onHeightChanged: root.rebuild()
        onAvailableChanged: if (available) root.rebuild()

        onPaint: (region) => {
            if (!root.theme || width <= 0 || height <= 0)
                return;
            const ctx = getContext("2d");
            ctx.save();
            ctx.clearRect(region.x, region.y, region.width, region.height);
            ctx.beginPath();
            ctx.rect(region.x, region.y, region.width, region.height);
            ctx.clip();
            function trace(points, colour, filled) {
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
            trace(root.primaryPoints, root.colour, true);
            trace(root.secondaryPoints, root.secondaryColour, false);
            ctx.restore();
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
