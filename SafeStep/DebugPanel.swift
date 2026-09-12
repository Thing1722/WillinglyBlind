import SwiftUI

struct DebugPanel: View {
    @ObservedObject var model: WalkSession
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("R = H + D + C + U").font(.title2.monospaced().bold())
                    Text(model.isDemo ? "Demo data passes through the same detector as LiDAR data." : "Scores derived from the current LiDAR reading.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if let result = model.result {
                    let risk = result.assessment
                    Section("Risk breakdown") {
                        row("H · Hazard severity", "\(risk.severityScore) / 4")
                        row("D · Distance risk", "\(risk.distanceScore) / 3")
                        row("C · Movement risk", "\(risk.movementScore) / 2")
                        row("U · User sensitivity", "\(risk.sensitivityScore) / 1")
                        row("Total", "\(risk.total) / 10 · \(risk.level.rawValue)")
                            .foregroundStyle(risk.level.color).bold()
                        if risk.hazard == .tooClose {
                            Text("Too close (< 0.8 m) overrides the score to High risk.").font(.caption)
                        }
                        if risk.hazard == .clear {
                            Text("No detected hazard: risk terms are zero.").font(.caption)
                        }
                    }
                    Section("Depth evidence") {
                        row("Reliable sample coverage", String(format: "%.0f%%", result.coverage * 100))
                        row("Nearby sample fraction", String(format: "%.0f%%", result.nearbyFraction * 100))
                        ForEach(0..<3) { index in
                            row(["Far band median", "Middle band median", "Near-ground median"][index], result.bandDepths[index].map { String(format: "%.2f m", $0) } ?? "Unavailable")
                        }
                    }
                } else {
                    Section { Text(model.status) }
                }
                Section("How to read the result") {
                    Text("0–3 Low · 4–6 Medium · 7–10 High")
                    Text("Obstacle: at least 20% of valid path samples within 1.5 m (2 m in Sensitive Mode). Too close: at least 10% within 0.8 m.")
                    Text("A band depth jump above 1.2 m (0.9 m in Sensitive Mode) suggests a possible drop-off. This heuristic does not classify stairs or measure their height.")
                    Text("Movement uses smoothed horizontal AR camera speed: below 0.15 m/s is stationary; 1.6 m/s or above is moving quickly. It estimates phone movement, not obstacle closing speed.")
                    Text("Missing or low-confidence depth is excluded. Coverage below 55%, limited tracking, or stale data clears the reading and displays an unavailable state.")
                }.font(.footnote)
            }
            .navigationTitle("Behind the alert").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .preferredColorScheme(.dark).tint(.stepMint)
    }
    private func row(_ title: String, _ value: String) -> some View {
        HStack { Text(title); Spacer(); Text(value).monospacedDigit().foregroundStyle(.secondary) }
    }
}
