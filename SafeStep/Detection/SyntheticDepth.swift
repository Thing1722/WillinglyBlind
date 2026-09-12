import Foundation

/// Geometric stand-ins for ARKit depth frames so the app can be demoed
/// without a LiDAR iPhone (Simulator, older devices, or a walkthrough).
enum SyntheticScene: String, CaseIterable, Identifiable {
    case clearHallway
    case obstacleAhead
    case emergencyStop
    case dropOff
    case overhead
    case obstacleLeft
    case obstacleRight

    var id: Self { self }

    var title: String {
        switch self {
        case .clearHallway: return "Clear hallway"
        case .obstacleAhead: return "Obstacle ahead"
        case .emergencyStop: return "Immediate stop"
        case .dropOff: return "Drop-off / stairs down"
        case .overhead: return "Overhead hazard"
        case .obstacleLeft: return "Obstacle on the left"
        case .obstacleRight: return "Obstacle on the right"
        }
    }
}

enum SyntheticDepth {
    static let width = 256
    static let height = 192

    static func make(_ scene: SyntheticScene, seed: Int = 1) -> DepthMap {
        var depth = hallway()
        switch scene {
        case .clearHallway:
            break
        case .obstacleAhead:
            stampBox(&depth, row0: 0.35, row1: 0.75, col0: 0.38, col1: 0.62, meters: 0.95)
        case .emergencyStop:
            stampBox(&depth, row0: 0.32, row1: 0.82, col0: 0.34, col1: 0.66, meters: 0.32)
        case .dropOff:
            stampBox(&depth, row0: 0.78, row1: 1.00, col0: 0.25, col1: 0.75, meters: 3.60)
        case .overhead:
            stampBox(&depth, row0: 0.02, row1: 0.22, col0: 0.30, col1: 0.70, meters: 0.90)
        case .obstacleLeft:
            stampBox(&depth, row0: 0.30, row1: 0.80, col0: 0.00, col1: 0.28, meters: 0.70)
        case .obstacleRight:
            stampBox(&depth, row0: 0.30, row1: 0.80, col0: 0.72, col1: 1.00, meters: 0.70)
        }
        addNoise(&depth, seed: seed)
        return DepthMap(width: width, height: height, meters: depth)
    }

    /// Floor gets closer toward the bottom of the frame, as a slightly
    /// downward-facing phone would see a hallway.
    private static func hallway() -> [Float] {
        var meters = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            let t = Float(y) / Float(height - 1) // 0 = top, 1 = bottom
            let ground = 0.65 + (1 - t) * 4.20
            for x in 0..<width {
                let xc = abs(Float(x) / Float(width - 1) - 0.5)
                meters[y * width + x] = ground + 0.15 * xc
            }
        }
        return meters
    }

    private static func stampBox(
        _ depth: inout [Float],
        row0: Float,
        row1: Float,
        col0: Float,
        col1: Float,
        meters: Float
    ) {
        let r0 = Int(row0 * Float(height))
        let r1 = Int(row1 * Float(height))
        let c0 = Int(col0 * Float(width))
        let c1 = Int(col1 * Float(width))
        var y = max(0, r0)
        while y < min(height, r1) {
            var x = max(0, c0)
            while x < min(width, c1) {
                depth[y * width + x] = meters
                x += 1
            }
            y += 1
        }
    }

    private static func addNoise(_ depth: inout [Float], seed: Int) {
        var state = UInt64(truncatingIfNeeded: seed &* 1_103_515_245 &+ 12_345)
        for i in 0..<depth.count {
            state = state &* 6_364_136_223_846_793_005 &+ 1
            let unit = Float(state >> 41) / Float(1 << 23)
            depth[i] += (unit - 0.5) * 0.06
        }
    }
}
