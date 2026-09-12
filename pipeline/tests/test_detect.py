from pathlib import Path
import sys

import numpy as np
import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from detect import HazardKind, WalkingMode, analyze
from simulate import EXPECTED_KIND, SCENES, make_clear_hallway, make_obstacle_ahead


@pytest.mark.parametrize("scene_name,factory", list(SCENES.items()))
def test_builtin_scenes_match_expected_alert(scene_name, factory):
    snapshot = analyze(factory(1), mode=WalkingMode.STANDARD)
    assert snapshot.primary.kind.value == EXPECTED_KIND[scene_name]


def test_sensitive_mode_warns_sooner_than_standard():
    depth = make_obstacle_ahead(1)
    # Push the box just beyond standard warn (1.4 m) but inside sensitive (2.2 m).
    h, w = depth.shape
    depth = depth.copy()
    depth[int(0.35 * h) : int(0.75 * h), int(0.38 * w) : int(0.62 * w)] = 1.7

    standard = analyze(depth, mode=WalkingMode.STANDARD)
    sensitive = analyze(depth, mode=WalkingMode.SENSITIVE)

    assert standard.primary.kind is HazardKind.CLEAR
    assert sensitive.primary.kind is HazardKind.OBSTACLE_AHEAD


def test_invalid_frame_asks_user_to_point_camera():
    blank = np.zeros((192, 256), dtype=np.float32)
    snapshot = analyze(blank)
    assert snapshot.primary.kind is HazardKind.NO_SIGNAL


def test_clear_hallway_has_finite_path_distance():
    snapshot = analyze(make_clear_hallway(1))
    assert snapshot.primary.kind is HazardKind.CLEAR
    assert snapshot.zones.center is not None
    assert snapshot.zones.center > 1.4
