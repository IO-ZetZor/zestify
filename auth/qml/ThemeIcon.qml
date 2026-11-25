import QtQuick
import QtQuick.Controls
import Zestify.Login 1.0

Item {
    id: root
    required property var spec
    property color color: Theme.data.colors.text
    property string family: Theme.data.fonts.iconFamily
    property real size: Theme.data.form.iconSize
    readonly property bool hasIcon: spec.source.length > 0 || spec.glyph.length > 0
    implicitWidth: hasIcon ? size : 0
    implicitHeight: hasIcon ? size : 0
    visible: hasIcon
    Image {
        id: picture
        objectName: "iconImage"
        anchors.fill: parent
        source: Theme.assetUrl(root.spec.source)
        sourceSize.width: Math.ceil(root.size * Theme.data.layout.scale)
        sourceSize.height: sourceSize.width
        fillMode: Image.PreserveAspectFit
        asynchronous: true
    }
    Label {
        anchors.fill: parent
        visible: root.spec.source.length === 0 || picture.status === Image.Error
        text: root.spec.glyph
        textFormat: Text.PlainText
        color: root.color
        font.family: root.family
        font.pixelSize: root.size
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }
}
