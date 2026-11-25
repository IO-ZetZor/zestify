"""Dolphin profile integration without touching the real desktop session."""

import json
import py_compile
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from zesti.paths import Paths
from zesti.theme import apply_theme, theme_targets
from zesti.dolphin import prepare_purge


class DolphinThemeTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="dolphin user's ")
        self.root = Path(self.temp.name)
        self.paths = Paths.from_env({"HOME": str(self.root)})
        self.config = {"theme": {"apply": {
            target.name: {"enabled": target.name in ("dolphin", "qt")}
            for target in theme_targets(self.paths, {})
        }}}
        self.scheme = {"colours": {
            "primary": "a8baff", "onPrimary": "142440", "secondary": "c0cada",
            "tertiary": "dcbde0", "surface": "15151d", "onSurface": "e5e1eb",
            "error": "ffb4ab",
        }}

    def tearDown(self):
        self.temp.cleanup()

    def write(self, path, text):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        return path

    def apply(self):
        results = apply_theme(self.scheme, self.paths, self.config, run=lambda *a, **k: 0)
        self.assertFalse([result for result in results if not result["ok"]], results)

    def test_profile_preserves_settings_arguments_and_backups_across_palette_changes(self):
        config = self.write(self.paths.config_home / "qtengine/config.json", json.dumps({
            "theme": {"font": {"family": "Personal", "size": 12}, "style": "Fusion"},
            "misc": {"singleClickActivate": False},
        }))
        desktop = self.write(self.paths.data_home / "applications/org.kde.dolphin.desktop",
                             '[Desktop Entry]\nName=My Files\nExec=dolphin --new-window %u\nDBusActivatable=true\n'
                             '[Desktop Action Terminal]\nExec=konsole --workdir %u\n')
        kde = self.write(self.paths.config_home / "kdeglobals", '[Icons]\nTheme=Old\n[KDE]\nShowDeleteCommand=false\n')
        constants = self.write(self.paths.config_home / "hypr/conf/const.lua",
                               'local M = {}\nM.fileManager = "dolphin" -- Files\nM.browser = "zen-browser"\nreturn M\n')
        settings = self.write(self.paths.config_home / "dolphinrc",
                              '[IconsMode]\nIconSize=48\n[PreviewSettings]\nPlugins=imagethumbnail,directorythumbnail,ffmpegthumbnailer\n')
        original = {p: p.read_text() for p in (config, desktop, settings, constants)}
        self.apply()
        launcher = self.paths.config_home / "zestify/theme/dolphin-launch"
        output = launcher.with_name("dolphin.qss")
        self.assertTrue(launcher.stat().st_mode & 0o111)
        self.assertEqual(launcher.with_name("dolphin").resolve(), launcher)
        self.assertIn("dolphin-launch", constants.read_text())
        self.assertIn('M.browser = "zen-browser"', constants.read_text())
        service = self.paths.data_home / "dbus-1/services/org.kde.dolphin.FileManager1.service"
        self.assertIn(' --daemon', service.read_text())
        self.assertNotIn("SystemdService=", service.read_text())
        py_compile.compile(str(launcher), doraise=True)
        self.assertIn("palette(highlight)", output.read_text())
        self.assertIn("Name=My Files", desktop.read_text())
        self.assertIn('" --new-window %u', desktop.read_text())
        self.assertIn("DBusActivatable=false", desktop.read_text())
        self.assertIn("Exec=konsole --workdir %u", desktop.read_text())
        self.assertIn("Theme=zestify-minimal", kde.read_text())
        self.assertIn("ShowDeleteCommand=false", kde.read_text())
        self.assertIn("IconSize=48", settings.read_text())
        self.assertIn("Plugins=imagethumbnail,ffmpegthumbnailer", settings.read_text())
        data = json.loads(config.read_text())
        self.assertEqual(data["theme"]["iconTheme"], "zestify-minimal")
        self.assertEqual(data["theme"]["font"], {"family": "Personal", "size": 12})
        self.assertEqual(data["theme"]["style"], "Fusion")
        self.assertFalse(data["misc"]["singleClickActivate"])
        icons = self.paths.data_home / "icons/zestify-minimal"
        self.assertIn("FollowsColorScheme=true", (icons / "index.theme").read_text())
        self.assertIn("ColorScheme-Accent", (icons / "scalable/places/folder.svg").read_text())
        self.scheme["colours"]["primary"] = "ffcc88"
        self.apply()
        self.assertIn("#ffcc88", (self.paths.config_home / "qtengine/zestify.colors").read_text())
        self.assertEqual(output.read_text(), (Path(__file__).resolve().parents[2] / "data/templates/dolphin.qss").read_text())
        for path, text in original.items():
            self.assertEqual(path.with_name(path.name + ".zestify.bak").read_text(), text)

        link = self.root / ".local/bin/dolphin"
        link.parent.mkdir(parents=True, exist_ok=True)
        link.symlink_to(launcher)
        rules = self.write(self.paths.config_home / "hypr/conf/rules.lua",
                           '-- keep me\n-- >>> zestify-dolphin >>>\ndofile("profile")\n-- <<< zestify-dolphin <<<\n')
        prepare_purge(self.paths, self.root)
        self.assertFalse(link.is_symlink())
        self.assertIn("Exec=/usr/bin/dolphin --new-window %u", desktop.read_text())
        self.assertIn("Exec=konsole --workdir %u", desktop.read_text())
        self.assertEqual(rules.read_text(), "-- keep me\n")
        self.assertEqual(constants.read_text(), original[constants])
        self.assertFalse(service.exists())

    def test_profile_is_opt_in(self):
        target = next(t for t in theme_targets(self.paths, {}) if t.name == "dolphin")
        self.assertFalse(target.enabled)
        self.config["theme"]["apply"]["dolphin"]["enabled"] = False
        self.apply()
        self.assertFalse((self.paths.config_home / "zestify/theme/dolphin.qss").exists())
        self.assertNotIn("iconTheme", json.loads((self.paths.config_home / "qtengine/config.json").read_text())["theme"])

    def test_installed_profile_survives_boolean_apply_setting_and_can_be_disabled(self):
        self.apply()
        target = next(t for t in theme_targets(self.paths, {"theme": {"apply": True}}) if t.name == "dolphin")
        self.assertTrue(target.enabled)
        disabled = {"theme": {"apply": {"dolphin": {"enabled": False}}}}
        self.assertFalse(next(t for t in theme_targets(self.paths, disabled) if t.name == "dolphin").enabled)

    def test_custom_file_manager_is_preserved(self):
        original = 'M.fileManager = "thunar"\n'
        constants = self.write(self.paths.config_home / "hypr/conf/const.lua", original)
        self.apply()
        self.assertEqual(constants.read_text(), original)

    @unittest.skipUnless(shutil.which("desktop-file-validate"), "desktop validator unavailable")
    def test_desktop_escaping_and_reapply_with_reserved_path_characters(self):
        self.paths = Paths.from_env({"HOME": str(self.root / 'back\\slash "quote" $cash `tick` %percent')})
        desktop = self.write(self.paths.data_home / "applications/org.kde.dolphin.desktop",
                             '[Desktop Entry]\nType=Application\nName=Files\nExec=dolphin --new-window %u\n')
        self.apply()
        first = desktop.read_text()
        self.apply()
        self.assertEqual(desktop.read_text(), first)
        checked = subprocess.run(["desktop-file-validate", str(desktop)], capture_output=True, text=True)
        self.assertEqual(checked.returncode, 0, checked.stderr + checked.stdout)


if __name__ == "__main__":
    unittest.main()
