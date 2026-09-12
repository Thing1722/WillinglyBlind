import SwiftUI

struct LiveDetectionView: View {
    let mode: WalkingMode

    @State private var isDetecting = false
    @State private var snapshot = DetectionSnapshot.placeholder

    var body: some View {
        VStack(spacing: 20) {
            cameraPreviewPlaceholder

            statusSection

            readingsSection

            Spacer(minLength: 0)

            VStack(spacing: 12) {
                Button {
                    isDetecting.toggle()
                } label: {
                    Text(isDetecting ? "Stop Detection" : "Start Detection")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .tint(isDetecting ? .red : .blue)
                .controlSize(.large)

                NavigationLink {
                    DebugPanelView(
                        mode: mode,
                        snapshot: snapshot,
                        isDetecting: isDetecting
                    )
                } label: {
                    Text("Debug Panel")
                        .font(.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(20)
        .navigationTitle("Live Detection")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text("Live Detection")
                        .font(.headline)
                    Text(mode.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var cameraPreviewPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.85))

            VStack(spacing: 10) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 44))
                    .foregroundStyle(.white.opacity(0.85))

                Text("Camera Preview")
                    .font(.headline)
                    .foregroundStyle(.white)

                Text("LiDAR feed reserved for later")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 240)
        .accessibilityLabel("Camera preview placeholder")
    }

    private var statusSection: some View {
        VStack(spacing: 6) {
            Text(snapshot.hazard.statusLabel)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(statusColor)
                .multilineTextAlignment(.center)

            Text(isDetecting ? "Detection running (placeholder)" : "Detection idle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var readingsSection: some View {
        VStack(spacing: 0) {
            readingRow(title: "Movement", value: snapshot.movementState.displayName)
            Divider()
            readingRow(title: "Nearest surface", value: snapshot.nearestSurfaceLabel)
            Divider()
            readingRow(title: "Risk level", value: snapshot.riskLevel.displayName)
        }
        .padding(.horizontal, 4)
    }

    private func readingRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    private var statusColor: Color {
        switch snapshot.riskLevel {
        case .low:
            return .green
        case .medium:
            return .orange
        case .high:
            return .red
        }
    }
}

struct LiveDetectionView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            LiveDetectionView(mode: .standard)
        }
    }
}
