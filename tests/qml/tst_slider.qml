import QtQuick
import QtTest
import "../../shell/components"

Rectangle {
    id: testRoot

    width: 400
    height: 200
    color: "transparent"

    QtObject {
        id: fakeTheme

        property color accent: "#ff0000"
        property color outline: "#888888"

        function withAlpha(color, alpha) {
            return Qt.rgba(color.r, color.g, color.b, alpha);
        }
    }

    ValueSlider {
        id: slider

        x: 0
        y: 0
        width: 200
        height: 20
        theme: fakeTheme
        s: 1
        from: 0
        to: 1
        stepSize: 0.01
        integer: false
        value: 0
    }

    TestCase {
        id: test

        name: "ValueSlider"
        when: windowShown

        SignalSpy {
            id: movedSpy
            target: slider
            signalName: "moved"
        }

        SignalSpy {
            id: committedSpy
            target: slider
            signalName: "committed"
        }

        function init() {
            slider.value = 0;
            slider.preview = -1;
            movedSpy.clear();
            committedSpy.clear();
        }

        function lastMoved() {
            return movedSpy.signalArguments[movedSpy.count - 1][0];
        }

        function test_drag_emits_values_while_moving() {
            mousePress(slider, 20, 10);
            wait(20);

            verify(movedSpy.count >= 1);
            verify(Math.abs(lastMoved() - 0.10) < 0.011);
            compare(committedSpy.count, 0);

            mouseMove(slider, 100, 10, 20, Qt.LeftButton);
            wait(20);

            verify(movedSpy.count >= 2);
            verify(Math.abs(lastMoved() - 0.50) < 0.011);
            compare(committedSpy.count, 0);

            mouseRelease(slider, 100, 10);
            wait(20);

            compare(committedSpy.count, 1);
            verify(Math.abs(committedSpy.signalArguments[0][0] - 0.50) < 0.011);
        }
    }
}
