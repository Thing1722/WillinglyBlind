#!/usr/bin/env python3
"""Run the SafeStep LiDAR danger pipeline on synthetic (or CSV) depth frames.

Examples:
  python3 pipeline/run_pipeline.py
  python3 pipeline/run_pipeline.py --mode sensitive
  python3 pipeline/run_pipeline.py --csv path/to/depth.csv --name custom_frame
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from detect import WalkingMode, analyze  # noqa: E402
from simulate import EXPECTED_KIND, SCENES, load_depth_csv  # noqa: E402
from visualize import render_heatmap, write_png, write_report  # noqa: E402


def _print_snapshot(name: str, snapshot) -> None:
    print(f"\n=== {name} ===")
    print(f"alert:    {snapshot.primary.kind.value}")
    print(f"message:  {snapshot.primary.message}")
    print(f"distance: {snapshot.closest_readable}")
    if snapshot.primary.spoken_phrase:
        print(f"speech:   {snapshot.primary.spoken_phrase}")
    print(
        "zones:    "
        f"L={snapshot.zones.left}  "
        f"ahead={snapshot.zones.center}  "
        f"R={snapshot.zones.right}  "
        f"ground={snapshot.zones.ground}  "
        f"overhead={snapshot.zones.overhead}"
    )


def main() -> int:
    parser = argparse.ArgumentParser(description="SafeStep LiDAR obstacle pipeline")
    parser.add_argument(
        "--mode",
        choices=["standard", "sensitive"],
        default="standard",
        help="Matches the iOS walking modes",
    )
    parser.add_argument(
        "--csv",
        action="append",
        default=[],
        help="Optional CSV depth map (row-major meters). Repeatable.",
    )
    parser.add_argument("--name", default="custom_frame", help="Label for --csv frames")
    parser.add_argument(
        "--out",
        default=str(ROOT / "output"),
        help="Directory for heatmaps, report.html, and results.json",
    )
    args = parser.parse_args()

    mode = WalkingMode.STANDARD if args.mode == "standard" else WalkingMode.SENSITIVE
    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)

    jobs: list[tuple[str, object]] = [(name, factory(1)) for name, factory in SCENES.items()]
    for index, csv_path in enumerate(args.csv):
        label = args.name if len(args.csv) == 1 else f"{args.name}_{index + 1}"
        jobs.append((label, load_depth_csv(csv_path)))

    rows = []
    payload = []
    failures = []

    for name, depth in jobs:
        snapshot = analyze(depth, mode=mode, scene_name=name)
        _print_snapshot(name, snapshot)
        image_path = out_dir / f"{name}.png"
        write_png(image_path, render_heatmap(depth, snapshot))
        rows.append((name, snapshot, image_path))
        payload.append(
            {
                "scene": name,
                "kind": snapshot.primary.kind.value,
                "message": snapshot.primary.message,
                "spoken": snapshot.primary.spoken_phrase,
                "distance_m": None
                if snapshot.primary.distance_m == float("inf")
                else round(float(snapshot.primary.distance_m), 3),
                "severity": snapshot.primary.severity,
            }
        )
        expected = EXPECTED_KIND.get(name)
        if expected and snapshot.primary.kind.value != expected:
            failures.append(f"{name}: expected {expected}, got {snapshot.primary.kind.value}")

    write_report(out_dir / "report.html", rows)
    (out_dir / "results.json").write_text(json.dumps(payload, indent=2), encoding="utf-8")

    print(f"\nWrote heatmaps and report to {out_dir}")
    print(f"Open {out_dir / 'report.html'} in a browser.")

    if failures:
        print("\nScene checks failed:")
        for item in failures:
            print(f"  - {item}")
        return 1

    print("\nAll built-in scenes matched the expected alert type.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
