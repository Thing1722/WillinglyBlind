import Foundation

enum WalkingMode: String, CaseIterable, Identifiable {
    case standard = "Standard Mode"
    case sensitive = "Sensitive Mode"

    var id: Self { self }

    var subtitle: String {
        switch self {
        case .standard:
            return "Alerts when something is about 1.4 m ahead"
        case .sensitive:
            return "Earlier alerts, about 2.2 m ahead"
        }
    }

    /// Distance (meters) where a center-path object becomes a spoken warning.
    var warnDistance: Float {
        switch self {
        case .standard: return 1.4
        case .sensitive: return 2.2
        }
    }

    /// Distance (meters) where the walker should stop immediately.
    var stopDistance: Float {
        switch self {
        case .standard: return 0.55
        case .sensitive: return 0.80
        }
    }

    /// If the ground patch looks farther than this, treat it as a drop-off.
    var dropDistance: Float {
        switch self {
        case .standard: return 2.2
        case .sensitive: return 1.8
        }
    }

    /// Distance (meters) where an overhead object is a hazard.
    var overheadDistance: Float {
        switch self {
        case .standard: return 1.3
        case .sensitive: return 1.6
        }
    }
}

enum HazardKind: String, Equatable {
    case clear
    case noSignal
    case obstacleAhead
    case obstacleLeft
    case obstacleRight
    case dropOff
    case overhead
    case stop
}

struct Hazard: Equatable, Identifiable {
    let kind: HazardKind
    let distanceMeters: Float
    let message: String
    let spokenPhrase: String
    let severity: Int

    var id: String { "\(kind.rawValue)-\(message)" }

    static let clear = Hazard(
        kind: .clear,
        distanceMeters: .infinity,
        message: "Path looks clear",
        spokenPhrase: "",
        severity: 0
    )

    static let noSignal = Hazard(
        kind: .noSignal,
        distanceMeters: .infinity,
        message: "Point the camera forward",
        spokenPhrase: "Point the camera forward",
        severity: 10
    )
}

struct ZoneDistances: Equatable {
    var left: Float?
    var center: Float?
    var right: Float?
    var ground: Float?
    var overhead: Float?
    var mid: Float?
}

struct DepthPreview: Equatable {
    let width: Int
    let height: Int
    /// Row-major meters. Values <= 0 mean invalid.
    let meters: [Float]
}

struct DetectionSnapshot: Equatable {
    let primary: Hazard
    let hazards: [Hazard]
    let zones: ZoneDistances
    let preview: DepthPreview
    let capturedAt: Date

    static let idle = DetectionSnapshot(
        primary: .clear,
        hazards: [.clear],
        zones: ZoneDistances(),
        preview: DepthPreview(width: 1, height: 1, meters: [0]),
        capturedAt: Date(timeIntervalSince1970: 0)
    )

    var closestReadable: String {
        let distance = primary.distanceMeters
        guard distance.isFinite, distance < 20 else { return "—" }
        return String(format: "%.1f m", distance)
    }
}

struct DepthMap {
    let width: Int
    let height: Int
    /// Row-major depth in meters.
    let meters: [Float]

    func sample(row: Int, column: Int) -> Float {
        meters[row * width + column]
    }
}
