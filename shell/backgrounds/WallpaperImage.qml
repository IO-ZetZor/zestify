import QtQuick

Image {
    id: root

    property string path: ""
    readonly property bool isVideo: /\.(mp4|webm|mkv|mov|m4v)$/i.test(path)

    source: path.length > 0 && !isVideo ? path : ""
    asynchronous: true
    cache: true
    smooth: true
    fillMode: Image.PreserveAspectCrop
    visible: !isVideo && status === Image.Ready
}
