import QtQuick
import QtTest
import "../../shell/lib/merge.js" as Merge

TestCase {
    name: "Merge"

    function test_deep_merge_keeps_defaults() {
        const result = Merge.merge(
            { bar: { height: 34, topGap: 8 }, theme: { mode: "dark" } },
            { bar: { height: 40 } }
        );
        compare(result.bar.height, 40);
        compare(result.bar.topGap, 8);
        compare(result.theme.mode, "dark");
    }

    function test_invalid_user_value_keeps_default() {
        const result = Merge.merge({ bar: { height: 34 } }, { bar: { height: "bad" } });
        compare(result.bar.height, 34);
    }
}
