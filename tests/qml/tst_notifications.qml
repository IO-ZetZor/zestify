import QtQuick
import QtTest
import "../../shell/lib/notifications.js" as Notifications

TestCase {
    name: "Notifications"

    function entry(id, title) {
        return {
            id: id,
            appName: "Test",
            summary: title,
            body: "Body",
            urgency: 1,
            time: id,
            image: ""
        };
    }

    function test_adds_newest_first_and_trims_history() {
        let history = [];
        history = Notifications.add(history, entry(1, "first"), 3);
        history = Notifications.add(history, entry(2, "second"), 3);
        history = Notifications.add(history, entry(3, "third"), 3);
        history = Notifications.add(history, entry(4, "fourth"), 3);

        compare(history.length, 3);
        compare(history[0].id, 4);
        compare(history[1].id, 3);
        compare(history[2].id, 2);
    }

    function test_dismiss_removes_only_matching_entry() {
        const history = [entry(3, "third"), entry(2, "second"), entry(1, "first")];
        const next = Notifications.dismiss(history, 2);

        compare(next.length, 2);
        compare(next[0].id, 3);
        compare(next[1].id, 1);
        compare(history.length, 3);
    }

    function test_replacement_updates_existing_entry_without_duplicates() {
        const history = [entry(2, "second"), entry(1, "first")];
        const next = Notifications.add(history, entry(1, "updated"), 3);
        compare(next.length, 2);
        compare(next[0].summary, "updated");
        compare(next[1].id, 2);
    }

    function test_clear_returns_empty_history() {
        compare(Notifications.clear().length, 0);
    }

    function test_dnd_suppresses_popups_but_keeps_history() {
        compare(Notifications.shouldPopup(true), false);
        compare(Notifications.shouldPopup(false), true);
    }
}
