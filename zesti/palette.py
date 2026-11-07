"""Palette generation and normalization for zesti.

Palette generation is Zesti-owned: images are opened with Pillow, quantised
through :mod:`materialyoucolor`, and scored with an adapted copy of Caelestia's
GPL source-colour selection. The matugen CLI is never invoked at runtime
(design spec: "backed directly by materialyoucolor and Pillow";
"Do not delegate palette generation to matugen or another CLI backend").
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Mapping

from PIL import Image
from materialyoucolor.hct.hct import Hct
from materialyoucolor.palettes.core_palette import CorePalette
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

#: matugen role -> (CorePalette attribute, dark tone, light tone).
_TONE_MAP = {
    "primary": ("a1", 80, 40),
    "on_primary": ("n1", 10, 95),
    "secondary": ("a2", 80, 40),
    "on_secondary": ("n1", 10, 95),
    "tertiary": ("a3", 80, 40),
    "on_tertiary": ("n1", 10, 95),
    "surface": ("n1", 10, 98),
    "on_surface": ("n1", 90, 10),
    "surface_variant": ("n1", 30, 90),
    "background": ("n1", 10, 98),
    "on_background": ("n1", 90, 10),
    "error": ("error", 60, 40),
    "on_error": ("n1", 10, 95),
}


class PaletteError(Exception):
    """Raised when palette generation or normalization cannot complete."""


@dataclass(frozen=True)
class PaletteSettings:
    mode: str = "smart"
    variant: str = "tonalspot"
    source_color_index: int = 0


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
    """Caelestia-adapted source-colour selection.

    Prefers the most prominent non-greyscale colour; falls back to the most
    prominent colour overall. Deterministic and dependency-free.
    """
    ordered = sorted(counts.items(), key=lambda item: item[1], reverse=True)
    for argb, _count in ordered:
        r = (argb >> 16) & 0xFF
        g = (argb >> 8) & 0xFF
        b = argb & 0xFF
        if abs(r - g) > 10 or abs(g - b) > 10 or abs(r - b) > 10:
            return argb
    return ordered[0][0] if ordered else 0


def _luminance_mode(argb: int) -> str:
    hct = Hct.from_int(argb)
    return "dark" if hct.tone < 50 else "light"


def _resolve_mode(settings: PaletteSettings, source_argb: int) -> str:
    if settings.mode == "smart":
        return _luminance_mode(source_argb)
    if settings.mode in ("dark", "light"):
        return settings.mode
    raise PaletteError(f"unknown palette mode: {settings.mode}")


def _build_payload(core: CorePalette, mode: str) -> dict:
    colors: dict[str, dict[str, dict[str, str]]] = {}
    for matugen_role, (attr, dark_tone, light_tone) in _TONE_MAP.items():
        palette = getattr(core, attr)
        colors[matugen_role] = {
            "dark": _color_entry(_hex(palette.tone(dark_tone))),
            "light": _color_entry(_hex(palette.tone(light_tone))),
        }

    neutral = core.n1
    base16: dict[str, dict[str, dict[str, str]]] = {}
    for i in range(16):
        tone = round(i * 100 / 15)
        name = f"base{i:02x}"
        base16[name] = {
            "dark": _color_entry(_hex(neutral.tone(tone))),
            "light": _color_entry(_hex(neutral.tone(100 - tone))),
        }

    return {"colors": colors, "base16": base16, "scheme": {"mode": mode, "variant": "tonal-spot"}}


def generate_palette(
    source: Path, settings: PaletteSettings, run: Callable[..., str] = _default_run
) -> dict:
    """Generate a matugen-shaped palette payload from an image or video.

    Returns ``{"colors": {...}, "base16": {...}, "scheme": {...}}`` where every
    colour is a ``{"color": "#rrggbb"}`` entry in both ``dark`` and ``light``
    modes. Raises :class:`PaletteError` on any failure; callers must not commit
    state when this raises.
    """
    source = Path(source)
    if not source.exists():
        raise PaletteError(f"source not found: {source}")

    image_path = source
    temp_dir = None
    try:
        if source.suffix.lower() in VIDEO_EXTENSIONS:
            import tempfile as _tempfile

            temp_dir = _tempfile.TemporaryDirectory(prefix="zesti-palette-")
            frame = Path(temp_dir.name) / "frame.png"
            rc = run(["ffmpeg", "-y", "-hide-banner", "-loglevel", "error",
                      "-i", str(source), "-frames:v", "1", str(frame)])
            if rc != 0 or not frame.exists():
                raise PaletteError("ffmpeg frame extraction failed")
            image_path = frame

        # Validate the image with Pillow before quantising.
        try:
            with Image.open(image_path) as img:
                img.load()
        except Exception as exc:  # noqa: BLE001 - unreadable image
            raise PaletteError(f"cannot read image {source}: {exc}") from exc

        counts = ImageQuantizeCelebi(str(image_path), 64, 1)
        if not counts:
            raise PaletteError(f"no colours quantised from {source}")

        source_argb = _pick_source_color(counts, settings.source_color_index)
        mode = _resolve_mode(settings, source_argb)
        core = CorePalette.of(source_argb)
        return _build_payload(core, mode)
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
