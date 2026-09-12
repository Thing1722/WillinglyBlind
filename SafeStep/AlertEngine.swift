import AVFoundation
import UIKit

/// Voice + haptic warnings. Speech is rate-limited so a 10 Hz depth stream
/// does not talk over itself; haptics fire more often on STOP.
final class AlertEngine {
    private let synthesizer = AVSpeechSynthesizer()
    private var lastSpokenAt: Date = .distantPast
    private var lastSpokenPhrase = ""
    private var lastHapticAt: Date = .distantPast
    private var audioReady = false

    func prepare() {
        guard !audioReady else { return }
        do {
            // Play through the speaker even if the Ring/Silent switch is off.
            try AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            audioReady = true
        } catch {
            audioReady = false
        }
    }

    func handle(_ snapshot: DetectionSnapshot) {
        prepare()
        haptic(snapshot.primary)
        speak(snapshot.primary)
    }

    func reset() {
        synthesizer.stopSpeaking(at: .immediate)
        lastSpokenPhrase = ""
        lastSpokenAt = .distantPast
    }

    private func haptic(_ hazard: Hazard) {
        let now = Date()
        let spacing: TimeInterval = hazard.kind == .stop || hazard.kind == .dropOff ? 0.28 : 0.70
        guard now.timeIntervalSince(lastHapticAt) >= spacing else { return }
        lastHapticAt = now

        switch hazard.kind {
        case .stop, .dropOff:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        case .obstacleAhead, .overhead:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .caution, .obstacleLeft, .obstacleRight:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .noSignal:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .clear:
            break
        }
    }

    private func speak(_ hazard: Hazard) {
        let phrase = hazard.spokenPhrase
        guard !phrase.isEmpty else { return }

        let now = Date()
        let repeated = phrase == lastSpokenPhrase
        let minGap: TimeInterval = repeated ? 2.4 : 0.8
        guard now.timeIntervalSince(lastSpokenAt) >= minGap else { return }

        lastSpokenAt = now
        lastSpokenPhrase = phrase

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .word)
        }

        let utterance = AVSpeechUtterance(string: phrase)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.92
        utterance.pitchMultiplier = hazard.kind == .stop ? 0.9 : 1.0
        synthesizer.speak(utterance)
    }
}
