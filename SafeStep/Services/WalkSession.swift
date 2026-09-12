import ARKit
import AVFoundation
import SwiftUI

final class WalkSession: NSObject, ObservableObject, ARSessionDelegate {
    let session = ARSession()
    let mode: WalkingMode
    let isDemo: Bool
    let alerts = AlertService()
    @Published private(set) var isRunning = false
    @Published private(set) var status = "Ready to scan"
    @Published private(set) var result: DetectionResult?
    @Published var scenario: DemoScenario = .clear { didSet { if isDemo && isRunning { updateDemo() } } }
    @Published var demoMovement: Movement = .walking { didSet { if isDemo && isRunning { updateDemo() } } }
    @Published var voiceEnabled = true { didSet { alerts.voiceEnabled = voiceEnabled; if !voiceEnabled { alerts.stop() } } }
    @Published var hapticsEnabled = true { didSet { alerts.hapticsEnabled = hapticsEnabled; if !hapticsEnabled { alerts.stop() } } }
    var viewport = CGSize(width: 390, height: 844)
    private var heartbeat: Timer?
    private var lastFrameTime: TimeInterval = 0
    private var lastGoodData = Date.distantPast
    private var previousPosition: SIMD3<Float>?
    private var filteredSpeed: Float = 0
    private var generation = 0

    static var supportsLiDAR: Bool { ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) }

    init(mode: WalkingMode, isDemo: Bool) {
        self.mode = mode
        self.isDemo = isDemo
        super.init()
        session.delegate = self
        session.delegateQueue = .main
    }

    func start() {
        guard !isRunning else { return }
        generation += 1
        let request = generation
        if isDemo { begin(); return }
        guard Self.supportsLiDAR else { status = "LiDAR is unavailable. Try the demo from the start screen."; return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: begin()
        case .notDetermined:
            status = "Waiting for camera permission"
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self = self, self.generation == request else { return }
                    if granted { self.begin() } else { self.status = "Camera access denied. Enable it in Settings to scan." }
                }
            }
        default: status = "Camera access denied. Enable it in Settings to scan."
        }
    }

    private func begin() {
        isRunning = true
        result = nil
        previousPosition = nil
        filteredSpeed = 0
        lastFrameTime = 0
        lastGoodData = Date()
        status = isDemo ? "Demo · simulated depth" : "Finding depth · point the rear camera ahead and slightly down"
        if isDemo { updateDemo() }
        else {
            let configuration = ARWorldTrackingConfiguration()
            configuration.frameSemantics = .sceneDepth
            session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        }
        heartbeat?.invalidate()
        heartbeat = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            guard let self = self, self.isRunning else { return }
            if !self.isDemo && Date().timeIntervalSince(self.lastGoodData) > 1.5 {
                self.invalidateReading("Depth unavailable · stop and check your surroundings")
            }
            if let assessment = self.result?.assessment { self.alerts.update(assessment) }
        }
    }

    func stop() {
        generation += 1
        isRunning = false
        session.pause()
        heartbeat?.invalidate()
        heartbeat = nil
        alerts.stop()
        result = nil
        status = "Walk paused"
    }

    private func updateDemo() {
        result = HazardDetector.analyze(scenario.frame, speed: demoMovement == .stationary ? 0 : demoMovement == .walking ? 0.8 : 2, mode: mode)
        status = "Demo · simulated depth"
    }

    private func invalidateReading(_ message: String) {
        result = nil
        status = message
        alerts.stop()
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard isRunning, !isDemo, frame.timestamp - lastFrameTime >= 0.1 else { return }
        guard case .normal = frame.camera.trackingState else {
            previousPosition = nil
            filteredSpeed = 0
            invalidateReading("Tracking limited · hold the camera steady")
            return
        }
        let position = SIMD3<Float>(frame.camera.transform.columns.3.x, frame.camera.transform.columns.3.y, frame.camera.transform.columns.3.z)
        if let previous = previousPosition {
            let delta = position - previous
            let speed = sqrt(delta.x * delta.x + delta.z * delta.z) / Float(max(0.01, frame.timestamp - lastFrameTime))
            filteredSpeed = filteredSpeed * 0.65 + min(speed, 5) * 0.35
        }
        previousPosition = position
        lastFrameTime = frame.timestamp
        guard let depth = frame.sceneDepth, let oriented = portraitDepth(depth, frame: frame) else {
            invalidateReading("Depth unavailable · check the camera view")
            return
        }
        guard let reading = HazardDetector.analyze(oriented, speed: filteredSpeed, mode: mode) else {
            invalidateReading("Not enough reliable depth · check the camera view")
            return
        }
        result = reading
        lastGoodData = Date()
        status = "LiDAR active · depth updated live"
    }

    // displayTransform accounts for sensor rotation and aspect-fill cropping.
    // Low-confidence samples remain invalid; missing depth never means path clear.
    private func portraitDepth(_ depth: ARDepthData, frame: ARFrame) -> DepthFrame? {
        let buffer = depth.depthMap
        let confidence = depth.confidenceMap
        guard CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        if let confidence { CVPixelBufferLockBaseAddress(confidence, .readOnly) }
        defer { if let confidence { CVPixelBufferUnlockBaseAddress(confidence, .readOnly) } }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        let transform = frame.displayTransform(for: .portrait, viewportSize: viewport).inverted()
        var values = [Float](repeating: .nan, count: 48 * 72)
        for y in 0..<72 {
            for x in 0..<48 {
                let point = CGPoint(x: (Double(x) + 0.5) / 48, y: (Double(y) + 0.5) / 72).applying(transform)
                guard point.x >= 0, point.x < 1, point.y >= 0, point.y < 1 else { continue }
                let px = min(width - 1, Int(point.x * Double(width)))
                let py = min(height - 1, Int(point.y * Double(height)))
                if let confidence, let confidenceBase = CVPixelBufferGetBaseAddress(confidence) {
                    let cx = min(CVPixelBufferGetWidth(confidence) - 1, Int(point.x * Double(CVPixelBufferGetWidth(confidence))))
                    let cy = min(CVPixelBufferGetHeight(confidence) - 1, Int(point.y * Double(CVPixelBufferGetHeight(confidence))))
                    let value = confidenceBase.advanced(by: cy * CVPixelBufferGetBytesPerRow(confidence) + cx).load(as: UInt8.self)
                    if value < 1 { continue }
                }
                values[y * 48 + x] = base.advanced(by: py * stride).assumingMemoryBound(to: Float.self)[px]
            }
        }
        return DepthFrame(width: 48, height: 72, meters: values)
    }

    func sessionWasInterrupted(_ session: ARSession) {
        stop()
        status = "Session interrupted · resume when ready"
    }
    func session(_ session: ARSession, didFailWithError error: Error) {
        stop()
        status = "Camera session failed: \(error.localizedDescription)"
    }

    deinit { heartbeat?.invalidate(); session.pause() }
}

struct CameraPreview: UIViewRepresentable {
    let model: WalkSession
    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.session = model.session
        view.automaticallyUpdatesLighting = false
        return view
    }
    func updateUIView(_ uiView: ARSCNView, context: Context) { }
}
