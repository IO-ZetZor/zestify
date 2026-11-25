pragma ComponentBehavior: Bound

import QtQuick
import "../backgrounds"
import "../lib/wallpapers.js" as WallpapersLib

Item {
    id: root
    objectName: "wallpaperStudio"
    property var theme
    property var screen
    property var wallpapers
    property var motion
    property real s: 1
    property string folder: ""
    property bool previewEnabled: true
    property string selectedPath: ""
    property string openingPath: currentPath
    property bool browsed: false
    property bool initialized: false
    signal closeRequested()
    signal applyRequested()

    readonly property string monitorName: screen ? screen.name : ""
    readonly property var collection: wallpapers ? wallpapers.items : []
    readonly property var items: {
        const index = collection.findIndex(item => item.path === openingPath);
        return index > 0 ? [collection[index]].concat(collection.slice(0, index), collection.slice(index + 1)) : collection;
    }
    readonly property string currentPath: wallpapers ? wallpapers.currentFor(monitorName) : ""
    readonly property var selectedItem: items.find(item => item.path === selectedPath) || null
    readonly property bool busy: wallpapers ? wallpapers.busy : false
    readonly property bool preparing: wallpapers ? !!wallpapers.preparing : false
    readonly property bool listing: wallpapers ? wallpapers.listing : false
    readonly property string error: wallpapers ? (wallpapers.lastError || wallpapers.previewError || "") : ""
    readonly property bool canApply: selectedItem !== null && !busy
    readonly property real u: Math.max(0.01, Math.min(s, width / 660, height / 700))

    function focusSelection() {
        if (root.enabled && root.previewEnabled && root.visible)
            orbit.forceActiveFocus(Qt.OtherFocusReason);
    }
    onEnabledChanged: if (enabled) Qt.callLater(root.focusSelection)

    function openAtCurrent() {
        if (!previewEnabled || browsed) return;
        openingPath = currentPath;
        selectedPath = items.some(item => item.path === currentPath) ? currentPath : (items.length ? items[0].path : "");
        orbit.currentIndex = Math.max(0, items.findIndex(item => item.path === selectedPath));
        root.focusSelection();
    }
    function clearPreview() {
        if (wallpapers) wallpapers.clearPreview(monitorName);
    }
    function preview(item) {
        if (!previewEnabled || busy || !item) return;
        browsed = true;
        selectedPath = item.path;
        wallpapers.preview(item, monitorName);
    }
    function selectIndex(index) {
        if (!previewEnabled || busy || !items.length) return;
        orbit.currentIndex = (index % items.length + items.length) % items.length;
        preview(items[orbit.currentIndex]);
        root.focusSelection();
    }
    function moveSelection(delta) {
        const index = items.findIndex(item => item.path === selectedPath);
        selectIndex((index < 0 ? 0 : index) + delta);
    }
    function applySelected(all) {
        if (!canApply) return;
        root.applyRequested();
        if (all) wallpapers.applyAll(selectedPath);
        else wallpapers.apply(selectedPath, monitorName);
    }
    onPreviewEnabledChanged: {
        if (!previewEnabled) clearPreview();
        else { browsed = false; Qt.callLater(openAtCurrent); }
    }
    onCurrentPathChanged: if (!browsed) Qt.callLater(openAtCurrent)
    onItemsChanged: {
        if (selectedPath.length && !items.some(item => item.path === selectedPath)) {
            selectedPath = "";
            clearPreview();
        }
        if (!browsed) Qt.callLater(openAtCurrent);
        else orbit.currentIndex = Math.max(0, items.findIndex(item => item.path === selectedPath));
    }
    Component.onCompleted: {
        initialized = true;
        Qt.callLater(openAtCurrent);
        if (wallpapers) wallpapers.refresh(true);
    }
    Component.onDestruction: clearPreview()

    Item {
        id: stage
        anchors.centerIn: parent
        width: 660 * root.u
        height: (root.error.length || !root.items.length ? 700 : 660) * root.u
        Item {
            id: grid
            objectName: "wallpaperGrid"
            anchors.horizontalCenter: parent.horizontalCenter
            width: 430 * root.u
            height: 520 * root.u
            PathView {
                id: orbit
                objectName: "wallpaperOrbit"
                width: parent.width
                height: 520 * root.u
                model: root.items
                pathItemCount: Math.min(9, root.items.length)
                cacheItemCount: 2
                preferredHighlightBegin: 0
                preferredHighlightEnd: 0
                highlightRangeMode: PathView.StrictlyEnforceRange
                highlightMoveDuration: root.motion && root.motion.calm ? 0 : (root.motion ? root.motion.morph : 420)
                interactive: !root.busy
                focus: true
                Accessible.role: Accessible.List
                Accessible.name: "Wallpapers"
                Accessible.description: "Click a circle or use arrows and the wheel to choose. Enter applies; Shift+Enter applies to all displays."
                Keys.onLeftPressed: root.moveSelection(-1)
                Keys.onUpPressed: root.moveSelection(-1)
                Keys.onRightPressed: root.moveSelection(1)
                Keys.onDownPressed: root.moveSelection(1)
                Keys.onReturnPressed: event => { if (!event.isAutoRepeat) root.applySelected(!!(event.modifiers & Qt.ShiftModifier)); }
                Keys.onEnterPressed: event => { if (!event.isAutoRepeat) root.applySelected(!!(event.modifiers & Qt.ShiftModifier)); }
                Keys.onEscapePressed: root.closeRequested()
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_R && !root.busy && !root.listing && root.wallpapers) {
                        root.wallpapers.refresh(true);
                        event.accepted = true;
                    }
                }
                onMovementEnded: {
                    if (root.previewEnabled && !root.busy && root.items[currentIndex])
                        root.preview(root.items[currentIndex]);
                }
                path: Path {
                    startX: 269 * root.u; startY: 44 * root.u
                    PathAttribute { name: "edgeVisibility"; value: 0 }
                    PathCubic {
                        x: 29 * root.u; y: 265 * root.u
                        control1X: 124 * root.u; control1Y: 44 * root.u
                        control2X: 29 * root.u; control2Y: 135 * root.u
                    }
                    PathAttribute { name: "edgeVisibility"; value: 1 }
                    PathCubic {
                        x: 269 * root.u; y: 486 * root.u
                        control1X: 29 * root.u; control1Y: 395 * root.u
                        control2X: 124 * root.u; control2Y: 486 * root.u
                    }
                    PathAttribute { name: "edgeVisibility"; value: 0 }
                }
                delegate: Item {
                    id: choice
                    required property var modelData
                    required property int index
                    readonly property bool selected: modelData.path === root.selectedPath
                    readonly property bool onOrbit: choice.PathView.onPath
                    readonly property real edgeVisibility: choice.PathView.edgeVisibility || 0
                    property bool entered: false
                    objectName: "wallpaperCard" + index
                    width: 58 * root.u
                    height: width
                    opacity: entered && onOrbit ? (selected ? 1 : Math.min(1, edgeVisibility * 5)) : 0
                    Behavior on opacity {
                        NumberAnimation {
                            duration: root.motion && root.motion.calm ? 0 : (root.motion ? root.motion.fast : 140)
                            easing.type: Easing.OutCubic
                        }
                    }
                    Component.onCompleted: entered = true
                    scale: selected ? 1.24 : 1
                    Behavior on scale { NumberAnimation { duration: root.motion && root.motion.calm ? 0 : 260; easing.type: Easing.OutCubic } }
                    z: selected ? 2 : 1
                    Rectangle {
                        objectName: "wallpaperThumbnail" + choice.index
                        anchors.fill: parent
                        radius: width / 2
                        color: root.theme.tileBg
                        layer.enabled: true
                        layer.smooth: true
                        layer.effect: ShaderEffect {
                            property var source
                            property vector2d shapeSize: Qt.vector2d(choice.width, choice.height)
                            property real cornerRadius: choice.width / 2
                            fragmentShader: "../shaders/rounded-card.frag.qsb"
                        }
                        Image {
                            objectName: "wallpaperImage" + choice.index
                            anchors.fill: parent
                            source: WallpapersLib.localUrl(choice.modelData.thumb)
                            sourceSize: Qt.size(160, 160)
                            asynchronous: true
                            retainWhileLoading: true
                            fillMode: Image.PreserveAspectCrop
                            smooth: true
                            mipmap: true
                            opacity: status === Image.Ready ? 1 : 0
                            Behavior on opacity {
                                NumberAnimation { duration: root.motion && root.motion.calm ? 0 : (root.motion ? root.motion.fast : 140) }
                            }
                        }
                    }
                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: "transparent"
                        border.width: choice.selected ? 3 : 1
                        border.color: choice.selected ? root.theme.cream : root.theme.border
                    }
                    Accessible.role: Accessible.ListItem
                    Accessible.name: modelData.name
                    Accessible.selected: selected
                    Accessible.onPressAction: root.selectIndex(choice.index)
                    TapHandler { onTapped: root.selectIndex(choice.index) }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                }
            }
            Rectangle {
                id: hero
                objectName: "wallpaperHero"
                x: 149 * root.u
                y: 140 * root.u
                width: 280 * root.u
                height: width
                radius: width / 2
                color: root.theme.tileBg
                layer.enabled: true
                layer.smooth: true
                layer.effect: ShaderEffect {
                    property var source
                    property vector2d shapeSize: Qt.vector2d(hero.width, hero.height)
                    property real cornerRadius: hero.width / 2
                    fragmentShader: "../shaders/rounded-card.frag.qsb"
                }
                Image {
                    anchors.fill: parent
                    source: root.selectedItem ? WallpapersLib.localUrl(root.selectedItem.thumb) : ""
                    sourceSize: Qt.size(640, 640)
                    retainWhileLoading: true
                    asynchronous: true
                    fillMode: Image.PreserveAspectCrop
                    smooth: true
                    mipmap: true
                }
                Loader {
                    objectName: "wallpaperHeroVideo"
                    anchors.fill: parent
                    active: root.previewEnabled && root.visible && root.selectedItem !== null && !!root.selectedItem.isVideo
                    sourceComponent: WallpaperPreviewFrame { item: root.selectedItem }
                }
                Rectangle {
                    anchors.fill: parent
                    color: "transparent"
                    radius: width / 2
                    border.width: 2
                    border.color: root.theme.withAlpha(root.theme.cream, 0.3)
                }
                Text {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 45 * root.u
                    visible: root.selectedItem !== null && !!root.selectedItem.isVideo
                    text: ""
                    font.family: root.theme.iconFont
                    font.pixelSize: 24 * root.u
                    color: root.theme.cream
                }
                TapHandler { onTapped: root.applySelected(false) }
                HoverHandler { cursorShape: root.canApply ? Qt.PointingHandCursor : Qt.ArrowCursor }
                Accessible.role: Accessible.Button
                Accessible.name: "Apply selected wallpaper to this display"
                Accessible.onPressAction: root.applySelected(false)
            }
        }
        Text {
            objectName: "wallpaperName"
            anchors.horizontalCenter: parent.horizontalCenter
            y: 530 * root.u
            width: 360 * root.u
            text: root.selectedItem ? root.selectedItem.name : "Wallpapers"
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideMiddle
            color: root.theme.cream
            font.family: root.theme.fontFamily
            font.pixelSize: 18 * root.u
        }
        Row {
            objectName: "wallpaperApplyButtons"
            anchors.horizontalCenter: parent.horizontalCenter
            y: 575 * root.u
            spacing: 10 * root.u
            Repeater {
                model: [{label: "Apply", all: false}, {label: "All displays", all: true}]
                delegate: Rectangle {
                    id: applyButton
                    required property var modelData
                    objectName: modelData.all ? "wallpaperApplyAll" : "wallpaperApply"
                    width: (modelData.all ? 138 : 112) * root.u
                    height: 40 * root.u
                    radius: 20 * root.u
                    enabled: root.canApply
                    opacity: enabled ? 1 : 0.45
                    color: modelData.all ? root.theme.withAlpha(root.theme.surface, 0.8) : root.theme.accent
                    activeFocusOnTab: true
                    Accessible.role: Accessible.Button
                    Accessible.name: modelData.label
                    Accessible.onPressAction: if (enabled) root.applySelected(modelData.all)
                    Keys.onReturnPressed: if (enabled) root.applySelected(modelData.all)
                    Keys.onSpacePressed: if (enabled) root.applySelected(modelData.all)
                    Keys.onEscapePressed: root.closeRequested()
                    Text {
                        anchors.centerIn: parent
                        text: root.preparing ? "Preparing…" : root.busy ? "Applying…" : applyButton.modelData.label
                        font.family: root.theme.fontFamily
                        font.pixelSize: 13 * root.u
                        color: applyButton.modelData.all ? root.theme.cream : root.theme.onAccent
                    }
                    TapHandler { onTapped: root.applySelected(applyButton.modelData.all) }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                }
            }
        }
        Text {
            objectName: "wallpaperHelp"
            anchors.horizontalCenter: parent.horizontalCenter
            y: 637 * root.u
            width: 560 * root.u
            text: "← / →  Choose     Enter  Apply     Shift+Enter  All displays     Esc  Close"
            horizontalAlignment: Text.AlignHCenter
            color: root.theme.dim
            font.family: root.theme.fontFamily
            font.pixelSize: 11 * root.u
        }
        Text {
            objectName: "wallpaperStatus"
            anchors.horizontalCenter: parent.horizontalCenter
            y: root.items.length ? 668 * root.u : 530 * root.u
            width: 580 * root.u
            visible: !root.items.length || root.error.length > 0
            text: root.error.length ? root.error : root.listing ? "Finding your wallpapers…" : "Add wallpapers to " + root.folder + " · Click to refresh"
            color: root.error.length ? root.theme.danger : root.theme.dim
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            font.family: root.theme.fontFamily
            font.pixelSize: 12 * root.u
            TapHandler { enabled: !root.busy && !root.listing; onTapped: if (root.wallpapers) root.wallpapers.refresh(true) }
        }
    }
    WheelHandler {
        onWheel: event => {
            const delta = event.angleDelta.y || event.angleDelta.x;
            if (delta) root.moveSelection(delta < 0 ? 1 : -1);
            event.accepted = true;
        }
    }
}
