import Foundation

enum HazardType: String, CaseIterable {
    case none
    case obstacle
    case tooClose
    case dropOff

    var statusLabel: String {
        switch self {
        case .none:
            return "PATH CLEAR"
        case .obstacle:
            return "OBSTACLE"
        case .tooClose:
            return "TOO CLOSE"
        case .dropOff:
            return "DROP-OFF"
        }
    }
}

enum RiskLevel: String, CaseIterable {
    case low
    case medium
    case high

    var displayName: String {
        rawValue.uppercased()
    }
}

enum MovementState: String, CaseIterable {
    case stationary
    case walking
    case movingQuickly

    var displayName: String {
        switch self {
        case .stationary:
            return "Stationary"
        case .walking:
            return "Walking"
        case .movingQuickly:
            return "Moving Quickly"
        }
    }
}

/// Placeholder snapshot used by Live Detection until real sensors are connected.
struct DetectionSnapshot {
    var hazard: HazardType
    var riskLevel: RiskLevel
    var movementState: MovementState
    var nearestSurfaceMeters: Double

    static let placeholder = DetectionSnapshot(
        hazard: .none,
        riskLevel: .low,
        movementState: .stationary,
        nearestSurfaceMeters: 3.7
    )

    var nearestSurfaceLabel: String {
        String(format: "%.1f m", nearestSurfaceMeters)
    }
}
