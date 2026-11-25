pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../components"
import Quickshell.Services.Mpris
import "../lib/time.js" as Time
import "../singletons"

SurfaceFrame {
    id: root

    property var screen
    property var players
    property var motion

    readonly property var player: root.players ? root.players.active : null

    property bool active: true
    readonly property real trackLength: root.player && root.player.metadata
        ? Math.max(0, Number(root.player.metadata["mpris:length"]) || 0) / 1000000
        : (root.player && root.player.lengthSupported ? root.player.length : 0)

    title: "Now playing"

    LyricsProvider {
        id: lyrics
        player: root.player
        active: root.active && root.visible
    }
    Timer {
        interval: 500
        repeat: true
        triggeredOnStart: true
        running: root.active && root.visible && root.player && root.player.isPlaying
        onTriggered: root.player.positionChanged()
    }

    function cycleLoop() {
        if (!root.player || !root.player.loopSupported)
            return;
        if (root.player.loopState === MprisLoopState.None)
            root.player.loopState = MprisLoopState.Track;
        else if (root.player.loopState === MprisLoopState.Track)
            root.player.loopState = MprisLoopState.Playlist;
        else
            root.player.loopState = MprisLoopState.None;
    }

    component Control: Rectangle {
        id: control

        property string glyph
        property bool active: false
        property bool available: true
        property real size: 34
        signal activated()

        Layout.preferredWidth: control.size * root.s
        Layout.preferredHeight: control.size * root.s
        radius: 9 * root.s
        color: control.active
            ? root.theme.withAlpha(root.theme.accent, 0.18)
            : (controlArea.containsMouse ? root.theme.withAlpha(root.theme.cream, 0.06) : "transparent")
        opacity: control.available ? 1 : 0.35

        Text {
            anchors.centerIn: parent
            text: control.glyph
            color: control.active ? root.theme.accent : root.theme.dim
            font.family: root.theme.iconFont
            font.pixelSize: 16 * root.s
        }

        MouseArea {
            id: controlArea
            anchors.fill: parent
            enabled: control.available
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: control.activated()
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 10 * root.s

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 182 * root.s
            Layout.maximumHeight: 182 * root.s
            spacing: 18 * root.s

            AlbumCover {
                Layout.preferredWidth: Math.min(180 * root.s, root.width * 0.35)
                Layout.preferredHeight: Layout.preferredWidth
                theme: root.theme
                s: root.s
                source: root.player ? root.player.trackArtUrl || "" : ""
                playing: root.player && root.player.isPlaying
                active: root.active && !(root.motion && root.motion.calm)
                onLongPressed: ShellState.toggleParty(root.screen ? root.screen.name : "")
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 4 * root.s

                Item { Layout.fillHeight: true }

                Text {
                    Layout.fillWidth: true
                    text: root.player ? (root.player.trackTitle || "Unknown track") : "Nothing playing"
                    color: root.theme.cream
                    font.family: root.theme.fontFamily
                    font.pixelSize: root.theme.fs.display * root.s
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                }

                Text {
                    Layout.fillWidth: true
                    text: {
                        if (!root.player)
                            return "Open a player to begin";
                        const artists = Time.joinArtists(root.player.trackArtist);
                        return artists.length > 0 ? artists : "Unknown artist";
                    }
                    color: root.theme.dim
                    font.family: root.theme.fontFamily
                    font.pixelSize: root.theme.fs.body * root.s
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    visible: root.player && root.player.trackAlbum
                    text: root.player ? root.player.trackAlbum : ""
                    color: root.theme.faint
                    font.family: root.theme.fontFamily
                    font.pixelSize: root.theme.fs.meta * root.s
                    elide: Text.ElideRight
                }

                Text {
                    Layout.fillWidth: true
                    text: root.player ? root.player.identity : ""
                    color: root.theme.faint
                    font.family: root.theme.monoFont
                    font.pixelSize: root.theme.fs.label * root.s
                    elide: Text.ElideRight
                }

                Item { Layout.fillHeight: true }
            }
        }

        LyricsView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 70 * root.s
            theme: root.theme
            s: root.s
            provider: lyrics
            players: root.players
        }

        Item {
            id: seekBar
            Layout.fillWidth: true
            Layout.preferredHeight: 16 * root.s

            readonly property real progress: root.player && root.trackLength > 0
                ? Math.max(0, Math.min(1, root.player.position / root.trackLength))
                : 0

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                height: 4 * root.s
                radius: height / 2
                color: root.theme.withAlpha(root.theme.outline, 0.35)
            }

            Rectangle {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(0, seekBar.width * seekBar.progress)
                height: 4 * root.s
                radius: height / 2
                color: root.theme.accent
            }

            Rectangle {
                x: Math.max(0, Math.min(seekBar.width - width, seekBar.width * seekBar.progress - width / 2))
                anchors.verticalCenter: parent.verticalCenter
                width: 10 * root.s
                height: 10 * root.s
                radius: width / 2
                color: root.theme.accent
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                enabled: root.player && root.player.canSeek && root.trackLength > 0
                onClicked: (mouse) => {
                    if (root.player && root.player.canSeek && root.trackLength > 0)
                        root.players.seek(Math.max(0, Math.min(1, mouse.x / width)) * root.trackLength);
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 3 * root.s

            Text {
                text: root.player ? Time.formatDuration(root.player.position) : "0:00"
                color: root.theme.faint
                font.family: root.theme.monoFont
                font.pixelSize: root.theme.fs.meta * root.s
            }

            Item { Layout.fillWidth: true }

            Control {
                glyph: "󰒝"
                size: 28
                visible: root.player && root.player.shuffleSupported
                active: root.player ? root.player.shuffle : false
                onActivated: if (root.player && root.player.shuffleSupported) root.player.shuffle = !root.player.shuffle
            }

            Control {
                glyph: "󰒮"
                size: 34
                available: root.player && root.player.canGoPrevious
                onActivated: root.players.previous()
            }

            Control {
                glyph: root.players && root.players.isPlaying ? "󰏤" : "󰐊"
                size: 42
                active: root.players && root.players.isPlaying
                available: root.player && root.player.canTogglePlaying
                onActivated: root.players.playPause()
            }

            Control {
                glyph: "󰒭"
                size: 34
                available: root.player && root.player.canGoNext
                onActivated: root.players.next()
            }

            Control {
                glyph: root.player && root.player.loopState === MprisLoopState.Track ? "󰑘" : "󰑖"
                size: 28
                visible: root.player && root.player.loopSupported
                active: root.player && root.player.loopState !== MprisLoopState.None
                onActivated: root.cycleLoop()
            }

            Item { Layout.fillWidth: true }

            Text {
                text: root.player ? Time.formatDuration(root.trackLength) : "0:00"
                color: root.theme.faint
                font.family: root.theme.monoFont
                font.pixelSize: root.theme.fs.meta * root.s
            }
        }
    }
}
