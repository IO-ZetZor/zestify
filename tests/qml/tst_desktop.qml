import QtQuick
import QtTest
import "../../shell/lib/desktop.js" as Desktop

TestCase {
    name: "Desktop"

    readonly property string kitty: "[Desktop Entry]\nName=Kitty\nExec=kitty --single-instance %U\nIcon=kitty\nTerminal=false\nNoDisplay=false\nCategories=System;TerminalEmulator;\n"

    function test_parses_desktop_entry() {
        const entry = Desktop.parse(kitty);
        compare(entry.name, "Kitty");
        compare(entry.exec, "kitty --single-instance %U");
        compare(entry.icon, "kitty");
        compare(entry.terminal, false);
        compare(entry.noDisplay, false);
        compare(entry.hidden, false);
        compare(entry.categories, ["System", "TerminalEmulator"]);
    }

    function test_ignores_comments_and_other_sections() {
        const text = "# a comment\n[Desktop Entry]\nName=Editor\nExec=editor %F\n# another comment\n\n[Desktop Action new]\nName=New Window\nExec=editor --new\n";
        const entry = Desktop.parse(text);
        compare(entry.name, "Editor");
        compare(entry.exec, "editor %F");
    }

    function test_parses_visibility_flags() {
        const entry = Desktop.parse("[Desktop Entry]\nName=Hidden\nExec=hidden\nTerminal=true\nNoDisplay=true\nHidden=true\nOnlyShowIn=Hyprland;GNOME;\n");
        compare(entry.terminal, true);
        compare(entry.noDisplay, true);
        compare(entry.hidden, true);
        compare(entry.onlyShowIn, ["Hyprland", "GNOME"]);
    }

    function test_resolve_exec_strips_field_codes() {
        compare(Desktop.resolveExec("kitty --single-instance %U"), ["kitty", "--single-instance"]);
        compare(Desktop.resolveExec("foo %F"), ["foo"]);
        compare(Desktop.resolveExec("foo \"bar baz\" %f"), ["foo", "bar baz"]);
        compare(Desktop.resolveExec("foo --file=%f"), ["foo", "--file="]);
    }

    function test_missing_entry_returns_empty_defaults() {
        const entry = Desktop.parse("");
        compare(entry.name, "");
        compare(entry.exec, "");
        compare(entry.terminal, false);
        compare(entry.noDisplay, false);
        compare(entry.hidden, false);
        compare(entry.categories, []);
    }

    function test_hidden_user_override_shadows_system_entry() {
        const entries = Desktop.collectFiles([
            { path: "/home/user/.local/share/applications/foo.desktop", text: "[Desktop Entry]\nName=Foo\nExec=foo\nHidden=true\n" },
            { path: "/usr/share/applications/foo.desktop", text: "[Desktop Entry]\nName=Foo System\nExec=foo\n" }
        ], ["Hyprland"]);
        compare(entries.length, 0);
    }

    function test_first_visible_entry_wins_and_results_are_sorted() {
        const entries = Desktop.collectFiles([
            { path: "/home/user/.local/share/applications/b.desktop", text: "[Desktop Entry]\nName=Zeta\nExec=zeta\n" },
            { path: "/usr/share/applications/b.desktop", text: "[Desktop Entry]\nName=Zeta System\nExec=zeta-system\n" },
            { path: "/usr/share/applications/a.desktop", text: "[Desktop Entry]\nName=Alpha\nExec=alpha\nOnlyShowIn=GNOME;\n" },
            { path: "/usr/share/applications/c.desktop", text: "[Desktop Entry]\nName=Alpha\nExec=alpha\n" }
        ], ["Hyprland"]);
        compare(entries.length, 2);
        compare(entries[0].name, "Alpha");
        compare(entries[1].name, "Zeta");
    }
}
