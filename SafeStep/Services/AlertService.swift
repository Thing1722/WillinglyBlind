import AVFoundation
import CoreHaptics
import UIKit

final class AlertService {
    private let speech = AVSpeechSynthesizer()
    private var engine: CHHapticEngine?
    private var player: CHHapticPatternPlayer?
    private var lastHaptic = Date.distantPast
    private var lastSpeech = Date.distantPast
    private var lastSpokenHazard: Hazard?
    var voiceEnabled = true
    var hapticsEnabled = true

    func update(_ assessment: RiskAssessment) {
        guard assessment.level != .low else { stop(); return }
        let high = assessment.level == .high
        let interval: TimeInterval = high ? max(0.3, min(1, Double(assessment.distance) * 0.4)) : 2
        if hapticsEnabled, Date().timeIntervalSince(lastHaptic) >= interval {
            lastHaptic = Date()
            playHaptic(high: high, sensitive: assessment.mode == .sensitive)
        }
        let shouldSpeak = high || assessment.mode == .sensitive
        if voiceEnabled, shouldSpeak,
           (lastSpokenHazard != assessment.hazard || Date().timeIntervalSince(lastSpeech) > 6) {
            speech.stopSpeaking(at: .immediate)
            let text = assessment.hazard == .tooClose
                ? "Immediate danger. Stop walking."
                : "Caution. \(assessment.hazard.rawValue), \(assessment.distanceText) ahead. \(assessment.hazard.advice)"
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
            utterance.rate = 0.48
            speech.speak(utterance)
            lastSpeech = Date()
            lastSpokenHazard = assessment.hazard
        }
    }

    private func playHaptic(high: Bool, sensitive: Bool) {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            if engine == nil {
                engine = try CHHapticEngine()
                engine?.isAutoShutdownEnabled = true
            }
            try engine?.start()
            let intensity: Float = high || sensitive ? 1 : 0.65
            let events = (0..<(high ? 3 : 2)).map { index in
                CHHapticEvent(eventType: .hapticTransient, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: high ? 0.9 : 0.5)
                ], relativeTime: Double(index) * (high ? 0.09 : 0.16))
            }
            let pattern = try CHHapticPattern(events: events, parameters: [])
            player = try engine?.makePlayer(with: pattern)
            try player?.start(atTime: CHHapticTimeImmediate)
        } catch {
            engine = nil
            UINotificationFeedbackGenerator().notificationOccurred(high ? .error : .warning)
        }
    }

    func stop() {
        speech.stopSpeaking(at: .immediate)
        try? player?.stop(atTime: CHHapticTimeImmediate)
        lastSpokenHazard = nil
        lastSpeech = .distantPast
        lastHaptic = .distantPast
    }
}
