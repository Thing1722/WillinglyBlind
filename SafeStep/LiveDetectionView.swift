import SwiftUI

struct LiveDetectionView: View {
    let mode: WalkingMode

    var body: some View {
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

            Text("Detection will appear here.")
                .foregroundStyle(.secondary)
        }
        .padding()
        .navigationTitle("Safe Walk")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct LiveDetectionView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            LiveDetectionView(mode: .standard)
        }
    }
}
