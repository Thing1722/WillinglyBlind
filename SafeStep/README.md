# SafeStep

Native SwiftUI walking-safety prototype for iOS 17+. Includes a start screen, live LiDAR camera view, accessible risk feedback, an inspectable score panel, and an interactive demo using synthetic depth frames.

## Run

1. Open the existing `../SafeStep.xcodeproj` in Xcode 15 or newer (the project in `WillinglyBlind`, one folder above these sources). It includes the app and the original XCTest target. The nested `SafeStep.xcodeproj` is a standalone alternative; avoid opening both simultaneously.
2. Select the SafeStep target, choose your development team under Signing & Capabilities, and use a unique bundle identifier if needed.
3. Run on a LiDAR-equipped iPhone or iPad and allow camera access. Portrait orientation is intentional: the detection region matches the portrait preview.
4. Choose Standard or Sensitive Mode, then **Start safe walk**. Point the rear camera ahead and slightly down so the path is visible.
5. On a simulator or device without LiDAR, select **Explore the interactive demo**. Change the hazard and movement selectors to inspect each result and alert.

No server, API key, network connection, camera recording, or model download is required. Demo mode does not request camera permission. iPads may not support haptic output; visual and speech alerts remain available.

## Implemented

- ARKit scene depth, confidence filtering, row-stride-aware pixel reads, and sensor-to-preview orientation/crop mapping.
- Rules for obstacles, possible drop-offs/downward stairs, and immediate proximity. Input covers the center third of the lower half of the camera view, matching its overlay.
- Horizontal camera movement estimated from AR tracking positions. This is a phone-motion estimate; it is not object-relative closing velocity or walking-direction detection.
- Risk `R = H + D + C + U`, with the requested distance and movement boundaries. Normal obstacles score 2; possible drop-offs score 4. The prototype does not separately classify stairs (severity 3).
- Low 0–3, Medium 4–6, High 7–10. Too-close detections override the computed level to High, with the override visible in the UI. No detected hazard scores zero.
- Medium double-tap haptics; High repeated rapid pulses with distance-based cadence. Sensitive Mode increases intensity, expands the obstacle threshold from 1.5 to 2 m, and lowers the discontinuity threshold from 1.2 to 0.9 m.
- High-risk speech in both modes, plus Medium-risk speech in Sensitive Mode. Voice and touch can be toggled independently. Repeated speech is throttled; speech and active haptics stop when detection stops or data becomes unavailable.
- Explicit states for camera denial, unsupported hardware, missing depth, limited tracking, interruption, stale frames, and session failure. App backgrounding pauses scanning; resume is manual.
- Debug view with score terms, reliable depth coverage, nearby sample fraction, band medians, and rule explanations.

## Detection checks

The core detector is independent of ARKit and SwiftUI. On macOS with a matching Swift compiler/SDK:

```sh
swiftc Detection/DepthProcessing.swift Models/RiskAssessment.swift Tests/DetectionTests.swift -o /tmp/safestep-tests
/tmp/safestep-tests
```

If the default SDK is newer than the compiler, select a compatible installed SDK with `swiftc -sdk /path/to/MacOSX.sdk ...`.

Checks cover risk boundaries, each demo scenario, immediate-proximity overrides, sensitive thresholds, invalid/empty/sparse frames, isolated noise, and grid indexing.

## Device validation still required

This repository was implemented without an installed Xcode/iOS SDK, so full iOS compilation and device behavior have not been verified here. Validate camera alignment, permission denial/recovery, background/resume, speech, and haptics on target hardware. Use a spotter and stationary measurements at known distances when checking prepared obstacles or stairs; verify behavior before attempting a supervised walking demonstration.

This is a rule-based demonstration, not validated navigation equipment. Depth jumps can arise from camera tilt or ordinary scene geometry. Ground planes are not reconstructed; stairs are not semantically recognized. Thin objects can be missed by the sample-fraction threshold. Glass, reflective surfaces, limited field of view, and low-confidence depth can also hide hazards. “Path clear” means no hazard met the current rules, not that the route is safe. There is no safe-direction recommendation or narrow-path detection in this MVP.

## Source map

- `Models/RiskAssessment.swift`: domain models, score calculation, detector, synthetic scenarios.
- `Detection/DepthProcessing.swift`: original depth frame and grid utilities.
- `Services/WalkSession.swift`: camera lifecycle, depth conversion, motion estimate, data freshness.
- `Services/AlertService.swift`: Core Haptics and AVSpeechSynthesizer output.
- `StartView.swift`, `LiveDetectionView.swift`, `DebugPanel.swift`: SwiftUI screens.

Platform references: [ARKit scene depth](https://developer.apple.com/documentation/arkit/arframe/scenedepth), [display transform](https://developer.apple.com/documentation/arkit/arframe/displaytransform(for:viewportsize:)), [Core Haptics](https://developer.apple.com/documentation/corehaptics).
