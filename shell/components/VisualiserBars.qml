pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

Item {
    id: root

    property var theme
    property real s: 1
    property var motion
    property string scriptsDir: ""
    property string python: "python3"
    property bool active: true

    property int barCount: 32
    property real barSpacing: 3 * root.s
    property real minHeight: 2 * root.s
    readonly property real maxHeight: Math.max(root.minHeight, root.height - 2 * root.s)

    implicitWidth: 320 * root.s
    implicitHeight: 64 * root.s

    function pushValues(values) {
        for (let i = 0; i < root.barCount; i++) {
            const bar = barsRepeater.itemAt(i);
            if (!bar)
                continue;
            // Keep peaks visible when a compact view groups the 32 audio bins.
            const start = Math.floor(i * values.length / root.barCount);
            const end = Math.floor((i + 1) * values.length / root.barCount);
            let level = 0;
            for (let j = start; j < end; j++)
                level = Math.max(level, values[j]);
            bar.level = level;
        }
    }

    VisualiserLevels {
        id: audio
        objectName: "visualiserLevels"
        scriptsDir: root.scriptsDir
        python: root.python
        active: root.active
    }

    Connections {
        target: audio
        function onValuesChanged() {
            root.pushValues(audio.values);
        }
    }

    RowLayout {
        anchors.fill: parent
        spacing: root.barSpacing

        Repeater {
            id: barsRepeater
            model: root.barCount

            Item {
                id: barItem
                required property int index
                objectName: "visualiserBar-" + index
                property real level: 0

                Layout.fillWidth: true
                Layout.fillHeight: true

                Rectangle {
                    objectName: "visualiserColumn-" + barItem.index
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: root.minHeight + barItem.level * (root.maxHeight - root.minHeight)
                    radius: Math.min(width, height) / 2
                    color: root.theme.accent
                }
            }
        }
    }
}
