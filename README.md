# SafeStep

Basic SwiftUI navigation for the SafeStep iOS app. This step contains UI
placeholders only; it does not use sensors, haptics, or speech.

## Files

- `SafeStep.xcodeproj/project.pbxproj` — Xcode project and app target settings.
- `SafeStep/SafeStepApp.swift` — app entry point that opens the start screen.
- `SafeStep/StartView.swift` — start screen, walking-mode selection, and start button.
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
