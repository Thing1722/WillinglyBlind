import SwiftUI

extension Color {
    static let stepBackground = Color(red: 0.035, green: 0.075, blue: 0.08)
    static let stepCard = Color(red: 0.08, green: 0.13, blue: 0.14)
    static let stepMint = Color(red: 0.65, green: 0.95, blue: 0.77)
}

struct StartView: View {
    @State private var selectedMode: WalkingMode = .standard

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HStack {
                        Label("SAFESTEP", systemImage: "figure.walk.circle.fill")
                            .font(.subheadline.weight(.bold)).tracking(2)
                        Spacer()
                        Text("WALK WITH AWARENESS").font(.system(size: 9, weight: .bold)).tracking(1)
                            .foregroundStyle(Color.stepMint)
                    }
                    .padding(.top, 20)

                    ZStack {
                        ForEach(0..<3) { ring in
                            Circle().stroke(Color.stepMint.opacity(0.1 + Double(ring) * 0.08), lineWidth: 1)
                                .frame(width: CGFloat(120 + ring * 60), height: CGFloat(120 + ring * 60))
                        }
                        Image(systemName: "figure.walk")
                            .font(.system(size: 72, weight: .light)).foregroundStyle(Color.stepMint)
                        Label("A LITTLE MORE AWARE", systemImage: "wave.3.right")
                            .font(.system(size: 9, weight: .bold)).tracking(2)
                            .padding(10).background(Color.stepCard, in: Capsule()).offset(y: 108)
                    }
                    .frame(maxWidth: .infinity).frame(height: 260)
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("See less.\nWalk safer.")
                            .font(.system(size: 48, weight: .semibold, design: .rounded)).tracking(-2)
                        Text("A heads-up for what’s ahead.").font(.title3).foregroundStyle(Color.stepMint)
                        Text("Nearby obstacles. Sudden drops. A little room to react.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("CHOOSE YOUR WALK").font(.caption.weight(.bold)).tracking(2).foregroundStyle(.secondary)
                        ForEach(WalkingMode.allCases) { mode in
                            Button { selectedMode = mode } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: mode == .standard ? "figure.walk" : "waveform.path")
                                        .font(.title2).frame(width: 30).foregroundStyle(Color.stepMint)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(mode.rawValue).font(.headline)
                                        Text(mode == .standard ? "Balanced alerts for everyday walks" : "Earlier warnings, stronger touch + voice")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: selectedMode == mode ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selectedMode == mode ? Color.stepMint : Color.gray)
                                }
                                .padding(18).background(Color.stepCard, in: RoundedRectangle(cornerRadius: 18))
                                .overlay(RoundedRectangle(cornerRadius: 18).stroke(selectedMode == mode ? Color.stepMint : Color.white.opacity(0.08)))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selectedMode == mode ? .isSelected : [])
                        }
                    }

                    VStack(spacing: 14) {
                        NavigationLink { LiveDetectionView(mode: selectedMode) } label: {
                            HStack { Text("Start safe walk"); Spacer(); Image(systemName: "arrow.up.right") }
                                .font(.headline).padding(20).foregroundStyle(Color.stepBackground)
                                .background(Color.stepMint, in: RoundedRectangle(cornerRadius: 18))
                        }
                        .disabled(!WalkSession.supportsLiDAR)
                        .opacity(WalkSession.supportsLiDAR ? 1 : 0.45)
                        NavigationLink { LiveDetectionView(mode: selectedMode, isDemo: true) } label: {
                            Label("Explore the interactive demo", systemImage: "play.circle")
                                .font(.subheadline.weight(.medium)).foregroundStyle(Color.stepMint)
                        }
                        Text(WalkSession.supportsLiDAR ? "LiDAR ready · depth processed on your device" : "Live scanning requires a LiDAR-equipped iPhone or iPad.")
                            .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    Text("Prototype assistance only. Keep looking ahead; the camera can miss hazards. Hold the rear camera toward your path and slightly downward.")
                        .font(.caption).foregroundStyle(.secondary).lineSpacing(3)
                }
                .padding(24)
            }
            .background(Color.stepBackground)
            .preferredColorScheme(.dark)
        }
        .tint(.stepMint)
    }
}

#Preview { StartView() }
