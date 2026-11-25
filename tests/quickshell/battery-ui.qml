import QtQuick
import QtTest
import Quickshell
import Quickshell.Services.UPower
import "../../shell/components"
import "../../shell/surfaces"

ShellRoot {
    Window {
        id: testWindow
        visible: true
        width: fixture.width
        height: fixture.height
        color: fixtureTheme.surface
        Item {
            id: fixture
            width: 520
            height: 500

            Theme { id: fixtureTheme }
            Rectangle { anchors.fill: parent; color: fixtureTheme.surface }

            QtObject {
                id: profiles
                property int profile: PowerProfile.Balanced
                property bool hasPerformanceProfile: true
                property int degradationReason: PerformanceDegradationReason.None
            }

            BatterySurface {
                id: surface
                anchors.fill: parent
                theme: fixtureTheme
                powerProfiles: profiles
                device: ({isPresent: true, percentage: 0.76, state: UPowerDeviceState.Discharging,
                    timeToEmpty: 7200, timeToFull: 0, healthSupported: true, healthPercentage: 0.93,
                    changeRate: 12.4, energy: 42, energyCapacity: 55, model: "Test battery"})
            }

            TestCase {
                id: tests
                name: "BatteryUI"
                when: false
                optional: true

                function card(profile) {
                    return findChild(surface, "powerProfile" + profile);
                }

                function init() {
                    fixture.width = 520;
                    fixture.height = 500;
                    surface.s = 1;
                    profiles.profile = PowerProfile.Balanced;
                    profiles.hasPerformanceProfile = true;
                    profiles.degradationReason = PerformanceDegradationReason.None;
                    surface.device = {isPresent: true, percentage: 0.76, state: UPowerDeviceState.Discharging,
                        timeToEmpty: 7200, timeToFull: 0, healthSupported: true, healthPercentage: 0.93,
                        changeRate: 12.4, energy: 42, energyCapacity: 55, model: "Test battery"};
                    mouseMove(fixture, fixture.width - 1, fixture.height - 1);
                    wait(30);
                }

                function test_click_switches_profiles_and_external_changes_update_selection() {
                    verify(card(PowerProfile.Balanced).selected);
                    mouseClick(card(PowerProfile.PowerSaver));
                    compare(profiles.profile, PowerProfile.PowerSaver);
                    verify(card(PowerProfile.PowerSaver).selected);
                    verify(!card(PowerProfile.Balanced).selected);
                    mouseClick(card(PowerProfile.Performance));
                    compare(profiles.profile, PowerProfile.Performance);
                    profiles.profile = PowerProfile.Balanced;
                    verify(card(PowerProfile.Balanced).selected);
                    verify(!card(PowerProfile.Performance).selected);
                }

                function test_unsupported_performance_is_disabled_and_rejected() {
                    profiles.hasPerformanceProfile = false;
                    verify(!card(PowerProfile.Performance).enabled);
                    mouseClick(card(PowerProfile.Performance));
                    compare(profiles.profile, PowerProfile.Balanced);
                    surface.selectProfile(PowerProfile.Performance);
                    compare(profiles.profile, PowerProfile.Balanced);
                    compare(findChild(surface, "powerProfileStatus").text,
                        "Performance is unavailable on this system");
                    mouseClick(card(PowerProfile.PowerSaver));
                    compare(profiles.profile, PowerProfile.PowerSaver);
                    profiles.hasPerformanceProfile = true;
                    verify(card(PowerProfile.Performance).enabled);
                    compare(surface.profileStatus, "");
                }

                function test_keyboard_activation() {
                    card(PowerProfile.PowerSaver).forceActiveFocus();
                    keyClick(Qt.Key_Space);
                    compare(profiles.profile, PowerProfile.PowerSaver);
                    keyClick(Qt.Key_Tab);
                    verify(card(PowerProfile.Balanced).activeFocus);
                    keyClick(Qt.Key_Return);
                    compare(profiles.profile, PowerProfile.Balanced);
                    keyClick(Qt.Key_Tab);
                    keyClick(Qt.Key_Enter);
                    compare(profiles.profile, PowerProfile.Performance);
                }

                function test_degradation_status_updates_without_disabling_performance() {
                    profiles.degradationReason = PerformanceDegradationReason.HighTemperature;
                    compare(surface.profileStatus, "Performance limited by high temperature");
                    verify(card(PowerProfile.Performance).enabled);
                    profiles.degradationReason = PerformanceDegradationReason.LapDetected;
                    compare(surface.profileStatus, "Performance limited while on your lap");
                    profiles.degradationReason = PerformanceDegradationReason.None;
                    verify(!findChild(surface, "powerProfileStatus").visible);
                }

                function test_profiles_remain_usable_without_battery() {
                    surface.device = null;
                    verify(!surface.present);
                    mouseClick(card(PowerProfile.Performance));
                    compare(profiles.profile, PowerProfile.Performance);
                    surface.device = {isPresent: false};
                    verify(!surface.present);
                    mouseClick(card(PowerProfile.PowerSaver));
                    compare(profiles.profile, PowerProfile.PowerSaver);
                }

                function test_controls_fit_scaled_surface_data() {
                    return [
                        {tag: "normal", scale: 1, width: 520, height: 500},
                        {tag: "small", scale: 0.8, width: 416, height: 400},
                        {tag: "large", scale: 1.25, width: 650, height: 625},
                        {tag: "narrow", scale: 1, width: 320, height: 500}
                    ];
                }

                function test_controls_fit_scaled_surface(data) {
                    fixture.width = data.width;
                    fixture.height = data.height;
                    surface.s = data.scale;
                    profiles.degradationReason = PerformanceDegradationReason.HighTemperature;
                    wait(30);
                    for (const profile of [PowerProfile.PowerSaver, PowerProfile.Balanced, PowerProfile.Performance]) {
                        const control = card(profile);
                        const position = control.mapToItem(surface, 0, 0);
                        verify(position.x >= 0 && position.y >= 0);
                        verify(position.x + control.width <= surface.width);
                        verify(position.y + control.height <= surface.height);
                    }
                    const status = findChild(surface, "powerProfileStatus");
                    verify(status.mapToItem(surface, 0, status.height).y <= surface.height);
                }
            }
        }
    }

    Timer {
        interval: 100
        running: true
        onTriggered: {
            let activeCase = "";
            try {
                let count = 0;
                for (const name in tests) {
                    if (!name.startsWith("test_") || name.endsWith("_data"))
                        continue;
                    const dataFunction = tests[name + "_data"];
                    const rows = dataFunction ? dataFunction() : [null];
                    for (const row of rows) {
                        activeCase = name + (row ? " (" + row.tag + ")" : "");
                        tests.init();
                        tests[name](row);
                        count++;
                    }
                }
                if (count === 0)
                    throw new Error("No tests were discovered");
                tests.init();
                fixture.grabToImage(result => {
                    if (!result.saveToFile(Quickshell.env("BATTERY_UI_PREVIEW")))
                        console.error("BATTERY UI FAIL: could not save preview");
                    else
                        console.log("BATTERY UI PASS: " + count + " cases");
                    Qt.quit();
                });
            } catch (error) {
                console.error("BATTERY UI FAIL: " + activeCase + ": " + error);
                Qt.quit();
            }
        }
    }
}
