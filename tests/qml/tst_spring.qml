import QtQuick
import QtTest
import "../../shell/lib/spring.js" as Spring

TestCase {
    name: "Spring"

    function test_moves_toward_target_and_settles() {
        const w = 2 * Math.PI / 0.34;
        let x = 1;
        let v = 0;
        const first = Spring.step(x, v, w, 1, 1 / 60);
        verify(first[0] < x);

        x = first[0];
        v = first[1];
        for (let i = 0; i < 100; i++) {
            const next = Spring.step(x, v, w, 1, 1 / 60);
            x = next[0];
            v = next[1];
        }
        verify(Math.abs(x) < 0.01);
        verify(Math.abs(v) < 0.1);
    }
}
