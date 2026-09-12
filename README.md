# SafeStep

iPhone LiDAR walks in front of you, looks for obstacles and drop-offs, and
warns with haptics plus spoken alerts before you hit them.

This is a hackathon prototype, not a replacement for vision or a cane.

```
iPhone LiDAR  →  depth map (meters)  →  zone detector  →  STOP / warn / clear
                                              ↓
                                    haptics + VoiceOver-style speech
```

## What you need

| Goal | Hardware / software |
| --- | --- |
| Live obstacle warnings | iPhone 12 Pro / 13 Pro / 14 Pro / 15 Pro / 16 Pro (or Pro Max), or iPad Pro with LiDAR. Xcode 15+ on a Mac. |
| Algorithm demo without a LiDAR phone | Python 3.10+ and `numpy`. Any laptop, including this repo's Linux environment. |

Non-Pro iPhones and the iOS Simulator have no LiDAR. The app still runs: it
cycles through the same synthetic depth scenes the Python pipeline uses.

---

## Step 1 — Get the code

```bash
git clone https://github.com/Thing1722/WillinglyBlind.git
cd WillinglyBlind
```

---

## Step 2 — Run the detector on a laptop (no iPhone)

This is the same math the Swift app runs on each `ARFrame.sceneDepth` buffer.
Use it to debug thresholds, generate a judge-facing report, or process a CSV
you exported from another LiDAR tool.

```bash
python3 -m pip install -r pipeline/requirements.txt
python3 pipeline/run_pipeline.py
python3 -m pytest pipeline/tests
```

Optional flags:

```bash
python3 pipeline/run_pipeline.py --mode sensitive
python3 pipeline/run_pipeline.py --csv /path/to/depth.csv --name hallway
```

CSV format: comma-separated **meters**, one row of the depth image per text
row, matching ARKit (row 0 is the top of the frame). Typical size is 192×256.

Outputs land in `pipeline/output/`:

- `report.html` — heatmaps plus the spoken warning for each scene
- `*.png` — colorized depth (red = close, blue = far)
- `results.json` — machine-readable alerts

Open the report:

```bash
# macOS
open pipeline/output/report.html

# Linux
xdg-open pipeline/output/report.html
```

Built-in scenes and the alert they must produce:

| Scene | What the depth looks like | Alert |
| --- | --- | --- |
| `clear_hallway` | Floor getting closer toward the bottom | Path looks clear |
| `obstacle_ahead` | Box in the walking path at 0.95 m | Obstacle ahead |
| `emergency_stop` | Box at 0.32 m | STOP |
| `drop_off` | Ground patch jumps to 3.6 m | Drop-off ahead |
| `overhead` | Close hits in the top of the frame | Low obstacle above |
| `obstacle_left` / `obstacle_right` | Close hits on one side | Obstacle on the left/right |

---

## Step 3 — Run the iPhone app

1. Open `SafeStep.xcodeproj` in Xcode 15 or newer.
2. Select the **SafeStep** scheme.
3. Set your Apple ID team: target **SafeStep** → **Signing & Capabilities** →
   Team. Change `com.example.SafeStep` if Xcode complains the bundle id is taken.
4. Plug in a LiDAR iPhone (or pick a Simulator to try demo scenes).
5. On the phone, Settings → Privacy & Security → Developer Mode → on
   (first run only).
6. Press **Run** (`⌘R`). Allow camera access when iOS asks.
7. Pick **Standard Mode** (warn ~1.4 m) or **Sensitive Mode** (warn ~2.2 m).
8. Tap **START SAFE WALK**. Hold the phone at chest height, rear camera
   pointing forward and slightly down, like a flashlight.
9. Walk toward a chair, a wall, a stair, or a hanging backpack strap. You
   should feel a haptic and hear a phrase such as
   `Obstacle ahead at 1.1 meters.`
10. Swipe back to end the walk. **TRY SYNTHETIC SCENES** on the start screen
    cycles the seven demo frames every 4 seconds (works on Simulator).

If the camera permission prompt never appears, delete the app and run again.
The usage string is set in `SafeStep.xcodeproj` as
`INFOPLIST_KEY_NSCameraUsageDescription`.

---

## Step 4 — How the detector works

Each depth frame is split into zones (fractions of image height/width):

```
overhead  rows  2–28% , cols 30–70%
left      rows 28–60% , cols  5–32%
center    rows 28–60% , cols 35–65%   ← walking path (above the near floor)
right     rows 28–60% , cols 68–95%
ground    rows 82–98% , cols 30–70%   ← near the feet
```

For each zone the code keeps valid LiDAR hits (0.08–8 m, medium/high
confidence on device) and takes the **10th percentile** as “closest object”
and the **median** for the ground patch.

Rules, evaluated every ~120 ms:

1. **STOP** if the path’s closest hit ≤ 0.55 m (0.80 m in Sensitive).
2. **Obstacle ahead** if that hit ≤ 1.4 m (2.2 m in Sensitive).
3. **Left / right** if that side is closer than the path by at least 15 cm
   and inside the warn distance.
4. **Drop-off** if the ground median is farther than the drop threshold
   **and** at least 0.70 m farther than the mid-path patch. That avoids
   calling a distant wall a hole.
5. **Overhead** if the top patch’s closest hit is inside 1.3 m (1.6 m
   Sensitive) — branches, signs, garage doors.
6. Else **clear**. If almost no pixels are valid: **point the camera forward**.

The loudest hazard wins. Speech is rate-limited (~2.4 s if the phrase repeats)
so a 8 Hz stream does not talk over itself. STOP / drop-off use an error
haptic; warnings use a lighter one. Audio session is `.playback` so voice
still works with the Ring/Silent switch off.

On device the depth source is ARKit:

```swift
let config = ARWorldTrackingConfiguration()
config.frameSemantics.insert(.smoothedSceneDepth)
session.run(config)
// later, on each ARFrame:
let depth = frame.smoothedSceneDepth ?? frame.sceneDepth
```

`smoothedSceneDepth` is preferred because it is less noisy while walking.

---

## Step 5 — Project map

```
SafeStep.xcodeproj          Xcode project (iOS 16+)
SafeStep/
  SafeStepApp.swift         App entry
  StartView.swift           Mode picker + start / demo buttons
  LiveDetectionView.swift   Camera + heatmap + alert card
  ARCameraPreview.swift     ARSCNView + depth heatmap
  LiDARSession.swift        ARKit capture, 8 Hz process, demo fallback
  DepthAnalyzer.swift       Zone math (keep in sync with pipeline/detect.py)
  DetectionModels.swift     WalkingMode, Hazard, DepthMap
  SyntheticDepth.swift      Demo scenes (keep in sync with pipeline/simulate.py)
  AlertEngine.swift         Speech + haptics
pipeline/
  detect.py                 Same detector in Python
  simulate.py               Same synthetic scenes
  visualize.py              Heatmaps + report.html
  run_pipeline.py           CLI
  tests/test_detect.py
  requirements.txt
```

Change a threshold in **both** `DepthAnalyzer.swift` and `pipeline/detect.py`.
The Python tests will catch a logic regression before you go back to Xcode.

---

## Step 6 — Hackathon walkthrough

1. Show the start screen: two modes, LiDAR vs demo.
2. Run **TRY SYNTHETIC SCENES** so judges hear STOP, drop-off, and clear
   without needing a hallway.
3. Switch to a real LiDAR iPhone, start a safe walk, and approach a chair.
4. Optionally open `pipeline/output/report.html` on a laptop to show the
   depth math and that the laptop pipeline agrees with the phone.

---

## Troubleshooting

| Symptom | What to try |
| --- | --- |
| App says demo on a Pro iPhone | Confirm the model has LiDAR. World-facing camera must be unobstructed. |
| No speech | Raise volume. Speech still plays in silent mode; haptics need physical device, not Simulator. |
| Alerts too late / too jumpy | Use Sensitive Mode, or lower `warnDistance` in both Swift and Python. |
| Drop-off never fires | Point slightly down so the bottom of the frame sees the floor, then the edge of the stair. |
| `pytest` not found | `python3 -m pip install -r pipeline/requirements.txt` then `python3 -m pytest pipeline/tests` |
| Signing error in Xcode | Pick your Personal Team and a unique bundle identifier. |

---

## License

MIT. See `LICENSE`.
