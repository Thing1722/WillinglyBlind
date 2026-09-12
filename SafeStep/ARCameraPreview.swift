import ARKit
import SceneKit
import SwiftUI

struct ARCameraPreview: UIViewRepresentable {
    let session: ARSession

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView(frame: .zero)
        view.session = session
        view.automaticallyUpdatesLighting = false
        view.rendersCameraGrain = false
        view.scene = SCNScene()
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {
        if uiView.session !== session {
            uiView.session = session
        }
    }
}

struct DepthHeatmapView: View {
    let preview: DepthPreview
    var maxRange: Float = 5.0

    var body: some View {
        Canvas { context, size in
            guard preview.width > 0, preview.height > 0 else { return }
            let cellWidth = size.width / CGFloat(preview.width)
            let cellHeight = size.height / CGFloat(preview.height)
            for y in 0..<preview.height {
                for x in 0..<preview.width {
                    let depth = preview.meters[y * preview.width + x]
                    let rect = CGRect(
                        x: CGFloat(x) * cellWidth,
                        y: CGFloat(y) * cellHeight,
                        width: cellWidth + 0.5,
                        height: cellHeight + 0.5
                    )
                    context.fill(Path(rect), with: .color(color(for: depth)))
                }
            }
        }
        .accessibilityLabel("Depth heatmap")
    }

    private func color(for depth: Float) -> Color {
        guard depth.isFinite, depth > 0.08, depth < 8 else {
            return Color.black.opacity(0.85)
        }
        let t = max(0, min(1, depth / maxRange))
        // Close = red/orange, far = blue.
        if t < 0.33 {
            let u = t / 0.33
            return Color(red: 1.0, green: Double(0.15 + 0.7 * u), blue: 0.05)
        } else if t < 0.66 {
            let u = (t - 0.33) / 0.33
            return Color(red: Double(1.0 - u), green: 0.85, blue: Double(0.1 + 0.5 * u))
        } else {
            let u = (t - 0.66) / 0.34
            return Color(red: 0.05, green: Double(0.55 - 0.25 * u), blue: Double(0.6 + 0.4 * u))
        }
    }
}
