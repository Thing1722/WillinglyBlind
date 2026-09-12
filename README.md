# SafeStep

SwiftUI navigation from the logic-test UI, plus a live camera / LiDAR preview
on the walk screen. Obstacle and drop-off thresholds still come from
`WalkingMode.detectionConfig`.

This step uses the camera on a LiDAR iPhone. Without LiDAR (Simulator or a
non-Pro phone) the walk screen cycles synthetic depth scenes instead.

## Files

- `SafeStep.xcodeproj/project.pbxproj` — Xcode project and app target settings.
- `SafeStep/SafeStepApp.swift` — app entry point that opens the start screen.
- `SafeStep/StartView.swift` — start screen, walking-mode selection, and start button.
- `SafeStep/LiveDetectionView.swift` — camera or depth-heatmap preview with the
  selected mode and the current alert.
- `SafeStep/ARCameraPreview.swift` — ARKit camera preview and depth heatmap.
- `SafeStep/LiDARSession.swift` — ARKit capture, 8 Hz processing, demo fallback.
- `SafeStep/AlertEngine.swift` — haptics and spoken warnings.
- `SafeStep/Detection/WalkingMode.swift` — walking modes and `DetectionConfig` thresholds.
- `SafeStep/Detection/DetectionModels.swift` — hazards, depth map, and snapshots.
- `SafeStep/Detection/DepthAnalyzer.swift` — zone detector using `DetectionConfig`.
- `SafeStep/Detection/SyntheticDepth.swift` — demo scenes when LiDAR is unavailable.

## Test in Xcode

1. Open `SafeStep.xcodeproj` in Xcode 15 or newer.
2. Select the **SafeStep** scheme.
3. On a LiDAR iPhone (12 Pro and later, or iPad Pro), or an iOS 16+ simulator.
4. Press **Run** (`⌘R`). Allow camera access when iOS asks.
5. Confirm **Standard Mode** starts selected, switch between both modes, then tap
   **START SAFE WALK**.
6. On a LiDAR phone, hold the rear camera forward and slightly down. You should
   see the camera preview and hear/feel alerts as you approach something.
7. On Simulator / non-Pro, confirm a depth heatmap and rotating demo scenes
   (clear, obstacle, STOP, drop-off, overhead, left, right).

Detection logic should read `WalkingMode.detectionConfig` rather than switching
on the mode:

- **Standard:** obstacle caution 2.0 m, warning 1.0 m, danger 0.5 m
- **Sensitive:** 2.5 m / 1.5 m / 0.8 m
- **Drop-off (both):** ground cell ~0.6 m farther than the expected walking
  surface, or mostly invalid samples
- **Debounce (both):** 3 consecutive frames to show a warning; 6 consecutive
  clear frames to hide it so the alert does not flicker off
