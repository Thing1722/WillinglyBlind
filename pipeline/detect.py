"""Obstacle detector that mirrors SafeStep/DepthAnalyzer.swift.

Input is a 2-D depth image in meters (same layout ARKit gives the iPhone:
row 0 is the top of the frame). Invalid samples are 0, NaN, or > 8 m.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from typing import Optional

import numpy as np

MAX_RANGE = 8.0
MIN_RANGE = 0.08


class WalkingMode(Enum):
    STANDARD = "standard"
    SENSITIVE = "sensitive"

    @property
    def warn_distance(self) -> float:
        return 1.4 if self is WalkingMode.STANDARD else 2.2

    @property
    def stop_distance(self) -> float:
        return 0.55 if self is WalkingMode.STANDARD else 0.80

    @property
    def drop_distance(self) -> float:
        return 2.2 if self is WalkingMode.STANDARD else 1.8

    @property
    def overhead_distance(self) -> float:
        return 1.3 if self is WalkingMode.STANDARD else 1.6


class HazardKind(str, Enum):
    CLEAR = "clear"
    NO_SIGNAL = "no_signal"
    OBSTACLE_AHEAD = "obstacle_ahead"
    OBSTACLE_LEFT = "obstacle_left"
    OBSTACLE_RIGHT = "obstacle_right"
    DROP_OFF = "drop_off"
    OVERHEAD = "overhead"
    STOP = "stop"


@dataclass(frozen=True)
class Hazard:
    kind: HazardKind
    distance_m: float
    message: str
    spoken_phrase: str
    severity: int


CLEAR = Hazard(HazardKind.CLEAR, float("inf"), "Path looks clear", "", 0)
NO_SIGNAL = Hazard(
    HazardKind.NO_SIGNAL,
    float("inf"),
    "Point the camera forward",
    "Point the camera forward",
    10,
)


@dataclass
class ZoneDistances:
    left: Optional[float] = None
    center: Optional[float] = None
    right: Optional[float] = None
    ground: Optional[float] = None
    overhead: Optional[float] = None
    mid: Optional[float] = None


@dataclass
class DetectionSnapshot:
    primary: Hazard
    hazards: list[Hazard]
    zones: ZoneDistances
    preview: np.ndarray
    scene_name: str = ""

    @property
    def closest_readable(self) -> str:
        d = self.primary.distance_m
        if not np.isfinite(d) or d >= 20:
            return "—"
        return f"{d:.1f} m"


@dataclass
class ZoneStats:
    p10: float
    median: float


def _spoken(meters: float) -> str:
    return f"{meters:.1f} meters"


def _obstacle_severity(distance: float, warn: float, stop: float) -> int:
    if distance <= stop:
        return 100
    if distance >= warn:
        return 0
    t = (warn - distance) / max(0.01, warn - stop)
    return int(round(70.0 + 25.0 * t))


def _zone_stats(
    depth: np.ndarray,
    row_start: float,
    row_end: float,
    col_start: float,
    col_end: float,
) -> Optional[ZoneStats]:
    h, w = depth.shape
    r0, r1 = int(row_start * h), max(int(row_start * h) + 1, int(row_end * h))
    c0, c1 = int(col_start * w), max(int(col_start * w) + 1, int(col_end * w))
    region = depth[r0:r1, c0:c1]
    valid = np.isfinite(region) & (region >= MIN_RANGE) & (region <= MAX_RANGE)
    if int(valid.sum()) < 24:
        return None
    values = np.sort(region[valid])
    p10 = float(values[min(len(values) - 1, max(0, int(len(values) * 0.10)))])
    median = float(values[len(values) // 2])
    return ZoneStats(p10=p10, median=median)


def _preview(depth: np.ndarray, width: int = 48, height: int = 36) -> np.ndarray:
    h, w = depth.shape
    ys = (np.linspace(0, h - 1, height)).astype(int)
    xs = (np.linspace(0, w - 1, width)).astype(int)
    return depth[ys][:, xs].astype(np.float32)


def analyze(
    depth: np.ndarray,
    mode: WalkingMode = WalkingMode.STANDARD,
    scene_name: str = "",
) -> DetectionSnapshot:
    depth = np.asarray(depth, dtype=np.float32)
    if depth.ndim != 2:
        raise ValueError("depth must be a 2-D array of meters")

    left = _zone_stats(depth, 0.28, 0.60, 0.05, 0.32)
    center = _zone_stats(depth, 0.28, 0.60, 0.35, 0.65)
    right = _zone_stats(depth, 0.28, 0.60, 0.68, 0.95)
    ground = _zone_stats(depth, 0.82, 0.98, 0.30, 0.70)
    overhead = _zone_stats(depth, 0.02, 0.28, 0.30, 0.70)
    mid = _zone_stats(depth, 0.50, 0.70, 0.35, 0.65)

    preview = _preview(depth)
    zones = ZoneDistances(
        left=None if left is None else left.p10,
        center=None if center is None else center.p10,
        right=None if right is None else right.p10,
        ground=None if ground is None else ground.median,
        overhead=None if overhead is None else overhead.p10,
        mid=None if mid is None else mid.median,
    )

    if not any(z is not None for z in (left, center, right, ground, overhead)):
        return DetectionSnapshot(NO_SIGNAL, [NO_SIGNAL], zones, preview, scene_name)

    hazards: list[Hazard] = []

    if center is not None:
        if center.p10 <= mode.stop_distance:
            hazards.append(
                Hazard(
                    HazardKind.STOP,
                    center.p10,
                    "STOP — obstacle too close",
                    f"Stop. Obstacle ahead at {_spoken(center.p10)}.",
                    100,
                )
            )
        elif center.p10 <= mode.warn_distance:
            hazards.append(
                Hazard(
                    HazardKind.OBSTACLE_AHEAD,
                    center.p10,
                    "Obstacle ahead",
                    f"Obstacle ahead at {_spoken(center.p10)}.",
                    _obstacle_severity(center.p10, mode.warn_distance, mode.stop_distance),
                )
            )

    if left is not None and left.p10 <= mode.warn_distance:
        center_p10 = center.p10 if center is not None else float("inf")
        if center_p10 > left.p10 + 0.15:
            hazards.append(
                Hazard(
                    HazardKind.OBSTACLE_LEFT,
                    left.p10,
                    "Obstacle on the left",
                    f"Obstacle on your left at {_spoken(left.p10)}.",
                    max(40, _obstacle_severity(left.p10, mode.warn_distance, mode.stop_distance) - 10),
                )
            )

    if right is not None and right.p10 <= mode.warn_distance:
        center_p10 = center.p10 if center is not None else float("inf")
        if center_p10 > right.p10 + 0.15:
            hazards.append(
                Hazard(
                    HazardKind.OBSTACLE_RIGHT,
                    right.p10,
                    "Obstacle on the right",
                    f"Obstacle on your right at {_spoken(right.p10)}.",
                    max(40, _obstacle_severity(right.p10, mode.warn_distance, mode.stop_distance) - 10),
                )
            )

    if ground is not None and mid is not None:
        looks_like_hole = (
            ground.median >= mode.drop_distance and ground.median >= mid.median + 0.70
        )
        if looks_like_hole:
            hazards.append(
                Hazard(
                    HazardKind.DROP_OFF,
                    ground.median,
                    "Drop-off ahead",
                    "Drop off ahead. Stop.",
                    90,
                )
            )

    if overhead is not None and overhead.p10 <= mode.overhead_distance:
        hazards.append(
            Hazard(
                HazardKind.OVERHEAD,
                overhead.p10,
                "Low obstacle above",
                f"Low obstacle above you at {_spoken(overhead.p10)}.",
                80,
            )
        )

    if not hazards:
        hazards = [CLEAR]

    hazards.sort(key=lambda h: h.severity, reverse=True)
    return DetectionSnapshot(hazards[0], hazards, zones, preview, scene_name)
