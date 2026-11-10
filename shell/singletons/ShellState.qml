pragma Singleton
import QtQuick
import Quickshell

/**
 * Global surface ownership. At most one expanded surface is open across all
 * monitors; opening another surface transfers ownership.
 */
Singleton {
    id: root

    property string surface: ""
    property string owner: ""
    property string notificationsOwner: ""

    function open(name, screenName) {
        if (!name || !name.length)
            return;
        if (name === "notifications") {
            openNotifications(screenName);
            return;
        }
        closeNotifications();
        root.surface = name;
        root.owner = screenName || "";
    }

    function openNotifications(screenName) {
        root.close();
        root.notificationsOwner = screenName || "";
    }

    function closeNotifications(screenName) {
        if (!screenName || root.notificationsOwner === screenName)
            root.notificationsOwner = "";
    }

    function close(screenName) {
        if (screenName && root.owner !== screenName)
            return;
        root.surface = "";
        root.owner = "";
    }

    function closeOtherSurfaces(screenName) {
        if (root.owner !== screenName)
            root.close();
    }

    function isOpenOn(screenName) {
        return root.surface.length > 0 && root.owner === screenName;
    }
}
