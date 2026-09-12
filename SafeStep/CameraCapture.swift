import AVFoundation
import CoreMedia
import CoreVideo
import SwiftUI
import UIKit

enum CameraStartResult {
    case depthAvailable
    case videoOnly
    case failed(String)
}

/// Regular rear camera (and optional depth) so the app still shows a live
/// view when ARKit LiDAR is missing. Do not run this at the same time as ARKit.
final class CameraCapture: NSObject {
    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.safestep.camera")
    private let depthQueue = DispatchQueue(label: "com.safestep.avdepth")
    private let depthOutput = AVCaptureDepthDataOutput()
    private var lastDepthTime = CFAbsoluteTimeGetCurrent()

    private(set) var hasDepth = false
    private(set) var hasVideo = false
    var onDepth: ((DepthFrame) -> Void)?

    static var hasRearCamera: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
    }

    func start(videoOnly: Bool, completion: @escaping (CameraStartResult) -> Void) {
        let finish: (CameraStartResult) -> Void = { result in
            DispatchQueue.main.async { completion(result) }
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            sessionQueue.async { self.configureAndRun(videoOnly: videoOnly, completion: finish) }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    self.sessionQueue.async { self.configureAndRun(videoOnly: videoOnly, completion: finish) }
                } else {
                    finish(.failed("Camera permission denied"))
                }
            }
        default:
            finish(.failed("Camera permission denied. Enable it in Settings."))
        }
    }

    func stop() {
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
            self.hasVideo = false
            self.hasDepth = false
        }
    }

    private func configureAndRun(videoOnly: Bool, completion: @escaping (CameraStartResult) -> Void) {
        session.beginConfiguration()
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }
        session.sessionPreset = .vga640x480

        guard let device = Self.bestDevice(preferDepth: !videoOnly) else {
            session.commitConfiguration()
            completion(.failed("No rear camera on this device"))
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                session.commitConfiguration()
                completion(.failed("Could not open the rear camera"))
                return
            }
            session.addInput(input)
        } catch {
            session.commitConfiguration()
            completion(.failed(error.localizedDescription))
            return
        }

        hasDepth = false
        if !videoOnly {
            hasDepth = configureDepth(on: device)
        }

        if let connection = session.connections.first(where: { $0.isVideoOrientationSupported }) {
            connection.videoOrientation = .portrait
        }

        session.commitConfiguration()
        if !session.isRunning {
            session.startRunning()
        }
        hasVideo = session.isRunning
        completion(hasDepth ? .depthAvailable : .videoOnly)
    }

    private func configureDepth(on device: AVCaptureDevice) -> Bool {
        guard let formats = pickDepthFormats(for: device) else { return false }
        do {
            try device.lockForConfiguration()
            device.activeFormat = formats.color
            device.activeDepthDataFormat = formats.depth
            device.unlockForConfiguration()
        } catch {
            return false
        }

        depthOutput.isFilteringEnabled = true
        guard session.canAddOutput(depthOutput) else { return false }
        session.addOutput(depthOutput)
        depthOutput.setDelegate(self, callbackQueue: depthQueue)
        if let connection = depthOutput.connection(with: .depthData), connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
        return true
    }

    private func pickDepthFormats(for device: AVCaptureDevice) -> (color: AVCaptureDevice.Format, depth: AVCaptureDevice.Format)? {
        let preferred: [FourCharCode] = [
            kCVPixelFormatType_DepthFloat32,
            kCVPixelFormatType_DepthFloat16,
            kCVPixelFormatType_DisparityFloat32,
            kCVPixelFormatType_DisparityFloat16
        ]
        for color in device.formats {
            for depthType in preferred {
                if let depth = color.supportedDepthDataFormats.first(where: {
                    CMFormatDescriptionGetMediaSubType($0.formatDescription) == depthType
                }) {
                    return (color, depth)
                }
            }
        }
        return nil
    }

    private static func bestDevice(preferDepth: Bool) -> AVCaptureDevice? {
        var types: [AVCaptureDevice.DeviceType] = [
            .builtInLiDARDepthCamera,
            .builtInDualWideCamera,
            .builtInDualCamera,
            .builtInWideAngleCamera
        ]
        if !preferDepth {
            types = [.builtInWideAngleCamera, .builtInDualWideCamera, .builtInDualCamera]
        }
        let discovered = AVCaptureDevice.DiscoverySession(
            deviceTypes: types,
            mediaType: .video,
            position: .back
        )
        return discovered.devices.first ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
    }
}

extension CameraCapture: AVCaptureDepthDataOutputDelegate {
    func depthDataOutput(
        _ output: AVCaptureDepthDataOutput,
        didOutput depthData: AVDepthData,
        timestamp: CMTime,
        connection: AVCaptureConnection
    ) {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastDepthTime >= 0.12 else { return }
        lastDepthTime = now

        let converted = depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
        guard let frame = DepthFrame(pixelBuffer: converted.depthDataMap, confidence: nil) else { return }
        onDepth?(frame)
    }
}

final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}

struct RearCameraPreview: UIViewRepresentable {
    let captureSession: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = captureSession
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        if uiView.previewLayer.session !== captureSession {
            uiView.previewLayer.session = captureSession
        }
        if let connection = uiView.previewLayer.connection, connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
    }
}
