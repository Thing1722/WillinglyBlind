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

            VStack(spacing: 16) {
                Image(systemName: "figure.walk")
                    .font(.system(size: 64))
                    .foregroundStyle(.blue)

                Text("Live Detection")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text(mode.rawValue)
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Text(session.snapshot.primary.message)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(alertColor(for: session.snapshot.primary.kind))
                    .multilineTextAlignment(.center)

                if session.snapshot.primary.distanceMeters.isFinite,
                   session.snapshot.primary.distanceMeters < 20 {
                    Text(session.snapshot.closestReadable)
                        .font(.title.monospacedDigit())
                }

                Text(session.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if let errorMessage = session.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .padding(24)
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
            switch session.captureSource {
            case .arkit:
                ARCameraPreview(session: session.session)
                    .ignoresSafeArea()
            case .avFoundation:
                RearCameraPreview(captureSession: session.cameraCapture.session)
                    .ignoresSafeArea()
            case .demo:
                EmptyView()
            }

            DepthHeatmapView(preview: session.snapshot.preview)
                .opacity(heatmapOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }

    private var heatmapOpacity: Double {
        switch session.captureSource {
        case .arkit, .avFoundation:
            return 0.42
        case .demo:
            return 1.0
        }
    }

    private func alertColor(for kind: HazardKind) -> Color {
        switch kind {
        case .stop, .dropOff:
            return .red
        case .obstacleAhead, .overhead:
            return .orange
        case .caution, .obstacleLeft, .obstacleRight:
            return Color.orange.opacity(0.9)
        case .noSignal:
            return .secondary
        case .clear:
            return .green
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
