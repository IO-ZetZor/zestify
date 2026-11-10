pragma Singleton
import QtQuick
import Quickshell
import "."

/**
 * Applies Hyprland layer rules that give translucent layer-shell surfaces a
 * blurred backdrop, mirroring Caelestia's approach. Blur is only enabled while
 * the configured transparency leaves the surfaces partially see-through.
 */
Singleton {
    id: root

    readonly property var namespaces: [
        "zestify-pill",
        "zestify-notifications",
        "zestify-notification-drawer",
        "zestify-osd"
    ]

    function applyLayerRules() {
        const curtainOpacity = Math.max(0, Math.min(1, Config.theme.transparency * Config.bar.opacity));
        Quickshell.execDetached(["hyprctl", "eval",
            'hl.layer_rule({ match = { namespace = "zestify-lock-pull" }, blur = '
                + (curtainOpacity < 1 ? "true" : "false") + ', ignore_alpha = '
                + Math.max(0.01, curtainOpacity - 0.03).toFixed(2) + ' })']);
        const blurEnabled = Config.theme.transparency < 1.0;
        const ignoreAlpha = Math.max(0, Math.min(1, Config.theme.transparency - 0.03)).toFixed(2);
        for (let i = 0; i < root.namespaces.length; i++) {
            const code = 'hl.layer_rule({ match = { namespace = "'
                + root.namespaces[i] + '" }, blur = '
                + (blurEnabled ? "true" : "false")
                + ', ignore_alpha = ' + ignoreAlpha + ' })';
            Quickshell.execDetached(["hyprctl", "eval", code]);
        }
    }
}
