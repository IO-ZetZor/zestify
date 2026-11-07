pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import "../lib/notifications.js" as NotificationLib

Singleton {
    id: root

    property var history: []
    property var popups: []
    property bool dnd: false

    property int _nextLocalId: -1

    readonly property int maxHistory: 100
    readonly property int maxPopups: 5
    readonly property int defaultTimeout: 5000

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
        inlineReplySupported: true

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
            expires: notification.expireTimeout > 0
                ? Math.max(1000, notification.expireTimeout)
                : root.defaultTimeout
        };
    }

    function addServerNotification(notification) {
        if (!notification)
            return;
        const entry = root.entryFor(notification);
        root.history = NotificationLib.add(root.history, entry, root.maxHistory);
        if (NotificationLib.shouldPopup(root.dnd))
            root.popups = [entry].concat(root.popups).slice(0, root.maxPopups);

        notification.closed.connect(function() {
            root.removePopup(entry.id);
        });
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
            expires: expires > 0 ? expires : root.defaultTimeout
        };
        root.history = NotificationLib.add(root.history, entry, root.maxHistory);
        if (NotificationLib.shouldPopup(root.dnd))
            root.popups = [entry].concat(root.popups).slice(0, root.maxPopups);
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
        for (let i = 0; i < root.history.length; i++) {
            const entry = root.history[i];
            if (entry && entry.notification)
                entry.notification.dismiss();
        }
        root.history = NotificationLib.clear();
        root.popups = [];
    }

    function toggleDnd() {
        root.dnd = !root.dnd;
    }

    function expirePopup(id) {
        root.removePopup(id);
    }
}
