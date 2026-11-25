"""Palette normalization and generation for zesti.

Uses materialyoucolor + Pillow in-process (never the matugen CLI) per the
design spec: "backed directly by materialyoucolor and Pillow" and
"Do not delegate palette generation to matugen or another CLI backend".
"""

import json
import io
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
    _pick_source_color,
    normalize_matugen,
    slug_role,
)


class PaletteThumbnailTest(unittest.TestCase):
    def test_thumbnail_before_rgb_preserves_the_original_samples(self):
        with tempfile.TemporaryDirectory() as directory:
            for mode, extension in [("RGB", ".jpg"), ("RGBA", ".png"), ("L", ".png"),
                                    ("P", ".png"), ("CMYK", ".jpg")]:
                with self.subTest(mode=mode):
                    source = Path(directory) / (mode + extension)
                    Image.effect_noise((513, 277), 80).convert(mode).save(source)
                    with Image.open(source) as original:
                        expected = original.convert("RGB")
                        expected.thumbnail((128, 128), Image.Resampling.NEAREST)
                    output = io.BytesIO()
                    expected.save(output, "JPEG")
                    def quantize(path, *args):
                        self.assertEqual(Path(path).read_bytes(), output.getvalue())
                        return {0xFFBA572A: 20}
                    with patch("zesti.palette.ImageQuantizeCelebi", side_effect=quantize), patch("zesti.palette._build_payload", return_value={}):
                        generate_palette(source, PaletteSettings(mode="dark"))


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
        self.assertEqual(quantize.call_args.args[1:], (1, 128))

    def test_gray_smart_palette_matches_reference_without_blue_accent(self):
        Image.new("RGB", (16, 16), (128, 128, 128)).save(self.root / "gray.png")
        payload = generate_palette(self.root / "gray.png", PaletteSettings(mode="dark", smart_scheme=True))
        self.assertEqual(payload["scheme"]["variant"], "neutral")
        # Golden roles from the reference palette implementation with materialyoucolor 3.0.2.
        for role, expected in {"primary": "c6c6c6", "on_primary": "404040", "surface": "030303"}.items():
            self.assertEqual(payload["colors"][role]["dark"]["color"], expected)

    def test_warm_wallpaper_matches_reference_hard_roles_and_terminals(self):
        Image.new("RGB", (16, 16), (190, 100, 35)).save(self.root / "warm.png")
        payload = generate_palette(self.root / "warm.png", PaletteSettings(mode="dark", smart_scheme=True))
        self.assertEqual(payload["scheme"]["variant"], "tonalspot")
        self.assertEqual(payload["scheme"]["flavour"], "hard")
        for role, expected in {"primary": "f6ba96", "on_primary": "5e361c", "surface": "050301"}.items():
            self.assertEqual(payload["colors"][role]["dark"]["color"], expected)
        self.assertEqual(payload["base16"]["base01"]["dark"]["color"], "ee6900")
        self.assertIn("primary_dim", payload["colors"])
        self.assertIn("surface_container_highest", payload["colors"])

    def test_smart_variant_distinguishes_muted_and_colourful_wallpapers(self):
        for rgb, expected in [((128, 128, 128), "neutral"), ((150, 130, 110), "content"), ((190, 100, 35), "tonalspot")]:
            with self.subTest(rgb=rgb):
                path = self.root / "variant.png"
                Image.new("RGB", (16, 16), rgb).save(path)
                payload = generate_palette(path, PaletteSettings(mode="dark", smart_scheme=True))
                self.assertEqual(payload["scheme"]["variant"], expected)

    def test_explicit_variants_change_the_palette(self):
        variants = {}
        for variant in ("tonalspot", "content", "neutral", "vibrant", "expressive", "fidelity", "fruitsalad", "monochrome", "rainbow"):
            payload = generate_palette(self.root / "source.png", PaletteSettings(mode="dark", variant=variant))
            self.assertEqual(payload["scheme"]["variant"], variant)
            variants[variant] = payload["colors"]["primary"]["dark"]["color"]
        self.assertGreater(len(set(variants.values())), 4)

    def test_smart_mode_uses_average_image_not_selected_accent(self):
        Image.new("RGB", (16, 16), (255, 255, 255)).save(self.root / "bright.png")
        with patch("zesti.palette.ImageQuantizeCelebi", return_value={0xFFBA572A: 20}):
            payload = generate_palette(self.root / "bright.png", PaletteSettings(mode="smart", smart_scheme=True))
        self.assertEqual(payload["scheme"]["mode"], "light")

    def test_black_wallpaper_does_not_recurse(self):
        Image.new("RGB", (16, 16), (0, 0, 0)).save(self.root / "black.png")
        payload = generate_palette(self.root / "black.png", PaletteSettings(smart_scheme=True))
        self.assertEqual(payload["scheme"]["mode"], "dark")
        self.assertEqual(payload["scheme"]["variant"], "neutral")

    def test_source_scoring_finds_warm_accent_among_grays(self):
        self.assertEqual(_pick_source_color({0xFF808080: 900, 0xFFBA572A: 100}), 0xFFBA572A)
        with self.assertRaises(PaletteError):
            _pick_source_color({})

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
