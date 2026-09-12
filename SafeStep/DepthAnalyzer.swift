import Foundation

/// Shared obstacle logic for live LiDAR frames and the Python demo pipeline.
///
/// The depth image is treated as a camera pointed forward and slightly down:
/// bottom rows are the ground near the feet, middle rows are the walking path,
/// top rows are overhead. Invalid samples (0, NaN, or > 8 m) are ignored.
enum DepthAnalyzer {
    private static let maxRange: Float = 8.0
    private static let minRange: Float = 0.08

    static func analyze(depth: DepthMap, mode: WalkingMode, now: Date = Date()) -> DetectionSnapshot {
        // Keep the walking-path band above the near floor so a hallway does not
        // look like an obstacle, especially in Sensitive mode (2.2 m warn).
        let left = zoneStats(depth, rowStart: 0.28, rowEnd: 0.60, colStart: 0.05, colEnd: 0.32)
        let center = zoneStats(depth, rowStart: 0.28, rowEnd: 0.60, colStart: 0.35, colEnd: 0.65)
        let right = zoneStats(depth, rowStart: 0.28, rowEnd: 0.60, colStart: 0.68, colEnd: 0.95)
        let ground = zoneStats(depth, rowStart: 0.82, rowEnd: 0.98, colStart: 0.30, colEnd: 0.70)
        let overhead = zoneStats(depth, rowStart: 0.02, rowEnd: 0.28, colStart: 0.30, colEnd: 0.70)
        let mid = zoneStats(depth, rowStart: 0.50, rowEnd: 0.70, colStart: 0.35, colEnd: 0.65)

        var hazards: [Hazard] = []

        let usable = [left, center, right, ground, overhead].compactMap { $0 }
        if usable.isEmpty {
            return DetectionSnapshot(
                primary: .noSignal,
                hazards: [.noSignal],
                zones: ZoneDistances(),
                preview: makePreview(depth),
                capturedAt: now
            )
        }

        if let center {
            if center.p10 <= mode.stopDistance {
                hazards.append(
                    makeHazard(
                        kind: .stop,
                        distance: center.p10,
                        message: "STOP — obstacle too close",
                        phrase: "Stop. Obstacle ahead at \(spoken(center.p10)).",
                        severity: 100
                    )
                )
            } else if center.p10 <= mode.warnDistance {
                hazards.append(
                    makeHazard(
                        kind: .obstacleAhead,
                        distance: center.p10,
                        message: "Obstacle ahead",
                        phrase: "Obstacle ahead at \(spoken(center.p10)).",
                        severity: obstacleSeverity(center.p10, warn: mode.warnDistance, stop: mode.stopDistance)
                    )
                )
            }
        }

        if let left, left.p10 <= mode.warnDistance, (center?.p10 ?? .infinity) > left.p10 + 0.15 {
            hazards.append(
                makeHazard(
                    kind: .obstacleLeft,
                    distance: left.p10,
                    message: "Obstacle on the left",
                    phrase: "Obstacle on your left at \(spoken(left.p10)).",
                    severity: max(40, obstacleSeverity(left.p10, warn: mode.warnDistance, stop: mode.stopDistance) - 10)
                )
            )
        }

        if let right, right.p10 <= mode.warnDistance, (center?.p10 ?? .infinity) > right.p10 + 0.15 {
            hazards.append(
                makeHazard(
                    kind: .obstacleRight,
                    distance: right.p10,
                    message: "Obstacle on the right",
                    phrase: "Obstacle on your right at \(spoken(right.p10)).",
                    severity: max(40, obstacleSeverity(right.p10, warn: mode.warnDistance, stop: mode.stopDistance) - 10)
                )
            )
        }

        if let ground, let mid {
            let looksLikeHole = ground.median >= mode.dropDistance && ground.median >= mid.median + 0.70
            if looksLikeHole {
                hazards.append(
                    makeHazard(
                        kind: .dropOff,
                        distance: ground.median,
                        message: "Drop-off ahead",
                        phrase: "Drop off ahead. Stop.",
                        severity: 90
                    )
                )
            }
        }

        if let overhead, overhead.p10 <= mode.overheadDistance {
            hazards.append(
                makeHazard(
                    kind: .overhead,
                    distance: overhead.p10,
                    message: "Low obstacle above",
                    phrase: "Low obstacle above you at \(spoken(overhead.p10)).",
                    severity: 80
                )
            )
        }

        if hazards.isEmpty {
            hazards = [.clear]
        }

        let primary = hazards.max(by: { $0.severity < $1.severity }) ?? .clear
        return DetectionSnapshot(
            primary: primary,
            hazards: hazards.sorted { $0.severity > $1.severity },
            zones: ZoneDistances(
                left: left?.p10,
                center: center?.p10,
                right: right?.p10,
                ground: ground?.median,
                overhead: overhead?.p10,
                mid: mid?.median
            ),
            preview: makePreview(depth),
            capturedAt: now
        )
    }

    private struct ZoneStats {
        let p10: Float
        let median: Float
    }

    private static func zoneStats(
        _ depth: DepthMap,
        rowStart: Float,
        rowEnd: Float,
        colStart: Float,
        colEnd: Float
    ) -> ZoneStats? {
        let r0 = Int(rowStart * Float(depth.height))
        let r1 = max(r0 + 1, Int(rowEnd * Float(depth.height)))
        let c0 = Int(colStart * Float(depth.width))
        let c1 = max(c0 + 1, Int(colEnd * Float(depth.width)))

        var values: [Float] = []
        values.reserveCapacity((r1 - r0) * (c1 - c0) / 2)

        var row = r0
        while row < min(r1, depth.height) {
            var col = c0
            while col < min(c1, depth.width) {
                let sample = depth.sample(row: row, column: col)
                if sample.isFinite, sample >= minRange, sample <= maxRange {
                    values.append(sample)
                }
                col += 1
            }
            row += 1
        }

        // Need a stable patch of valid LiDAR hits, not a handful of noisy pixels.
        guard values.count >= 24 else { return nil }
        values.sort()
        let p10Index = min(values.count - 1, max(0, Int(Float(values.count) * 0.10)))
        let medianIndex = values.count / 2
        return ZoneStats(p10: values[p10Index], median: values[medianIndex])
    }

    private static func obstacleSeverity(_ distance: Float, warn: Float, stop: Float) -> Int {
        if distance <= stop { return 100 }
        if distance >= warn { return 0 }
        let t = (warn - distance) / max(0.01, warn - stop)
        return Int((70.0 + 25.0 * t).rounded())
    }

    private static func spoken(_ meters: Float) -> String {
        String(format: "%.1f meters", meters)
    }

    private static func makeHazard(
        kind: HazardKind,
        distance: Float,
        message: String,
        phrase: String,
        severity: Int
    ) -> Hazard {
        Hazard(
            kind: kind,
            distanceMeters: distance,
            message: message,
            spokenPhrase: phrase,
            severity: severity
        )
    }

    private static func makePreview(_ depth: DepthMap) -> DepthPreview {
        let width = 48
        let height = 36
        var meters = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            let srcY = min(depth.height - 1, y * depth.height / height)
            for x in 0..<width {
                let srcX = min(depth.width - 1, x * depth.width / width)
                meters[y * width + x] = depth.sample(row: srcY, column: srcX)
            }
        }
        return DepthPreview(width: width, height: height, meters: meters)
    }
}
