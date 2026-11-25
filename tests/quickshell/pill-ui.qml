import QtQuick
import QtTest
import Quickshell
import "../../shell/components"

ShellRoot {
    Window {
        id: fixtureWindow
        visible: true
        width: 800
        height: 170
        color: fixtureTheme.surface

        Item {
            id: fixture
            anchors.fill: parent
            Theme { id: fixtureTheme }
            QtObject { id: telemetry; property real cpuPercent: 0 }
            QtObject {
                id: motion
                property bool calm: false
                readonly property int fast: 140
                readonly property int morph: 420
            }
            QtObject { id: media; property bool isPlaying: false }

            Component {
                id: startupModulesComponent
                PillModules {
                    theme: fixtureTheme
                    stats: telemetry
                    players: media
                    motion: motion
                    showTray: false
                    windowObject: fixtureWindow
                }
            }

            PillModules {
                id: modules
                x: 20
                y: 20
                width: implicitWidth
                height: 34
                theme: fixtureTheme
                stats: telemetry
                players: media
                motion: motion
                showTray: false
                windowObject: fixtureWindow
            }

            RemIcon {
                x: 20
                y: 70
                width: 80
                height: 80
                color: fixtureTheme.iconDim
            }

            SignalSpy { id: launcher; target: modules; signalName: "launcherRequested" }
            SignalSpy { id: system; target: modules; signalName: "systemRequested" }

            TestCase {
                id: tests
                name: "PillUI"
                when: false
                optional: true

                function exercise() {
                    const icon = findChild(modules, "pillLauncher");
                    const warning = findChild(modules, "pillCpuWarning");
                    const clock = findChild(modules, "pillClock");
                    const workspaces = findChild(modules, "pillWorkspaces");
                    const status = findChild(modules, "pillStatusIcons");
                    const rightGroup = findChild(modules, "pillRightGroup");
                    const visualiser = findChild(modules, "pillVisualiser");
                    const levels = findChild(visualiser, "visualiserLevels");
                    verify(icon !== null && warning !== null);
                    verify(!warning.visible);
                    verify(!visualiser.visible && !levels.active);
                    const idleWidth = modules.implicitWidth;
                    compare(modules.spacing, 28);
                    mouseClick(icon);
                    compare(launcher.count, 1);
                    mouseMove(fixture, 799, 169);
                    icon.forceActiveFocus();
                    keyClick(Qt.Key_Return);
                    compare(launcher.count, 2);
                    telemetry.cpuPercent = 90;
                    verify(!warning.visible);
                    telemetry.cpuPercent = 90.01;
                    verify(warning.visible);
                    wait(50);
                    verify(modules.implicitWidth >= idleWidth);
                    fuzzyCompare(clock.x + clock.width / 2, modules.width / 2, 1);
                    const workspaceRight = workspaces.mapToItem(modules, workspaces.width, 0).x;
                    fuzzyCompare(clock.x - workspaceRight, modules.spacing, 1);
                    verify(warning.mapToItem(modules, 0, 0).x - (clock.x + clock.width) >= modules.spacing - 1);
                    fuzzyCompare(rightGroup.mapToItem(modules, rightGroup.width, 0).x, modules.width, 1);
                    compare(workspaces.width, 107);
                    tryVerify(() => warning.pulse > 0.1);
                    mouseClick(warning);
                    compare(system.count, 1);
                    telemetry.cpuPercent = 99;
                    const highWidth = modules.implicitWidth;
                    telemetry.cpuPercent = 100;
                    wait(50);
                    compare(modules.implicitWidth, highWidth);
                    telemetry.cpuPercent = 90;
                    wait(50);
                    compare(modules.implicitWidth, idleWidth);
                    verify(!warning.visible && !warning.animating);
                    fuzzyCompare(clock.x + clock.width / 2, modules.width / 2, 1);
                    verify(status.mapToItem(modules, 0, 0).x - (clock.x + clock.width) >= modules.spacing - 1);
                    fuzzyCompare(rightGroup.mapToItem(modules, rightGroup.width, 0).x, modules.width, 1);
                    for (const scale of [1, 1.5]) {
                        modules.s = scale;
                        wait(50);
                        verify(icon.width >= 20 * scale && icon.height >= 20 * scale);
                        fuzzyCompare(workspaces.width, 107 * scale, 1);
                        for (let i = 0; i < 9; i++) {
                            const label = findChild(workspaces, "workspaceLabel-" + i);
                            compare(label.font.family, fixtureTheme.monoFont);
                            compare(label.font.pixelSize, Math.round(12 * scale));
                            compare(label.scale, 1);
                            compare(label.renderType, Text.NativeRendering);
                        }
                        fuzzyCompare(clock.x + clock.width / 2, modules.width / 2, 1);
                        fuzzyCompare(rightGroup.mapToItem(modules, rightGroup.width, 0).x, modules.width, 1);
                    }
                    modules.s = 1;
                    modules.width = 600;
                    wait(50);
                    fuzzyCompare(clock.x + clock.width / 2, modules.width / 2, 1);
                    fuzzyCompare(rightGroup.mapToItem(modules, rightGroup.width, 0).x, modules.width, 1);
                    fuzzyCompare(icon.mapToItem(modules, 0, 0).x, 0, 1);
                    modules.width = Qt.binding(() => modules.implicitWidth);
                    media.isPlaying = true;
                    compare(visualiser.opacity, 0, "Playback should begin with transparent bars");
                    wait(60);
                    verify(visualiser.opacity > 0 && visualiser.opacity < 0.4,
                           "Playback should fade in gently instead of popping into view");
                    tryCompare(visualiser, "opacity", 1, 500);
                    verify(visualiser.visible && levels.active);
                    compare(visualiser.barCount, 12);
                    fuzzyCompare(clock.x + clock.width / 2, modules.width / 2, 1);
                    verify(visualiser.mapToItem(modules, 0, 0).x >= clock.x + clock.width);
                    const bins = Array(32).fill(0);
                    bins[1] = 0.8;
                    bins[31] = 0.6;
                    visualiser.pushValues(bins);
                    compare(findChild(visualiser, "visualiserBar-0").level, 0.8);
                    compare(findChild(visualiser, "visualiserBar-11").level, 0.6);
                    compare(findChild(visualiser, "visualiserBar-2").level, 0);
                    const playingWidth = modules.implicitWidth;
                    modules.hovering = true;
                    verify(visualiser.opacity > 0, "Hover should fade the compact bars");
                    tryCompare(visualiser, "opacity", 0, 500);
                    tryCompare(levels, "active", false, 500);
                    compare(modules.implicitWidth, playingWidth, "Hover must retain clock spacing");
                    modules.hovering = false;
                    tryCompare(visualiser, "opacity", 1, 500);
                    verify(levels.active);
                    for (const scale of [1, 1.5]) {
                        modules.s = scale;
                        wait(50);
                        const left = visualiser.mapToItem(modules, 0, 0).x;
                        const right = visualiser.mapToItem(modules, visualiser.width, 0).x;
                        fuzzyCompare(left - (clock.x + clock.width), fixtureTheme.sp.m * scale, 1);
                        fuzzyCompare(rightGroup.mapToItem(modules, 0, 0).x - right,
                                     fixtureTheme.sp.m * scale, 1);
                        verify(visualiser.width >= 64 * scale - 1);
                        fuzzyCompare(clock.x + clock.width / 2, modules.width / 2, 1);
                    }
                    modules.s = 1;
                    wait(50);
                    modules.mediaActive = false;
                    verify(!levels.active);
                    modules.mediaActive = true;
                    fixtureWindow.visible = false;
                    verify(!levels.active, "Hidden display widgets must stop audio capture");
                    fixtureWindow.visible = true;
                    verify(levels.active);
                    modules.locked = true;
                    verify(!levels.active);
                    modules.locked = false;
                    media.isPlaying = false;
                    tryCompare(visualiser, "visible", false, 500);
                    verify(!levels.active);
                    fuzzyCompare(modules.implicitWidth, idleWidth, 1);
                    media.isPlaying = true;
                    tryCompare(visualiser, "opacity", 1, 500);
                    const startupModules = startupModulesComponent.createObject(fixture,
                        {width: 600, height: 34});
                    verify(startupModules !== null);
                    const startupVisualiser = findChild(startupModules, "pillVisualiser");
                    compare(startupVisualiser.opacity, 0, "Already-playing media should also fade in on load");
                    wait(60);
                    verify(startupVisualiser.opacity > 0 && startupVisualiser.opacity < 0.4);
                    tryCompare(startupVisualiser, "opacity", 1, 700);
                    startupModules.destroy();
                    telemetry.cpuPercent = 95;
                    mouseMove(fixture, 799, 169);
                    wait(100);
                    fixture.grabToImage(result => {
                        if (!result.saveToFile(Quickshell.env("PILL_UI_PREVIEW"))) {
                            console.error("PILL UI FAIL: preview could not be saved");
                            Qt.exit(1);
                        } else {
                            console.log("PILL UI PASS: launcher, CPU warning, balanced layout, workspace fonts, media bars and hover fade");
                            Qt.quit();
                        }
                    });
                }
            }

            Timer {
                interval: 200
                running: true
                onTriggered: {
                    try { tests.exercise(); }
                    catch (error) {
                        console.error("PILL UI FAIL:", error);
                        Qt.exit(1);
                    }
                }
            }
        }
    }
}
