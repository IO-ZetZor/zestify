"""Application theme rendering tests for zesti.

Tests inject fake targets/renderers so no real desktop config is touched and
template rendering is isolated from application adapters.
"""

import json
import os
import tempfile
import threading
import unittest
from pathlib import Path
from unittest.mock import patch

from zesti.paths import Paths
from zesti.theme import (
    ThemeError,
    ThemeResult,
    ThemeTarget,
    apply_theme,
    render_template,
    theme_targets,
)


def fake_paths(env_overrides=None):
    env = {
        "XDG_STATE_HOME": "/tmp/zt/state",
        "XDG_CACHE_HOME": "/tmp/zt/cache",
        "XDG_CONFIG_HOME": "/tmp/zt/config",
    }
    if env_overrides:
        env.update(env_overrides)
    return Paths.from_env(env)


SCHEME = {
    "mode": "dark",
    "variant": "tonal-spot",
    "colours": {
        "primary": "8bceff",
        "onPrimary": "1a1c1e",
        "secondary": "b7c9d9",
        "surface": "1a1c1e",
        "background": "1a1c1e",
        "error": "ff5449",
    },
    "metadata": {"name": "test", "flavour": "tonalspot", "mode": "dark", "variant": "tonal-spot", "colours": 6},
}


class RenderTemplateTest(unittest.TestCase):
    def test_exact_hex_without_hash(self):
        self.assertEqual(render_template("{primary}", SCHEME["colours"], "dark"), "8bceff")

    def test_hash_prefix(self):
        self.assertEqual(render_template("{primary}", SCHEME["colours"], "dark", hash_prefix=True), "#8bceff")

    def test_hash_prefix_idempotent(self):
        self.assertEqual(render_template("#{primary}", SCHEME["colours"], "dark", hash_prefix=True), "#8bceff")

    def test_mode_substitution(self):
        self.assertEqual(render_template("mode={mode}", SCHEME["colours"], "light"), "mode=light")

    def test_multiple_placeholders(self):
        text = "bg={background} fg={onPrimary} err={error}"
        self.assertEqual(render_template(text, SCHEME["colours"], "dark"), "bg=1a1c1e fg=1a1c1e err=ff5449")

    def test_unknown_placeholder_fails(self):
        with self.assertRaises(ThemeError):
            render_template("{noSuchColour}", SCHEME["colours"], "dark")


class ThemeTargetTest(unittest.TestCase):
    def test_theme_target_immutable(self):
        t = ThemeTarget(name="t", enabled=True, template="{primary}", output=Path("/tmp/x"))
        with self.assertRaises((AttributeError, Exception)):
            t.name = "other"


class ApplyThemeTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.home = self.root / "home"
        self.home.mkdir()
        self.env = {
            "HOME": str(self.home),
            "XDG_STATE_HOME": str(self.home / ".local/state"),
            "XDG_CACHE_HOME": str(self.home / ".cache"),
            "XDG_CONFIG_HOME": str(self.home / ".config"),
        }
        self.paths = Paths.from_env(self.env)
        self.paths.state_home.mkdir(parents=True, exist_ok=True)

    def tearDown(self):
        self.temp.cleanup()

    def _config(self, targets):
        return {"theme": {"apply": targets}}

    def test_applies_enabled_targets_and_skips_disabled(self):
        out_ok = self.home / "ok.sh"
        out_skip = self.home / "skip.sh"
        config = self._config({
            "ok": {"enabled": True, "template": "bg={background}", "output": str(out_ok)},
            "skip": {"enabled": False, "template": "bg={background}", "output": str(out_skip)},
        })
        results = apply_theme(SCHEME, self.paths, config, run=lambda *a, **k: 0)
        by_name = {r["target"]: r for r in results}
        self.assertTrue(by_name["ok"]["ok"])
        self.assertEqual(out_ok.read_text().strip(), "bg=1a1c1e")
        self.assertTrue(by_name["skip"]["ok"])  # skipped counts as ok/no-op
        self.assertFalse(out_skip.exists())

    def test_failure_isolation(self):
        out_good = self.home / "good.sh"
        out_bad = self.home / "bad.sh"
        config = self._config({
            "good": {"enabled": True, "template": "bg={background}", "output": str(out_good)},
            "bad": {"enabled": True, "template": "nope={noSuchColour}", "output": str(out_bad)},
        })
        results = apply_theme(SCHEME, self.paths, config, run=lambda *a, **k: 0)
        by_name = {r["target"]: r for r in results}
        self.assertTrue(by_name["good"]["ok"])
        self.assertEqual(out_good.read_text().strip(), "bg=1a1c1e")
        self.assertFalse(by_name["bad"]["ok"])
        self.assertIn("error", by_name["bad"])
        self.assertFalse(out_bad.exists())

    def test_output_writes_are_atomic_no_temp_left(self):
        out = self.home / "out.sh"
        config = self._config({
            "t": {"enabled": True, "template": "x={primary}", "output": str(out)},
        })
        apply_theme(SCHEME, self.paths, config, run=lambda *a, **k: 0)
        self.assertTrue(out.exists())
        self.assertEqual(out.read_text().strip(), "x=8bceff")
        leftovers = [p for p in self.paths.state_home.rglob("*") if p.suffix in (".tmp", ".bak")]
        self.assertEqual(leftovers, [])

    def test_concurrent_calls_serialize_on_theme_lock(self):
        out1 = self.home / "a.sh"
        out2 = self.home / "b.sh"
        config = self._config({
            "t": {"enabled": True, "template": "x={primary}", "output": str(out1)},
        })
        barrier = threading.Barrier(2)
        errors = []

        def worker(path):
            try:
                barrier.wait()
                apply_theme(SCHEME, self.paths, config, run=lambda *a, **k: 0)
            except Exception as exc:  # noqa: BLE001
                errors.append(exc)

        t1 = threading.Thread(target=worker, args=(out1,))
        t2 = threading.Thread(target=worker, args=(out1,))
        t1.start(); t2.start(); t1.join(); t2.join()
        self.assertEqual(errors, [])
        self.assertTrue(out1.exists())


class ThemeTargetsTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.data = self.root / "data" / "templates"
        self.data.mkdir(parents=True)
        (self.data / "colors.sh").write_text("bg={background}\n")

    def tearDown(self):
        self.temp.cleanup()

    def test_theme_targets_discovers_data_templates(self):
        paths = fake_paths()
        config = {"theme": {"apply": {}}}
        targets = theme_targets(paths, config, data_dir=self.data)
        names = {t.name for t in targets}
        self.assertIn("colors", names)


if __name__ == "__main__":
    unittest.main()
