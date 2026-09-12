"""Synthetic LiDAR frames used by the Python demo and the iOS demo mode.

Geometry matches SafeStep/SyntheticDepth.swift so a Mac without a LiDAR
iPhone and a Linux test box produce the same alerts.
"""

from __future__ import annotations

from typing import Callable

import numpy as np

WIDTH = 256
HEIGHT = 192


def _hallway(h: int = HEIGHT, w: int = WIDTH) -> np.ndarray:
    ys = np.linspace(0, 1, h, dtype=np.float32)[:, None]  # 0 = top
    xs = np.linspace(0, 1, w, dtype=np.float32)[None, :]
    ground = 0.65 + (1.0 - ys) * 4.20
    return (ground + 0.15 * np.abs(xs - 0.5)).astype(np.float32)


def _stamp_box(
    depth: np.ndarray,
    row0: float,
    row1: float,
    col0: float,
    col1: float,
    meters: float,
) -> np.ndarray:
    out = depth.copy()
    h, w = out.shape
    r0, r1 = int(row0 * h), int(row1 * h)
    c0, c1 = int(col0 * w), int(col1 * w)
    out[r0:r1, c0:c1] = np.float32(meters)
    return out


def _noise(depth: np.ndarray, seed: int = 1) -> np.ndarray:
    rng = np.random.default_rng(seed)
    return (depth + rng.normal(0.0, 0.03, size=depth.shape).astype(np.float32)).astype(
        np.float32
    )


def make_clear_hallway(seed: int = 1) -> np.ndarray:
    return _noise(_hallway(), seed)


def make_obstacle_ahead(seed: int = 1) -> np.ndarray:
    return _noise(_stamp_box(_hallway(), 0.35, 0.75, 0.38, 0.62, 0.95), seed)


def make_emergency_stop(seed: int = 1) -> np.ndarray:
    return _noise(_stamp_box(_hallway(), 0.32, 0.82, 0.34, 0.66, 0.32), seed)


def make_drop_off(seed: int = 1) -> np.ndarray:
    return _noise(_stamp_box(_hallway(), 0.78, 1.00, 0.25, 0.75, 3.60), seed)


def make_overhead(seed: int = 1) -> np.ndarray:
    return _noise(_stamp_box(_hallway(), 0.02, 0.22, 0.30, 0.70, 0.90), seed)


def make_obstacle_left(seed: int = 1) -> np.ndarray:
    return _noise(_stamp_box(_hallway(), 0.30, 0.80, 0.00, 0.28, 0.70), seed)


def make_obstacle_right(seed: int = 1) -> np.ndarray:
    return _noise(_stamp_box(_hallway(), 0.30, 0.80, 0.72, 1.00, 0.70), seed)


SCENES: dict[str, Callable[[int], np.ndarray]] = {
    "clear_hallway": make_clear_hallway,
    "obstacle_ahead": make_obstacle_ahead,
    "emergency_stop": make_emergency_stop,
    "drop_off": make_drop_off,
    "overhead": make_overhead,
    "obstacle_left": make_obstacle_left,
    "obstacle_right": make_obstacle_right,
}

EXPECTED_KIND = {
    "clear_hallway": "clear",
    "obstacle_ahead": "obstacle_ahead",
    "emergency_stop": "stop",
    "drop_off": "drop_off",
    "overhead": "overhead",
    "obstacle_left": "obstacle_left",
    "obstacle_right": "obstacle_right",
}


def load_depth_csv(path: str) -> np.ndarray:
    """Load a row-major CSV of meters exported from another tool."""
    return np.loadtxt(path, delimiter=",", dtype=np.float32)
