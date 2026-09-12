import SwiftUI

struct DebugPanelView: View {
    let mode: WalkingMode
    let snapshot: DetectionSnapshot
    let isDetecting: Bool

    var body: some View {
        List {
            Section("Session") {
                LabeledContent("Walking mode", value: mode.rawValue)
                LabeledContent("Detecting", value: isDetecting ? "Yes" : "No")
            }

            Section("Placeholder Readings") {
                LabeledContent("Hazard", value: snapshot.hazard.rawValue)
                LabeledContent("Status", value: snapshot.hazard.statusLabel)
                LabeledContent("Risk", value: snapshot.riskLevel.displayName)
                LabeledContent("Movement", value: snapshot.movementState.displayName)
                LabeledContent("Nearest surface", value: snapshot.nearestSurfaceLabel)
            }

            Section {
                Text("Sensor feeds are not connected yet. Values on this screen are placeholders for layout and navigation.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Debug Panel")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct DebugPanelView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            DebugPanelView(
                mode: .standard,
                snapshot: .placeholder,
                isDetecting: false
            )
        }
    }
}
