import ARKit
import Combine
import Foundation

/// Owns the ARKit session, converts each LiDAR depth frame into a
/// `DetectionSnapshot`, and falls back to cycling synthetic scenes when the
/// device has no scene-depth camera.
final class LiDARSession: NSObject, ObservableObject, ARSessionDelegate {
    @Published var snapshot: DetectionSnapshot = .idle
    @Published var isDemoMode = false
    @Published var isRunning = false
    @Published var lidarSupported = false
    @Published var statusText = "Starting…"
    @Published var errorMessage: String?
    @Published var demoScene: SyntheticScene = .clearHallway

    let session = ARSession()
    let mode: WalkingMode

    private let alerts = AlertEngine()
    private let forceDemo: Bool
    private var demoTimer: Timer?
    private var demoIndex = 0
    private var lastProcessTime: TimeInterval = 0
    private var debouncer = AlertDebouncer()
    private let processQueue = DispatchQueue(label: "com.safestep.depth", qos: .userInitiated)

    static var deviceSupportsLiDAR: Bool {
        ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
            || ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth)
    }

    init(mode: WalkingMode, forceDemo: Bool = false) {
        self.mode = mode
        self.forceDemo = forceDemo
        super.init()
        session.delegate = self
        lidarSupported = Self.deviceSupportsLiDAR
    }

    func start() {
        errorMessage = nil
        alerts.prepare()
        isRunning = true
        processQueue.async { [weak self] in
            self?.debouncer.reset()
        }

        if forceDemo || !lidarSupported {
            startDemo(reason: forceDemo ? "Demo scenes" : "No LiDAR on this device — demo scenes")
            return
        }

        guard ARWorldTrackingConfiguration.isSupported else {
            startDemo(reason: "ARKit world tracking unavailable — demo scenes")
            return
        }

        let config = ARWorldTrackingConfiguration()
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            config.frameSemantics.insert(.smoothedSceneDepth)
        } else {
            config.frameSemantics.insert(.sceneDepth)
        }
        config.environmentTexturing = .none
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
        isDemoMode = false
        statusText = "LiDAR live · \(mode.rawValue)"
    }

    func stop() {
        isRunning = false
        demoTimer?.invalidate()
        demoTimer = nil
        session.pause()
        alerts.reset()
        statusText = "Stopped"
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard isRunning, !isDemoMode else { return }
        guard frame.timestamp - lastProcessTime >= 0.12 else { return }
        lastProcessTime = frame.timestamp

        let depthData = frame.smoothedSceneDepth ?? frame.sceneDepth
        guard let depthData else { return }
        let buffer = depthData.depthMap
        let confidence = depthData.confidenceMap

        processQueue.async { [weak self] in
            guard let self else { return }
            guard let map = DepthMap(pixelBuffer: buffer, confidence: confidence) else { return }
            var result = DepthAnalyzer.analyze(depth: map, config: self.mode.detectionConfig)
            result = self.debouncer.apply(result, config: self.mode.detectionConfig)
            DispatchQueue.main.async {
                self.snapshot = result
                self.alerts.handle(result)
            }
        }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.errorMessage = error.localizedDescription
            self.startDemo(reason: "Camera failed — demo scenes")
        }
    }

    func sessionWasInterrupted(_ session: ARSession) {
        DispatchQueue.main.async {
            self.statusText = "Camera interrupted"
        }
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        DispatchQueue.main.async {
            if !self.isDemoMode {
                self.start()
            }
        }
    }

    private func startDemo(reason: String) {
        session.pause()
        isDemoMode = true
        lidarSupported = Self.deviceSupportsLiDAR && !forceDemo
        statusText = reason
        demoIndex = 0
        publishDemoScene()
        demoTimer?.invalidate()
        let timer = Timer(timeInterval: 4.0, repeats: true) { [weak self] _ in
            guard let self, self.isRunning else { return }
            self.demoIndex += 1
            self.publishDemoScene()
        }
        RunLoop.main.add(timer, forMode: .common)
        demoTimer = timer
    }

    private func publishDemoScene() {
        let scenes = SyntheticScene.allCases
        let scene = scenes[demoIndex % scenes.count]
        demoScene = scene
        let map = SyntheticDepth.make(scene, seed: demoIndex + 1)
        // Demo publishes one frame per scene, so skip debounce.
        let result = DepthAnalyzer.analyze(depth: map, config: mode.detectionConfig)
        snapshot = result
        alerts.handle(result)
        statusText = "Demo · \(scene.title)"
    }
}

/// Holds a warning until it is seen for `warningAppearFrameCount` frames,
/// and keeps it until `warningClearFrameCount` consecutive clear frames.
struct AlertDebouncer {
    private var displayed: Hazard = .clear
    private var candidate: Hazard = .clear
    private var candidateStreak = 0
    private var clearStreak = 0

    mutating func reset() {
        displayed = .clear
        candidate = .clear
        candidateStreak = 0
        clearStreak = 0
    }

    mutating func apply(_ snapshot: DetectionSnapshot, config: DetectionConfig) -> DetectionSnapshot {
        snapshot.replacingPrimary(process(snapshot.primary, config: config))
    }

    private mutating func process(_ incoming: Hazard, config: DetectionConfig) -> Hazard {
        if incoming.kind == .noSignal {
            displayed = incoming
            candidate = incoming
            candidateStreak = 0
            clearStreak = 0
            return displayed
        }

        if incoming.kind == .clear {
            clearStreak += 1
            candidateStreak = 0
            candidate = .clear
            if clearStreak >= config.warningClearFrameCount {
                displayed = .clear
            }
            return displayed
        }

        clearStreak = 0
        if incoming.kind == candidate.kind {
            candidateStreak += 1
            candidate = incoming
        } else {
            candidate = incoming
            candidateStreak = 1
        }

        if incoming.kind == displayed.kind {
            displayed = incoming
            return displayed
        }

        if candidateStreak >= config.warningAppearFrameCount {
            displayed = incoming
        }
        return displayed
    }
}

extension DepthMap {
    init?(pixelBuffer: CVPixelBuffer, confidence: CVPixelBuffer?) {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > 0, height > 0 else { return nil }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        var meters = [Float](repeating: 0, count: width * height)

        var confidenceLock = false
        var confidenceBase: UnsafeMutableRawPointer?
        var confidenceBytesPerRow = 0
        if let confidence {
            CVPixelBufferLockBaseAddress(confidence, .readOnly)
            confidenceLock = true
            confidenceBase = CVPixelBufferGetBaseAddress(confidence)
            confidenceBytesPerRow = CVPixelBufferGetBytesPerRow(confidence)
        }
        defer {
            if confidenceLock, let confidence {
                CVPixelBufferUnlockBaseAddress(confidence, .readOnly)
            }
        }

        for y in 0..<height {
            let row = base.advanced(by: y * bytesPerRow).assumingMemoryBound(to: Float.self)
            let confidenceRow = confidenceBase?.advanced(by: y * confidenceBytesPerRow).assumingMemoryBound(to: UInt8.self)
            for x in 0..<width {
                var value = row[x]
                // ARConfidenceLevel.low == 0; drop noisy LiDAR hits.
                if let confidenceRow, confidenceRow[x] == 0 {
                    value = 0
                }
                meters[y * width + x] = value
            }
        }

        self.width = width
        self.height = height
        self.meters = meters
    }
}
