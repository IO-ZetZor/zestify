import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root
    property var flow: null
    property var theme: null
    property string failure: ""
    readonly property color cream: theme ? theme.cream : "#e6e4f0"
    readonly property color dim: theme ? theme.dim : "#abaab5"
    readonly property color accent: theme ? theme.accent : "#bfc4ee"
    readonly property color danger: theme ? theme.danger : "#f97386"
    readonly property bool responseRequired: flow && flow.isResponseRequired && !flow.isCompleted
    implicitWidth: 420
    implicitHeight: content.implicitHeight + 48
    radius: 24
    color: theme ? theme.surfaceHigh : "#14151f"
    border.color: theme ? theme.border : "#363846"
    border.width: 1

    function submit() {
        if (!responseRequired) return;
        const value = response.text;
        response.clear();
        failure = "";
        flow.submit(value);
    }
    function cancel() {
        response.clear();
        if (flow && !flow.isCompleted) flow.cancelAuthenticationRequest();
    }
    function resetResponse() {
        response.clear();
        if (responseRequired) response.forceActiveFocus();
    }
    onFlowChanged: { failure = ""; resetResponse(); }
    onResponseRequiredChanged: resetResponse()
    Component.onDestruction: response.clear()

    Connections {
        target: root.flow
        function onAuthenticationFailed() {
            root.failure = "Authentication failed. Try again.";
            root.resetResponse();
        }
        function onSelectedIdentityChanged() { root.failure = ""; root.resetResponse(); }
        function onIsCompletedChanged() { root.resetResponse(); }
        function onInputPromptChanged() { root.resetResponse(); }
    }

    ColumnLayout {
        id: content
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 24 }
        spacing: 16
        Label {
            text: "Authentication required"
            color: root.cream
            font.family: root.theme ? root.theme.fontFamily : "sans-serif"
            font.pixelSize: 20
            font.weight: Font.Medium
        }
        Label {
            Layout.fillWidth: true
            text: root.flow ? root.flow.message : ""
            color: root.dim
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            font.pixelSize: 14
        }
        ComboBox {
            id: identities
            objectName: "identities"
            Layout.fillWidth: true
            visible: root.flow && root.flow.identities.length > 1
            enabled: root.flow && !root.flow.isCompleted
            model: root.flow ? root.flow.identities.map(identity => identity.displayName || identity.string) : []
            currentIndex: root.flow ? root.flow.identities.indexOf(root.flow.selectedIdentity) : -1
            onActivated: index => {
                if (root.flow && index >= 0 && index < root.flow.identities.length)
                    root.flow.selectedIdentity = root.flow.identities[index];
            }
            palette.button: root.theme ? root.theme.tileBg : "#222432"
            palette.buttonText: root.cream
            palette.text: root.cream
            palette.base: root.color
            palette.highlight: root.accent
        }
        Label {
            Layout.fillWidth: true
            visible: root.flow && root.flow.identities.length === 1
            text: root.flow && root.flow.selectedIdentity ? "Authenticate as "
                + (root.flow.selectedIdentity.displayName || root.flow.selectedIdentity.string) : ""
            textFormat: Text.PlainText
            color: root.dim
            font.pixelSize: 12
        }
        TextField {
            id: response
            objectName: "authResponse"
            Layout.fillWidth: true
            implicitHeight: 48
            enabled: root.responseRequired
            placeholderText: root.flow ? root.flow.inputPrompt || "Password" : "Password"
            echoMode: root.flow && root.flow.responseVisible ? TextInput.Normal : TextInput.Password
            maximumLength: 4096
            color: root.cream
            placeholderTextColor: root.dim
            selectByMouse: false
            inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText | Qt.ImhNoAutoUppercase
            background: Rectangle {
                radius: 12
                color: root.theme ? root.theme.tileBg : "#0d0e15"
                border.width: response.activeFocus ? 2 : 1
                border.color: response.activeFocus ? root.accent : (root.theme ? root.theme.outline : "#363846")
            }
            onAccepted: root.submit()
            Keys.onEscapePressed: root.cancel()
        }
        Label {
            Layout.fillWidth: true
            text: root.failure || (root.flow ? root.flow.supplementaryMessage : "")
            visible: text.length > 0
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            color: root.failure || (root.flow && root.flow.supplementaryIsError) ? root.danger : root.dim
            font.pixelSize: 12
        }
        RowLayout {
            Layout.fillWidth: true
            Button {
                objectName: "authCancel"
                text: "Cancel"
                onClicked: root.cancel()
                palette.button: root.theme ? root.theme.tileBg : "#222432"
                palette.buttonText: root.cream
            }
            Item { Layout.fillWidth: true }
            Button {
                objectName: "authSubmit"
                text: root.responseRequired ? "Authenticate" : "Please wait…"
                enabled: root.responseRequired
                onClicked: root.submit()
                palette.button: root.accent
                palette.buttonText: root.theme ? root.theme.onAccent : "#383e61"
            }
        }
    }
}
