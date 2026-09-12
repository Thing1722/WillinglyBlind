import Foundation

@main
struct DetectionTests {
    static func main() {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message)
            checks += 1
        }
        func detect(_ scenario: DemoScenario, mode: WalkingMode = .standard, speed: Float = 0.8) -> DetectionResult {
            HazardDetector.analyze(scenario.frame, speed: speed, mode: mode)!
        }
        check(detect(.clear).assessment.total == 0, "Clear path must have zero risk")
        check(detect(.clear, mode: .sensitive, speed: 2).assessment.level == .low, "Movement alone is not a hazard")
        check(detect(.obstacle).assessment.hazard == .obstacle, "Obstacle detection")
        check(detect(.obstacle).assessment.total == 5, "Obstacle score")
        check(detect(.dropOff).assessment.hazard == .dropOff, "Depth discontinuity detection")
        check(detect(.dropOff).assessment.total == 7, "Drop-off score")
        check(detect(.tooClose, speed: 0).assessment.total == 5, "Stationary proximity score")
        check(detect(.tooClose, speed: 0).assessment.level == .high, "Proximity must override low score")
        for (distance, score): (Float, Int) in [(0.99, 3), (1, 2), (1.99, 2), (2, 1), (3, 1), (3.01, 0)] {
            check(RiskAssessment(hazard: .obstacle, distance: distance, movement: .stationary, mode: .standard).distanceScore == score, "Distance boundary \(distance)")
        }
        check(Movement(speed: 0.14) == .stationary, "Stationary threshold")
        check(Movement(speed: 0.15) == .walking, "Walking threshold")
        check(Movement(speed: 1.6) == .fast, "Fast threshold")
        let early = DepthFrame(width: 24, height: 36, meters: Array(repeating: 1.8, count: 864))
        check(HazardDetector.analyze(early, speed: 0.8, mode: .standard)!.assessment.hazard == .clear, "Standard threshold")
        check(HazardDetector.analyze(early, speed: 0.8, mode: .sensitive)!.assessment.hazard == .obstacle, "Sensitive warning earlier")
        for invalid: Float in [.nan, .infinity, 0, -1] {
            let frame = DepthFrame(width: 24, height: 36, meters: Array(repeating: invalid, count: 864))
            check(HazardDetector.analyze(frame, speed: 0, mode: .standard) == nil, "Invalid depth must not report clear")
        }
        check(HazardDetector.analyze(DepthFrame(width: 0, height: 0, meters: []), speed: 0, mode: .standard) == nil, "Empty frame")
        var noisy = DemoScenario.clear.frame.meters
        noisy[30 * 24 + 12] = 0.1
        check(HazardDetector.analyze(DepthFrame(width: 24, height: 36, meters: noisy), speed: 0.8, mode: .standard)!.assessment.hazard == .clear, "One outlier must not trigger immediate danger")
        var sparse = Array(repeating: Float.nan, count: 864)
        for y in 18..<36 { for x in 8..<11 { sparse[y * 24 + x] = 3.7 } }
        check(HazardDetector.analyze(DepthFrame(width: 24, height: 36, meters: sparse), speed: 0, mode: .standard) == nil, "Insufficient coverage")
        let grid = DepthGridSampler.sample(DepthFrame(width: 3, height: 3, meters: [1, 2, 3, 4, .nan, 6, 7, 8, 9]))
        check(grid.cell(row: .mid, column: .center).minMeters == nil, "Grid invalid cell")
        check(grid.cell(row: .nearGround, column: .center).minMeters == 8, "Grid indexing")
        for hazard in [Hazard.obstacle, .dropOff, .tooClose] {
            for mode in WalkingMode.allCases {
                for movement in Movement.allCases {
                    let risk = RiskAssessment(hazard: hazard, distance: 0.5, movement: movement, mode: mode)
                    check((0...10).contains(risk.total), "Score bounds")
                }
            }
        }
        print("Passed \(checks) detection and scoring checks.")
    }
}
