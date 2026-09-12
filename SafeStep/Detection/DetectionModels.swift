import Foundation

enum HazardKind: String, Equatable {
    case clear
    case noSignal
    case caution
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

    func replacingPrimary(_ hazard: Hazard) -> DetectionSnapshot {
        DetectionSnapshot(
            primary: hazard,
            hazards: [hazard] + hazards.filter { $0.kind != hazard.kind },
            zones: zones,
            preview: preview,
            capturedAt: capturedAt
        )
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
