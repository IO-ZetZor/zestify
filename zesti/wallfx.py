"""Map pipeline adapted from a GPL-3.0 wallfx implementation (2026-11-24).

The channel layouts and outline/contagion map mathematics match the reference
wallfx helper. Zestify adds XDG ownership, atomic cache publication, private-
runtime setup, and a bounded immutable colony pool instead of forked background
map renewal. See NOTICE for source attribution.
"""
from __future__ import annotations

import fcntl
import hashlib
import heapq
import json
import os
from pathlib import Path
import secrets
import shutil
import subprocess
import sys
import tempfile

from .paths import Paths, atomic_json

MODEL = "birefnet-general-lite"
VERSION = "pocket-v15-zestify-1"
FIELD_MAX = 1280
SD_RANGE = 16.0
WIDE = 48.0
POOL = 12
GRID_WIDTH = 480
GRID_HEIGHT = 270
_session = None
_session_models = None
_STEPS = ((-1, 0, 1.0), (1, 0, 1.0), (0, -1, 1.0), (0, 1, 1.0),
          (-1, -1, 1.4142), (1, -1, 1.4142), (-1, 1, 1.4142), (1, 1, 1.4142))


def cache_dir(paths: Paths) -> Path:
    return paths.cache_home / "zestify/wallfx"


def runtime_dir(paths: Paths) -> Path:
    return paths.data_home / "zestify/wallfx"


def runtime_python(paths: Paths) -> Path | None:
    data = runtime_dir(paths)
    python = data / "venv/bin/python"
    ready = _read_metadata(data / "ready.json")
    return python if ready and ready.get("ok") is True and python.is_file() and os.access(python, os.X_OK) else None


def setup_runtime(paths: Paths) -> dict:
    """Install the isolated CPU inference runtime and download its model.

    This is explicitly invoked by the CLI; preparing maps never installs
    packages. Package/model download progress is kept off the JSON stdout.
    """
    data = runtime_dir(paths)
    data.mkdir(parents=True, exist_ok=True)
    with (data / ".setup.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        (data / "ready.json").unlink(missing_ok=True)
        environment = dict(os.environ, U2NET_HOME=str(data / "models"))
        uv = shutil.which("uv")
        python = data / "venv/bin/python"
        try:
            if not python.is_file():
                command = [uv, "venv", "--python", "3.12", str(data / "venv")] if uv else [
                    sys.executable, "-m", "venv", str(data / "venv")]
                subprocess.run(command, check=True, stdout=sys.stderr, stderr=sys.stderr, env=environment)
            packages = ["rembg[cpu]>=2.0.60,<3", "opencv-python-headless>=4.8,<5", "pillow>=10,<13"]
            command = [uv, "pip", "install", "--python", str(python), *packages] if uv else [
                str(python), "-m", "pip", "install", *packages]
            subprocess.run(command, check=True, stdout=sys.stderr, stderr=sys.stderr, env=environment)
            prepared = subprocess.run([str(python), "-c", "import json; from rembg import new_session; "
                            f"session = new_session({MODEL!r}, providers=['CPUExecutionProvider']); "
                            "print(json.dumps({'model_file': str(session.__class__.download_models())}))"],
                           check=True, stdout=subprocess.PIPE, stderr=sys.stderr, text=True, env=environment)
            # rembg versions support both legacy flat and per-model layouts.
            model_file = Path(json.loads(prepared.stdout)["model_file"])
            if not model_file.resolve().is_relative_to((data / "models").resolve()):
                raise ValueError("BiRefNet model was installed outside the private model directory")
            stamp = model_file.stat()
            result = {"ok": True, "python": str(python), "model": MODEL, "models": str(data / "models"),
                      "model_file": str(model_file), "model_size": stamp.st_size, "model_mtime_ns": stamp.st_mtime_ns}
            atomic_json(data / "ready.json", result)
            return result
        except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
            return {"ok": False, "error": f"Could not install wallpaper inference runtime: {error}"}


def source_key(source: Path) -> str:
    source = source.resolve(strict=True)
    stamp = source.stat()
    value = f"{VERSION}|{MODEL}|{source}|{stamp.st_size}|{stamp.st_mtime_ns}"
    return hashlib.sha256(value.encode()).hexdigest()[:24]


def _value_noise(rng, width: int, height: int, scale: float):
    import numpy as np
    nx, ny = int(width / scale) + 3, int(height / scale) + 3
    lattice = rng.random((ny, nx))
    xs, ys = np.arange(width) / scale, np.arange(height) / scale
    ix, iy = xs.astype(int), ys.astype(int)
    fx, fy = xs - ix, ys - iy
    fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    top = lattice[iy][:, ix] * (1 - fx) + lattice[iy][:, ix + 1] * fx
    bottom = lattice[iy + 1][:, ix] * (1 - fx) + lattice[iy + 1][:, ix + 1] * fx
    return top * (1 - fy)[:, None] + bottom * fy[:, None]


def _blur(array, sigma: float):
    import numpy as np
    radius = int(3 * sigma) + 1
    x = np.arange(-radius, radius + 1)
    kernel = np.exp(-x * x / (2.0 * sigma * sigma))
    kernel /= kernel.sum()
    array = np.pad(array, radius, mode="edge")
    array = sum(kernel[i] * array[:, i:i + array.shape[1] - 2 * radius]
                for i in range(2 * radius + 1))
    array = sum(kernel[i] * array[i:i + array.shape[0] - 2 * radius, :]
                for i in range(2 * radius + 1))
    return array


def _rgb16(values, extra=None):
    """GB stores a 16-bit number; R optionally stores contour progress.

    These are RGB textures, never RGBA: alpha premultiplication corrupts maps.
    """
    import numpy as np
    quantized = np.clip(values * 65535.0 + 0.5, 0, 65535).astype(np.uint16)
    rgb = np.zeros(values.shape + (3,), np.uint8)
    if extra is not None:
        rgb[..., 0] = extra
    rgb[..., 1], rgb[..., 2] = quantized >> 8, quantized & 255
    return rgb


def _arrival(cost, seeds, width: int, height: int):
    arrival = [float("inf")] * (width * height)
    heap = []
    for index, start in seeds:
        if start < arrival[index]:
            arrival[index] = start
            heap.append((start, index))
    heapq.heapify(heap)
    while heap:
        time, index = heapq.heappop(heap)
        if time != arrival[index]:
            continue
        x, y = index % width, index // width
        for dx, dy, distance in _STEPS:
            nx, ny = x + dx, y + dy
            if 0 <= nx < width and 0 <= ny < height:
                neighbor = ny * width + nx
                candidate = time + (cost[index] + cost[neighbor]) * 0.5 * distance
                if candidate < arrival[neighbor]:
                    arrival[neighbor] = candidate
                    heapq.heappush(heap, (candidate, neighbor))
    return arrival


def _ranked(arrival, shape):
    import numpy as np
    array = np.asarray(arrival)
    rank = np.empty(array.size)
    rank[np.argsort(array, kind="stable")] = np.arange(array.size)
    return (rank / max(array.size - 1, 1) * 65535).astype(np.uint16).reshape(shape)


def contagion_map(seed: int, width: int = GRID_WIDTH, height: int = GRID_HEIGHT):
    """Reference Dijkstra/noise colonies, ranked by revealed screen area."""
    import numpy as np
    rng = np.random.default_rng(seed)
    noise = (0.52 * _value_noise(rng, width, height, rng.uniform(18, 65))
             + 0.30 * _value_noise(rng, width, height, rng.uniform(7, 20))
             + 0.18 * _value_noise(rng, width, height, rng.uniform(2, 6)))
    cost = 0.12 + np.exp(rng.uniform(5, 9) * (noise - 0.5)) + rng.uniform(0.15, 0.65) * rng.random((height, width))
    seeds = []
    for _ in range(int(rng.integers(6, 13))):
        x, y = int(rng.uniform(0.06, 0.94) * width), int(rng.uniform(0.08, 0.92) * height)
        seeds.append((y * width + x, float(rng.uniform(0, (width * height) ** 0.5 * 0.12))))
    return _ranked(_arrival(cost.ravel().tolist(), seeds, width, height), (height, width))


def _write_image(path: Path, array) -> None:
    from PIL import Image
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, name = tempfile.mkstemp(prefix=".map-", suffix=".png", dir=path.parent)
    os.close(descriptor)
    temporary = Path(name)
    try:
        Image.fromarray(array).save(temporary, format="PNG")
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)


def _read_metadata(path: Path) -> dict | None:
    try:
        value = json.loads(path.read_text())
        return value if isinstance(value, dict) else None
    except (OSError, ValueError):
        return None


def _complete_pair(field: Path, line: Path, *, width=None, height=None) -> bool:
    from PIL import Image
    try:
        dimensions = []
        for path in (field, line):
            with Image.open(path) as image:
                if image.mode != "RGB":
                    return False
                dimensions.append(image.size)
                image.verify()
        return dimensions[0] == dimensions[1] and (
            width is None or height is None or dimensions[0] == (width, height))
    except (OSError, ValueError):
        return False


def _spread(paths: Paths) -> dict:
    """Select one immutable map from a bounded pool.

    A fresh draw selects a slot, each slot has a fixed seed derived from the
    algorithm version. No process overwrites textures another shell is loading.
    """
    import numpy as np
    slot = secrets.randbelow(POOL)
    directory = cache_dir(paths) / "spread"
    directory.mkdir(parents=True, exist_ok=True)
    prefix = directory / f"{VERSION}-{slot}"
    field, line = prefix.with_suffix(".field.png"), prefix.with_suffix(".line.png")
    metadata_path = prefix.with_suffix(".json")
    with prefix.with_suffix(".lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        metadata = _read_metadata(metadata_path)
        if not metadata or not _complete_pair(field, line, width=metadata.get("width"), height=metadata.get("height")):
            seed = int(hashlib.sha256(f"{VERSION}|{slot}".encode()).hexdigest()[:16], 16)
            arrival = contagion_map(seed)
            rgb = np.zeros(arrival.shape + (3,), np.uint8)
            rgb[..., 0], rgb[..., 1] = arrival >> 8, arrival & 255
            _write_image(field, rgb)
            _write_image(line, _rgb16(_blur(arrival.astype(np.float64) / 65535.0, 2.5)))
            atomic_json(metadata_path, {"ok": True, "version": VERSION,
                                        "width": arrival.shape[1], "height": arrival.shape[0]})
    return {"kind": "contagio", "field": str(field.resolve()), "line": str(line.resolve())}


def _cutout(image, paths: Paths):
    global _session, _session_models
    from rembg import new_session, remove
    data = runtime_dir(paths)
    models = data / "models"
    ready = _read_metadata(data / "ready.json")
    model_file = Path(ready.get("model_file", models / (MODEL + ".onnx"))) if ready else models / (MODEL + ".onnx")
    try:
        stamp = model_file.stat()
    except OSError as error:
        raise RuntimeError("Run wallpaper effects setup to install the BiRefNet model") from error
    if not ready or ready.get("ok") is not True or ready.get("model") != MODEL \
            or ready.get("model_size") != stamp.st_size or ready.get("model_mtime_ns") != stamp.st_mtime_ns:
        raise RuntimeError("BiRefNet model installation is missing or changed; run wallpaper effects setup")
    os.environ["U2NET_HOME"] = str(models)
    if _session is None or _session_models != models:
        import onnxruntime as ort
        options = ort.SessionOptions()
        options.enable_cpu_mem_arena = False
        options.enable_mem_pattern = False
        _session = new_session(MODEL, sess_opts=options, providers=["CPUExecutionProvider"])
        _session_models = models
    return remove(image, session=_session, only_mask=True).convert("L")


def contour_maps(mask, key: str):
    """Produce reference perfil field/line RGB arrays from a BiRefNet mask.

    Returns (field, line, metadata); a confidently unsuitable mask returns
    (None, None, metadata). Masks may be PIL images or uint8 NumPy arrays.
    """
    import cv2
    import numpy as np
    values = np.asarray(mask, np.float32) / 255.0
    if values.ndim != 2 or not values.size:
        raise ValueError("Subject mask must be a nonempty grayscale image")
    height, width = values.shape
    binary = (values > 0.5).astype(np.uint8)
    count, labels, stats, _ = cv2.connectedComponentsWithStats(binary, connectivity=8)
    keep = np.zeros(count, bool)
    keep[1:] = stats[1:, cv2.CC_STAT_AREA] >= 0.002 * width * height
    binary = keep[labels].astype(np.uint8)
    cover = float(binary.mean())
    unsure = float(((values > 0.1) & (values < 0.9)).mean())
    metadata = {"ok": 0.008 <= cover <= 0.72 and unsure <= 0.06,
                "cover": cover, "unsure": unsure, "width": width, "height": height}
    if not metadata["ok"]:
        return None, None, metadata
    inside_distance = cv2.distanceTransform(binary, cv2.DIST_L2, 5)
    outside_distance = cv2.distanceTransform(1 - binary, cv2.DIST_L2, 5)
    signed_distance = outside_distance - inside_distance
    inner = np.clip(inside_distance / max(np.percentile(inside_distance[binary > 0], 99), 1.0), 0, 1)
    rng = np.random.default_rng(int(key[:8], 16))
    noise = (0.6 * _value_noise(rng, width, height, width / 9.0)
             + 0.4 * _value_noise(rng, width, height, width / 28.0))
    warped = outside_distance * (0.75 + 0.5 * noise) + noise * 0.08 * max(width, height)
    outside = binary == 0
    order = np.zeros((height, width), np.float32)
    ranks = np.empty(int(outside.sum()))
    ranks[np.argsort(warped[outside], kind="stable")] = np.arange(ranks.size)
    order[outside] = ranks / max(ranks.size - 1, 1)
    edge = np.zeros((height, width), np.uint8)
    parameter = np.zeros((height, width), np.float32)
    contours, _ = cv2.findContours(binary, cv2.RETR_LIST, cv2.CHAIN_APPROX_NONE)
    for contour in contours:
        if len(contour) < 40 or abs(cv2.contourArea(contour)) < 0.0008 * width * height:
            continue
        contour = contour[:, 0, :]
        segment = np.sqrt((np.diff(contour, axis=0, append=contour[:1]) ** 2).sum(1))
        distance = np.concatenate([[0], np.cumsum(segment)[:-1]])
        perimeter = distance[-1] + segment[-1]
        distance = (distance - distance[np.argmin(contour[:, 1])]) % perimeter
        progress = np.minimum(distance, perimeter - distance) / (perimeter / 2)
        progress[(contour[:, 0] <= 1) | (contour[:, 0] >= width - 2)
                 | (contour[:, 1] <= 1) | (contour[:, 1] >= height - 2)] = -1
        edge[contour[:, 1], contour[:, 0]] = 1
        parameter[contour[:, 1], contour[:, 0]] = progress
    line = np.zeros((height, width), np.uint8)
    if edge.any():
        _, nearest = cv2.distanceTransformWithLabels(1 - edge, cv2.DIST_L2, 5,
                                                     labelType=cv2.DIST_LABEL_PIXEL)
        ys, xs = np.nonzero(edge)
        table = np.concatenate([[0], parameter[ys, xs]])
        near = np.abs(signed_distance) < SD_RANGE
        progress = table[nearest[near]]
        line[near] = np.where(progress < 0, 0, np.clip(progress * 255, 1, 255)).astype(np.uint8)
    field = np.zeros((height, width, 3), np.uint8)
    field[..., 0] = np.clip(outside_distance / WIDE * 255, 0, 255)
    field[..., 1] = np.clip(inner * 255, 0, 255)
    field[..., 2] = np.clip((signed_distance + SD_RANGE) / (2 * SD_RANGE) * 255, 0, 255)
    line_map = _rgb16(cv2.GaussianBlur(order, (0, 0), 4.0), extra=line)
    return field, line_map, metadata


def prepare_effect(source: Path, paths: Paths, *, allow_inference: bool = True) -> dict:
    """Choose the true subject-outline effect or reference colony fallback.

    Confirmed negative masks are cached. Missing dependencies and inference
    failures are not negative evidence, so they never poison the outline cache.
    """
    from PIL import Image
    source = Path(source).resolve(strict=True)
    key = source_key(source)
    directory = cache_dir(paths) / "perfil"
    directory.mkdir(parents=True, exist_ok=True)
    prefix = directory / key
    metadata_path = prefix.with_suffix(".json")
    field, line = prefix.with_suffix(".field.png"), prefix.with_suffix(".line.png")
    mask_path = prefix.with_suffix(".mask.png")
    reason = "No cached subject mask"
    transient_error = None
    if not allow_inference:
        metadata = _read_metadata(metadata_path)
        # Published maps are immutable for this source fingerprint. A cache
        # reader need not wait for another process holding the inference lock.
        if metadata and metadata.get("key") == key and metadata.get("ok") \
                and _complete_pair(field, line, width=metadata.get("width"), height=metadata.get("height")):
            return {"kind": "perfil", "field": str(field.resolve()), "line": str(line.resolve()),
                    "key": key, "cached": True}
    with prefix.with_suffix(".lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | (0 if allow_inference else fcntl.LOCK_NB))
        except BlockingIOError:
            # Apply must never queue behind an expensive background inference.
            return dict(_spread(paths), key=key, cached=False, pending=True,
                        reason="Subject mask is being prepared")
        metadata = _read_metadata(metadata_path)
        if metadata and metadata.get("key") == key:
            if metadata.get("ok") and _complete_pair(field, line, width=metadata.get("width"), height=metadata.get("height")):
                return {"kind": "perfil", "field": str(field.resolve()), "line": str(line.resolve()),
                        "key": key, "cached": True}
            if metadata.get("ok") is False:
                reason = "No clear subject"
                result = _spread(paths)
                return dict(result, key=key, cached=True, reason=reason)
        if allow_inference:
            try:
                with Image.open(source) as original:
                    image = original.convert("RGB")
                image.thumbnail((FIELD_MAX, FIELD_MAX))
                mask = None
                if mask_path.is_file():
                    try:
                        with Image.open(mask_path) as saved:
                            mask = saved.convert("L")
                    except (OSError, ValueError):
                        pass  # A damaged cache is not evidence about the image.
                if mask is None:
                    mask = _cutout(image, paths)
                mask = mask.resize(image.size)
                field_array, line_array, metadata = contour_maps(mask, key)
                # Cache a successfully inferred mask even if map publication
                # is interrupted, so retrying need not repeat the model work.
                _write_image(mask_path, __import__("numpy").asarray(mask))
                metadata.update(key=key, source=str(source), model=MODEL, version=VERSION)
                if metadata["ok"]:
                    _write_image(field, field_array)
                    _write_image(line, line_array)
                    atomic_json(metadata_path, metadata)
                    return {"kind": "perfil", "field": str(field.resolve()), "line": str(line.resolve()),
                            "key": key, "cached": False}
                atomic_json(metadata_path, metadata)
                reason = "No clear subject"
            except Exception as error:  # ONNX providers expose several exception types.
                reason = f"Subject segmentation unavailable: {error}"
                transient_error = reason
    result = dict(_spread(paths), key=key, cached=False, reason=reason)
    if transient_error:
        result["error"] = transient_error
    return result
