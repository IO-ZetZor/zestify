pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import "../singletons"
import "../surfaces"
import "../lib/wallpapers.js" as WallpapersLib

PanelWindow {
    id: root
    property var targetScreen: null
    property var theme
    property var motion
    property real uiScale: 1
    readonly property string screenName: targetScreen ? targetScreen.name : ""
    readonly property bool opened: ShellState.surface === "wallpaper" && ShellState.owner === screenName
        && !Session.locked && Session.dpmsActive
    readonly property alias studio: picker.item
    property bool focusRequested: false
    property bool dismissing: false
    readonly property bool interactive: opened && !dismissing
    screen: targetScreen
    visible: interactive || backdrop.opacity > 0
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "zestify-wallpaper-picker"
    WlrLayershell.keyboardFocus: interactive
        ? (focusRequested ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand) : WlrKeyboardFocus.None
    anchors { top: true; bottom: true; left: true; right: true }
    mask: interactive ? pickerMask : emptyMask
    Region { id: emptyMask; width: 0; height: 0 }
    Region {
        id: pickerMask
        x: 6; y: 8
        width: Math.max(0, root.width - 12)
        height: Math.max(0, root.height - 16)
    }
    onOpenedChanged: {
        dismissing = false;
        focusRequested = opened;
        if (opened) focusPulse.restart();
        else {
            focusPulse.stop();
            Wallpapers.clearPreview(screenName);
        }
    }
    function dismissForApply() {
        root.dismissing = true;
        root.focusRequested = false;
        focusPulse.stop();
    }
    Timer { id: focusPulse; interval: 100; onTriggered: root.focusRequested = false }
    Connections {
        target: Wallpapers
        function onApplied() { if (root.opened) ShellState.close(root.screenName); }
        function onApplyFailed() {
            if (!root.opened || !root.dismissing) return;
            root.dismissing = false;
            root.focusRequested = true;
            focusPulse.restart();
        }
    }
    Connections {
        target: Session
        function onLockedChanged() { if (Session.locked) ShellState.close(root.screenName); }
        function onDpmsActiveChanged() { if (!Session.dpmsActive) ShellState.close(root.screenName); }
    }
    Component.onDestruction: {
        Wallpapers.clearPreview(screenName);
        if (opened) ShellState.close(screenName);
    }
    Item {
        id: backdrop
        objectName: "wallpaperPickerBackdrop"
        anchors.fill: parent
        opacity: root.interactive ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: root.motion && root.motion.calm ? 0 : (root.motion ? root.motion.fast : 140)
                easing.type: Easing.OutCubic
            }
        }
        Image {
            id: savedImage
            anchors.fill: parent
            source: {
                const path = Wallpapers.currentFor(root.screenName);
                const item = Wallpapers.items.find(item => item.path === path);
                return item ? WallpapersLib.localUrl(item.thumb) : "";
            }
            asynchronous: true
            fillMode: Image.PreserveAspectCrop
            sourceSize: Qt.size(root.width, root.height)
        }
        CachedBlur {
            anchors.fill: parent
            sourceItem: savedImage
            sourceReady: savedImage.status === Image.Ready
            revision: savedImage.source
            blur: 1
            blurMax: 48
        }
        Rectangle { anchors.fill: parent; color: root.theme.surface; opacity: 0.5 }
        MouseArea { anchors.fill: parent; onClicked: ShellState.close(root.screenName) }
        Loader {
            id: picker
            anchors.centerIn: parent
            width: Math.min(parent.width - 32, 820 * root.uiScale)
            height: Math.min(parent.height - 40, 780 * root.uiScale)
            active: root.opened || backdrop.opacity > 0
            sourceComponent: WallpaperStudio {
                theme: root.theme
                screen: root.targetScreen
                wallpapers: Wallpapers
                motion: root.motion
                s: root.uiScale
                folder: Config.wallpaper.dir
                previewEnabled: root.opened
                enabled: root.interactive
                visible: root.interactive || backdrop.opacity > 0
                onApplyRequested: root.dismissForApply()
                onCloseRequested: ShellState.close(root.screenName)
            }
        }
    }
}
