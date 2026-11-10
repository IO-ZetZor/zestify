import QtQuick

Item {
    id: slider

    property var theme
    property real s: 1
    property real value: 0
    property real from: 0
    property real to: 100
    property real stepSize: 1
    property bool integer: true
    property real preview: -1
    property real startValue: 0

    signal moved(real value)
    signal committed(real value)

    readonly property real shown: slider.preview >= 0 ? slider.preview : slider.value
    readonly property real ratio: slider.to > slider.from
        ? Math.max(0, Math.min(1, (slider.shown - slider.from) / (slider.to - slider.from)))
        : 0

    implicitWidth: 150 * slider.s
    implicitHeight: 20 * slider.s

    function valueAt(positionX) {
        const fraction = Math.max(0, Math.min(1, positionX / Math.max(1, slider.width)));
        let next = slider.from + fraction * (slider.to - slider.from);
        next = Math.round(next / slider.stepSize) * slider.stepSize;
        return slider.integer ? Math.round(next) : Math.round(next * 100) / 100;
    }

    function moveTo(positionX) {
        const next = slider.valueAt(positionX);
        if (next === slider.preview)
            return;
        slider.preview = next;
        slider.moved(next);
    }

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 4 * slider.s
        radius: height / 2
        color: slider.theme.withAlpha(slider.theme.outline, 0.3)
    }

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(4 * slider.s, slider.ratio * parent.width)
        height: 4 * slider.s
        radius: height / 2
        color: slider.theme.accent
    }

    Rectangle {
        width: 10 * slider.s
        height: 10 * slider.s
        radius: width / 2
        y: (parent.height - height) / 2
        x: Math.max(0, Math.min(parent.width - width, slider.ratio * parent.width - width / 2))
        color: slider.theme.accent
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor

        onPressed: (mouse) => {
            slider.startValue = slider.value;
            slider.moveTo(mouse.x);
        }
        onPositionChanged: (mouse) => {
            if (pressed)
                slider.moveTo(mouse.x);
        }
        onReleased: {
            if (slider.preview >= 0) {
                slider.committed(slider.preview);
                slider.preview = -1;
            }
        }
        onCanceled: {
            if (slider.preview >= 0) {
                slider.committed(slider.startValue);
                slider.preview = -1;
            }
        }
    }
}
