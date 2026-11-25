import QtQuick
import QtQuick.Layouts

RowLayout {
    id: root

    property var theme
    property var screen
    property var stats
    property var players: null
    property var motion
    property string scriptsDir: ""
    property bool hovering: false
    property bool mediaActive: true
    property real s: 1
    property bool showTray: true
    property bool locked: false
    property var windowObject

    signal calendarRequested()
    signal systemRequested()
    signal networkRequested()
    signal bluetoothRequested()
    signal batteryRequested()
    signal launcherRequested()

    readonly property real sideWidth: Math.max(leftGroup.implicitWidth, rightGroup.implicitWidth
        + (visualiser.playing || visualiser.opacity > 0
            ? visualiser.implicitWidth + 2 * root.theme.sp.m * root.s - spacing : 0))
    implicitWidth: 2 * sideWidth + clock.implicitWidth + 2 * spacing
    spacing: 28 * s

    // Copy the live visuals and their layout, without sharing items across windows.
    function partyElements(targetWidth) {
        const result = [];
        const layoutWidth = targetWidth === undefined ? root.width : targetWidth;
        function visit(item) {
            const name = item.objectName || "";
            const textItem = name === "pillClock" || name.indexOf("workspaceLabel-") === 0
                || name === "pillWifiIcon" || name === "pillBluetoothIcon" || name === "pillBatteryIcon"
                || (name === "resourceCpuIcon" && root.stats && root.stats.cpuPercent > 90)
                || (name === "pillLockIcon" && root.locked);
            const trayIcon = name === "pillTrayIcon" && root.showTray;
            const column = name.indexOf("visualiserColumn-") === 0 && visualiser.playing;
            if (name === "pillLauncher" || textItem || trayIcon || column) {
                const center = item.mapToItem(root, item.width / 2, item.height / 2);
                const spec = { key: name, x: center.x, y: center.y, width: item.width / root.s,
                    height: item.height / root.s };
                // Use target slot geometry even before the expanded source has
                // finished collapsing or a playback change has polished its layout.
                if (column) {
                    const margin = root.theme.sp.m * root.s;
                    const width = Math.max(0, layoutWidth / 2 - clock.implicitWidth / 2
                        - rightGroup.implicitWidth - 2 * margin);
                    const barWidth = Math.max(0, (width - (visualiser.barCount - 1)
                        * visualiser.barSpacing) / visualiser.barCount);
                    const index = Number(name.slice("visualiserColumn-".length));
                    spec.x = layoutWidth / 2 + clock.implicitWidth / 2 + margin
                        + (index + 0.5) * barWidth + index * visualiser.barSpacing;
                    spec.width = barWidth / root.s;
                } else if (name === "pillClock") {
                    spec.x = layoutWidth / 2;
                } else if (name !== "pillLauncher" && name.indexOf("workspaceLabel-") !== 0) {
                    spec.x = layoutWidth - rightGroup.implicitWidth
                        + item.mapToItem(rightGroup, item.width / 2, item.height / 2).x;
                }
                if (name === "pillLauncher") {
                    spec.rem = true;
                    spec.color = root.theme.iconDim;
                } else if (textItem) {
                    spec.text = item.text;
                    spec.color = item.color;
                    spec.family = item.font.family;
                    spec.size = item.font.pixelSize / root.s;
                    spec.weight = item.font.weight;
                    spec.native = name.indexOf("workspaceLabel-") === 0;
                    if (spec.native && item.parent.active) {
                        spec.background = root.theme.accent;
                        spec.width = item.parent.width / root.s;
                        spec.height = item.parent.height / root.s;
                        spec.radius = 4;
                    }
                } else if (trayIcon) {
                    spec.source = String(item.source);
                    if (!spec.source) {
                        spec.text = "󰀻";
                        spec.color = root.theme.iconDim;
                        spec.family = root.theme.iconFont;
                        spec.size = 13;
                    }
                } else {
                    spec.background = item.color;
                    spec.radius = item.radius / root.s;
                }
                result.push(spec);
            }
            for (const child of item.children || [])
                visit(child);
        }
        visit(root);
        return result.map((spec, index) => Object.assign(spec, {
            delay: 0.02 + index * 0.19 / Math.max(1, result.length - 1),
            drift: (index % 2 ? 1 : -1) * (0.2 + index % 3 * 0.15),
            spin: (index % 2 ? 1 : -1) * (0.4 + index % 3 * 0.2)
        }));
    }

    Item {
        Layout.preferredWidth: root.sideWidth
        Layout.fillWidth: true
        Layout.fillHeight: true

        RowLayout {
            id: leftGroup
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: root.theme.sp.m * root.s
            RemIcon {
                objectName: "pillLauncher"
                color: launcherHover.hovered ? root.theme.accent : root.theme.iconDim
                implicitWidth: 20 * root.s
                implicitHeight: 20 * root.s
                Layout.alignment: Qt.AlignVCenter
                activeFocusOnTab: true
                Accessible.role: Accessible.Button
                Accessible.name: "Open launcher"
                Keys.onReturnPressed: root.launcherRequested()
                Keys.onSpacePressed: root.launcherRequested()

                HoverHandler {
                    id: launcherHover
                    cursorShape: Qt.PointingHandCursor
                }

                TapHandler {
                    onTapped: root.launcherRequested()
                }
            }

            Workspaces {
                objectName: "pillWorkspaces"
                theme: root.theme
                screen: root.screen
                motion: root.motion
                s: root.s
                Layout.alignment: Qt.AlignVCenter
            }
        }
    }

    Clock {
        id: clock
        objectName: "pillClock"
        theme: root.theme
        s: root.s
        Layout.alignment: Qt.AlignVCenter
        onClicked: root.calendarRequested()
    }

    Item {
        Layout.preferredWidth: root.sideWidth
        Layout.fillWidth: true
        Layout.fillHeight: true

        VisualiserBars {
            id: visualiser
            objectName: "pillVisualiser"
            anchors.left: parent.left
            anchors.leftMargin: -root.spacing + root.theme.sp.m * root.s
            anchors.right: rightGroup.left
            anchors.rightMargin: root.theme.sp.m * root.s
            anchors.verticalCenter: parent.verticalCenter
            height: implicitHeight
            theme: root.theme
            motion: root.motion
            s: root.s
            scriptsDir: root.scriptsDir
            barCount: 12
            barSpacing: 2 * root.s
            minHeight: 1 * root.s
            implicitWidth: 64 * root.s
            implicitHeight: 18 * root.s
            property bool ready: false
            readonly property bool playing: root.players ? root.players.isPlaying : false
            readonly property bool showBars: ready && playing && !root.hovering
            visible: playing || opacity > 0
            opacity: showBars ? 1 : 0
            active: root.visible && opacity > 0 && root.mediaActive && !root.locked
                && (!root.windowObject || root.windowObject.visible)

            // Start transparent even when a player is already active at load.
            Component.onCompleted: Qt.callLater(() => visualiser.ready = true)

            Behavior on opacity {
                NumberAnimation {
                    duration: root.motion && root.motion.calm ? 0
                        : visualiser.showBars ? (root.motion ? root.motion.morph : 420)
                        : (root.motion ? root.motion.fast : 140)
                    easing.type: visualiser.showBars ? Easing.InOutCubic : Easing.OutCubic
                }
            }
        }

        RowLayout {
            id: rightGroup
            objectName: "pillRightGroup"
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: root.theme.sp.m * root.s
            Resources {
                objectName: "pillCpuWarning"
                theme: root.theme
                stats: root.stats
                motion: root.motion
                s: root.s
                Layout.alignment: Qt.AlignVCenter
                onClicked: root.systemRequested()
            }

            StatusIcons {
                objectName: "pillStatusIcons"
                theme: root.theme
                s: root.s
                Layout.alignment: Qt.AlignVCenter
                onWifiClicked: root.networkRequested()
                onBluetoothClicked: root.bluetoothRequested()
                onBatteryClicked: root.batteryRequested()
            }

            Tray {
                visible: root.showTray
                theme: root.theme
                s: root.s
                anchorWindow: root.windowObject
                Layout.alignment: Qt.AlignVCenter
            }

            Text {
                objectName: "pillLockIcon"
                visible: root.locked
                text: "󰌾"
                color: root.theme.accent
                font.family: root.theme.iconFont
                font.pixelSize: root.theme.fs.title * root.s
                Layout.alignment: Qt.AlignVCenter
            }
        }
    }
}
