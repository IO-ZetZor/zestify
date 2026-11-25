import QtQuick
import QtTest
import "../../shell/components"

Item {
    id: fixture
    width: 800
    height: 500
    property double now: 100000
    Theme { id: theme }
    FocusSession { id: session; clock: () => fixture.now }
    FocusCard {
        id: card
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        width: 360
        theme: theme
        session: session
    }
    SignalSpy { id: completion; target: session; signalName: "finished" }

    TestCase {
        name: "Focus"
        when: windowShown

        function init() {
            session.end();
            session.task = "";
            fixture.now = 100000;
            completion.clear();
            card.dismiss();
            card.enabled = true;
            card.defaultMode = "countdown";
            card.defaultMinutes = 25;
            card.defaultDnd = false;
            card.width = 360;
            card.s = 1;
            mouseMove(fixture, 790, 490);
            wait(220);
        }

        function test_countdown_elapsed_time_pause_resume_and_single_completion() {
            verify(session.start("  Review patch  ", "countdown", 25, true));
            compare(session.task, "Review patch");
            compare(session.timeText, "25:00");
            verify(session.suppressNotifications);
            fixture.now += 83456;
            session.pause();
            compare(session.timeText, "23:37");
            compare(session.status, "paused");
            const elapsed = session.elapsedMs;
            fixture.now += 300000;
            session.update();
            compare(session.elapsedMs, elapsed);
            session.resume();
            fixture.now += 1500000 - elapsed;
            session.update();
            compare(session.status, "finished");
            compare(session.timeText, "00:00");
            compare(completion.count, 1);
            verify(!session.suppressNotifications);
            fixture.now += 60000;
            session.update();
            compare(completion.count, 1);
        }

        function test_hidden_card_does_not_stop_countdown_and_end_preserves_task() {
            verify(session.start("Read docs", "countdown", 1, true));
            card.enabled = false;
            fixture.now += 60001;
            session.update();
            compare(session.status, "finished");
            compare(completion.count, 1);
            session.end();
            compare(session.status, "idle");
            compare(session.task, "Read docs");
            verify(!session.suppressNotifications);
        }

        function test_stopwatch_does_not_expire_and_formats_hours() {
            verify(session.start("Investigate", "stopwatch", 25, false));
            fixture.now += 3661000;
            session.update();
            compare(session.timeText, "1:01:01");
            compare(session.status, "running");
            compare(completion.count, 0);
            session.pause();
            fixture.now += 3000;
            session.resume();
            fixture.now += 2000;
            session.update();
            compare(session.timeText, "1:01:03");
        }

        function test_break_and_continue_require_explicit_action() {
            verify(session.start("Write", "countdown", 1, true));
            fixture.now += 60000;
            session.update();
            compare(session.status, "finished");
            verify(!session.onBreak);
            session.takeBreak();
            verify(session.onBreak);
            compare(session.timeText, "05:00");
            verify(!session.suppressNotifications);
            fixture.now += 300000;
            session.update();
            compare(session.status, "finished");
            compare(completion.count, 2);
            session.keepGoing();
            verify(!session.onBreak);
            compare(session.timeText, "01:00");
            verify(session.suppressNotifications);
            compare(session.task, "Write");
        }

        function test_validation_and_edit_do_not_replace_running_timer() {
            for (const minutes of [0, -1, 241, NaN, Infinity])
                verify(!session.start("Task", "countdown", minutes, false));
            verify(!session.start("   ", "countdown", 25, false));
            verify(!session.start("Task", "unknown", 25, false));
            verify(session.start("Task", "countdown", 50, false));
            fixture.now += 20000;
            session.update();
            verify(!session.start("Replacement", "stopwatch", 25, true));
            verify(session.editTask("New title"));
            compare(session.elapsedMs, 20000);
            compare(session.durationMinutes, 50);
            compare(session.task, "New title");
            verify(!session.editTask(" "));
        }

        function typeText(input, text) {
            mouseClick(input);
            input.selectAll();
            for (const character of text) keyClick(character);
        }

        function test_card_task_duration_dnd_start_pause_edit_and_end() {
            mouseClick(card, 120, 20);
            verify(card.editorOpen);
            wait(220);
            const input = findChild(card, "focusTaskInput");
            typeText(input, "Read docs");
            mouseClick(findChild(card, "focus50"));
            mouseClick(findChild(card, "focusQuiet"));
            mouseClick(findChild(card, "focusStart"));
            verify(!card.editorOpen);
            compare(session.task, "Read docs");
            compare(session.durationMinutes, 50);
            verify(session.suppressNotifications);
            mouseMove(card, 120, 20);
            wait(250);
            mouseClick(findChild(card, "focusPause"));
            compare(session.status, "paused");
            mouseClick(findChild(card, "focusEdit"));
            wait(220);
            typeText(input, "Read API");
            keyClick(Qt.Key_Return);
            compare(session.task, "Read API");
            compare(session.status, "paused");
            mouseMove(card, 120, 20);
            wait(220);
            mouseClick(findChild(card, "focusPause"));
            compare(session.status, "running");
            mouseClick(findChild(card, "focusEnd"));
            compare(session.status, "idle");
            verify(!session.suppressNotifications);
        }

        function test_card_stopwatch_custom_validation_escape_and_disable() {
            card.beginEdit();
            wait(220);
            card.taskDraft = "Debug";
            card.minutesDraft = "0";
            verify(!card.canCommit);
            card.minutesDraft = "17";
            verify(card.canCommit);
            mouseClick(findChild(card, "focusStopwatch"));
            compare(card.modeDraft, "stopwatch");
            keyClick(Qt.Key_Escape);
            verify(!card.editorOpen);
            compare(session.status, "idle");
            card.beginEdit();
            wait(220);
            card.taskDraft = "Debug";
            mouseClick(findChild(card, "focusStopwatch"));
            mouseClick(findChild(card, "focusStart"));
            compare(session.mode, "stopwatch");
            card.beginEdit();
            card.enabled = false;
            verify(!card.editorOpen);
            compare(session.status, "running");
        }

        function test_portrait_card_editor_and_finished_actions_fit() {
            card.s = 0.711;
            card.width = 360 * card.s;
            card.beginEdit();
            wait(250);
            const start = findChild(card, "focusStart");
            const edge = start.mapToItem(card, start.width, start.height);
            verify(edge.x <= card.width);
            verify(edge.y <= card.height);
            card.taskDraft = "A long task title that should be elided on a portrait display";
            card.minutesDraft = "1";
            card.commitEditor();
            fixture.now += 60000;
            session.update();
            card.hovered = true;
            wait(250);
            const end = findChild(card, "focusEnd");
            const endEdge = end.mapToItem(card, end.width, end.height);
            verify(endEdge.x <= card.width);
            verify(endEdge.y <= card.height);
        }
    }
}
