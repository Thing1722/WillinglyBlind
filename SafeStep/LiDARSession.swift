import ARKit
import Combine
import Foundation

enum CaptureSource: Equatable {
    case arkit
    case avFoundation
    case demo
}

/// Owns the ARKit session, converts each LiDAR depth frame into a
/// `DetectionSnapshot`, and falls back to AVFoundation then synthetic scenes
/// when the device has no scene-depth camera.
final class LiDARSession: NSObject, ObservableObject, ARSessionDelegate {
    @Published var snapshot: DetectionSnapshot = .idle
    @Published var isDemoMode = false
    @Published var isRunning = false
    @Published var lidarSupported = false
    @Published var hasCameraPreview = false
    @Published var captureSource: CaptureSource = .demo
    @Published var statusText = "Starting…"
    @Published var errorMessage: String?
    @Published var demoScene: SyntheticScene = .clearHallway

    let session = ARSession()
    let cameraCapture = CameraCapture()
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
        cameraCapture.onDepth = { [weak self] frame in
            self?.handleCapturedDepth(frame)
        }

        if forceDemo {
            cameraCapture.stop()
            startDemo(reason: "Demo scenes")
            return
        }

        if lidarSupported, ARWorldTrackingConfiguration.isSupported {
            cameraCapture.stop()
            let config = ARWorldTrackingConfiguration()
            if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
                config.frameSemantics.insert(.smoothedSceneDepth)
            } else {
                config.frameSemantics.insert(.sceneDepth)
            }
            config.environmentTexturing = .none
            session.run(config, options: [.resetTracking, .removeExistingAnchors])
            captureSource = .arkit
            isDemoMode = false
            hasCameraPreview = true
            statusText = "LiDAR live · \(mode.rawValue)"
            return
        }

        startRearCamera(preferDepth: true)
    }

    func stop() {
        isRunning = false
        demoTimer?.invalidate()
        demoTimer = nil
        session.pause()
        cameraCapture.stop()
        alerts.reset()
        hasCameraPreview = false
        statusText = "Stopped"
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard isRunning, captureSource == .arkit else { return }
        guard frame.timestamp - lastProcessTime >= 0.12 else { return }
        lastProcessTime = frame.timestamp

        let depthData = frame.smoothedSceneDepth ?? frame.sceneDepth
        guard let depthData else { return }
        let buffer = depthData.depthMap
        let confidence = depthData.confidenceMap

        processQueue.async { [weak self] in
            guard let self else { return }
            guard let depth = DepthFrame(pixelBuffer: buffer, confidence: confidence) else { return }
            self.publishAnalyzed(depth, skipDebounce: false)
        }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.errorMessage = error.localizedDescription
            self.startRearCamera(preferDepth: true)
        }
    }

    func sessionWasInterrupted(_ session: ARSession) {
        DispatchQueue.main.async {
            self.statusText = "Camera interrupted"
        }
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        DispatchQueue.main.async {
            if self.captureSource == .arkit {
                self.start()
            }
        }
    }

    private func startRearCamera(preferDepth: Bool) {
        session.pause()
        cameraCapture.start(videoOnly: !preferDepth) { [weak self] result in
            guard let self, self.isRunning else { return }
            switch result {
            case .depthAvailable:
                self.captureSource = .avFoundation
                self.isDemoMode = false
                self.hasCameraPreview = true
                self.statusText = "Rear camera depth · \(self.mode.rawValue)"
            case .videoOnly:
                self.captureSource = .avFoundation
                self.hasCameraPreview = true
                self.startDemo(reason: "No LiDAR on this device — camera + demo alerts", keepCamera: true)
            case .failed(let message):
                self.hasCameraPreview = false
                self.errorMessage = message
                self.startDemo(reason: message)
            }
        }
    }

    private func handleCapturedDepth(_ frame: DepthFrame) {
        guard isRunning, captureSource == .avFoundation, !isDemoMode else { return }
        processQueue.async { [weak self] in
            self?.publishAnalyzed(frame, skipDebounce: false)
        }
    }

    private func publishAnalyzed(_ depth: DepthFrame, skipDebounce: Bool) {
        var result = DepthAnalyzer.analyze(depth: depth, config: mode.detectionConfig)
        if !skipDebounce {
            result = debouncer.apply(result, config: mode.detectionConfig)
        }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isRunning else { return }
            self.snapshot = result
            self.alerts.handle(result)
        }
    }

    private func startDemo(reason: String, keepCamera: Bool = false) {
        session.pause()
        if !keepCamera {
            cameraCapture.stop()
            captureSource = .demo
            hasCameraPreview = false
        }
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
        let frame = SyntheticDepth.make(scene, seed: demoIndex + 1)
        // Demo publishes one frame per scene, so skip debounce.
        let result = DepthAnalyzer.analyze(depth: frame, config: mode.detectionConfig)
        snapshot = result
        alerts.handle(result)
        statusText = "Demo · \(scene.title)"
    }
}

extension DepthFrame {
    init?(pixelBuffer: CVPixelBuffer, confidence: CVPixelBuffer?) {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > 0, height > 0 else { return nil }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }

        let metersBytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        var confidenceLock = false
        var confidenceBase: UnsafePointer<UInt8>?
        var confidenceBytesPerRow = 0
        if let confidence {
            CVPixelBufferLockBaseAddress(confidence, .readOnly)
            confidenceLock = true
            confidenceBase = CVPixelBufferGetBaseAddress(confidence)?.assumingMemoryBound(to: UInt8.self)
            confidenceBytesPerRow = CVPixelBufferGetBytesPerRow(confidence)
        }
        defer {
            if confidenceLock, let confidence {
                CVPixelBufferUnlockBaseAddress(confidence, .readOnly)
            }
        }

        let meters = DepthBufferCopy.copyMeters(
            width: width,
            height: height,
            meters: base.assumingMemoryBound(to: Float.self),
            metersBytesPerRow: metersBytesPerRow,
            confidence: confidenceBase,
            confidenceBytesPerRow: confidenceBytesPerRow
        )
        self.init(width: width, height: height, meters: meters)
    }
}
