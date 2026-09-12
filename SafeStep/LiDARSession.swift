import ARKit
import Combine
import Foundation

enum CaptureSource {
    case arkit
    case avFoundation
    case demo
}

/// Owns capture: ARKit LiDAR when the phone has it, otherwise the regular
/// rear camera (AVFoundation). Missing LiDAR is normal — ARKit is already
/// part of iOS and is not a separate install.
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
        cameraCapture.onDepth = { [weak self] map in
            self?.handleDepth(map)
        }

        if forceDemo {
            startCameraThenDemo(reason: "Demo scenes (manual)")
            return
        }

        if lidarSupported, ARWorldTrackingConfiguration.isSupported {
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
                self.hasCameraPreview = true
                self.startDemo(reason: "No LiDAR on this device — camera + demo alerts")
            case .failed(let message):
                self.hasCameraPreview = false
                self.errorMessage = message
                self.startDemo(reason: message)
            }
        }
    }

    private func startCameraThenDemo(reason: String) {
        startDemo(reason: reason)
        cameraCapture.start(videoOnly: true) { [weak self] result in
            guard let self, self.isRunning else { return }
            if case .failed(let message) = result {
                self.hasCameraPreview = false
                self.errorMessage = message
            } else {
                self.hasCameraPreview = true
            }
        }
    }

    private func handleDepth(_ map: DepthMap) {
        guard isRunning, !isDemoMode else { return }
        processQueue.async { [weak self] in
            guard let self else { return }
            let result = DepthAnalyzer.analyze(depth: map, mode: self.mode)
            DispatchQueue.main.async {
                self.snapshot = result
                self.alerts.handle(result)
            }
        }
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
            let result = DepthAnalyzer.analyze(depth: map, mode: self.mode)
            DispatchQueue.main.async {
                self.snapshot = result
                self.alerts.handle(result)
            }
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
            if !self.isDemoMode {
                self.start()
            }
        }
    }

    private func startDemo(reason: String) {
        session.pause()
        isDemoMode = true
        captureSource = .demo
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
        let result = DepthAnalyzer.analyze(depth: map, mode: mode)
        snapshot = result
        alerts.handle(result)
        statusText = "Demo · \(scene.title)"
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
