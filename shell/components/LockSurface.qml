import QtQuick
import Quickshell.Wayland
import Quickshell
import "../singletons"

WlSessionLockSurface {
    id: root

    required property var auth
    property string authScreen: ""
    property string userName: ""
    property string layoutText: ""
    property bool capsLocked: false
    property var handoffFrame: null
    property string handoffScreen: ""
    property bool unlocking: false
    property int unlockSerial: 0
    signal unlockCaptured(string screenName, var frame, int serial)

    onUnlockingChanged: {
        if (unlocking) captureTimer.restart();
        else captureTimer.stop();
    }
    signal screenSelected(string name)

    readonly property string screenName: screen ? screen.name : ""
    readonly property bool showingHandoff: handoffImage.status === Image.Ready && !blur.cached
    color: themeObject.surface

    Theme {
        id: themeObject
        scheme: Colours.schemeFor(root.screenName)
        mode: Config.theme.mode
        fontFamily: Config.theme.fontFamily
        iconFont: Config.theme.iconFont
        transparency: Config.theme.transparency
    }

    Item {
        id: scene
        anchors.fill: parent

        Item {
            id: background
            anchors.fill: parent
            Rectangle { anchors.fill: parent; color: themeObject.surface }
            LockWallpaper {
                id: wallpaper
                anchors.fill: parent
                path: Wallpapers.currentFor(root.screenName)
            }

            CachedBlur {
                id: blur
                anchors.fill: parent
                sourceItem: wallpaper
                sourceReady: wallpaper.ready
                revision: wallpaper.revision
            }

            PillBody {
                anchors.fill: parent
                theme: themeObject
                cornerRadius: 0
                animateCornerRadius: false
                backgroundOpacity: Config.bar.opacity
            }

            Image {
                id: handoffImage
                anchors.fill: parent
                source: root.handoffFrame && root.screenName === root.handoffScreen
                    ? root.handoffFrame.url : ""
                // The grab URL is already cached in memory; make it available for
                // the very first lock buffer, before the compositor drops overlays.
                asynchronous: false
                visible: root.showingHandoff
            }
        }

        MouseArea {
            anchors.fill: parent
            enabled: !root.unlocking
            onClicked: root.screenSelected(root.screenName)
        }

        LockScreenFace {
            id: face
            enabled: !root.unlocking
            anchors.fill: parent
            theme: themeObject
            s: Math.max(0.75, Math.min(1.1, Math.min(width, height) / 1080)) * Config.bar.scale
            userName: root.userName
            batteryText: Stats.batteryPercent > 0
                ? Math.round(Stats.batteryPercent) + "% · " + (Session.charging ? "Charging" : "On battery") : ""
            handoffProgress: 1
            locked: true
            auth: root.auth
            authActive: root.authScreen === root.screenName || !root.authScreen.length
            layoutText: root.layoutText
            capsLocked: root.capsLocked
            onLayoutRequested: Quickshell.execDetached(["hyprctl", "switchxkblayout", "all", "next"])
            onSleepRequested: Session.sleep()
            onActivateRequested: root.screenSelected(root.screenName)
        }

        Timer {
            id: captureTimer
            interval: 1
            onTriggered: {
                const serial = root.unlockSerial;
                const name = root.screenName;
                if (!scene.grabToImage(result => {
                    if (root.unlocking && serial === root.unlockSerial)
                        root.unlockCaptured(name, result, serial);
                }, Qt.size(Math.max(1, Math.round(root.width * scene.Screen.devicePixelRatio)),
                           Math.max(1, Math.round(root.height * scene.Screen.devicePixelRatio)))))
                    root.unlockCaptured(name, null, serial);
            }
        }

        Timer {
            interval: 1000
            running: true
            repeat: true
            triggeredOnStart: true
            onTriggered: face.now = new Date()
        }
    }
}
