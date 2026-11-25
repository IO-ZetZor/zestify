pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "."

/**
 * Applies Hyprland layer rules that give translucent layer-shell surfaces a
 * blurred backdrop, mirroring the reference approach. Blur is only enabled while
 * the configured transparency leaves the surfaces partially see-through.
 */
Singleton {
    id: root
    property string appliedSettings: ""
    property int ruleGeneration: 0
    property bool rulesPending: false

    readonly property var namespaces: [
        "zestify-pill",
        "zestify-focus",
        "zestify-notifications",
        "zestify-notification-drawer",
        "zestify-power-drawer",
        "zestify-shortcut-drawer",
        "zestify-osd"
    ]

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            // Compositor reloads discard runtime rules, even when our theme
            // settings did not change. Restore blur and surface motion rules.
            if (event.name !== "configreloaded") return;
            root.ruleGeneration++;
            root.appliedSettings = "";
            root.applyLayerRules();
        }
    }

    Process {
        id: layerRules
        property string settings: ""
        property int generation: 0
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0 && exitStatus === 0 && generation === root.ruleGeneration)
                root.appliedSettings = settings;
            if (root.rulesPending) {
                root.rulesPending = false;
                root.applyLayerRules();
            }
        }
    }

    function applyLayerRules() {
        if (layerRules.running) {
            root.rulesPending = true;
            return;
        }
        const settings = JSON.stringify([Config.theme.transparency, Config.bar.opacity]);
        if (settings === root.appliedSettings)
            return;
        const curtainOpacity = Math.max(0, Math.min(1, Config.theme.transparency * Config.bar.opacity));
        const commands = [
            'hl.layer_rule({ match = { namespace = "zestify-lock-pull" }, blur = '
                + (curtainOpacity < 1 ? "true" : "false") + ', ignore_alpha = '
                + Math.max(0.01, curtainOpacity - 0.03).toFixed(2) + ', no_anim = true })'];
        const blurEnabled = Config.theme.transparency < 1.0;
        const ignoreAlpha = Math.max(0, Math.min(1, Config.theme.transparency - 0.03)).toFixed(2);
        for (let i = 0; i < root.namespaces.length; i++) {
            const code = 'hl.layer_rule({ match = { namespace = "'
                + root.namespaces[i] + '" }, blur = '
                + (blurEnabled ? "true" : "false")
                + ', ignore_alpha = ' + ignoreAlpha
                // QML owns pill/drawer motion. Popups should appear as soon as
                // they arrive, without a second compositor transition.
                + (["zestify-pill", "zestify-shortcut-drawer", "zestify-notifications"]
                    .includes(root.namespaces[i]) ? ', no_anim = true' : '') + ' })';
            commands.push(code);
        }
        layerRules.settings = settings;
        layerRules.generation = root.ruleGeneration;
        layerRules.command = ["hyprctl", "eval", commands.join("; ")];
        layerRules.running = true;
    }
}
