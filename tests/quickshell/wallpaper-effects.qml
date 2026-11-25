import QtQuick
import QtTest
import Quickshell
import "../../shell/singletons"

ShellRoot {
    id: fixture
    property var completed: []
    Connections {
        target: WallpaperEffects
        function onReady(source, maps) { fixture.completed = fixture.completed.concat([{source: source, maps: maps}]); }
    }
    TestCase {
        id: checks
        when: false
        optional: true
        function expect(condition, message, timeout) {
            const end = Date.now() + (timeout || 3000);
            while (!condition() && Date.now() < end) wait(10);
            if (!condition()) throw new Error(message);
        }
        function reset() {
            expect(() => !WallpaperEffects.busy && !WallpaperEffects.warming, "Workers did not settle", 5000);
            WallpaperEffects.invalidate();
            WallpaperEffects.pendingWarm = "";
            WallpaperEffects.warmDelay.stop();
            WallpaperEffects.lastWarmMs = 0;
            WallpaperEffects.watchdog.interval = 5000;
            fixture.completed = [];
        }
        function result(source) { return fixture.completed.filter(entry => entry.source === source); }
        function run() {
            reset();
            WallpaperEffects.prepare("shared");
            WallpaperEffects.prepare("shared");
            expect(() => result("shared").length === 1, "Shared output preparation was duplicated");
            const cached = result("shared")[0].maps.field;
            WallpaperEffects.prepare("shared");
            expect(() => result("shared").length === 2, "Cached maps were not returned");
            if (result("shared")[1].maps.field !== cached) throw new Error("Cache hit reran preparation");

            reset();
            WallpaperEffects.prepare("replaced");
            expect(() => result("replaced").length === 1, "First source did not prepare");
            const oldField = result("replaced")[0].maps.field;
            WallpaperEffects.invalidate();
            WallpaperEffects.prepare("replaced");
            expect(() => result("replaced").length === 2, "Rescan did not revalidate maps");
            if (result("replaced")[1].maps.field === oldField) throw new Error("Rescan reused stale maps");

            reset();
            WallpaperEffects.warm("obsolete");
            WallpaperEffects.warm("latest");
            WallpaperEffects.prepare("apply");
            expect(() => result("apply").length === 1 && !!WallpaperEffects.cache.latest, "Lookup or latest warming failed");
            if (WallpaperEffects.cache.obsolete) throw new Error("Obsolete selection was warmed");

            reset();
            WallpaperEffects.prepare("bad-json");
            WallpaperEffects.prepare("after-error");
            expect(() => fixture.completed.length === 2, "Invalid response blocked queue");
            if (!result("bad-json")[0].maps.fallback || result("after-error")[0].maps.kind !== "perfil")
                throw new Error("Invalid response did not use the safe fallback");

            reset();
            WallpaperEffects.prepare("transient");
            expect(() => result("transient").length === 1, "Temporary failure did not resolve");
            WallpaperEffects.prepare("transient");
            expect(() => result("transient").length === 2, "Temporary failure did not retry");
            if (result("transient")[0].maps.field === result("transient")[1].maps.field)
                throw new Error("Temporary inference failure was cached");

            reset();
            WallpaperEffects.warm("outline-soon");
            expect(() => WallpaperEffects.warming && WallpaperEffects.warmStarted, "Warm worker did not start");
            WallpaperEffects.lastWarmMs = 650;
            const started = Date.now();
            WallpaperEffects.prepare("outline-soon");
            expect(() => result("outline-soon").length === 1, "Near-ready outline was not delivered");
            if (result("outline-soon")[0].maps.kind !== "perfil" || Date.now() - started > 2200)
                throw new Error("Near-ready outline missed the two-second budget");

            reset();
            WallpaperEffects.warm("outline-slow");
            expect(() => WallpaperEffects.warming && WallpaperEffects.warmStarted, "Slow warm worker did not start");
            WallpaperEffects.lastWarmMs = 650;
            const slowStart = Date.now();
            WallpaperEffects.prepare("outline-slow");
            expect(() => result("outline-slow").length === 1, "Slow outline blocked Apply");
            if (result("outline-slow")[0].maps.kind !== "contagio" || Date.now() - slowStart > 2200)
                throw new Error("Slow outline exceeded the budget instead of spreading");
            expect(() => WallpaperEffects.cache["outline-slow"]?.kind === "perfil", "Slow mask was not cached in background", 4000);
            WallpaperEffects.prepare("outline-slow");
            expect(() => result("outline-slow").length === 2, "Cached outline did not resolve");
            if (result("outline-slow")[1].maps.kind !== "perfil") throw new Error("Cached outline did not replace spread");

            reset();
            const deadlineStart = Date.now();
            WallpaperEffects.prepare("deadline");
            expect(() => result("deadline").length === 1, "Slow cache lookup exceeded the budget");
            if (!result("deadline")[0].maps.fallback || Date.now() - deadlineStart > 2200)
                throw new Error("Bundled fallback did not respect the deadline");
            expect(() => WallpaperEffects.cache.deadline?.kind === "perfil", "Late lookup never warmed the missing mask", 4000);

            reset();
            WallpaperEffects.prepare("generation");
            expect(() => WallpaperEffects.busy && WallpaperEffects.started, "Generation lookup did not start");
            WallpaperEffects.invalidate();
            WallpaperEffects.prepare("generation");
            expect(() => result("generation").length === 2, "Replacement source did not prepare");
            if (!result("generation")[1].maps.field.endsWith("-2.png")) throw new Error("Old worker satisfied new-generation request");
            if (WallpaperEffects.cache.generation.field !== result("generation")[1].maps.field)
                throw new Error("Stale maps repopulated the cache");

            reset();
            WallpaperEffects.prepare("slow-overflow");
            expect(() => WallpaperEffects.busy && WallpaperEffects.started, "Overflow worker did not start");
            for (let i = 0; i < 12; i++) WallpaperEffects.prepare("overflow-" + i);
            expect(() => fixture.completed.length === 13 && !WallpaperEffects.busy, "Queue overflow stranded clients");
            for (let i = 0; i < 4; i++)
                if (!result("overflow-" + i)[0].maps.fallback) throw new Error("Dropped request lacked fallback");

            reset();
            WallpaperEffects.requests = {"missing-start": {deadline: Date.now()+2000, generation: WallpaperEffects.generation,
                candidate: WallpaperEffects.fallbackMaps}};
            WallpaperEffects.source = "missing-start";
            WallpaperEffects.workerGeneration = WallpaperEffects.generation;
            WallpaperEffects.started = false;
            WallpaperEffects.busy = true;
            WallpaperEffects.worker.command = ["/nonexistent/zestify-map-helper"];
            WallpaperEffects.worker.running = true;
            expect(() => result("missing-start").length === 1 && !WallpaperEffects.busy, "Missing helper stranded Apply");
            if (!result("missing-start")[0].maps.fallback) throw new Error("Missing helper did not use bundled maps");
            WallpaperEffects.prepare("after-missing");
            expect(() => result("after-missing").length === 1, "Missing helper blocked following job");
            console.log("WALLPAPER EFFECTS PASS: fast cache lookup, two-second outline budget, background warming, stale generations and failure recovery");
        }
    }
    Timer {
        interval: 50
        running: true
        onTriggered: {
            try { checks.run(); Qt.exit(0); }
            catch (error) { console.error("WALLPAPER EFFECTS FAIL:", error); Qt.exit(1); }
        }
    }
}
