"""Palette generation and normalization for zesti.

Palette generation is Zesti-owned: images are opened with Pillow, quantised
through :mod:`materialyoucolor`, and scored with an adapted copy of the reference
GPL source-colour selection. The matugen CLI is never invoked at runtime
(design spec: "backed directly by materialyoucolor and Pillow";
"Do not delegate palette generation to matugen or another CLI backend").
"""

from __future__ import annotations

import re
import math
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Mapping

from materialyoucolor.quantize import ImageQuantizeCelebi


#: Video extensions whose palette is derived from a cached ffmpeg frame.
VIDEO_EXTENSIONS = {".mp4", ".webm", ".mkv", ".mov", ".gif"}

#: Material roles emitted to the shell (camelCase, no leading '#').
REQUIRED_ROLES = (
    "primary",
    "onPrimary",
    "secondary",
    "onSecondary",
    "tertiary",
    "onTertiary",
    "surface",
    "onSurface",
    "surfaceVariant",
    "background",
    "onBackground",
    "error",
    "onError",
)

#: matugen snake_case role -> zesti camelCase role.
ROLE_MAP = {
    "primary": "primary",
    "on_primary": "onPrimary",
    "secondary": "secondary",
    "on_secondary": "onSecondary",
    "tertiary": "tertiary",
    "on_tertiary": "onTertiary",
    "surface": "surface",
    "on_surface": "onSurface",
    "surface_variant": "surfaceVariant",
    "background": "background",
    "on_background": "onBackground",
    "error": "error",
    "on_error": "onError",
}

_SCHEMES = {
    "content": ("content", "SchemeContent"), "expressive": ("expressive", "SchemeExpressive"),
    "fidelity": ("fidelity", "SchemeFidelity"), "fruitsalad": ("fruit_salad", "SchemeFruitSalad"),
    "monochrome": ("monochrome", "SchemeMonochrome"), "neutral": ("neutral", "SchemeNeutral"),
    "rainbow": ("rainbow", "SchemeRainbow"), "tonalspot": ("tonal_spot", "SchemeTonalSpot"),
    "vibrant": ("vibrant", "SchemeVibrant"),
}

# Reference Gruvbox terminal colours, harmonized towards the wallpaper hue.
_TERMINAL = {
    "dark": "282828 CC241D 98971A D79921 458588 B16286 689D6A A89984 "
            "928374 FB4934 B8BB26 FABD2F 83A598 D3869B 8EC07C EBDBB2",
    "light": "FDF9F3 FF6188 A9DC76 FC9867 FFD866 F47FD4 78DCE8 333034 "
             "121212 FF6188 A9DC76 FC9867 FFD866 F47FD4 78DCE8 333034",
}


class PaletteError(Exception):
    """Raised when palette generation or normalization cannot complete."""


@dataclass(frozen=True)
class PaletteSettings:
    mode: str = "smart"
    variant: str = "tonalspot"
    source_color_index: int = 0
    smart_scheme: bool = False
    flavour: str = "hard"


@dataclass(frozen=True)
class SchemeMetadata:
    name: str
    flavour: str
    mode: str
    variant: str
    colours: int


def slug_role(name: str) -> str:
    """Convert a matugen-style role name to a shell camelCase role.

    Leading '#' is stripped; runs of non-alphanumerics separate words; the
    first word is lowercased and every following word is capitalised.
    """
    name = str(name).lstrip("#")
    parts = [p for p in re.split(r"[^a-zA-Z0-9]+", name) if p]
    if not parts:
        return ""
    out = parts[0].lower()
    for part in parts[1:]:
        out += part[:1].upper() + part[1:].lower()
    return out


def _hex(argb: int) -> str:
    return f"{(argb >> 16) & 0xFF:02x}{(argb >> 8) & 0xFF:02x}{argb & 0xFF:02x}"


def _color_entry(hex_color: str) -> Mapping[str, object]:
    return {"color": hex_color}


def _default_run(cmd, **kwargs):  # pragma: no cover - real subprocess path
    import subprocess

    return subprocess.run(cmd, **kwargs).returncode


def _pick_source_color(counts: Mapping[int, int], source_color_index: int = 0) -> int:
    """Rank hue prominence and chroma using the reference source-colour score."""
    from materialyoucolor.dislike.dislike_analyzer import DislikeAnalyzer
    from materialyoucolor.hct.hct import Hct

    if not counts or sum(counts.values()) <= 0:
        raise PaletteError("no colours to score")
    if source_color_index < 0:
        raise PaletteError("source colour index must be non-negative")
    colours = [(Hct.from_int(argb), population) for argb, population in counts.items()]
    total = sum(counts.values())
    hue_population = [0] * 360
    for hct, population in colours:
        hue_population[int(hct.hue)] += population
    proportions = [0.0] * 360
    for hue, population in enumerate(hue_population):
        for neighbour in range(hue - 14, hue + 16):
            proportions[neighbour % 360] += population / total

    def score(hct):
        weight = 0.1 if hct.chroma < 48 else 0.3
        return proportions[round(hct.hue) % 360] * 70 + (hct.chroma - 48) * weight

    ranked = sorted((hct for hct, _ in colours), key=score, reverse=True)
    for cutoff in range(20, -1, -1):
        candidates = [hct for hct in ranked if hct.chroma > cutoff and hct.tone > cutoff * 3]
        if candidates:
            return DislikeAnalyzer.fix_if_disliked(candidates[min(source_color_index, len(candidates) - 1)]).to_int()
    # Pure black has no eligible tone; avoid the reference scorer's recursion.
    return ranked[0].to_int()


def _smart_variant(image: Image.Image) -> str:
    """Reference colourfulness thresholds, without large pixel lists."""
    count = image.width * image.height
    rg_sum = yb_sum = rg_sq = yb_sq = 0.0
    pixels = image.get_flattened_data() if hasattr(image, "get_flattened_data") else image.getdata()
    for r, g, b in pixels:
        rg = abs(r - g)
        yb = abs((r + g) * 0.5 - b)
        rg_sum += rg
        yb_sum += yb
        rg_sq += rg * rg
        yb_sq += yb * yb
    mean_rg, mean_yb = rg_sum / count, yb_sum / count
    variance = max(0.0, rg_sq / count - mean_rg**2 + yb_sq / count - mean_yb**2)
    colourfulness = math.sqrt(variance) + 0.3 * math.hypot(mean_rg, mean_yb)
    return "neutral" if colourfulness < 10 else "content" if colourfulness < 20 else "tonalspot"


def _resolve_mode(settings: PaletteSettings, image: Image.Image) -> str:
    from PIL import Image
    from materialyoucolor.hct.hct import Hct

    if settings.mode == "smart":
        average = image.resize((1, 1), Image.Resampling.LANCZOS).getpixel((0, 0))
        r, g, b = average
        return "light" if Hct.from_int(0xFF000000 | r << 16 | g << 8 | b).tone > 60 else "dark"
    if settings.mode in ("dark", "light"):
        return settings.mode
    raise PaletteError(f"unknown palette mode: {settings.mode}")


def _adjust_tone(colour: Hct, amount: float, light: bool) -> Hct:
    from materialyoucolor.hct.hct import Hct

    diff = (100 - colour.tone) * amount if light else -colour.tone * amount
    return Hct.from_hct(colour.hue, colour.chroma + diff / 5, colour.tone + diff)


def _build_payload(source_argb: int, mode: str, variant: str, flavour: str) -> dict:
    from importlib import import_module
    from materialyoucolor.dynamiccolor.material_dynamic_colors import MaterialDynamicColors
    from materialyoucolor.hct.hct import Hct
    from materialyoucolor.utils.math_utils import difference_degrees, rotation_direction

    if variant not in _SCHEMES:
        raise PaletteError(f"unknown palette variant: {variant}")
    if flavour not in ("hard", "soft"):
        raise PaletteError(f"unknown palette flavour: {flavour}")
    module, name = _SCHEMES[variant]
    scheme_type = getattr(import_module("materialyoucolor.scheme.scheme_" + module), name)
    colors: dict[str, dict[str, dict[str, str]]] = {}
    base16: dict[str, dict[str, dict[str, str]]] = {}
    dynamic = MaterialDynamicColors()
    roles = dynamic.all_colors if hasattr(dynamic, "all_colors") else [
        role for role in vars(MaterialDynamicColors).values() if hasattr(role, "get_hct")
    ]
    for selected_mode in ("dark", "light"):
        light = selected_mode == "light"
        scheme = scheme_type(Hct.from_int(source_argb), not light, 0.0)
        # Copy cached HCT values before applying the reference flavour adjustments.
        colours = {role.name: Hct.from_int(role.get_argb(scheme)) for role in roles}
        key = colours.get("primaryPaletteKeyColor", colours.get("primary_paletteKeyColor"))
        for i, value in enumerate(_TERMINAL[selected_mode].split()):
            hct = Hct.from_int(int("ff" + value, 16))
            if variant == "monochrome":
                hct = _adjust_tone(hct, 0.35 if light else 0.65, not light)
                hct.chroma = 0
            else:
                rotation = min(difference_degrees(hct.hue, key.hue) * 0.8, 100)
                hue = (hct.hue + rotation * rotation_direction(hct.hue, key.hue)) % 360
                boost = (0.35 if i < 8 else 0.2) * (-1 if light else 1)
                hct = Hct.from_hct(hue, hct.chroma, hct.tone * (1 + boost))
            colours[f"term{i}"] = hct
        if variant == "neutral":
            for hct in colours.values():
                hct.chroma -= 15
        if flavour == "hard":
            for name in colours:
                if name == "background" or name.startswith("surface"):
                    colours[name] = _adjust_tone(colours[name], 0.4 if light else 0.8, light)
            colours["term0"] = _adjust_tone(colours["term0"], 0.4 if light else 0.9, light)
        for name, hct in colours.items():
            if name.startswith("term"):
                base16.setdefault(f"base{int(name[4:]):02x}", {})[selected_mode] = _color_entry(_hex(hct.to_int()))
            else:
                role = re.sub(r"(?<=[a-z0-9])([A-Z])", r"_\1", name).lower()
                colors.setdefault(role, {})[selected_mode] = _color_entry(_hex(hct.to_int()))
    return {"colors": colors, "base16": base16,
            "scheme": {"mode": mode, "variant": variant, "flavour": flavour}}


def generate_palette(
    source: Path, settings: PaletteSettings, run: Callable[..., str] = _default_run
) -> dict:
    """Generate a matugen-shaped palette payload from an image or video.

    Returns ``{"colors": {...}, "base16": {...}, "scheme": {...}}`` where every
    colour is a ``{"color": "#rrggbb"}`` entry in both ``dark`` and ``light``
    modes. Raises :class:`PaletteError` on any failure; callers must not commit
    state when this raises.
    """
    from PIL import Image

    source = Path(source)
    if not source.exists():
        raise PaletteError(f"source not found: {source}")

    image_path = source
    temp_dir = None
    try:
        if source.suffix.lower() in VIDEO_EXTENSIONS:
            temp_dir = tempfile.TemporaryDirectory(prefix="zesti-palette-")
            frame = Path(temp_dir.name) / "frame.png"
            rc = run(["ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
                      "-i", str(source), "-frames:v", "1", str(frame)])
            if rc != 0 or not frame.exists():
                raise PaletteError("ffmpeg frame extraction failed")
            image_path = frame

        # The reference implementation scores a 128px RGB JPEG thumbnail, not the full-size image.
        try:
            with Image.open(image_path) as img:
                # Keep nearest-neighbour sampling identical to the RGB-first
                # path; JPEG draft/reduction changes the palette's source pixels.
                img.thumbnail((128, 128), Image.Resampling.NEAREST, reducing_gap=None)
                image = img.convert("RGB")
        except Exception as exc:  # noqa: BLE001 - unreadable image
            raise PaletteError(f"cannot read image {source}: {exc}") from exc

        if temp_dir is None:
            temp_dir = tempfile.TemporaryDirectory(prefix="zesti-palette-")
        thumbnail = Path(temp_dir.name) / "thumbnail.jpg"
        image.save(thumbnail, "JPEG")
        counts = ImageQuantizeCelebi(str(thumbnail), 1, 128)
        if not counts:
            raise PaletteError(f"no colours quantised from {source}")

        source_argb = _pick_source_color(counts, settings.source_color_index)
        with Image.open(thumbnail) as image:
            mode = _resolve_mode(settings, image)
            variant = _smart_variant(image) if settings.smart_scheme else settings.variant
        return _build_payload(source_argb, mode, variant, settings.flavour)
    except PaletteError:
        raise
    except Exception as exc:  # noqa: BLE001 - any generation failure
        raise PaletteError(f"palette generation failed for {source}: {exc}") from exc
    finally:
        if temp_dir is not None:
            temp_dir.cleanup()


def normalize_matugen(
    payload: Mapping[str, object],
    requested_mode: str,
    metadata: SchemeMetadata,
) -> dict:
    """Normalise a matugen-shaped payload into shell camelCase roles.

    ``requested_mode`` is one of ``dark``, ``light``, or ``smart``. With
    ``smart`` the payload's own ``scheme.mode`` is used. A pre-existing scheme
    file is never touched here; callers decide whether to persist.
    """
    if not isinstance(payload, dict):
        raise PaletteError("payload must be a JSON object")

    colors = payload.get("colors")
    base16 = payload.get("base16")
    scheme = payload.get("scheme")
    if not isinstance(colors, dict) or not isinstance(base16, dict):
        raise PaletteError("payload missing colors or base16 map")

    palette_mode: str | None = scheme.get("mode") if isinstance(scheme, dict) else None
    if requested_mode == "smart":
        mode = palette_mode
        if mode not in ("dark", "light"):
            raise PaletteError("cannot determine smart mode from payload")
    elif requested_mode in ("dark", "light"):
        mode = requested_mode
    else:
        raise PaletteError(f"unknown requested mode: {requested_mode}")

    result: dict[str, object] = {}
    for matugen_role, camel in ROLE_MAP.items():
        entry = colors.get(matugen_role)
        if not isinstance(entry, dict):
            raise PaletteError(f"missing role {matugen_role}")
        mode_entry = entry.get(mode)
        if not isinstance(mode_entry, dict):
            raise PaletteError(f"missing {mode} entry for role {matugen_role}")
        color = mode_entry.get("color")
        if not isinstance(color, str):
            raise PaletteError(f"non-string color for role {matugen_role}")
        result[camel] = color.lstrip("#")

    # Keep additional Material roles, including the shell's surface containers.
    for role, entry in colors.items():
        if role in ROLE_MAP or not isinstance(entry, dict):
            continue
        selected = entry.get(mode)
        if isinstance(selected, dict) and isinstance(selected.get("color"), str):
            result[slug_role(role)] = selected["color"].lstrip("#")

    # term0 .. term15 from base16.base00 .. base0f.
    for i in range(16):
        name = f"base{i:02x}"
        entry = base16.get(name)
        if not isinstance(entry, dict):
            raise PaletteError(f"missing base16 entry {name}")
        mode_entry = entry.get(mode)
        if not isinstance(mode_entry, dict):
            raise PaletteError(f"missing {mode} entry for base16 {name}")
        color = mode_entry.get("color")
        if not isinstance(color, str):
            raise PaletteError(f"non-string color for base16 {name}")
        result[f"term{i}"] = color.lstrip("#")

    for role in REQUIRED_ROLES:
        if role not in result:
            raise PaletteError(f"normalised palette missing required role {role}")

    result["metadata"] = {
        "name": metadata.name,
        "flavour": metadata.flavour,
        "mode": mode,
        "variant": metadata.variant,
        "colours": metadata.colours,
    }
    return result
