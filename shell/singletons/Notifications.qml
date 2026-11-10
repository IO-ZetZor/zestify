pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import "../lib/notifications.js" as NotificationLib
import "."

Singleton {
    id: root

    property var history: []
    property var popups: []
    readonly property bool dnd: Config.notifications.dnd

    property int _nextLocalId: -1
    property var _live: ({})

    readonly property int maxHistory: 100
    readonly property int maxPopups: 5
    readonly property int defaultTimeout: Config.notifications.timeout

    NotificationServer {
        id: server

        keepOnReload: true
        persistenceSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: true
        bodyImagesSupported: true
        actionsSupported: true
        actionIconsSupported: true
        imageSupported: true
        inlineReplySupported: false

        onNotification: (notification) => root.addServerNotification(notification)
    }

    function entryFor(notification) {
        return {
            id: notification.id,
            appName: notification.appName || "Notification",
            appIcon: notification.appIcon || "",
            summary: notification.summary || "",
            body: notification.body || "",
            urgency: NotificationUrgency.toString(notification.urgency),
            time: Date.now(),
            image: notification.image || "",
            notification: notification,
            expires: notification.expireTimeout === 0 ? 0 : notification.expireTimeout > 0
                ? Math.max(1000, notification.expireTimeout)
                : (notification.urgency === NotificationUrgency.Critical ? 0 : root.defaultTimeout)
        };
    }

    function addServerNotification(notification) {
        if (!notification)
            return;
        notification.tracked = true;
        const entry = root.entryFor(notification);
        root.storeEntry(entry);
        if (root._live[entry.id] === notification) return;
        root._live[entry.id] = notification;

        const update = function() {
            const fresh = root.entryFor(notification);
            root.history = root.history.map(item => item.id === entry.id ? fresh : item);
            root.popups = root.popups.map(item => item.id === entry.id ? fresh : item);
        };
        notification.summaryChanged.connect(update);
        notification.bodyChanged.connect(update);
        notification.appNameChanged.connect(update);
        notification.appIconChanged.connect(update);
        notification.imageChanged.connect(update);
        notification.urgencyChanged.connect(update);
        notification.expireTimeoutChanged.connect(update);

        notification.closed.connect(function() {
            root.removePopup(entry.id);
            root.history = root.history.map(item => item.id === entry.id
                ? Object.assign({}, item, {notification: null, image: ""}) : item);
            delete root._live[entry.id];
        });
    }

    function storeEntry(entry) {
        const evicted = root.history.filter(item => item && item.id !== entry.id).slice(root.maxHistory - 1);
        root.history = NotificationLib.add(root.history, entry, root.maxHistory);
        if (NotificationLib.shouldPopup(root.dnd))
            root.popups = NotificationLib.add(root.popups, entry, root.maxPopups);
        for (const old of evicted) {
            root.removePopup(old.id);
            if (old.notification) old.notification.expire();
        }
    }

    function notify(title, body, urgency, appName, expires) {
        const id = root._nextLocalId--;
        const entry = {
            id: id,
            appName: appName || "Zestify",
            appIcon: "",
            summary: title || "",
            body: body || "",
            urgency: urgency || "normal",
            time: Date.now(),
            image: "",
            notification: null,
            expires: expires === 0 ? 0 : (expires > 0 ? expires
                : (String(urgency).toLowerCase() === "critical" ? 0 : root.defaultTimeout))
        };
        root.storeEntry(entry);
        return id;
    }

    function removePopup(id) {
        root.popups = root.popups.filter(entry => !entry || entry.id !== id);
    }

    function dismiss(id) {
        const entry = root.history.find(item => item && item.id === id);
        if (entry && entry.notification)
            entry.notification.dismiss();
        root.history = NotificationLib.dismiss(root.history, id);
        root.removePopup(id);
    }

    function clear() {
        const entries = root.history.slice();
        for (let i = 0; i < entries.length; i++) {
            const entry = entries[i];
            if (entry && entry.notification)
                entry.notification.dismiss();
        }
        root.history = NotificationLib.clear();
        root.popups = [];
    }

    function toggleDnd() {
        Config.setValue("notifications.dnd", !root.dnd);
    }

    function expirePopup(id) {
        const entry = root.history.find(item => item && item.id === id);
        root.removePopup(id);
        if (entry && entry.notification) entry.notification.expire();
    }

    function invokeAction(id, identifier) {
        const entry = root.history.find(item => item && item.id === id);
        if (!entry || !entry.notification) return;
        const action = entry.notification.actions.find(item => item.identifier === identifier);
        if (action) action.invoke();
    }
}
