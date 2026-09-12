import SwiftUI

struct LiveDetectionView: View {
    let mode: WalkingMode

    @StateObject private var session: LiDARSession

    init(mode: WalkingMode, forceDemo: Bool = false) {
        self.mode = mode
        _session = StateObject(wrappedValue: LiDARSession(mode: mode, forceDemo: forceDemo))
    }

    var body: some View {
        ZStack {
            cameraBackground
            VStack {
                topStatus
                Spacer()
                zoneMeters
                alertCard
                endHint
            }
            .padding(16)
        }
        .background(Color.black)
        .navigationTitle("Safe Walk")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { session.start() }
        .onDisappear { session.stop() }
    }

    @ViewBuilder
    private var cameraBackground: some View {
        ZStack {
            if session.captureSource == .arkit {
                ARCameraPreview(session: session.session)
                    .ignoresSafeArea()
            } else if session.hasCameraPreview {
                RearCameraPreview(captureSession: session.cameraCapture.session)
                    .ignoresSafeArea()
            }

            DepthHeatmapView(preview: session.snapshot.preview)
                .opacity(heatmapOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }

    private var heatmapOpacity: Double {
        if session.captureSource == .arkit || session.captureSource == .avFoundation {
            return 0.42
        }
        return session.hasCameraPreview ? 0.50 : 1.0
    }

    private var topStatus: some View {
        HStack {
            Label(mode.rawValue, systemImage: "figure.walk")
            Spacer()
            Circle()
                .fill(session.isDemoMode ? Color.orange : Color.green)
                .frame(width: 8, height: 8)
            Text(session.isDemoMode ? "DEMO" : (session.captureSource == .arkit ? "LIDAR" : "CAMERA"))
                .fontWeight(.semibold)
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var zoneMeters: some View {
        HStack(spacing: 10) {
            zoneChip("Left", session.snapshot.zones.left)
            zoneChip("Ahead", session.snapshot.zones.center)
            zoneChip("Right", session.snapshot.zones.right)
        }
    }

    private func zoneChip(_ title: String, _ meters: Float?) -> some View {
        VStack(spacing: 2) {
            Text(title.uppercased())
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(format(meters))
                .font(.headline.monospacedDigit())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var alertCard: some View {
        let hazard = session.snapshot.primary
        return VStack(spacing: 8) {
            if session.isDemoMode {
                Text(session.demoScene.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
            }

            Text(hazard.message)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)

            Text(session.snapshot.closestReadable)
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .monospacedDigit()

            if let extra = session.snapshot.hazards.dropFirst().first {
                Text(extra.message)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
            }

            if let errorMessage = session.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.yellow)
            }

            Text(session.statusText)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(alertColor(for: hazard.kind).opacity(0.92), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: alertColor(for: hazard.kind).opacity(0.45), radius: 16, y: 6)
        .animation(.easeInOut(duration: 0.2), value: hazard.kind)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(hazard.message), \(session.snapshot.closestReadable)")
    }

    private var endHint: some View {
        Text("Swipe back to end the walk")
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.7))
            .padding(.top, 4)
    }

    private func format(_ meters: Float?) -> String {
        guard let meters, meters.isFinite, meters < 20 else { return "—" }
        return String(format: "%.1fm", meters)
    }

    private func alertColor(for kind: HazardKind) -> Color {
        switch kind {
        case .stop, .dropOff:
            return Color.red
        case .obstacleAhead, .overhead:
            return Color.orange
        case .obstacleLeft, .obstacleRight:
            return Color.yellow.opacity(0.95)
        case .noSignal:
            return Color.gray
        case .clear:
            return Color.green
        }
    }
}

struct LiveDetectionView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            LiveDetectionView(mode: .standard, forceDemo: true)
        }
    }
}
