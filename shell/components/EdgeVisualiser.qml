pragma ComponentBehavior: Bound

import QtQuick
import "../lib/party.js" as Party

// Rounded bars growing inward from one screen edge.
Item {
    id: root

    property string edge: "top"
    property var levels: []
    property int barCount: 48
    property var theme
    property real s: 1

    readonly property bool horizontal: edge === "top" || edge === "bottom"
    readonly property bool mirrored: edge === "bottom" || edge === "right"
    readonly property bool atEnd: edge === "bottom" || edge === "right"
    readonly property real minLength: 2 * root.s
    readonly property real inset: 18 * root.s
    readonly property real span: Math.max(0, horizontal
        ? root.width - inset * 2
        : root.height - inset * 2)
    readonly property real step: span / Math.max(1, barCount)
    readonly property real maxLength: horizontal
        ? Math.max(minLength, root.height * 0.14)
        : Math.max(minLength, root.width * 0.08)

    readonly property real thickness: Math.max(2 * root.s,
        Math.min(6 * root.s, step * 0.42))

    readonly property color edgeColor: theme ? theme.accent : "#bfc4ee"

    function pushLevels() {
        for (let i = 0; i < barCount; i++) {
            const bar = barRepeater.itemAt(i);
            if (bar)
                bar.level = Party.sampleLevel(levels, i, barCount);
        }
    }

    function cornerWeight(index) {
        const edgeDistance = Math.min(index, Math.max(0, barCount - 1 - index));
        return 0.18 + 0.82 * Math.min(1, edgeDistance / 4);
    }

    onLevelsChanged: root.pushLevels()
    onBarCountChanged: root.pushLevels()
    Component.onCompleted: root.pushLevels()

    Repeater {
        id: barRepeater
        model: root.barCount

        Item {
            id: barItem
            required property int index
            property real level: Party.sampleLevel(root.levels, index, root.barCount)

            objectName: "edgeBar" + index

            x: root.horizontal
                ? (root.mirrored
                    ? root.width - root.inset - (index + 0.5) * root.step
                        - root.thickness / 2
                    : root.inset + (index + 0.5) * root.step - root.thickness / 2)
                : (root.edge === "left" ? 0 : root.width - width)
            y: root.horizontal
                ? (root.edge === "top" ? 0 : root.height - height)
                : (root.mirrored
                    ? root.height - root.inset - (index + 0.5) * root.step
                        - root.thickness / 2
                    : root.inset + (index + 0.5) * root.step - root.thickness / 2)

            width: root.horizontal
                ? root.thickness
                : root.minLength + barItem.level
                    * Math.max(0, root.maxLength * root.cornerWeight(index) - root.minLength)
            height: root.horizontal
                ? root.minLength + barItem.level
                    * Math.max(0, root.maxLength * root.cornerWeight(index) - root.minLength)
                : root.thickness

            Rectangle {
                anchors.fill: parent
                radius: root.thickness / 2
                antialiasing: true
                opacity: 0.75 + barItem.level * 0.25

                gradient: Gradient {
                    orientation: root.horizontal ? Gradient.Vertical : Gradient.Horizontal
                    GradientStop {
                        position: 0.0
                        color: Qt.rgba(root.edgeColor.r, root.edgeColor.g, root.edgeColor.b,
                            (root.edge === "bottom" || root.edge === "right") ? 0.12 : 0.9)
                    }
                    GradientStop {
                        position: 1.0
                        color: Qt.rgba(root.edgeColor.r, root.edgeColor.g, root.edgeColor.b,
                            (root.edge === "bottom" || root.edge === "right") ? 0.9 : 0.12)
                    }
                }
            }
        }
    }
}
