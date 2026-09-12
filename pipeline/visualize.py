"""Tiny PNG + HTML helpers so the demo has no extra Python packages."""

from __future__ import annotations

import html
import struct
import zlib
from pathlib import Path

import numpy as np

from detect import DetectionSnapshot, HazardKind


def write_png(path: Path, rgb: np.ndarray) -> None:
    rgb = np.asarray(rgb, dtype=np.uint8)
    if rgb.ndim != 3 or rgb.shape[2] != 3:
        raise ValueError("rgb must be HxWx3")
    height, width, _ = rgb.shape
    raw = b"".join(b"\x00" + rgb[row].tobytes() for row in range(height))

    def chunk(tag: bytes, data: bytes) -> bytes:
        crc = zlib.crc32(tag + data) & 0xFFFFFFFF
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", crc)

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    payload = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(raw, 9))
        + chunk(b"IEND", b"")
    )
    path.write_bytes(payload)


def _colormap(depth: np.ndarray, vmax: float = 5.0) -> np.ndarray:
    t = np.clip(depth / vmax, 0.0, 1.0)
    rgb = np.zeros(depth.shape + (3,), dtype=np.float32)
    invalid = ~np.isfinite(depth) | (depth <= 0.08) | (depth >= 8.0)

    close = t < 0.33
    mid = (t >= 0.33) & (t < 0.66)
    far = t >= 0.66

    u = np.zeros_like(t)
    u[close] = t[close] / 0.33
    rgb[close] = np.stack(
        [np.ones_like(u[close]), 0.15 + 0.70 * u[close], np.full(u[close].shape, 0.05)],
        axis=-1,
    )

    u = np.zeros_like(t)
    u[mid] = (t[mid] - 0.33) / 0.33
    rgb[mid] = np.stack(
        [1.0 - u[mid], np.full(u[mid].shape, 0.85), 0.10 + 0.50 * u[mid]],
        axis=-1,
    )

    u = np.zeros_like(t)
    u[far] = (t[far] - 0.66) / 0.34
    rgb[far] = np.stack(
        [np.full(u[far].shape, 0.05), 0.55 - 0.25 * u[far], 0.60 + 0.40 * u[far]],
        axis=-1,
    )
    rgb[invalid] = 0.05
    return (np.clip(rgb, 0, 1) * 255).astype(np.uint8)


def _draw_rect(rgb: np.ndarray, r0: float, r1: float, c0: float, c1: float, color: tuple[int, int, int]) -> None:
    h, w, _ = rgb.shape
    y0, y1 = int(r0 * h), min(h - 1, int(r1 * h))
    x0, x1 = int(c0 * w), min(w - 1, int(c1 * w))
    rgb[y0, x0:x1] = color
    rgb[y1, x0:x1] = color
    rgb[y0:y1, x0] = color
    rgb[y0:y1, x1] = color


def render_heatmap(depth: np.ndarray, snapshot: DetectionSnapshot, scale: int = 4) -> np.ndarray:
    rgb = _colormap(depth)
    _draw_rect(rgb, 0.28, 0.60, 0.35, 0.65, (255, 255, 255))  # center path
    _draw_rect(rgb, 0.28, 0.60, 0.05, 0.32, (180, 180, 255))  # left
    _draw_rect(rgb, 0.28, 0.60, 0.68, 0.95, (180, 180, 255))  # right
    _draw_rect(rgb, 0.82, 0.98, 0.30, 0.70, (255, 220, 80))  # ground / drop
    _draw_rect(rgb, 0.02, 0.28, 0.30, 0.70, (80, 220, 255))  # overhead
    if scale > 1:
        rgb = np.repeat(np.repeat(rgb, scale, axis=0), scale, axis=1)
    return rgb


KIND_COLORS = {
    HazardKind.CLEAR: "#22c55e",
    HazardKind.NO_SIGNAL: "#64748b",
    HazardKind.OBSTACLE_AHEAD: "#f97316",
    HazardKind.OBSTACLE_LEFT: "#eab308",
    HazardKind.OBSTACLE_RIGHT: "#eab308",
    HazardKind.DROP_OFF: "#ef4444",
    HazardKind.OVERHEAD: "#f97316",
    HazardKind.STOP: "#dc2626",
}


def write_report(path: Path, rows: list[tuple[str, DetectionSnapshot, Path]]) -> None:
    cards = []
    for scene_name, snapshot, image_path in rows:
        color = KIND_COLORS.get(snapshot.primary.kind, "#64748b")
        extras = "".join(
            f"<li>{html.escape(h.message)} "
            f"({h.distance_m:.1f} m, severity {h.severity})</li>"
            for h in snapshot.hazards
        )
        zones = snapshot.zones
        cards.append(
            f"""
            <article class="card">
              <img src="{html.escape(image_path.name)}" alt="{html.escape(scene_name)} depth heatmap"/>
              <div class="body">
                <div class="badge" style="background:{color}">{html.escape(snapshot.primary.kind.value)}</div>
                <h2>{html.escape(scene_name.replace('_', ' '))}</h2>
                <p class="message">{html.escape(snapshot.primary.message)}</p>
                <p class="distance">{html.escape(snapshot.closest_readable)}</p>
                <p class="speech">{html.escape(snapshot.primary.spoken_phrase or 'No spoken warning')}</p>
                <ul>{extras}</ul>
                <p class="zones">L { _fmt(zones.left) } · Ahead { _fmt(zones.center) } · R { _fmt(zones.right) }</p>
              </div>
            </article>
            """
        )

    path.write_text(
        f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1"/>
  <title>SafeStep LiDAR pipeline</title>
  <style>
    :root {{ color-scheme: dark; }}
    body {{
      margin: 0; font-family: ui-sans-serif, system-ui, sans-serif;
      background: #0b1220; color: #e5eefc;
    }}
    header {{ padding: 32px 24px 8px; max-width: 1100px; margin: 0 auto; }}
    header p {{ color: #93a4c3; max-width: 70ch; }}
    .grid {{
      display: grid; gap: 18px; padding: 16px 24px 48px;
      grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
      max-width: 1100px; margin: 0 auto;
    }}
    .card {{
      background: #152033; border-radius: 18px; overflow: hidden;
      border: 1px solid #22324c;
    }}
    .card img {{ width: 100%; display: block; background: #000; }}
    .body {{ padding: 16px; }}
    .badge {{
      display: inline-block; color: #0b1220; font-weight: 700;
      font-size: 12px; padding: 4px 8px; border-radius: 999px;
      text-transform: uppercase; letter-spacing: 0.04em;
    }}
    h2 {{ margin: 10px 0 4px; text-transform: capitalize; }}
    .message {{ margin: 0; font-weight: 600; }}
    .distance {{ font-size: 40px; font-weight: 800; margin: 8px 0; }}
    .speech {{ color: #9fb4d9; font-style: italic; }}
    ul {{ margin: 8px 0; padding-left: 18px; color: #c5d4ee; }}
    .zones {{ color: #7f93b5; font-size: 13px; }}
    .legend {{ color: #93a4c3; font-size: 14px; }}
  </style>
</head>
<body>
  <header>
    <h1>SafeStep LiDAR danger pipeline</h1>
    <p>
      Each card is a synthetic iPhone LiDAR depth frame. White box = walking path,
      yellow = ground / drop-off, cyan = overhead. Close surfaces are red; far
      surfaces are blue. The detector is the same algorithm the iOS app runs
      on live <code>ARFrame.sceneDepth</code>.
    </p>
    <p class="legend">Red / orange = warn or stop · Green = clear path</p>
  </header>
  <section class="grid">
    {''.join(cards)}
  </section>
</body>
</html>
""",
        encoding="utf-8",
    )


def _fmt(value: float | None) -> str:
    if value is None or not np.isfinite(value):
        return "—"
    return f"{value:.1f}m"
