import QtQuick
import QtTest
import QtQuick.Effects
import "../../shell/components"

Item {
    id: fixture
    width: 520; height: 240
    Rectangle {
        id: sourceRect
        width: cache.width; height: cache.height
        color: "#00ff00"
        Rectangle { id: stripe; width: parent.width / 2; height: parent.height; color: "#0000ff"; visible: false }
    }
    CachedBlur {
        id: cache
        x: 20; y: 20; width: 200; height: 160
        sourceItem: sourceRect
        sourceReady: true
        revision: 0
        blurMax: 16
    }
    MultiEffect {
        id: reference
        x: 280; y: 20; width: cache.width; height: cache.height
        source: sourceRect
        autoPaddingEnabled: false
        blurEnabled: true; blurMax: cache.blurMax; blur: cache.blur
        visible: false
    }
    TestCase {
        name: "CachedBlur"
        when: windowShown
        function init() {
            reference.visible = false;
            stripe.visible = false;
            cache.visible = true;
            cache.opacity = 1;
            cache.width = 200; cache.height = 160;
            cache.devicePixelRatio = fixture.Screen.devicePixelRatio;
            sourceRect.color = "#00ff00";
            cache.sourceReady = true;
            cache.revision++;
        }
        function test_cached_output_matches_live_blur() {
            if (fixture.GraphicsInfo.api === GraphicsInfo.Software)
                skip("Blur output requires the native shader backend");
            stripe.visible = true;
            reference.visible = true;
            cache.revision++;
            tryCompare(cache, "cached", true);
            wait(50);
            const picture = grabImage(fixture);
            for (let y = 4; y < cache.height - 4; y += 9)
                for (let x = 4; x < cache.width - 4; x += 9) {
                    verify(Math.abs(picture.red(x + 20, y + 20) - picture.red(x + 280, y + 20)) <= 2);
                    verify(Math.abs(picture.green(x + 20, y + 20) - picture.green(x + 280, y + 20)) <= 2, "green at " + x + "," + y + ": " + picture.green(x + 20, y + 20) + " vs " + picture.green(x + 280, y + 20));
                    verify(Math.abs(picture.blue(x + 20, y + 20) - picture.blue(x + 280, y + 20)) <= 2);
                }
        }
        function test_cache_invalidates_for_source_geometry_and_scale() {
            if (fixture.GraphicsInfo.api === GraphicsInfo.Software)
                skip("Blur output requires the native shader backend");
            tryCompare(cache, "cached", true);
            let picture = grabImage(fixture);
            verify(picture.green(100, 100) > 240);
            const generation = cache.generation;
            cache.opacity = 0.5;
            wait(50);
            compare(cache.generation, generation, "animated opacity must not invalidate blur");
            cache.opacity = 1;
            sourceRect.color = "#0000ff";
            cache.revision++;
            tryCompare(cache, "cached", true);
            wait(50);
            picture = grabImage(fixture);
            verify(picture.blue(100, 100) > 240);
            cache.width = 240;
            cache.devicePixelRatio = 2;
            tryCompare(cache, "cached", true);
            picture = grabImage(fixture);
            verify(picture.blue(220, 100) > 240);
        }
        function test_hidden_capture_reveals_and_refreshes() {
            if (fixture.GraphicsInfo.api === GraphicsInfo.Software)
                skip("Blur output requires the native shader backend");
            tryCompare(cache, "cached", true);
            cache.opacity = 0;
            sourceRect.color = "#0000ff";
            cache.revision++;
            cache.refresh();
            wait(50);
            cache.opacity = 1;
            tryCompare(cache, "cached", true);
            verify(grabImage(fixture).blue(100, 100) > 240);
            cache.visible = false;
            sourceRect.color = "#ff0000";
            cache.revision++;
            cache.refresh();
            wait(50);
            cache.visible = true;
            tryCompare(cache, "cached", true);
            verify(grabImage(fixture).red(100, 100) > 240);
        }
        function test_obsolete_completion_cannot_validate_unready_source() {
            if (fixture.GraphicsInfo.api === GraphicsInfo.Software)
                skip("Blur output requires the native shader backend");
            cache.invalidate();
            cache.refresh();
            cache.sourceReady = false;
            wait(100);
            compare(cache.cached, false);
            sourceRect.color = "#ff0000";
            cache.revision++;
            cache.sourceReady = true;
            tryCompare(cache, "cached", true);
            const picture = grabImage(fixture);
            verify(picture.red(100, 100) > 240);
        }
    }
}
