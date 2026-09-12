# SafeStep

SwiftUI navigation from the logic-test start screen, plus a live ARKit camera /
LiDAR detection pipeline on the walk screen. Obstacle and drop-off thresholds
come only from `WalkingMode.detectionConfig`.

## Pipeline

```
StartView --WalkingMode--> LiveDetectionView --> LiDARSession
Capture: LiDARSession --> ARKit (ARWorldTracking + sceneDepth)
                      OR CameraCapture (AVFoundation rear camera)
                      OR SyntheticDepth
ARKit / AV Float32 + confidence --> DepthFrame
DepthFrame --> DepthGridSampler and DepthAnalyzer
DepthAnalyzer + DetectionConfig --> DetectionSnapshot
                                 --> AlertDebouncer --> AlertEngine + LiveDetectionView
```

Hold the phone like a flashlight: rear camera forward and slightly down.
Bottom of the depth image is near-ground; middle is the walking path; top is overhead.

## Device behavior

| Device | Camera | Depth | Alerts |
|---|---|---|---|
| iPhone 12 Pro+ / iPad Pro (LiDAR) | ARKit rear camera preview | `smoothedSceneDepth` else `sceneDepth`, ~8 Hz | Live |
| Non-Pro iPhone | AVFoundation rear camera | Synthetic scenes (or AV depth if present) | Demo / AV depth |
| Simulator | Heatmap only | Synthetic scenes cycling | Demo (skip debounce) |

## Files

- `SafeStep.xcodeproj/project.pbxproj` — Xcode project, camera usage string, portrait lock, ARKit / SceneKit / AVFoundation, `SafeStepTests`.
- `SafeStep/SafeStepApp.swift` — app entry point that opens the start screen.
- `SafeStep/StartView.swift` — start screen, walking-mode selection, and start button.
- `SafeStep/LiveDetectionView.swift` — ARKit / rear-camera / heatmap background with the current alert.
- `SafeStep/ARCameraPreview.swift` — `ARSCNView` bound to the shared `ARSession`, plus depth heatmap.
- `SafeStep/CameraCapture.swift` — AVFoundation rear-camera fallback and `RearCameraPreview`.
- `SafeStep/LiDARSession.swift` — ARKit capture, 8 Hz processing, AV fallback, demo scenes.
- `SafeStep/AlertEngine.swift` — haptics and spoken warnings.
- `SafeStep/Detection/WalkingMode.swift` — walking modes and `DetectionConfig` thresholds.
- `SafeStep/Detection/DepthProcessing.swift` — `DepthFrame`, 3×3 `DepthGridSampler` (Foundation + simd only).
- `SafeStep/Detection/DetectionModels.swift` — hazards and `DetectionSnapshot`.
- `SafeStep/Detection/DepthAnalyzer.swift` — zone detector using `DetectionConfig`.
- `SafeStep/Detection/SyntheticDepth.swift` — demo scenes when LiDAR is unavailable.
- `SafeStep/Detection/AlertDebouncer.swift` — 3-frame appear / 6-frame clear.
- `SafeStepTests/` — Foundation-only XCTest coverage (no ARKit).

## Test on a device

1. Open `SafeStep.xcodeproj` in **Xcode 15 or newer**.
2. Select the **SafeStep** scheme. Set your signing team.
3. Plug in a **real LiDAR device** (iPhone 12 Pro or later, or iPad Pro). Simulator has no LiDAR.
4. Press **Run** (`⌘R`). When iOS asks, **allow camera** access.
5. Confirm **Standard Mode** starts selected. Switch to **Sensitive Mode** and back.
6. Tap **START SAFE WALK**.
7. Hold the phone like a flashlight: rear camera forward and slightly down.
8. Walk toward a chair, wall, or box:
   - Standard caution / warning / danger bands are **2.0 / 1.0 / 0.5 m**.
   - Sensitive bands are **2.5 / 1.5 / 0.8 m** (danger fires farther).
9. Confirm **speech** (spoken phrases) and **haptics** (heavier on STOP / drop-off). Clear path is silent.
10. Point at a stair / missing floor to check drop-off (ground ≥ walking surface + **0.6 m**, or ≥ **50%** invalid samples).
11. Alerts should take **3** consecutive hazard frames to appear and **6** clear frames to hide.

On Simulator or a non-Pro iPhone, the walk screen cycles synthetic hallway scenes (clear, obstacle, STOP, drop-off, overhead, left, right). Non-Pro still shows the rear camera when permission is granted.

## Unit tests

In Xcode: Product → Test (`⌘U`) on an iOS 16+ simulator. `SafeStepTests` is Foundation-only and does not need a LiDAR device.

Detection logic should read `WalkingMode.detectionConfig` rather than switching on the mode:

- **Standard:** obstacle caution 2.0 m, warning 1.0 m, danger 0.5 m
- **Sensitive:** 2.5 m / 1.5 m / 0.8 m
- **Drop-off (both):** ground cell ~0.6 m farther than the expected walking surface, or mostly invalid samples
- **Debounce (both):** 3 consecutive frames to show a warning; 6 consecutive clear frames to hide it so the alert does not flicker off

This Linux environment cannot compile for iOS. Run the tests from Xcode on a Mac.
