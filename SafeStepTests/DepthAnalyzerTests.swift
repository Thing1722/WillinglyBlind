import XCTest
@testable import SafeStep

final class DepthAnalyzerTests: XCTestCase {
    func testSyntheticScenesMapToExpectedHazardUnderStandardConfig() {
        let expected: [(SyntheticScene, HazardKind)] = [
            (.clearHallway, .clear),
            (.obstacleAhead, .obstacleAhead),
            (.emergencyStop, .stop),
            (.dropOff, .dropOff),
            (.overhead, .overhead),
            (.obstacleLeft, .obstacleLeft),
            (.obstacleRight, .obstacleRight)
        ]

        for (scene, kind) in expected {
            let snapshot = DepthAnalyzer.analyze(
                depth: SyntheticDepth.make(scene, seed: 1),
                config: .standard
            )
            XCTAssertEqual(
                snapshot.primary.kind,
                kind,
                "\(scene.title) should be \(kind.rawValue), got \(snapshot.primary.kind.rawValue)"
            )
        }
    }

    func testSensitiveDangerBandFiresFartherThanStandard() {
        let frame = SyntheticDepth.hallwayWithCenterObstacle(meters: 0.65)
        let standard = DepthAnalyzer.analyze(depth: frame, config: .standard)
        let sensitive = DepthAnalyzer.analyze(depth: frame, config: .sensitive)

        XCTAssertEqual(standard.primary.kind, .obstacleAhead)
        XCTAssertEqual(sensitive.primary.kind, .stop)
        XCTAssertEqual(DetectionConfig.standard.obstacleAlertBand(distanceMeters: 0.65), .warning)
        XCTAssertEqual(DetectionConfig.sensitive.obstacleAlertBand(distanceMeters: 0.65), .danger)
    }

    func testNoSignalWhenEntireFrameInvalid() {
        let frame = DepthFrame(width: 32, height: 32, meters: Array(repeating: 0, count: 32 * 32))
        let snapshot = DepthAnalyzer.analyze(depth: frame, config: .standard)
        XCTAssertEqual(snapshot.primary.kind, .noSignal)
    }

    func testDropOffWhenGroundFartherThanWalkingSurface() {
        XCTAssertTrue(
            DetectionConfig.standard.isDropOff(
                measuredGroundMeters: 2.5,
                expectedWalkingSurfaceMeters: 1.8,
                invalidSampleRatio: 0.1
            )
        )
        XCTAssertFalse(
            DetectionConfig.standard.isDropOff(
                measuredGroundMeters: 2.0,
                expectedWalkingSurfaceMeters: 1.8,
                invalidSampleRatio: 0.1
            )
        )
        XCTAssertTrue(
            DetectionConfig.standard.isDropOff(
                measuredGroundMeters: 1.8,
                expectedWalkingSurfaceMeters: 1.8,
                invalidSampleRatio: 0.5
            )
        )
        XCTAssertTrue(
            DetectionConfig.standard.isDropOff(
                measuredGroundMeters: nil,
                expectedWalkingSurfaceMeters: 1.8,
                invalidSampleRatio: 0.1
            )
        )
        XCTAssertEqual(DetectionConfig.standard.dropOffDepthMeters, DetectionConfig.sensitive.dropOffDepthMeters)
        XCTAssertEqual(
            DetectionConfig.standard.dropOffInvalidSampleRatio,
            DetectionConfig.sensitive.dropOffInvalidSampleRatio
        )
    }

    func testAnalyzerDropOffFromInvalidGroundSamples() {
        let hallway = SyntheticDepth.make(.clearHallway, seed: 1)
        var meters = hallway.meters
        let y0 = Int(0.82 * Float(hallway.height))
        for y in y0..<hallway.height {
            for x in 0..<hallway.width {
                meters[y * hallway.width + x] = 0
            }
        }
        let frame = DepthFrame(width: hallway.width, height: hallway.height, meters: meters)
        let snapshot = DepthAnalyzer.analyze(depth: frame, config: .standard)
        XCTAssertEqual(snapshot.primary.kind, .dropOff)
    }

    func testClearSpokenPhraseIsEmpty() {
        let snapshot = DepthAnalyzer.analyze(
            depth: SyntheticDepth.make(.clearHallway, seed: 1),
            config: .standard
        )
        XCTAssertEqual(snapshot.primary.spokenPhrase, "")
    }
}
