import QtQuick
import Zestify.Login 1.0

Item {
    id: root
    property bool playing: true
    readonly property var settings: Theme.data.background
    readonly property bool live: settings.type === "video" || settings.type === "animated"
    readonly property string mediaError: video.status === Loader.Error ? "Qt Multimedia could not load"
        : video.item ? video.item.mediaError : animation.status === Image.Error ? "Animated wallpaper could not load" : ""
    readonly property int animatedFrame: animation.currentFrame
    readonly property int videoFrames: video.item ? video.item.frames : 0
    readonly property real videoPosition: video.item ? video.item.position : 0
    readonly property int imageFit: settings.fillMode === "fit" ? Image.PreserveAspectFit
        : settings.fillMode === "stretch" ? Image.Stretch : Image.PreserveAspectCrop

    Rectangle {
        anchors.fill: parent
        color: root.settings.color
    }
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0; color: root.settings.gradientTop }
            GradientStop { position: 0.55; color: root.settings.gradientMiddle }
            GradientStop { position: 1; color: root.settings.gradientBottom }
        }
    }
    Image {
        anchors.fill: parent
        source: Theme.assetUrl(root.settings.type === "image" ? root.settings.source : root.settings.fallback)
        asynchronous: true
        fillMode: root.imageFit
        opacity: root.settings.opacity
        sourceSize: Qt.size(Math.ceil(root.width), Math.ceil(root.height))
    }
    AnimatedImage {
        id: animation
        objectName: "animatedWallpaper"
        anchors.fill: parent
        source: root.settings.type === "animated" ? Theme.assetUrl(root.settings.source) : ""
        fillMode: root.imageFit
        // Large animations should not cache every decoded frame.
        cache: false
        playing: true
        paused: !root.playing
        speed: root.settings.speed
        opacity: root.settings.opacity
        visible: status === Image.Ready
        sourceSize: Qt.size(Math.ceil(root.width), Math.ceil(root.height))
    }
    Loader {
        id: video
        anchors.fill: parent
        active: root.settings.type === "video" && root.settings.source.length > 0
        source: active ? "VideoWallpaper.qml" : ""
        opacity: root.settings.opacity
        Binding { target: video.item; property: "source"; value: Theme.assetUrl(root.settings.source); when: video.item !== null }
        Binding { target: video.item; property: "playing"; value: root.playing; when: video.item !== null }
        Binding { target: video.item; property: "speed"; value: root.settings.speed; when: video.item !== null }
        Binding { target: video.item; property: "fit"; value: root.settings.fillMode; when: video.item !== null }
    }
    Rectangle {
        anchors.fill: parent
        color: root.settings.overlayColor
        opacity: root.settings.overlayOpacity
    }
}
