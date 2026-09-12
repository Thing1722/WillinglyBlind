import SwiftUI

extension RiskLevel {
    var color: Color {
        switch self {
        case .low: return .stepMint
        case .medium: return Color(red: 1, green: 0.79, blue: 0.32)
        case .high: return Color(red: 1, green: 0.38, blue: 0.36)
        }
    }
    var icon: String { self == .low ? "checkmark.shield" : self == .medium ? "exclamationmark.triangle" : "hand.raised.fill" }
}

struct LiveDetectionView: View {
    @StateObject private var model: WalkSession
    @Environment(\.scenePhase) private var scenePhase
    @State private var showDebug = false

    init(mode: WalkingMode, isDemo: Bool = false) {
        _model = StateObject(wrappedValue: WalkSession(mode: mode, isDemo: isDemo))
    }
    private var tint: Color { model.result?.assessment.level.color ?? .gray }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack {
                    Label(model.isDemo ? "DEMO SESSION" : "LIVE DETECTION", systemImage: model.isDemo ? "play.circle" : "dot.radiowaves.left.and.right")
                        .font(.caption.weight(.bold)).tracking(1.5).foregroundStyle(Color.stepMint)
                    Spacer()
                    Text(model.mode == .sensitive ? "SENSITIVE" : "STANDARD")
                        .font(.system(size: 10, weight: .bold)).padding(8)
                        .background(Color.stepCard, in: Capsule())
                }
                camera
                statusCard
                if model.isDemo { demoControls }
                HStack(spacing: 12) {
                    metric("NEAREST SURFACE", value: model.result?.assessment.distanceText ?? "—", icon: "arrow.left.and.right")
                    metric("MOVEMENT", value: model.result?.assessment.movement.rawValue ?? "—", icon: "figure.walk")
                }
                HStack {
                    Toggle(isOn: $model.voiceEnabled) { Label("Voice", systemImage: "speaker.wave.2") }
                    Toggle(isOn: $model.hapticsEnabled) { Label("Touch", systemImage: "iphone.radiowaves.left.and.right") }
                }
                .font(.caption).tint(.stepMint)
                Text(model.status).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                Button { showDebug = true } label: {
                    HStack {
                        Label("Behind the alert", systemImage: "slider.horizontal.3")
                        Spacer()
                        Text(model.result.map { "\($0.assessment.total)/10" } ?? "—")
                        Image(systemName: "chevron.right")
                    }.font(.subheadline).padding(18).background(Color.stepCard, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
            }
            .padding(20)
        }
        .background(Color.stepBackground)
        .safeAreaInset(edge: .bottom) {
            Button {
                if model.isRunning { model.stop() } else { model.start() }
            } label: {
                Label(model.isRunning ? "Pause walk" : "Resume walk", systemImage: model.isRunning ? "pause.fill" : "play.fill")
                    .font(.headline).frame(maxWidth: .infinity).padding(18)
                    .foregroundStyle(Color.stepBackground).background(Color.stepMint, in: RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal, 20).padding(.vertical, 12).background(Color.stepBackground)
        }
        .navigationTitle("Safe walk")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showDebug) { DebugPanel(model: model) }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
        .onChange(of: scenePhase) { phase in if phase != .active { model.stop() } }
    }

    private var camera: some View {
        GeometryReader { geometry in
            ZStack {
                if model.isDemo {
                    LinearGradient(colors: [.stepCard, .stepBackground], startPoint: .top, endPoint: .bottom)
                    VStack(spacing: 12) {
                        Image(systemName: model.scenario == .dropOff ? "stairs" : model.scenario == .clear ? "figure.walk" : "shippingbox")
                            .font(.system(size: 54, weight: .ultraLight))
                        Text("SIMULATED CAMERA").font(.caption2.weight(.bold)).tracking(2)
                    }
                    .foregroundStyle(tint).offset(y: -45)
                } else { CameraPreview(model: model) }
                // Matches the detector: center third, lower half of the preview.
                Rectangle().fill(tint.opacity(0.08))
                    .overlay(Rectangle().stroke(tint.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, dash: [8, 6])))
                    .frame(width: geometry.size.width / 3, height: geometry.size.height / 2)
                    .position(x: geometry.size.width / 2, y: geometry.size.height * 0.75)
                VStack {
                    HStack {
                        Label(model.isRunning ? "SCANNING" : "PAUSED", systemImage: model.isRunning ? "record.circle" : "pause.circle")
                        Spacer()
                        Image(systemName: "viewfinder")
                    }
                    .font(.caption2.weight(.bold)).padding(12).background(.black.opacity(0.35))
                    Spacer()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .onAppear { model.viewport = geometry.size }
            .onChange(of: geometry.size) { model.viewport = $0 }
        }
        .frame(height: 300)
        .accessibilityLabel(model.isDemo ? "Simulated camera preview" : "Rear camera preview with central walking region")
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let assessment = model.result?.assessment {
                HStack {
                    Label("\(assessment.level.rawValue.uppercased()) RISK", systemImage: assessment.level.icon)
                        .font(.caption.weight(.bold)).tracking(1)
                    Spacer()
                    Text("\(assessment.total)/10").font(.caption.monospacedDigit())
                }
                Text(assessment.hazard.rawValue).font(.title2.weight(.bold))
                Text(assessment.hazard.advice).font(.subheadline)
                if assessment.hazard == .tooClose { Text("Immediate proximity override").font(.caption2) }
            } else {
                Label(model.isRunning ? "WAITING FOR DEPTH" : "DETECTION PAUSED", systemImage: "viewfinder")
                    .font(.headline)
                Text(model.isRunning ? "No reliable reading yet. Look ahead." : "Resume when you’re ready to scan.")
                    .font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(20)
        .foregroundStyle(tint).background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(tint.opacity(0.25)))
        .accessibilityElement(children: .combine)
    }

    private var demoControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TRY A SCENARIO").font(.caption2.weight(.bold)).tracking(1.5)
            Picker("Simulated hazard", selection: $model.scenario) {
                ForEach(DemoScenario.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            Picker("Simulated movement", selection: $model.demoMovement) {
                ForEach(Movement.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.menu)
            Text("Synthetic depth · real detection rules and alerts")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .disabled(!model.isRunning)
    }

    private func metric(_ title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon).font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
            Text(value).font(.headline.monospacedDigit()).minimumScaleFactor(0.7).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
            .background(Color.stepCard, in: RoundedRectangle(cornerRadius: 16))
    }
}
