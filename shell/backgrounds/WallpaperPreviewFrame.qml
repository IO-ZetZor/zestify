pragma ComponentBehavior: Bound

import QtQuick
import "."
import "../lib/wallpapers.js" as WallpapersLib

Item {
    id: root

    property var item: null
    readonly property bool isVideo: item !== null && WallpapersLib.isVideoPath(item.path)
    readonly property VideoWallpaper video: videoLoader.item as VideoWallpaper
    readonly property alias image: fallback
    readonly property bool ready: isVideo
        ? (video !== null && (video.failed ? fallback.status === Image.Ready : video.hasFirstFrame))
        : fallback.status === Image.Ready

    WallpaperImage {
        id: fallback
        anchors.fill: parent
        path: root.item ? (root.item.thumb || (root.isVideo ? "" : root.item.path)) : ""
        visible: status === Image.Ready && (root.video === null
            || !root.video.hasFirstFrame || root.video.failed)
    }

    Loader {
        id: videoLoader
        anchors.fill: parent
        active: root.isVideo
        visible: root.video !== null && root.video.hasFirstFrame && !root.video.failed
        sourceComponent: VideoWallpaper {
            source: root.item ? root.item.path : ""
            playing: true
            shouldDecode: true
            muted: true
        }
    }
}
