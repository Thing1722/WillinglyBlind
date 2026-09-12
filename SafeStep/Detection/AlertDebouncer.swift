import Foundation

/// Holds a warning until it is seen for `warningAppearFrameCount` frames,
/// and keeps it until `warningClearFrameCount` consecutive clear frames.
struct AlertDebouncer {
    private var displayed: Hazard = .clear
    private var candidate: Hazard = .clear
    private var candidateStreak = 0
    private var clearStreak = 0

    mutating func reset() {
        displayed = .clear
        candidate = .clear
        candidateStreak = 0
        clearStreak = 0
    }

    mutating func apply(_ snapshot: DetectionSnapshot, config: DetectionConfig) -> DetectionSnapshot {
        snapshot.replacingPrimary(process(snapshot.primary, config: config))
    }

    private mutating func process(_ incoming: Hazard, config: DetectionConfig) -> Hazard {
        if incoming.kind == .noSignal {
            displayed = incoming
            candidate = incoming
            candidateStreak = 0
            clearStreak = 0
            return displayed
        }

        if incoming.kind == .clear {
            clearStreak += 1
            candidateStreak = 0
            candidate = .clear
            if clearStreak >= config.warningClearFrameCount {
                displayed = .clear
            }
            return displayed
        }

        clearStreak = 0
        if incoming.kind == candidate.kind {
            candidateStreak += 1
            candidate = incoming
        } else {
            candidate = incoming
            candidateStreak = 1
        }

        if incoming.kind == displayed.kind {
            displayed = incoming
            return displayed
        }

        if candidateStreak >= config.warningAppearFrameCount {
            displayed = incoming
        }
        return displayed
    }
}
