"""Palette normalization and generation for zesti.

Uses materialyoucolor + Pillow in-process (never the matugen CLI) per the
design spec: "backed directly by materialyoucolor and Pillow" and
"Do not delegate palette generation to matugen or another CLI backend".
"""

import json
import tempfile
import unittest
from dataclasses import FrozenInstanceError
from pathlib import Path
from unittest.mock import patch

from PIL import Image

from zesti.palette import (
    PaletteError,
    PaletteSettings,
    ROLE_MAP,
    SchemeMetadata,
    generate_palette,
    normalize_matugen,
    slug_role,
)


def _role(color):
    return {"color": color}


def _fixture():
    """Matugen 4-shaped payload: colors.<role>.<mode>.color / base16.baseNN.<mode>.color.

    Role keys are snake_case (per the spec: snake_case roles become camelCase).
    Every role in ROLE_MAP is provided so normalisation can require them all.
    """
    colors = {}
    for role in ROLE_MAP:
        colors[role] = {
            "dark": _role("#112233"),
            "light": _role("#aabbcc"),
        }
    base16 = {}
    for i in range(16):
        name = f"base{i:02x}"
        base16[name] = {
            "dark": _role(f"#{i:02x}{i:02x}{i:02x}"),
            "light": _role(f"#{(15 - i):02x}{(15 - i):02x}{(15 - i):02x}"),
        }
    return {"colors": colors, "base16": base16, "scheme": {"mode": "dark", "variant": "tonal-spot"}}


class SlugRoleTest(unittest.TestCase):
    def test_slug_role_lowercases_and_strips_hash(self):
        self.assertEqual(slug_role("on-primary"), "onPrimary")
        self.assertEqual(slug_role("surface_variant"), "surfaceVariant")
        self.assertEqual(slug_role("COLOR_BACKGROUND"), "colorBackground")
        self.assertEqual(slug_role("#ff0000"), "ff0000")

    def test_slug_role_single_word_unchanged(self):
        self.assertEqual(slug_role("primary"), "primary")
        self.assertEqual(slug_role("background"), "background")


class NormalizeMatugenTest(unittest.TestCase):
    def setUp(self):
        self.metadata = SchemeMetadata(
            name="test-palette",
            flavour="tonalspot",
            mode="dark",
            variant="tonal-spot",
            colours=12,
        )

    def test_exact_dark_selection(self):
        result = normalize_matugen(_fixture(), "dark", self.metadata)
        self.assertEqual(result["primary"], "112233")
        self.assertEqual(result["onPrimary"], "112233")
        self.assertEqual(result["secondary"], "112233")
        self.assertEqual(result["surface"], "112233")
        self.assertEqual(result["background"], "112233")
        self.assertEqual(result["error"], "112233")

    def test_exact_light_selection(self):
        result = normalize_matugen(_fixture(), "light", self.metadata)
        self.assertEqual(result["primary"], "aabbcc")
        self.assertEqual(result["surface"], "aabbcc")

    def test_smart_uses_payload_mode(self):
        result = normalize_matugen(_fixture(), "smart", self.metadata)
        self.assertEqual(result["primary"], "112233")  # fixture scheme.mode == dark

    def test_roles_have_no_hash_prefix(self):
        result = normalize_matugen(_fixture(), "dark", self.metadata)
        for value in result.values():
            if isinstance(value, str):
                self.assertFalse(value.startswith("#"))

    def test_required_shell_roles_present(self):
        required = [
            "primary", "onPrimary", "secondary", "onSecondary", "tertiary",
            "onTertiary", "surface", "onSurface", "surfaceVariant",
            "background", "onBackground", "error", "onError",
        ]
        result = normalize_matugen(_fixture(), "dark", self.metadata)
        for role in required:
            self.assertIn(role, result, f"missing required role {role}")

    def test_term0_through_term15_from_base16(self):
        result = normalize_matugen(_fixture(), "dark", self.metadata)
        for i in range(16):
            key = f"term{i}"
            self.assertIn(key, result)
        self.assertEqual(result["term0"], "000000")
        self.assertEqual(result["term15"], "0f0f0f")

    def test_metadata_carried_into_result(self):
        result = normalize_matugen(_fixture(), "dark", self.metadata)
        self.assertEqual(result["metadata"]["name"], "test-palette")
        self.assertEqual(result["metadata"]["flavour"], "tonalspot")
        self.assertEqual(result["metadata"]["mode"], "dark")
        self.assertEqual(result["metadata"]["variant"], "tonal-spot")
        self.assertEqual(result["metadata"]["colours"], 12)

    def test_malformed_json_raises_palette_error(self):
        with self.assertRaises(PaletteError):
            normalize_matugen({"not": "a payload"}, "dark", self.metadata)

    def test_missing_colors_map_raises_palette_error(self):
        with self.assertRaises(PaletteError):
            normalize_matugen({"base16": {}}, "dark", self.metadata)

    def test_missing_selected_mode_raises_palette_error(self):
        payload = {"colors": {"primary": {"dark": _role("#112233")}}}
        with self.assertRaises(PaletteError):
            normalize_matugen(payload, "light", self.metadata)

    def test_non_string_color_raises_palette_error(self):
        payload = {"colors": {"primary": {"dark": {"color": 123}}}}
        with self.assertRaises(PaletteError):
            normalize_matugen(payload, "dark", self.metadata)


class PaletteSettingsTest(unittest.TestCase):
    def test_settings_are_immutable(self):
        s = PaletteSettings(mode="dark", variant="tonalspot")
        with self.assertRaises((AttributeError, FrozenInstanceError)):
            s.mode = "light"

    def test_defaults(self):
        s = PaletteSettings(mode="smart", variant="tonalspot")
        self.assertEqual(s.source_color_index, 0)


class GeneratePaletteTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        img = Image.new("RGB", (1, 1), (23, 41, 54))
        img.save(self.root / "source.png", "PNG")

    def tearDown(self):
        self.temp.cleanup()

    def test_generate_palette_returns_required_structure(self):
        img = self.root / "source.png"
        settings = PaletteSettings(mode="dark", variant="tonalspot")
        with patch("zesti.palette.ImageQuantizeCelebi") as quantize:
            quantize.return_value = {0xFF172936: 100, 0xFF000000: 10}
            result = generate_palette(img, settings, run=lambda *a, **k: None)
        self.assertIn("colors", result)
        self.assertIn("base16", result)
        self.assertIn("scheme", result)
        self.assertIn("mode", result["scheme"])

    def test_invalid_image_raises_palette_error_and_leaves_state_untouched(self):
        bad = self.root / "bad.png"
        bad.write_bytes(b"not an image")
        settings = PaletteSettings(mode="dark", variant="tonalspot")
        before = self.root / "scheme.json"
        before.write_text('{"primary": "112233"}')
        with self.assertRaises(PaletteError):
            generate_palette(bad, settings, run=lambda *a, **k: None)
        # save is never called: scheme file remains byte-identical
        self.assertEqual(before.read_text(), '{"primary": "112233"}')

    def test_video_uses_hide_banner_flag(self):
        video = self.root / "clip.mp4"
        video.write_bytes(b"mp4")
        calls = []

        def run(cmd, **kwargs):
            calls.append(cmd)
            Image.new("RGB", (1, 1), (23, 41, 54)).save(cmd[-1], "PNG")
            return 0

        settings = PaletteSettings(mode="dark", variant="tonalspot")
        with patch("zesti.palette.ImageQuantizeCelebi") as quantize:
            quantize.return_value = {0xFF172936: 100, 0xFF000000: 10}
            generate_palette(video, settings, run=run)
        self.assertIn("ffmpeg", calls[0])
        self.assertIn("-hide_banner", calls[0])
        self.assertNotIn("-hide-banner", calls[0])


if __name__ == "__main__":
    unittest.main()
