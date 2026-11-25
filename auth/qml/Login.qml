import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import Zestify.Login 1.0

ApplicationWindow {
    id: root
    objectName: "loginWindow"
    width: 1280
    height: 800
    visible: true
    visibility: Login.preview ? Window.Windowed : Window.FullScreen
    title: "Zestify Login"
    color: settings.background.color
    readonly property var settings: Theme.data
    readonly property string iconFamily: iconFont.status === FontLoader.Ready ? iconFont.name : settings.fonts.iconFamily
    property date now: new Date()
    property string selectedUser: ""
    property string selectedSession: ""
    font.family: bodyFont.status === FontLoader.Ready ? bodyFont.name : settings.fonts.family
    font.pixelSize: settings.form.textSize
    palette.window: settings.colors.panel
    palette.windowText: settings.colors.text
    palette.text: settings.colors.text
    palette.buttonText: settings.colors.text
    palette.base: settings.colors.input
    palette.button: settings.colors.button
    palette.highlight: settings.colors.selection
    palette.highlightedText: settings.colors.accentText

    FontLoader { id: bodyFont; objectName: "bodyFont"; source: Theme.assetUrl(root.settings.fonts.file) }
    FontLoader { id: clockFont; source: Theme.assetUrl(root.settings.fonts.clockFile) }
    FontLoader { id: iconFont; source: Theme.assetUrl(root.settings.fonts.iconFile) }

    function restoreSelection(model, wanted) {
        for (let i = 0; i < model.length; ++i)
            if (model[i].id === wanted) return i;
        return model.length > 0 ? 0 : -1;
    }
    function selectChoices() {
        if (!Login.ready) return;
        username.currentIndex = restoreSelection(Login.users,
            selectedUser || settings.form.defaultUser || Login.preferredUser);
        sessions.currentIndex = restoreSelection(Login.sessions,
            selectedSession || settings.form.defaultSession || Login.preferredSession);
        selectedUser = username.currentValue || "";
        selectedSession = sessions.currentValue || "";
    }
    function submit() {
        if (!Login.ready || (!Login.needsResponse && Login.busy) || !response.text.length) return;
        const value = response.text;
        response.clear();
        if (Login.needsResponse) Login.respond(value);
        else if (username.currentIndex >= 0 && sessions.currentIndex >= 0)
            Login.submitPassword(username.currentValue, sessions.currentValue, value);
    }
    function fieldRow(name) { return settings.form.fieldOrder.split(",").indexOf(name); }
    Timer { interval: 1000; running: root.visible; repeat: true; onTriggered: root.now = new Date() }
    Connections {
        target: Login
        function onClearResponse() { response.clear(); }
        function onChanged() {
            root.selectChoices();
            if (Login.ready && (!Login.busy || Login.needsResponse) && !editor.opened) response.forceActiveFocus();
        }
    }
    Component.onCompleted: selectChoices()

    Wallpaper {
        id: wallpaper
        objectName: "wallpaper"
        anchors.fill: parent
        playing: !root.settings.background.paused && root.visible
            && (!root.settings.background.pauseWhenInactive || root.active || Login.preview)
            && (!root.settings.background.pauseWhileAuthenticating || !Login.busy)
    }
    Positioned {
        objectName: "brandWidget"
        position: root.settings.brand.position
        visible: root.settings.brand.visible
        width: brandContents.implicitWidth
        height: brandContents.implicitHeight
        RowLayout {
            id: brandContents
            spacing: root.settings.form.iconSpacing
            ThemeIcon { spec: root.settings.icons.brand; family: root.iconFamily; color: root.settings.brand.color }
            Label {
                text: root.settings.brand.text
                textFormat: Text.PlainText
                color: root.settings.brand.color
                font.pixelSize: root.settings.brand.fontSize
                font.letterSpacing: root.settings.brand.letterSpacing
            }
        }
    }
    Positioned {
        objectName: "welcomeWidget"
        position: root.settings.welcome.position
        visible: root.settings.welcome.visible
        width: welcome.implicitWidth
        height: welcome.implicitHeight
        Label {
            id: welcome
            text: root.settings.welcome.text
            textFormat: Text.PlainText
            color: root.settings.welcome.color
            font.pixelSize: root.settings.welcome.fontSize
            font.letterSpacing: root.settings.welcome.letterSpacing
        }
    }
    Positioned {
        objectName: "clockWidget"
        position: root.settings.clock.position
        visible: root.settings.clock.visible || root.settings.clock.dateVisible
        width: Math.max(time.implicitWidth, date.implicitWidth)
        height: clockContents.implicitHeight
        Column {
            id: clockContents
            width: parent.width
            spacing: root.settings.clock.spacing
            Label {
                id: time
                objectName: "clockText"
                width: parent.width
                visible: root.settings.clock.visible
                text: Qt.formatDateTime(root.now, root.settings.clock.format)
                textFormat: Text.PlainText
                color: root.settings.colors.text
                font.family: clockFont.status === FontLoader.Ready ? clockFont.name : root.settings.fonts.clockFamily
                font.pixelSize: root.settings.clock.fontSize
                font.weight: root.settings.clock.weight
                horizontalAlignment: root.settings.clock.alignment === "left" ? Text.AlignLeft
                    : root.settings.clock.alignment === "right" ? Text.AlignRight : Text.AlignHCenter
            }
            Label {
                id: date
                width: parent.width
                visible: root.settings.clock.dateVisible
                text: Qt.formatDateTime(root.now, root.settings.clock.dateFormat)
                textFormat: Text.PlainText
                color: root.settings.colors.muted
                font.pixelSize: root.settings.clock.dateFontSize
                horizontalAlignment: time.horizontalAlignment
            }
        }
    }
    Positioned {
        id: panel
        objectName: "formWidget"
        position: root.settings.form.position
        width: Math.min(root.settings.form.width, (parent.width - 2 * margin) / uiScale)
        height: Math.min(scroll.contentHeight, (parent.height - 2 * margin) / uiScale)
        Rectangle {
            anchors.fill: parent
            radius: root.settings.form.radius
            color: root.settings.colors.panel
            opacity: root.settings.form.opacity * (1 - root.settings.layout.transparency)
            border.color: root.settings.colors.border
            border.width: root.settings.form.borderWidth
        }
        Flickable {
            id: scroll
            anchors.fill: parent
            clip: true
            contentWidth: width
            contentHeight: form.implicitHeight + 2 * root.settings.form.padding
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}
            function revealInput(input) {
                const bottom = input.y + input.height + root.settings.form.padding;
                if (bottom > contentY + height) contentY = bottom - height;
                if (input.y < contentY) contentY = input.y;
            }
            GridLayout {
                id: form
                x: root.settings.form.padding
                y: root.settings.form.padding
                width: Math.max(1, scroll.width - 2 * root.settings.form.padding)
                columns: 1
                rowSpacing: root.settings.form.spacing
                columnSpacing: 0
                Label {
                    Layout.row: root.fieldRow("title")
                    Layout.column: 0
                    visible: root.settings.form.showTitle
                    Layout.fillWidth: true
                    text: Login.needsResponse ? root.settings.form.verifyTitle : root.settings.form.title
                    textFormat: Text.PlainText
                    wrapMode: Text.WordWrap
                    color: root.settings.colors.text
                    font.pixelSize: root.settings.form.titleSize
                    font.weight: Font.Medium
                    horizontalAlignment: root.settings.form.titleAlignment === "left" ? Text.AlignLeft
                        : root.settings.form.titleAlignment === "right" ? Text.AlignRight : Text.AlignHCenter
                }
                LoginChoice {
                    id: username
                    Layout.row: root.fieldRow("username")
                    Layout.column: 0
                    objectName: "username"
                    Layout.fillWidth: true
                    iconSpec: root.settings.icons.user
                    iconFamily: root.iconFamily
                    enabled: Login.ready && !Login.busy
                    model: Login.users
                    showAccountId: true
                    onActivated: { root.selectedUser = currentValue; response.clear(); response.forceActiveFocus(); }
                    Keys.onEscapePressed: Login.cancel()
                }
                LoginChoice {
                    id: sessions
                    Layout.row: root.fieldRow("session")
                    Layout.column: 0
                    objectName: "sessions"
                    Layout.fillWidth: true
                    model: Login.sessions
                    textRole: "name"
                    valueRole: "id"
                    visible: root.settings.form.showSession
                    enabled: Login.ready && !Login.busy
                    iconSpec: root.settings.icons.session
                    iconFamily: root.iconFamily
                    onActivated: { root.selectedSession = currentValue; response.clear(); response.forceActiveFocus(); }
                }
                LoginField {
                    id: response
                    Layout.row: root.fieldRow("response")
                    Layout.column: 0
                    objectName: "response"
                    Layout.fillWidth: true
                    iconSpec: root.settings.icons.password
                    iconFamily: root.iconFamily
                    visible: true
                    enabled: Login.ready && (Login.needsResponse || (!Login.busy && username.currentIndex >= 0))
                    placeholderText: Login.busy && !Login.needsResponse ? root.settings.form.waitingText
                        : Login.needsResponse ? Login.prompt : root.settings.form.passwordPlaceholder
                    echoMode: Login.echo ? TextInput.Normal : TextInput.Password
                    maximumLength: 4096
                    selectByMouse: false
                    inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
                    onAccepted: root.submit()
                    onActiveFocusChanged: { if (activeFocus) Qt.callLater(scroll.revealInput, response); }
                    Keys.onEscapePressed: Login.cancel()
                }
                Label {
                    Layout.row: root.fieldRow("message")
                    Layout.column: 0
                    Layout.fillWidth: true
                    text: Login.ready && Login.users.length === 0 ? "No local login accounts found." : Login.message
                    visible: text.length > 0
                    wrapMode: Text.WordWrap
                    textFormat: Text.PlainText
                    color: Login.error ? root.settings.colors.error : root.settings.colors.muted
                    font.pixelSize: root.settings.form.messageSize
                }
                RowLayout {
                    Layout.row: root.fieldRow("actions")
                    Layout.column: 0
                    Layout.fillWidth: true
                    Item { Layout.fillWidth: true; visible: root.settings.form.buttonAlignment !== "left" }
                    ThemeButton {
                        text: root.settings.form.cancelText
                        iconSpec: root.settings.icons.cancel
                        iconFamily: root.iconFamily
                        visible: Login.busy
                        onClicked: Login.cancel()
                    }
                    Item { width: root.settings.form.iconSpacing }
                    ThemeButton {
                        objectName: "submit"
                        text: Login.busy ? (Login.needsResponse ? root.settings.form.continueText : root.settings.form.waitingText) : root.settings.form.submitText
                        iconSpec: root.settings.icons.submit
                        iconFamily: root.iconFamily
                        primary: true
                        enabled: Login.ready && response.text.length > 0
                            && (Login.needsResponse || (!Login.busy && username.currentIndex >= 0 && sessions.currentIndex >= 0))
                        onClicked: root.submit()
                    }
                    Item { Layout.fillWidth: true; visible: root.settings.form.buttonAlignment !== "right" }
                }
            }
        }
    }
    Positioned {
        objectName: "hintWidget"
        position: root.settings.hint.position
        visible: root.settings.hint.visible
        width: Math.min(hint.implicitWidth, (parent.width - 2 * margin) / uiScale)
        height: hint.implicitHeight
        Label {
            id: hint
            width: parent.width
            text: root.settings.hint.text
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            color: root.settings.hint.color
            font.pixelSize: root.settings.hint.fontSize
            font.letterSpacing: root.settings.hint.letterSpacing
        }
    }
    Button {
        objectName: "customize"
        visible: Login.preview
        anchors { right: parent.right; bottom: parent.bottom; margins: 16 }
        text: "Customize"
        onClicked: editor.open()
    }
    ThemeEditor {
        id: editor
        objectName: "themeEditor"
        wallpaperError: wallpaper.mediaError
        onClosed: { if (response.enabled) response.forceActiveFocus(); }
    }
}
