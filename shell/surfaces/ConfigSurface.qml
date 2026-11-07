pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../singletons"

/**
 * Data-driven settings surface. The schema comes straight from
 * `Defaults.data`, so every config key automatically gets a row with a
 * control matched to its type. Edits are written back to config.json through
 * `Config.setValue` and apply live.
 */
SurfaceFrame {
    id: root

    property var motion

    title: "Settings"

    readonly property var sectionOrder: [
        "bar", "theme", "wallpaper", "system",
        "notifications", "osd", "power", "session", "monitor"
    ]

    readonly property var sectionLabels: ({
        bar: "Bar",
        theme: "Theme",
        wallpaper: "Wallpaper",
        system: "System",
        notifications: "Notifications",
        osd: "OSD",
        power: "Power",
        session: "Session",
        monitor: "Monitor"
    })

    function labelFor(path) {
        let key = String(path).split(".").pop();
        key = key.replace(/([a-z0-9])([A-Z])/g, "$1 $2").toLowerCase();
        key = key.replace(/\bdnd\b/g, "DND")
            .replace(/\bosd\b/g, "OSD")
            .replace(/\bdpms\b/g, "DPMS")
            .replace(/\bcrf\b/g, "CRF");
        return key.charAt(0).toUpperCase() + key.slice(1);
    }

    function kindOf(value) {
        if (Array.isArray(value))
            return "array";
        return typeof value;
    }

    function flatten(node, prefix, out) {
        for (const key in node) {
            const value = node[key];
            const path = prefix.length > 0 ? prefix + "." + key : key;
            if (value !== null && typeof value === "object" && !Array.isArray(value)) {
                root.flatten(value, path, out);
            } else {
                out.push({
                    path: path,
                    label: root.labelFor(path),
                    fallback: value,
                    kind: root.kindOf(value)
                });
            }
        }
        return out;
    }

    function rowsFor(section) {
        const node = Defaults.data[section];
        return node === undefined ? [] : root.flatten(node, section, []);
    }

    readonly property var sections: {
        const result = [];
        for (let i = 0; i < root.sectionOrder.length; i++) {
            const id = root.sectionOrder[i];
            if (Defaults.data[id] === undefined)
                continue;
            result.push({
                id: id,
                label: root.sectionLabels[id] || root.labelFor(id),
                rows: root.rowsFor(id)
            });
        }
        return result;
    }

    function choicesFor(path) {
        switch (path) {
        case "theme.mode":
            return ["dark", "light"];
        case "bar.trayOn":
            return ["primary", "all", "none"];
        case "bar.titleOn":
            return ["focused", "all"];
        case "osd.position":
            return ["top-center", "bottom-center", "top-right", "bottom-right"];
        default:
            return [];
        }
    }

    function isFloat(path) {
        return path === "theme.transparency"
            || path === "bar.opacity"
            || path === "bar.scale";
    }

    function rangeFor(path) {
        switch (path) {
        case "theme.transparency":
            return [0.0, 1.0, 0.01];
        case "bar.opacity":
            return [0.0, 1.0, 0.01];
        case "bar.scale":
            return [0.5, 2.0, 0.05];
        case "bar.height":
            return [24, 64, 1];
        case "bar.topGap":
            return [0, 32, 1];
        case "system.pollInterval":
            return [250, 5000, 50];
        case "system.graphSeconds":
            return [10, 300, 5];
        case "notifications.timeout":
            return [1000, 15000, 250];
        case "osd.timeout":
            return [500, 10000, 100];
        case "power.confirmHoldMs":
            return [0, 2000, 50];
        case "session.lockAfter":
            return [0, 3600, 30];
        case "session.dpmsOffAfter":
            return [0, 3600, 30];
        case "session.suspendAfter":
            return [0, 7200, 60];
        case "session.criticalBattery":
            return [0, 30, 1];
        case "wallpaper.pauseOnBatteryBelow":
            return [0, 100, 1];
        case "wallpaper.pauseUnfocusedAfter":
            return [0, 600, 10];
        case "wallpaper.proxy.crf":
            return [0, 51, 1];
        default: {
            const value = Number(Config.value(path, 0)) || 0;
            return [0, Math.max(100, Math.ceil(value * 2 / 10) * 10), 1];
        }
        }
    }

    function formatValue(path, value) {
        if (root.isFloat(path))
            return Number(value).toFixed(2);
        return String(Math.round(Number(value)));
    }

    function commitArray(row, text) {
        const parts = String(text).split(",").map(part => part.trim()).filter(part => part.length > 0);
        const numeric = row.fallback.length > 0 && typeof row.fallback[0] === "number";
        Config.setValue(row.path, numeric ? parts.map(Number) : parts);
    }

    component Toggle: Item {
        id: toggle

        property bool checked: false

        signal toggled()

        implicitWidth: 34 * root.s
        implicitHeight: 18 * root.s

        Rectangle {
            id: track
            anchors.fill: parent
            radius: height / 2
            color: toggle.checked
                ? root.theme.accent
                : root.theme.withAlpha(root.theme.outline, 0.35)

            Behavior on color {
                ColorAnimation { duration: 120 }
            }

            Rectangle {
                width: toggle.height - 4 * root.s
                height: width
                radius: width / 2
                y: 2 * root.s
                x: toggle.checked ? track.width - width - 2 * root.s : 2 * root.s
                color: toggle.checked ? root.theme.onAccent : root.theme.cream

                Behavior on x {
                    NumberAnimation {
                        duration: 140
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: toggle.toggled()
        }
    }

    component ValueSlider: Item {
        id: slider

        property real value: 0
        property real from: 0
        property real to: 100
        property real stepSize: 1
        property bool integer: true
        property real preview: -1

        signal committed(real value)

        readonly property real shown: slider.preview >= 0 ? slider.preview : slider.value
        readonly property real ratio: slider.to > slider.from
            ? Math.max(0, Math.min(1, (slider.shown - slider.from) / (slider.to - slider.from)))
            : 0

        implicitWidth: 150 * root.s
        implicitHeight: 20 * root.s

        function valueAt(positionX) {
            const fraction = Math.max(0, Math.min(1, positionX / Math.max(1, slider.width)));
            let next = slider.from + fraction * (slider.to - slider.from);
            next = Math.round(next / slider.stepSize) * slider.stepSize;
            return slider.integer ? Math.round(next) : Math.round(next * 100) / 100;
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: 4 * root.s
            radius: height / 2
            color: root.theme.withAlpha(root.theme.outline, 0.3)
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(4 * root.s, slider.ratio * parent.width)
            height: 4 * root.s
            radius: height / 2
            color: root.theme.accent
        }

        Rectangle {
            width: 10 * root.s
            height: 10 * root.s
            radius: width / 2
            y: (parent.height - height) / 2
            x: Math.max(0, Math.min(parent.width - width, slider.ratio * parent.width - width / 2))
            color: root.theme.accent
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor

            onPressed: (mouse) => slider.preview = slider.valueAt(mouse.x)
            onPositionChanged: (mouse) => {
                if (pressed)
                    slider.preview = slider.valueAt(mouse.x);
            }
            onReleased: {
                if (slider.preview >= 0) {
                    slider.committed(slider.preview);
                    slider.preview = -1;
                }
            }
            onCanceled: slider.preview = -1
        }
    }

    component ValueField: Rectangle {
        id: field

        property string text: ""
        property bool arrayMode: false

        signal committed(string value)

        implicitWidth: 170 * root.s
        implicitHeight: 24 * root.s
        radius: 6 * root.s
        color: root.theme.withAlpha(root.theme.surfaceHighest, 0.7)
        border.width: input.activeFocus ? 1 : 0
        border.color: root.theme.accent

        TextInput {
            id: input
            anchors.fill: parent
            anchors.margins: 6 * root.s
            verticalAlignment: TextInput.AlignVCenter
            text: field.text
            color: root.theme.cream
            font.family: field.arrayMode ? root.theme.monoFont : root.theme.fontFamily
            font.pixelSize: root.theme.fs.meta * root.s
            selectByMouse: true
            clip: true
            onEditingFinished: field.committed(text)
        }
    }

    component ChoiceRow: RowLayout {
        id: choiceRow

        property var choices: []
        property string current: ""

        signal chosen(string value)

        spacing: 4 * root.s

        Repeater {
            model: choiceRow.choices

            delegate: Rectangle {
                id: choiceChip
                required property string modelData

                implicitWidth: choiceLabel.implicitWidth + 14 * root.s
                implicitHeight: 20 * root.s
                radius: height / 2
                color: choiceChip.modelData === choiceRow.current
                    ? root.theme.accent
                    : (choiceHover.hovered
                        ? root.theme.withAlpha(root.theme.accent, 0.18)
                        : root.theme.withAlpha(root.theme.outline, 0.14))

                Text {
                    id: choiceLabel
                    anchors.centerIn: parent
                    text: choiceChip.modelData
                    color: choiceChip.modelData === choiceRow.current ? root.theme.onAccent : root.theme.dim
                    font.family: root.theme.fontFamily
                    font.pixelSize: root.theme.fs.label * root.s
                }

                HoverHandler {
                    id: choiceHover
                    cursorShape: Qt.PointingHandCursor
                }

                TapHandler {
                    onTapped: choiceRow.chosen(choiceChip.modelData)
                }
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 8 * root.s

        RowLayout {
            Layout.fillWidth: true
            spacing: 8 * root.s

            Text {
                Layout.fillWidth: true
                text: "Changes are written to config.json and apply immediately"
                color: root.theme.faint
                font.family: root.theme.fontFamily
                font.pixelSize: root.theme.fs.label * root.s
                elide: Text.ElideRight
            }

            Rectangle {
                implicitWidth: resetLabel.implicitWidth + 16 * root.s
                implicitHeight: 22 * root.s
                radius: height / 2
                color: resetHover.hovered
                    ? root.theme.withAlpha(root.theme.accent, 0.22)
                    : root.theme.withAlpha(root.theme.surfaceHigh, 0.6)

                Text {
                    id: resetLabel
                    anchors.centerIn: parent
                    text: "Reset all"
                    color: root.theme.dim
                    font.family: root.theme.fontFamily
                    font.pixelSize: root.theme.fs.label * root.s
                }

                HoverHandler {
                    id: resetHover
                    cursorShape: Qt.PointingHandCursor
                }

                TapHandler {
                    onTapped: Config.reset()
                }
            }
        }

        Flickable {
            id: scroller

            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: settingsColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: settingsColumn

                width: scroller.width
                spacing: 8 * root.s

                Repeater {
                    model: root.sections

                    delegate: Rectangle {
                        id: sectionCard
                        required property var modelData

                        Layout.fillWidth: true
                        Layout.preferredHeight: sectionColumn.implicitHeight + 2 * root.theme.sp.m * root.s
                        radius: root.theme.r.tile * root.s
                        color: root.theme.withAlpha(root.theme.surfaceHigh, 0.45)
                        border.width: 1
                        border.color: root.theme.withAlpha(root.theme.outline, 0.15)

                        ColumnLayout {
                            id: sectionColumn
                            anchors.fill: parent
                            anchors.margins: root.theme.sp.m * root.s
                            spacing: 2 * root.s

                            Text {
                                Layout.fillWidth: true
                                text: sectionCard.modelData.label
                                color: root.theme.cream
                                font.family: root.theme.fontFamily
                                font.pixelSize: root.theme.fs.body * root.s
                                font.weight: Font.Medium
                            }

                            Repeater {
                                model: sectionCard.modelData.rows

                                delegate: RowLayout {
                                    id: settingRow
                                    required property var modelData

                                    readonly property var current: Config.value(modelData.path, modelData.fallback)
                                    readonly property var choices: root.choicesFor(modelData.path)
                                    readonly property var range: root.rangeFor(modelData.path)

                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 28 * root.s
                                    spacing: 8 * root.s

                                    Text {
                                        Layout.fillWidth: true
                                        text: settingRow.modelData.label
                                        color: root.theme.dim
                                        font.family: root.theme.fontFamily
                                        font.pixelSize: root.theme.fs.label * root.s
                                        elide: Text.ElideRight
                                    }

                                    Toggle {
                                        visible: settingRow.modelData.kind === "boolean"
                                        checked: settingRow.current === true
                                        Layout.alignment: Qt.AlignVCenter
                                        onToggled: Config.setValue(settingRow.modelData.path, !checked)
                                    }

                                    RowLayout {
                                        visible: settingRow.modelData.kind === "number"
                                        spacing: 6 * root.s

                                        ValueSlider {
                                            id: valueSlider
                                            from: settingRow.range[0]
                                            to: settingRow.range[1]
                                            stepSize: settingRow.range[2]
                                            integer: !root.isFloat(settingRow.modelData.path)
                                            value: Number(settingRow.current) || 0
                                            onCommitted: (value) => Config.setValue(settingRow.modelData.path, value)
                                        }

                                        Text {
                                            Layout.preferredWidth: 38 * root.s
                                            text: root.formatValue(settingRow.modelData.path, valueSlider.shown)
                                            color: root.theme.cream
                                            font.family: root.theme.monoFont
                                            font.pixelSize: root.theme.fs.meta * root.s
                                            horizontalAlignment: Text.AlignRight
                                        }
                                    }

                                    ChoiceRow {
                                        visible: settingRow.modelData.kind === "string"
                                            && settingRow.choices.length > 0
                                        choices: settingRow.choices
                                        current: String(settingRow.current)
                                        onChosen: (value) => Config.setValue(settingRow.modelData.path, value)
                                    }

                                    ValueField {
                                        visible: settingRow.modelData.kind === "string"
                                            && settingRow.choices.length === 0
                                        Layout.preferredWidth: 180 * root.s
                                        Layout.alignment: Qt.AlignVCenter
                                        text: String(settingRow.current)
                                        onCommitted: (value) => Config.setValue(settingRow.modelData.path, value)
                                    }

                                    ValueField {
                                        visible: settingRow.modelData.kind === "array"
                                        Layout.preferredWidth: 180 * root.s
                                        Layout.alignment: Qt.AlignVCenter
                                        arrayMode: true
                                        text: settingRow.modelData.kind === "array"
                                            ? settingRow.current.join(", ")
                                            : String(settingRow.current)
                                        onCommitted: (value) => root.commitArray(settingRow.modelData, value)
                                    }

                                    Text {
                                        text: "󰑓"
                                        color: resetRowHover.hovered ? root.theme.accent : root.theme.withAlpha(root.theme.outline, 0.6)
                                        font.family: root.theme.iconFont
                                        font.pixelSize: root.theme.fs.meta * root.s
                                        Layout.alignment: Qt.AlignVCenter

                                        HoverHandler {
                                            id: resetRowHover
                                            cursorShape: Qt.PointingHandCursor
                                        }

                                        TapHandler {
                                            onTapped: Config.setValue(settingRow.modelData.path, settingRow.modelData.fallback)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
