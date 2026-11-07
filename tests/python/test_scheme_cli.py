"""Scheme state and CLI handlers for zesti."""

import json
import tempfile
import unittest
from dataclasses import FrozenInstanceError
from pathlib import Path
from unittest.mock import patch

from zesti.paths import Paths
from zesti.scheme import (
    SchemeChoice,
    VALID_VARIANTS,
    list_schemes,
    load_scheme,
    save_scheme,
    select_variant,
    validate_variant,
)


class SchemeChoiceTest(unittest.TestCase):
    def test_scheme_choice_immutable(self):
        choice = SchemeChoice(name="nord", flavour="tonalspot", path=Path("/x/nord.json"))
        with self.assertRaises((AttributeError, FrozenInstanceError)):
            choice.name = "other"


class ListSchemesTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.dir = Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def test_list_schemes_discovers_static_schemes(self):
        (self.dir / "nord.json").write_text("{}")
        (self.dir / "dracula.toml").write_text("")
        (self.dir / "not-a-scheme.txt").write_text("ignore")
        choices = list_schemes(self.dir)
        names = sorted(c.name for c in choices)
        self.assertEqual(names, ["dracula", "nord"])
        for c in choices:
            self.assertIsInstance(c, SchemeChoice)
            self.assertTrue(c.path.exists())

    def test_list_schemes_empty_dir(self):
        self.assertEqual(list_schemes(self.dir), [])

    def test_list_schemes_sorted_by_name(self):
        (self.dir / "zeta.json").write_text("{}")
        (self.dir / "alpha.json").write_text("{}")
        names = [c.name for c in list_schemes(self.dir)]
        self.assertEqual(names, ["alpha", "zeta"])


class ValidateVariantTest(unittest.TestCase):
    def test_all_documented_variants_are_valid(self):
        expected = {
            "tonalspot", "vibrant", "expressive", "fidelity", "fruitsalad",
            "monochrome", "neutral", "rainbow", "content",
        }
        self.assertEqual(VALID_VARIANTS, expected)

    def test_validate_variant_accepts_documented(self):
        for variant in VALID_VARIANTS:
            self.assertIsNone(validate_variant(variant))

    def test_validate_variant_rejects_unknown(self):
        with self.assertRaises(ValueError):
            validate_variant("not-a-variant")
        with self.assertRaises(ValueError):
            validate_variant("")

    def test_random_is_not_a_valid_explicit_variant(self):
        with self.assertRaises(ValueError):
            validate_variant("random")


class SelectVariantTest(unittest.TestCase):
    def test_explicit_variant_passthrough(self):
        self.assertEqual(select_variant("tonalspot"), "tonalspot")

    def test_random_selection_is_injectable(self):
        rng = __import__("random").Random(42)
        picked = {select_variant("random", rng=rng) for _ in range(50)}
        self.assertTrue(picked <= VALID_VARIANTS)
        self.assertGreaterEqual(len(picked), 2)


class LoadSaveSchemeTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        (self.root / "config" / "zestify").mkdir(parents=True)
        self.paths = Paths.from_env({
            "XDG_STATE_HOME": str(self.root / "state"),
            "XDG_CONFIG_HOME": str(self.root / "config"),
        })

    def tearDown(self):
        self.temp.cleanup()

    def test_save_then_load_round_trip(self):
        scheme = {"primary": "112233", "metadata": {"mode": "dark"}}
        save_scheme(self.paths, scheme)
        self.assertTrue(self.paths.scheme_file.exists())
        loaded = load_scheme(self.paths)
        self.assertEqual(loaded, scheme)

    def test_save_is_atomic_no_temp_left_behind(self):
        save_scheme(self.paths, {"a": 1})
        leftovers = [p for p in self.paths.state_home.rglob("*") if p.name.endswith((".tmp", ".bak"))]
        self.assertEqual(leftovers, [])

    def test_load_scheme_missing_file_returns_empty(self):
        self.assertEqual(load_scheme(self.paths), {})

    def test_load_scheme_invalid_json_raises(self):
        self.paths.scheme_file.parent.mkdir(parents=True, exist_ok=True)
        self.paths.scheme_file.write_text("{not json")
        with self.assertRaises(ValueError):
            load_scheme(self.paths)


if __name__ == "__main__":
    unittest.main()
