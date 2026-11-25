import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../../shell/components"
import "../../shell/singletons"

ShellRoot {
    id: root
    SessionLock { id: locker }
    Theme { id: themeObject; transparency: Config.theme.transparency }
    Variants {
        model: Quickshell.screens
        PanelWindow {
            required property var modelData
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            WlrLayershell.layer: WlrLayer.Background
            WlrLayershell.namespace: "zestify-unlock-test-desktop"
            color: "#26384b"
            mask: Region { width: 0; height: 0 }
        }
    }
    property var curtain: null
    Variants {
        model: Quickshell.screens
        LockPullWindow {
            required property var modelData
            targetScreen: modelData
            theme: themeObject
            backgroundOpacity: Config.bar.opacity
            Component.onCompleted: if (!root.curtain) root.curtain = this
        }
    }
    function findGesture(item) {
        if (item.handoffGeneration !== undefined) return item;
        for (const child of item.children || []) {
            const found = findGesture(child);
            if (found) return found;
        }
        return null;
    }
    function findNamed(item, name) {
        if (item.objectName === name) return item;
        for (const child of item.children || []) {
            const found = findNamed(child, name);
            if (found) return found;
        }
        return null;
    }
    IpcHandler {
        target: "zestify"
        function lock(): int { return locker.requestLock(""); }
        function lockStatus(): string { return locker.status(); }
        function testState(): string {
            return JSON.stringify({locked: Session.locked, locking: Session.locking,
                busy: locker.testAuth.busy, feedback: locker.testAuth.feedback,
                unlocking: locker.unlocking, pending: locker.pendingUnlockScreens,
                animated: locker.testUnlockAnimated, readySecure: locker.testReadySecure,
                exitActive: root.findNamed(root.curtain.contentItem, "unlockFade").active,
                exitProgress: root.findNamed(root.curtain.contentItem, "unlockFade").progress,
                screens: Quickshell.screens.map(screen => screen.name)});
        }
        function selectScreen(name: string): void { locker.authScreen = name; }
        function holdUnlock(value: bool): void { locker.testHoldUnlock = value; }
        function prepareCurtain(): void {
            const gesture = root.findGesture(curtain.contentItem);
            gesture.dragging = true;
            gesture.pull = gesture.height;
            gesture.handoffProgress = 1;
        }
        function curtainReady(): bool {
            const loader = root.findNamed(curtain.contentItem, "lockPullBlur");
            return loader && loader.item && loader.item.cached;
        }
        function curtainPreview(path: string): void {
            root.findNamed(curtain.contentItem, "lockPullBackground")
                .grabToImage(result => result.saveToFile(path));
        }
        function finishCurtain(): void {
            const gesture = root.findGesture(curtain.contentItem);
            gesture.dragging = false;
            gesture.requestingLock = true;
            gesture.handOff();
        }
    }
}
