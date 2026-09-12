import Foundation

/// Shared obstacle logic for live LiDAR frames and synthetic demo scenes.
///
/// The depth image is treated as a camera pointed forward and slightly down:
/// bottom rows are the ground near the feet, middle rows are the walking path,
/// top rows are overhead. Invalid samples (0, NaN, or > 8 m) are ignored.
///
/// Mode-dependent thresholds come only from `DetectionConfig`.
enum DepthAnalyzer {
    private static let maxRange: Float = 8.0
    private static let minRange: Float = 0.08
    /// Overhead is not in `DetectionConfig`; Standard and Sensitive share it.
    private static let overheadDistance: Float = 1.3

    static func analyze(
        depth: DepthMap,
        config: DetectionConfig,
        now: Date = Date()
    ) -> DetectionSnapshot {
        let left = zoneStats(depth, rowStart: 0.28, rowEnd: 0.60, colStart: 0.05, colEnd: 0.32)
        let center = zoneStats(depth, rowStart: 0.28, rowEnd: 0.60, colStart: 0.35, colEnd: 0.65)
        let right = zoneStats(depth, rowStart: 0.28, rowEnd: 0.60, colStart: 0.68, colEnd: 0.95)
        let ground = zoneStats(depth, rowStart: 0.82, rowEnd: 0.98, colStart: 0.30, colEnd: 0.70)
        let overhead = zoneStats(depth, rowStart: 0.02, rowEnd: 0.28, colStart: 0.30, colEnd: 0.70)
        let mid = zoneStats(depth, rowStart: 0.50, rowEnd: 0.70, colStart: 0.35, colEnd: 0.65)

        var hazards: [Hazard] = []

        let usable = [left, center, right, ground, overhead].compactMap(\.closest)
        if usable.isEmpty {
            return DetectionSnapshot(
                primary: .noSignal,
                hazards: [.noSignal],
                zones: ZoneDistances(),
                preview: makePreview(depth),
                capturedAt: now
            )
        }

        if let centerDistance = center.closest {
            hazards.append(contentsOf: centerHazards(distance: centerDistance, config: config))
        }

        let cautionMeters = Float(config.obstacleCautionMeters)
        if let leftDistance = left.closest,
           leftDistance <= cautionMeters,
           (center.closest ?? .infinity) > leftDistance + 0.15 {
            hazards.append(
                makeHazard(
                    kind: .obstacleLeft,
                    distance: leftDistance,
                    message: "Obstacle on the left",
                    phrase: "Obstacle on your left at \(spoken(leftDistance)).",
                    severity: max(40, sideSeverity(leftDistance, config: config))
                )
            )
        }

        if let rightDistance = right.closest,
           rightDistance <= cautionMeters,
           (center.closest ?? .infinity) > rightDistance + 0.15 {
            hazards.append(
                makeHazard(
                    kind: .obstacleRight,
                    distance: rightDistance,
                    message: "Obstacle on the right",
                    phrase: "Obstacle on your right at \(spoken(rightDistance)).",
                    severity: max(40, sideSeverity(rightDistance, config: config))
                )
            )
        }

        let dropOff: Bool
        if ground.invalidSampleRatio >= config.dropOffInvalidSampleRatio {
            dropOff = true
        } else if let measured = ground.median, let expected = mid.median {
            dropOff = config.isDropOff(
                measuredGroundMeters: Double(measured),
                expectedWalkingSurfaceMeters: Double(expected),
                invalidSampleRatio: ground.invalidSampleRatio
            )
        } else {
            dropOff = false
        }
        if dropOff {
            hazards.append(
                makeHazard(
                    kind: .dropOff,
                    distance: ground.median ?? 0,
                    message: "Drop-off ahead",
                    phrase: "Drop off ahead. Stop.",
                    severity: 90
                )
            )
        }

        if let overheadDistanceValue = overhead.closest, overheadDistanceValue <= overheadDistance {
            hazards.append(
                makeHazard(
                    kind: .overhead,
                    distance: overheadDistanceValue,
                    message: "Low obstacle above",
                    phrase: "Low obstacle above you at \(spoken(overheadDistanceValue)).",
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
                left: left.closest,
                center: center.closest,
                right: right.closest,
                ground: ground.median,
                overhead: overhead.closest,
                mid: mid.median
            ),
            preview: makePreview(depth),
            capturedAt: now
        )
    }

    private struct ZoneStats {
        let p10: Float?
        let median: Float?
        let invalidSampleRatio: Double

        var closest: Float? { p10 }
    }

    private static func zoneStats(
        _ depth: DepthMap,
        rowStart: Float,
        rowEnd: Float,
        colStart: Float,
        colEnd: Float
    ) -> ZoneStats {
        let r0 = Int(rowStart * Float(depth.height))
        let r1 = max(r0 + 1, Int(rowEnd * Float(depth.height)))
        let c0 = Int(colStart * Float(depth.width))
        let c1 = max(c0 + 1, Int(colEnd * Float(depth.width)))

        var values: [Float] = []
        var total = 0
        var invalid = 0
        values.reserveCapacity((r1 - r0) * (c1 - c0) / 2)

        var row = r0
        while row < min(r1, depth.height) {
            var col = c0
            while col < min(c1, depth.width) {
                let sample = depth.sample(row: row, column: col)
                total += 1
                if sample.isFinite, sample >= minRange, sample <= maxRange {
                    values.append(sample)
                } else {
                    invalid += 1
                }
                col += 1
            }
            row += 1
        }

        let ratio = total == 0 ? 1.0 : Double(invalid) / Double(total)
        // Need a stable patch of valid LiDAR hits, not a handful of noisy pixels.
        guard values.count >= 24 else {
            return ZoneStats(p10: nil, median: nil, invalidSampleRatio: ratio)
        }
        values.sort()
        let p10Index = min(values.count - 1, max(0, Int(Float(values.count) * 0.10)))
        let medianIndex = values.count / 2
        return ZoneStats(
            p10: values[p10Index],
            median: values[medianIndex],
            invalidSampleRatio: ratio
        )
    }

    private static func centerHazards(distance: Float, config: DetectionConfig) -> [Hazard] {
        switch config.obstacleAlertBand(distanceMeters: Double(distance)) {
        case .danger:
            return [
                makeHazard(
                    kind: .stop,
                    distance: distance,
                    message: "STOP — obstacle too close",
                    phrase: "Stop. Obstacle ahead at \(spoken(distance)).",
                    severity: 100
                )
            ]
        case .warning:
            return [
                makeHazard(
                    kind: .obstacleAhead,
                    distance: distance,
                    message: "Obstacle ahead",
                    phrase: "Obstacle ahead at \(spoken(distance)).",
                    severity: obstacleSeverity(distance, config: config)
                )
            ]
        case .caution:
            return [
                makeHazard(
                    kind: .caution,
                    distance: distance,
                    message: "Caution ahead",
                    phrase: "Caution. Obstacle ahead at \(spoken(distance)).",
                    severity: max(30, obstacleSeverity(distance, config: config) - 20)
                )
            ]
        case .clear:
            return []
        }
    }

    private static func obstacleSeverity(_ distance: Float, config: DetectionConfig) -> Int {
        let warn = Float(config.obstacleWarningMeters)
        let stop = Float(config.obstacleDangerMeters)
        if distance <= stop { return 100 }
        if distance >= warn { return 35 }
        let t = (warn - distance) / max(0.01, warn - stop)
        return Int((70.0 + 25.0 * t).rounded())
    }

    private static func sideSeverity(_ distance: Float, config: DetectionConfig) -> Int {
        obstacleSeverity(distance, config: config) - 10
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
