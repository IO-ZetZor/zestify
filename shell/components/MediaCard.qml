pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../lib/time.js" as Time

RowLayout {
    id: root

    property var theme
    property var players
    property real s: 1
    property var motion
    property string scriptsDir: ""
    property bool active: true

    readonly property var player: root.players ? root.players.active : null

    signal coverActivated()
    signal partyRequested()

    LyricsProvider {
        id: lyrics
        player: root.player
        active: root.active && root.visible
    }

    spacing: 20 * root.s

    ColumnLayout {
        Layout.preferredWidth: 220 * root.s
        Layout.fillHeight: true
        spacing: 6 * root.s

        Item {
            Layout.fillHeight: true
        }

        AlbumCover {
            Layout.preferredWidth: 190 * root.s
            Layout.preferredHeight: 190 * root.s
            Layout.alignment: Qt.AlignHCenter
            theme: root.theme
            s: root.s
            source: root.player ? root.player.trackArtUrl || "" : ""
            playing: root.player && root.player.isPlaying
            active: root.active && !(root.motion && root.motion.calm)
            onClicked: root.coverActivated()
            onLongPressed: root.partyRequested()
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredHeight: 32 * root.s
            spacing: 6 * root.s

            component Control: Rectangle {
                id: control

                property string glyph
                property bool available: true
                property bool primary: false
                signal activated()

                Layout.preferredWidth: 32 * root.s
                Layout.preferredHeight: 32 * root.s
                radius: 10 * root.s
                color: control.primary
                    ? root.theme.withAlpha(root.theme.accent, 0.16)
                    : (controlArea.containsMouse
                        ? root.theme.withAlpha(root.theme.cream, 0.08)
                        : "transparent")
                opacity: control.available ? 1 : 0.35

                Text {
                    anchors.centerIn: parent
                    text: control.glyph
                    color: control.primary
                        ? root.theme.accent
                        : (controlArea.containsMouse ? root.theme.accent : root.theme.dim)
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

            Control {
                glyph: "󰒮"
                available: root.player && root.player.canGoPrevious
                onActivated: root.players.previous()
            }
            Control {
                glyph: root.players && root.players.isPlaying ? "󰏤" : "󰐊"
                primary: true
                available: root.player && root.player.canTogglePlaying
                onActivated: root.players.playPause()
            }
            Control {
                glyph: "󰒭"
                available: root.player && root.player.canGoNext
                onActivated: root.players.next()
            }
        }

        Item {
            Layout.fillHeight: true
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 2 * root.s

        Text {
            Layout.fillWidth: true
            text: root.player ? (root.player.trackTitle || "Unknown track") : "Nothing playing"
            color: root.theme.cream
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.fs.display * root.s
            font.weight: Font.DemiBold
            elide: Text.ElideRight
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
            font.pixelSize: root.theme.fs.title * root.s
            elide: Text.ElideRight
        }

        Text {
            Layout.fillWidth: true
            visible: root.player && String(root.player.trackAlbum || "").length > 0
            text: root.player ? (root.player.trackAlbum || "") : ""
            color: root.theme.faint
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.fs.body * root.s
            elide: Text.ElideRight
        }

        Text {
            Layout.fillWidth: true
            visible: root.player && String(root.player.identity || "").length > 0
            text: root.player ? (root.player.identity || "") : ""
            color: root.theme.accentDim
            font.family: root.theme.monoFont
            font.pixelSize: root.theme.fs.label * root.s
            elide: Text.ElideRight
        }

        VisualiserBars {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: 10 * root.s
            Layout.bottomMargin: 4 * root.s
            theme: root.theme
            s: root.s
            motion: root.motion
            scriptsDir: root.scriptsDir
            active: root.active
        }

        Text {
            Layout.fillWidth: true
            Layout.topMargin: 4 * root.s
            visible: lyrics.currentLine.length > 0
            text: lyrics.currentLine
            textFormat: Text.PlainText
            color: root.theme.accent
            font.family: root.theme.fontFamily
            font.pixelSize: root.theme.fs.body * root.s
            elide: Text.ElideRight
        }

        // Quickshell's Mpris position does not update reactively while a track
        // plays; poll it so the seek bar and elapsed time keep progressing.
        // Mirrors the reference player (500 ms media update interval).
        Timer {
            interval: 500
            running: root.active && root.visible && root.player && root.player.isPlaying
            triggeredOnStart: true
            repeat: true
            onTriggered: root.player.positionChanged()
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 18 * root.s
            spacing: 8 * root.s

            Text {
                text: root.player ? Time.formatDuration(root.player.position) : "0:00"
                color: root.theme.faint
                font.family: root.theme.monoFont
                font.pixelSize: root.theme.fs.meta * root.s
            }

            Item {
                id: seekBar
                Layout.fillWidth: true
                Layout.preferredHeight: 16 * root.s

                // Quickshell's length() falls back to position() when
                // lengthSupported is false (some players, e.g. Firefox,
                // don't expose mpris:length in a way Quickshell reads).
                // Read mpris:length from metadata directly (microseconds).
                readonly property real trackLength: root.player && root.player.metadata
                    ? Math.max(0, Number(root.player.metadata["mpris:length"]) || 0) / 1000000.0
                    : 0

                readonly property real progress: root.player && trackLength > 0
                    ? Math.max(0, Math.min(1, root.player.position / trackLength))
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
                    id: seekMouseArea
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    enabled: root.player && root.player.canSeek && seekBar.trackLength > 0
                    onClicked: (mouse) => {
                        if (root.player && root.player.canSeek && seekBar.trackLength > 0) {
                            const bw = seekBar.width > 0 ? seekBar.width : 1;
                            const fraction = Math.max(0, Math.min(1, mouse.x / bw));
                            root.players.seek(fraction * seekBar.trackLength);
                        }
                    }
                }
            }

            Text {
                text: root.player ? Time.formatDuration(seekBar.trackLength) : "0:00"
                color: root.theme.faint
                font.family: root.theme.monoFont
                font.pixelSize: root.theme.fs.meta * root.s
            }
        }
    }
}
