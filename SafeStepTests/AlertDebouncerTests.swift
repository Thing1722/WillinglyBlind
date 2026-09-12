import XCTest
@testable import SafeStep

final class AlertDebouncerTests: XCTestCase {
    func testTwoHazardFramesDoNotShowWarning() {
        var debouncer = AlertDebouncer()
        let config = DetectionConfig.standard
        var snapshot = debouncer.apply(hazardSnapshot(.obstacleAhead), config: config)
        XCTAssertEqual(snapshot.primary.kind, .clear)
        snapshot = debouncer.apply(hazardSnapshot(.obstacleAhead), config: config)
        XCTAssertEqual(snapshot.primary.kind, .clear)
    }

    func testThreeHazardFramesShowWarning() {
        var debouncer = AlertDebouncer()
        let config = DetectionConfig.standard
        _ = debouncer.apply(hazardSnapshot(.obstacleAhead), config: config)
        _ = debouncer.apply(hazardSnapshot(.obstacleAhead), config: config)
        let snapshot = debouncer.apply(hazardSnapshot(.obstacleAhead), config: config)
        XCTAssertEqual(snapshot.primary.kind, .obstacleAhead)
        XCTAssertEqual(config.warningAppearFrameCount, 3)
    }

    func testFiveClearFramesKeepWarning() {
        var debouncer = AlertDebouncer()
        let config = DetectionConfig.standard
        for _ in 0..<3 {
            _ = debouncer.apply(hazardSnapshot(.stop), config: config)
        }
        var snapshot = DetectionSnapshot.idle
        for _ in 0..<5 {
            snapshot = debouncer.apply(hazardSnapshot(.clear), config: config)
        }
        XCTAssertEqual(snapshot.primary.kind, .stop)
    }

    func testSixClearFramesHideWarning() {
        var debouncer = AlertDebouncer()
        let config = DetectionConfig.standard
        XCTAssertEqual(config.warningClearFrameCount, 6)
        for _ in 0..<3 {
            _ = debouncer.apply(hazardSnapshot(.stop), config: config)
        }
        var snapshot = DetectionSnapshot.idle
        for _ in 0..<6 {
            snapshot = debouncer.apply(hazardSnapshot(.clear), config: config)
        }
        XCTAssertEqual(snapshot.primary.kind, .clear)
    }

    func testNoSignalBypassesDebounce() {
        var debouncer = AlertDebouncer()
        let snapshot = debouncer.apply(hazardSnapshot(.noSignal), config: .standard)
        XCTAssertEqual(snapshot.primary.kind, .noSignal)
    }

    func testAppearAndClearCountsMatchBothModes() {
        XCTAssertEqual(
            DetectionConfig.standard.warningAppearFrameCount,
            DetectionConfig.sensitive.warningAppearFrameCount
        )
        XCTAssertEqual(
            DetectionConfig.standard.warningClearFrameCount,
            DetectionConfig.sensitive.warningClearFrameCount
        )
    }

    private func hazardSnapshot(_ kind: HazardKind) -> DetectionSnapshot {
        let hazard: Hazard
        switch kind {
        case .clear:
            hazard = .clear
        case .noSignal:
            hazard = .noSignal
        default:
            hazard = Hazard(
                kind: kind,
                distanceMeters: 0.9,
                message: kind.rawValue,
                spokenPhrase: kind.rawValue,
                severity: 70
            )
        }
        return DetectionSnapshot(
            primary: hazard,
            hazards: [hazard],
            zones: ZoneDistances(),
            preview: DepthPreview(width: 1, height: 1, meters: [1]),
            capturedAt: Date(timeIntervalSince1970: 0)
        )
    }
}
