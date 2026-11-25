pragma Singleton
import QtQuick
import Quickshell
import "../lib/party.js" as Party

/**
 * Global surface ownership. At most one expanded surface is open across all
 * monitors; opening another surface transfers ownership.
 */
Singleton {
    id: root

    property string surface: ""
    property string owner: ""
    property string notificationsOwner: ""
    property string powerOwner: ""
    property string shortcutsOwner: ""
    property string partyOwner: ""

    function open(name, screenName) {
        if (!name || !name.length)
            return;
        if (name === "notifications") {
            openNotifications(screenName);
            return;
        }
        if (name === "power") {
            openPower(screenName);
            return;
        }
        if (name === "shortcuts") {
            openShortcuts(screenName);
            return;
        }
        closeParty();
        closeNotifications();
        closePower();
        closeShortcuts();
        root.surface = name;
        root.owner = screenName || "";
    }

    function openNotifications(screenName) {
        closeParty();
        root.close();
        root.closePower();
        root.closeShortcuts();
        root.notificationsOwner = screenName || "";
    }

    function openPower(screenName) {
        closeParty();
        root.close();
        root.closeNotifications();
        root.closeShortcuts();
        root.powerOwner = screenName || "";
    }

    function openShortcuts(screenName) {
        closeParty();
        root.close();
        root.closeNotifications();
        root.closePower();
        root.shortcutsOwner = screenName || "";
    }

    function toggleParty(screenName) {
        if (!screenName)
            return;
        const next = Party.toggleOwner(root.partyOwner, screenName);
        if (next === screenName) {
            root.close();
            root.closeNotifications();
            root.closePower();
            root.closeShortcuts();
        }
        root.partyOwner = next;
    }

    function closeParty(screenName) {
        root.partyOwner = Party.closeOwner(root.partyOwner, screenName || "");
    }

    function isPartyOn(screenName) {
        return Party.isOn(root.partyOwner, screenName || "");
    }

    function closePower(screenName) {
        if (!screenName || root.powerOwner === screenName)
            root.powerOwner = "";
    }

    function closeShortcuts(screenName) {
        if (!screenName || root.shortcutsOwner === screenName)
            root.shortcutsOwner = "";
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
