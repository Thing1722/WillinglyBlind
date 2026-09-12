import SwiftUI

enum WalkingMode: String, CaseIterable, Identifiable {
    case standard = "Standard Mode"
    case sensitive = "Sensitive Mode"

    var id: Self { self }
}

struct StartView: View {
    @State private var selectedMode: WalkingMode = .standard

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                VStack(spacing: 8) {
                    Text("SafeStep")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("See less. Walk safer.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 12) {
                    ForEach(WalkingMode.allCases) { mode in
                        modeButton(for: mode)
                    }
                }
                .padding(.top, 24)

                Spacer()

                NavigationLink {
                    LiveDetectionView(mode: selectedMode)
                } label: {
                    Text("START SAFE WALK")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(24)
        }
    }

    private func modeButton(for mode: WalkingMode) -> some View {
        Button {
            selectedMode = mode
        } label: {
            HStack {
                Text(mode.rawValue)
                    .fontWeight(.semibold)

                Spacer()

                Image(systemName: selectedMode == mode ? "checkmark.circle.fill" : "circle")
            }
            .frame(maxWidth: .infinity)
            .padding()
            .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
        .tint(selectedMode == mode ? .blue : .secondary)
        .accessibilityAddTraits(selectedMode == mode ? .isSelected : [])
    }
}

struct StartView_Previews: PreviewProvider {
    static var previews: some View {
        StartView()
    }
}
