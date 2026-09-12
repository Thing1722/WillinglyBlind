# SafeStep

Basic SwiftUI navigation for the SafeStep iOS app. This step contains UI
placeholders only; it does not use sensors, haptics, or speech.

## Files

- `SafeStep.xcodeproj/project.pbxproj` — Xcode project and app target settings.
- `SafeStep/SafeStepApp.swift` — app entry point that opens the start screen.
- `SafeStep/StartView.swift` — start screen, walking-mode selection, and start button.
- `SafeStep/Detection/WalkingMode.swift` — walking modes and `DetectionConfig` thresholds.
- `SafeStep/DetectionModels.swift` — `HazardType`, `RiskLevel`, `MovementState`, and
  `DetectionSnapshot` placeholders for later sensor wiring.
- `SafeStep/LiveDetectionView.swift` — live detection screen with camera preview
  placeholder, status readings, Start/Stop Detection, and Debug Panel link.
- `SafeStep/DebugPanelView.swift` — simple debug panel showing placeholder readings.

## Test in Xcode

1. Open `SafeStep.xcodeproj` in Xcode 14 or newer.
2. Select the **SafeStep** scheme and an iOS 16+ simulator.
3. Press **Run** (`⌘R`).
4. Confirm **Standard Mode** starts selected, switch between both modes, then tap
   **START SAFE WALK**.
5. On Live Detection, confirm the camera preview area, **PATH CLEAR**,
   **Stationary**, **3.7 m**, **LOW**, Start/Stop Detection, and Debug Panel.

Detection logic (not yet wired to sensors) should read
`WalkingMode.detectionConfig` rather than switching on the mode:

- **Standard:** obstacle caution 2.0 m, warning 1.0 m, danger 0.5 m
- **Sensitive:** 2.5 m / 1.5 m / 0.8 m
- **Drop-off (both):** ground cell ~0.6 m farther than the expected walking
  surface, or mostly invalid samples
- **Debounce (both):** 3 consecutive frames to show a warning; 6 consecutive
  clear frames to hide it so the alert does not flicker off
