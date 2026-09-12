import Foundation

/// Walking mode chosen on the start screen.
///
/// Detection code should not switch on this type except through
/// `detectionConfig`, which is the only mode-dependent API.
enum WalkingMode: String, CaseIterable, Identifiable {
    case standard = "Standard Mode"
    case sensitive = "Sensitive Mode"

    var id: Self { self }

    var detectionConfig: DetectionConfig {
        switch self {
        case .standard:
            return .standard
        case .sensitive:
            return .sensitive
        }
    }
}

/// Distance and stability thresholds shared by obstacle and drop-off detection.
///
/// Standard and Sensitive differ only in obstacle bands. Drop-off depth,
/// invalid-cell handling, debounce, and hysteresis are the same for both.
struct DetectionConfig: Equatable {
    /// Forward distance that starts an obstacle caution, in meters.
    let obstacleCautionMeters: Double
    /// Forward distance that starts an obstacle warning, in meters.
    let obstacleWarningMeters: Double
    /// Forward distance that starts an obstacle danger alert, in meters.
    let obstacleDangerMeters: Double

    /// A ground cell is a drop-off when it is farther than the expected
    /// walking surface by this amount, in meters.
    let dropOffDepthMeters: Double
    /// A ground cell is also a drop-off when at least this fraction of
    /// depth samples are invalid.
    let dropOffInvalidSampleRatio: Double

    /// Consecutive frames a hazard must be present before a warning appears.
    let warningAppearFrameCount: Int
    /// Consecutive clear frames required before a warning is removed.
    /// Larger than `warningAppearFrameCount` so alerts do not flicker off.
    let warningClearFrameCount: Int

    static let standard = DetectionConfig(
        obstacleCautionMeters: 2.0,
        obstacleWarningMeters: 1.0,
        obstacleDangerMeters: 0.5,
        dropOffDepthMeters: sharedDropOffDepthMeters,
        dropOffInvalidSampleRatio: sharedDropOffInvalidSampleRatio,
        warningAppearFrameCount: sharedWarningAppearFrameCount,
        warningClearFrameCount: sharedWarningClearFrameCount
    )

    static let sensitive = DetectionConfig(
        obstacleCautionMeters: 2.5,
        obstacleWarningMeters: 1.5,
        obstacleDangerMeters: 0.8,
        dropOffDepthMeters: sharedDropOffDepthMeters,
        dropOffInvalidSampleRatio: sharedDropOffInvalidSampleRatio,
        warningAppearFrameCount: sharedWarningAppearFrameCount,
        warningClearFrameCount: sharedWarningClearFrameCount
    )

    private static let sharedDropOffDepthMeters = 0.6
    private static let sharedDropOffInvalidSampleRatio = 0.5
    private static let sharedWarningAppearFrameCount = 3
    private static let sharedWarningClearFrameCount = 6

    /// Obstacle band for a measured forward distance. Uses this config's
    /// caution / warning / danger thresholds.
    func obstacleAlertBand(distanceMeters: Double) -> ObstacleAlertBand {
        if distanceMeters <= obstacleDangerMeters {
            return .danger
        }
        if distanceMeters <= obstacleWarningMeters {
            return .warning
        }
        if distanceMeters <= obstacleCautionMeters {
            return .caution
        }
        return .clear
    }

    /// True when a ground cell is farther than the expected walking surface
    /// by `dropOffDepthMeters`, or when most of its samples are invalid.
    func isDropOff(
        measuredGroundMeters: Double?,
        expectedWalkingSurfaceMeters: Double,
        invalidSampleRatio: Double
    ) -> Bool {
        if invalidSampleRatio >= dropOffInvalidSampleRatio {
            return true
        }
        guard let measuredGroundMeters else {
            return true
        }
        return measuredGroundMeters >= expectedWalkingSurfaceMeters + dropOffDepthMeters
    }
}

/// Forward-obstacle severity derived from `DetectionConfig` distance bands.
enum ObstacleAlertBand: Int, Comparable {
    case clear
    case caution
    case warning
    case danger

    static func < (lhs: ObstacleAlertBand, rhs: ObstacleAlertBand) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
