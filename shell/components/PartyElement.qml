import QtQuick

Item {
    id: root

    property var spec: ({})
    property var theme
    property real s: 1
    property int index: 0

    implicitWidth: spec.width !== undefined ? spec.width * s
        : spec.chip ? 18 * s : label.implicitWidth
    implicitHeight: spec.height !== undefined ? spec.height * s
        : spec.chip ? 24 * s : label.implicitHeight

    Rectangle {
        anchors.fill: parent
        visible: root.spec.background !== undefined || root.spec.chip === true
        color: root.spec.background !== undefined ? root.spec.background
            : root.theme ? root.theme.withAlpha(root.theme.accent, 0.38) : "#303040"
        radius: (root.spec.radius === undefined ? 5 : root.spec.radius) * root.s
    }

    Loader {
        anchors.fill: parent
        active: root.spec.rem === true
        sourceComponent: RemIcon {
            color: root.spec.color || (root.theme ? root.theme.iconDim : "#aaaaaa")
        }
    }

    Image {
        anchors.fill: parent
        visible: !!root.spec.source
        source: root.spec.source || ""
        fillMode: Image.PreserveAspectFit
        sourceSize.width: Math.ceil(width)
        sourceSize.height: Math.ceil(height)
        smooth: true
        mipmap: true
    }

    Text {
        id: label
        anchors.centerIn: parent
        visible: !root.spec.rem && !root.spec.source
        text: root.spec.text !== undefined ? root.spec.text
            : root.spec.chip ? root.index
            : root.spec.clock ? Qt.formatDateTime(new Date(), "HH:mm") : root.spec.glyph || ""
        color: root.spec.color || (root.theme ? root.theme.iconDim : "#aaaaaa")
        font.family: root.spec.family || (root.theme
            ? root.spec.clock || root.spec.chip ? root.theme.fontFamily : root.theme.iconFont : "sans")
        font.pixelSize: (root.spec.size || (root.spec.chip ? 11 : 13)) * root.s
        font.weight: root.spec.weight === undefined ? Font.Normal : root.spec.weight
        renderType: root.spec.native ? Text.NativeRendering : Text.QtRendering
    }
}
