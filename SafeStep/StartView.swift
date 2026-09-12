import SwiftUI

struct StartView: View {
    @State private var selectedMode: WalkingMode = .standard

    private var lidarAvailable: Bool {
        LiDARSession.deviceSupportsLiDAR
    }

    private var hasRearCamera: Bool {
        CameraCapture.hasRearCamera
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 10) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 44))
                        .foregroundStyle(.blue)
                        .accessibilityHidden(true)

                    Text("SafeStep")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("See less. Walk safer.")
                        .font(.title3)
                        .foregroundStyle(.secondary)

                    Text(statusLine)
                        .font(.footnote)
                        .foregroundStyle(lidarAvailable ? .green : .orange)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }

                VStack(spacing: 12) {
                    ForEach(WalkingMode.allCases) { mode in
                        modeButton(for: mode)
                    }
                }
                .padding(.top, 32)

                VStack(alignment: .leading, spacing: 8) {
                    labeledRow("1", "Point the rear camera forward")
                    labeledRow("2", lidarAvailable
                               ? "LiDAR depth is scanned ~8 times a second"
                               : "No LiDAR here — demo scenes still warn you")
                    labeledRow("3", "Haptics + voice warn before you hit something")
                }
                .padding(.top, 28)
                .padding(.horizontal, 4)

                Spacer()

                VStack(spacing: 12) {
                    NavigationLink {
                        LiveDetectionView(mode: selectedMode, forceDemo: false)
                    } label: {
                        Text(primaryButtonTitle)
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    NavigationLink {
                        LiveDetectionView(mode: selectedMode, forceDemo: true)
                    } label: {
                        Text("TRY SYNTHETIC SCENES")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(24)
        }
    }

    private var statusLine: String {
        if lidarAvailable {
            return "LiDAR ready on this iPhone"
        }
        if hasRearCamera {
            return "No LiDAR on this device. ARKit is already part of iOS — you do not install it. Start a walk to use the rear camera plus demo alerts."
        }
        return "No LiDAR or camera on this Simulator. Use TRY SYNTHETIC SCENES, or the Python pipeline on a laptop."
    }

    private var primaryButtonTitle: String {
        if lidarAvailable { return "START SAFE WALK" }
        if hasRearCamera { return "START CAMERA WALK" }
        return "START DEMO WALK"
    }

    private func labeledRow(_ step: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(step)
                .font(.caption.weight(.bold))
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.blue.opacity(0.15)))
                .foregroundStyle(.blue)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func modeButton(for mode: WalkingMode) -> some View {
        Button {
            selectedMode = mode
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(mode.rawValue)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    Text(mode.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: selectedMode == mode ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .tint(selectedMode == mode ? .blue : .secondary)
        .accessibilityAddTraits(selectedMode == mode ? .isSelected : [])
        .accessibilityHint(mode.subtitle)
    }
}

struct StartView_Previews: PreviewProvider {
    static var previews: some View {
        StartView()
    }
}
