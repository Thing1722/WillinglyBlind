# SafeStep

Basic SwiftUI navigation for the SafeStep iOS app. This step contains UI
placeholders only; it does not use sensors, haptics, or speech.

## Files

- `SafeStep.xcodeproj/project.pbxproj` — Xcode project and app target settings.
- `SafeStep/SafeStepApp.swift` — app entry point that opens the start screen.
- `SafeStep/StartView.swift` — start screen, walking-mode selection, and start button.
- `SafeStep/LiveDetectionView.swift` — placeholder destination for a safe walk.

## Test in Xcode

1. Open `SafeStep.xcodeproj` in Xcode 14 or newer.
2. Select the **SafeStep** scheme and an iOS 16+ simulator.
3. Press **Run** (`⌘R`).
4. Confirm **Standard Mode** starts selected, switch between both modes, then tap
   **START SAFE WALK** and confirm the Live Detection placeholder opens with the
   selected mode.
