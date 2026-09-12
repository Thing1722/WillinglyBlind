import Foundation

enum WalkingMode: String, CaseIterable, Identifiable {
    case standard = "Standard Mode"
    case sensitive = "Sensitive Mode"
    var id: Self { self }
    var sensitivity: Int { self == .sensitive ? 1 : 0 }
}

enum Movement: String, CaseIterable {
    case stationary = "Stationary", walking = "Walking", fast = "Moving quickly"
    init(speed: Float) {
        self = speed < 0.15 ? .stationary : speed < 1.6 ? .walking : .fast
    }
    var score: Int { self == .stationary ? 0 : self == .walking ? 1 : 2 }
}

enum Hazard: String {
    case clear = "Path clear"
    case obstacle = "Obstacle ahead"
    case dropOff = "Possible drop-off / stairs down"
    case tooClose = "Too close"
    var severity: Int {
        switch self {
        case .clear: return 0
        case .obstacle, .tooClose: return 2
        case .dropOff: return 4
        }
    }
    var advice: String {
        switch self {
        case .clear: return "Stay aware of your surroundings"
        case .obstacle: return "Slow down. Check the path ahead."
        case .dropOff: return "Stop. Check the ground ahead."
        case .tooClose: return "Stop walking. Look ahead."
        }
    }
}

enum RiskLevel: String { case low = "Low", medium = "Medium", high = "High" }

struct RiskAssessment: Equatable {
    let hazard: Hazard
    let distance: Float
    let movement: Movement
    let mode: WalkingMode
    var severityScore: Int { hazard.severity }
    var distanceScore: Int {
        guard hazard != .clear else { return 0 }
        return distance < 1 ? 3 : distance < 2 ? 2 : distance <= 3 ? 1 : 0
    }
    var movementScore: Int { hazard == .clear ? 0 : movement.score }
    var sensitivityScore: Int { hazard == .clear ? 0 : mode.sensitivity }
    var total: Int { severityScore + distanceScore + movementScore + sensitivityScore }
    var level: RiskLevel {
        if hazard == .tooClose { return .high }
        return total >= 7 ? .high : total >= 4 ? .medium : .low
    }
    var distanceText: String { String(format: "%.1f m", distance) }
}

struct DetectionResult {
    let assessment: RiskAssessment
    let coverage: Float
    let bandDepths: [Float?]
    let nearbyFraction: Float
}

/// Rule-based prototype. Input is oriented to match the portrait camera preview.
/// A depth discontinuity is only a *possible* drop-off, not stair classification.
enum HazardDetector {
    static func analyze(_ frame: DepthFrame, speed: Float, mode: WalkingMode) -> DetectionResult? {
        guard frame.width >= 3, frame.height >= 6 else { return nil }
        func samples(_ lower: Float, _ upper: Float) -> [Float] {
            let x0 = frame.width / 3, x1 = frame.width * 2 / 3
            let y0 = Int(Float(frame.height) * lower), y1 = Int(Float(frame.height) * upper)
            return (y0..<y1).flatMap { y in
                (x0..<x1).map { frame[$0, y] }.filter(DepthFrame.isValid)
            }
        }
        func percentile(_ values: [Float], _ fraction: Float) -> Float? {
            guard !values.isEmpty else { return nil }
            let sorted = values.sorted()
            return sorted[Int(Float(sorted.count - 1) * fraction)]
        }
        // Three equal horizontal bands within the lower half of the displayed image.
        let bands = [samples(0.5, 2.0 / 3.0), samples(2.0 / 3.0, 5.0 / 6.0), samples(5.0 / 6.0, 1)]
        let all = bands.flatMap { $0 }
        let expected = (frame.width * 2 / 3 - frame.width / 3) * (frame.height - frame.height / 2)
        let coverage = Float(all.count) / Float(max(expected, 1))
        guard coverage >= 0.55, let nearest = percentile(all, 0.1) else { return nil }
        let depths = bands.map { percentile($0, 0.5) }
        let obstacleThreshold: Float = mode == .sensitive ? 2 : 1.5
        let fraction = Float(all.filter { $0 < obstacleThreshold }.count) / Float(all.count)
        let closeFraction = Float(all.filter { $0 < 0.8 }.count) / Float(all.count)
        var hazard: Hazard = .clear
        var distance = nearest
        if closeFraction >= 0.1 {
            hazard = .tooClose
        } else if let far = depths[0], let middle = depths[1], let near = depths[2],
                  bands.allSatisfy({ $0.count >= expected / 6 }),
                  max(far - middle, middle - near) > (mode == .sensitive ? 0.9 : 1.2) {
            hazard = .dropOff
            distance = near
        } else if fraction >= 0.2 {
            hazard = .obstacle
        }
        return DetectionResult(
            assessment: RiskAssessment(hazard: hazard, distance: distance, movement: Movement(speed: speed), mode: mode),
            coverage: coverage, bandDepths: depths, nearbyFraction: fraction
        )
    }
}

enum DemoScenario: String, CaseIterable, Identifiable {
    case clear = "Clear", obstacle = "Obstacle", dropOff = "Drop-off", tooClose = "Too close"
    var id: Self { self }
    var frame: DepthFrame {
        let values: [Float] = (0..<36).flatMap { y in
            (0..<24).map { _ -> Float in
                switch self {
                case .clear: return 3.7
                case .obstacle: return 1.3
                case .tooClose: return 0.5
                case .dropOff: return y < 24 ? 3.8 : y < 30 ? 1.5 : 1.2
                }
            }
        }
        return DepthFrame(width: 24, height: 36, meters: values)
    }
}
