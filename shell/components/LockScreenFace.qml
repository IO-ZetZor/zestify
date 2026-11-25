pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls

Item {
    id: root

    property var theme
    property real s: 1
    property date now: new Date()
    property string userName: ""
    property string batteryText: ""
    property string prompt: "Pull down to lock"
    property bool ready: false
    property bool requestingLock: false
    property real handoffProgress: 0
    property bool locked: false
    property var auth: null
    property bool authActive: true
    property string layoutText: ""
    property bool capsLocked: false
    signal layoutRequested()
    signal sleepRequested()
    signal activateRequested()

    readonly property color foreground: theme ? theme.cream : "#e6e4f0"
    readonly property color dim: theme ? theme.dim : "#abaab5"
    readonly property color accent: theme ? theme.accent : "#bfc4ee"

    function fontPixels(size) {
        return Math.max(1, Math.round(size * s * 0.75)) * 4 / 3;
    }

    function focusResponse() {
        if (locked && authActive)
            response.forceActiveFocus();
    }

    function submit() {
        if (!auth || !authActive || auth.busy || !response.text.length)
            return;
        const value = response.text;
        response.clear();
        auth.submit(value);
    }

    onAuthActiveChanged: {
        response.clear();
        focusResponse();
    }
    onLockedChanged: focusResponse()
    Component.onCompleted: focusResponse()
    Component.onDestruction: response.clear()

    Connections {
        target: root.auth
        function onCleared() { response.clear(); root.focusResponse(); }
        function onBusyChanged() { root.focusResponse(); }
        function onAvailableChanged() { root.focusResponse(); }
    }

    Text {
        x: 36 * root.s
        y: 32 * root.s
        text: "Z E S T I F Y"
        color: root.dim
        font.family: root.theme ? root.theme.fontFamily : ""
        font.pixelSize: root.fontPixels(11)
    }

    Text {
        anchors.right: parent.right
        anchors.rightMargin: 36 * root.s
        y: 32 * root.s
        text: root.batteryText
        textFormat: Text.PlainText
        color: root.dim
        font.family: root.theme ? root.theme.fontFamily : ""
        font.pixelSize: root.fontPixels(12)
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.height / 2 - 300 * root.s - height / 2
        text: "󰌾"
        color: root.accent
        font.family: root.theme ? root.theme.iconFont : ""
        font.pixelSize: root.fontPixels(24)
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.height / 2 - 200 * root.s - height / 2
        text: Qt.formatDateTime(root.now, "HH:mm")
        color: root.foreground
        font.family: root.theme ? root.theme.fontFamily : ""
        font.pixelSize: root.fontPixels(88)
        font.weight: Font.Light
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.height / 2 - 120 * root.s - height / 2
        text: Qt.formatDateTime(root.now, "dddd, MMMM d")
        color: root.dim
        font.family: root.theme ? root.theme.fontFamily : ""
        font.pixelSize: root.fontPixels(17)
    }

    Item {
        id: card
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.height / 2 + 35 * root.s - height / 2
        width: Math.min(380 * root.s, root.width - 32 * root.s)
        height: 180 * root.s
        visible: !root.locked || root.authActive

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 40 * root.s - height / 2
            text: root.userName
            textFormat: Text.PlainText
            color: root.foreground
            font.family: root.theme ? root.theme.fontFamily : ""
            font.pixelSize: root.fontPixels(17)
            font.weight: Font.Medium
        }

        Item {
            id: inputArea
            anchors.horizontalCenter: parent.horizontalCenter
            y: 74 * root.s
            width: card.width - 70 * root.s
            height: 52 * root.s
            readonly property color responseColor: root.capsLocked ? "#e6c77d"
                : root.auth && root.auth.failed ? (root.theme ? root.theme.danger : "#f97386")
                : root.foreground
            readonly property real dotSize: 8 * root.s
            readonly property real dotSpacing: 8 * root.s
            readonly property int dotLimit: Math.max(1, Math.min(64,
                Math.floor((width + dotSpacing) / (dotSize + dotSpacing))))

            function syncDots() {
                const count = root.locked && !(root.auth && root.auth.responseVisible)
                    ? Math.min(response.text.length, dotLimit) : 0;
                // Append/remove only the changed slots so existing dots keep
                // their opacity while a new character fades in. Never copy
                // response text into the presentation model.
                while (dotModel.count < count) dotModel.append({ slot: dotModel.count });
                if (dotModel.count > count) dotModel.remove(count, dotModel.count - count);
            }
            onDotLimitChanged: syncDots()
            Connections {
                target: root.auth
                function onResponseVisibleChanged() { inputArea.syncDots(); }
            }
            ListModel { id: dotModel }

            Text {
                anchors.centerIn: parent
                text: "Pull to lock"
                visible: !root.locked
                opacity: 1 - root.handoffProgress
                color: root.dim
                font.family: root.theme ? root.theme.fontFamily : ""
                font.pixelSize: 13 * root.s
            }

            Text {
                anchors.centerIn: parent
                text: "Password"
                visible: !root.locked
                opacity: root.handoffProgress
                color: root.dim
                font.family: root.theme ? root.theme.fontFamily : ""
                font.pixelSize: 13 * root.s
            }

            TextField {
                id: response
                objectName: "lockResponse"
                anchors.fill: parent
                anchors.margins: 6 * root.s
                visible: root.locked
                enabled: root.locked && root.authActive
                readOnly: !root.auth || !root.auth.available || root.auth.busy
                background: Item {}
                // Retain a real focused editor for keyboard, IME and PAM
                // responses; render its presentation separately, without a
                // field, native password glyphs, selection or typing caret.
                opacity: 0
                horizontalAlignment: TextInput.AlignHCenter
                font.family: root.theme ? root.theme.fontFamily : ""
                font.pixelSize: 13 * root.s
                echoMode: root.auth && root.auth.responseVisible ? TextInput.Normal : TextInput.Password
                passwordCharacter: "●"
                maximumLength: 4096
                selectByMouse: false
                inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                cursorDelegate: Item {
                    width: 0
                    height: 0
                }
                onTextChanged: inputArea.syncDots()
                onVisibleChanged: inputArea.syncDots()
                onAccepted: root.submit()
                Keys.onEscapePressed: {
                    response.clear();
                    if (root.auth) root.auth.clear();
                }
            }

            Row {
                id: dots
                objectName: "lockDots"
                anchors.centerIn: parent
                spacing: inputArea.dotSpacing
                visible: root.locked && !(root.auth && root.auth.responseVisible)
                Repeater {
                    model: dotModel
                    Rectangle {
                        id: dot
                        required property int index
                        objectName: "lockDot" + index
                        width: inputArea.dotSize
                        height: width
                        radius: width / 2
                        color: inputArea.responseColor
                        opacity: 0
                        Component.onCompleted: appear.start()
                        NumberAnimation {
                            id: appear
                            target: dot
                            property: "opacity"
                            from: 0
                            to: 1
                            duration: 180
                            easing.type: Easing.OutCubic
                        }
                    }
                }
            }

            Text {
                objectName: "lockVisibleResponse"
                anchors.centerIn: parent
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                visible: root.locked && root.auth && root.auth.responseVisible
                text: visible ? response.text : ""
                textFormat: Text.PlainText
                color: inputArea.responseColor
                font: response.font
            }

            Text {
                objectName: "lockPrompt"
                anchors.centerIn: parent
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                visible: root.locked && !response.text.length
                text: root.auth && root.auth.busy ? "Verifying…"
                    : root.auth ? root.auth.prompt : "Password"
                textFormat: Text.PlainText
                color: root.dim
                font: response.font
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 155 * root.s - height / 2
            text: root.prompt
            visible: !root.locked
            opacity: 1 - root.handoffProgress
            color: root.ready ? root.accent : root.dim
            font.family: root.theme ? root.theme.fontFamily : ""
            font.pixelSize: root.fontPixels(11)
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 155 * root.s - height / 2
            width: card.width - 24 * root.s
            horizontalAlignment: Text.AlignHCenter
            text: root.auth && root.auth.feedback ? root.auth.feedback
                : root.capsLocked ? "Caps Lock is on" : "Enter to unlock · Esc to clear"
            textFormat: Text.PlainText
            elide: Text.ElideRight
            opacity: root.handoffProgress
            color: root.auth && root.auth.failed ? (root.theme ? root.theme.danger : "#f97386") : root.dim
            font.family: root.theme ? root.theme.fontFamily : ""
            font.pixelSize: root.fontPixels(11)
        }
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.height / 2 + 35 * root.s
        text: "Session locked · Click to unlock here"
        color: root.dim
        font.family: root.theme ? root.theme.fontFamily : ""
        font.pixelSize: root.fontPixels(17)
        visible: root.locked && !root.authActive
        MouseArea {
            anchors.fill: parent
            onClicked: root.activateRequested()
        }
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 36 * root.s
        text: root.layoutText
        textFormat: Text.PlainText
        color: root.dim
        font.family: root.theme ? root.theme.fontFamily : ""
        font.pixelSize: root.fontPixels(12)
        visible: root.locked && root.authActive
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: { root.layoutRequested(); root.focusResponse(); }
        }
    }

    Rectangle {
        anchors.right: parent.right
        anchors.rightMargin: 36 * root.s
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 28 * root.s
        width: 90 * root.s
        height: 36 * root.s
        radius: 18 * root.s
        color: "transparent"
        border.width: 1
        border.color: root.theme ? root.theme.withAlpha(root.theme.outline, 0.3) : "#4d74757f"
        opacity: root.handoffProgress
        MouseArea {
            anchors.fill: parent
            enabled: root.locked
            cursorShape: Qt.PointingHandCursor
            onClicked: root.sleepRequested()
        }

        Text {
            anchors.centerIn: parent
            text: "Sleep"
            color: root.dim
            font.family: root.theme ? root.theme.fontFamily : ""
            font.pixelSize: root.fontPixels(12)
        }
    }
}
