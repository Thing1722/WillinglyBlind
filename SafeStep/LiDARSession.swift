import ARKit
import Combine
import CoreVideo
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
        // Serialize with in-flight analyze. Mutating the struct needs a non-optional self.
        processQueue.sync {
            self.debouncer.reset()
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
        guard let depthData = depthData else { return }
        // Copy out of ARKit's recycled pixel buffers before this callback returns.
        guard let depth = DepthFrame(
            pixelBuffer: depthData.depthMap,
            confidence: depthData.confidenceMap
        ) else { return }

        processQueue.async { [weak self] in
            self?.publishAnalyzed(depth, skipDebounce: false)
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
            guard let self = self, self.isRunning else { return }
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
            guard let self = self, self.isRunning else { return }
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
            guard let self = self, self.isRunning else { return }
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
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > 0, height > 0 else { return nil }
        guard let meters = Self.copyFloat32Rows(from: pixelBuffer, width: width, height: height) else {
            return nil
        }

        var confidenceBytes: [UInt8]?
        if let confidenceBuffer = confidence {
            confidenceBytes = Self.copyUInt8Rows(from: confidenceBuffer, width: width, height: height)
        }

        self.init(
            width: width,
            height: height,
            meters: DepthBufferCopy.copyMeters(
                width: width,
                height: height,
                meters: meters,
                confidence: confidenceBytes
            )
        )
    }

    /// Copies a Float32 depth map, respecting `bytesPerRow` padding.
    private static func copyFloat32Rows(from pixelBuffer: CVPixelBuffer, width: Int, height: Int) -> [Float]? {
        CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags.readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags.readOnly) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        var values = [Float](repeating: 0, count: width * height)
        for row in 0..<height {
            let rowPointer = baseAddress.advanced(by: row * bytesPerRow).assumingMemoryBound(to: Float.self)
            for column in 0..<width {
                values[row * width + column] = rowPointer[column]
            }
        }
        return values
    }

    /// Copies an 8-bit confidence map, respecting `bytesPerRow` padding.
    private static func copyUInt8Rows(from pixelBuffer: CVPixelBuffer, width: Int, height: Int) -> [UInt8]? {
        CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags.readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags.readOnly) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        var values = [UInt8](repeating: 0, count: width * height)
        for row in 0..<height {
            let rowPointer = baseAddress.advanced(by: row * bytesPerRow).assumingMemoryBound(to: UInt8.self)
            for column in 0..<width {
                values[row * width + column] = rowPointer[column]
            }
        }
        return values
    }
}
