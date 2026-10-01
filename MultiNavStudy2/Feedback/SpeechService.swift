// SpeechService.swift
// Speaks map names the moment the finger reaches them, cutting off the last.
// With VoiceOver on, speech goes through VoiceOver as an interrupting
// announcement so it uses the listener's own voice and rate. Without it,
// the system speech synthesiser is used.

import AVFoundation
import UIKit

final class SpeechService {
    private let synthesizer = AVSpeechSynthesizer()
    private let voice = AVSpeechSynthesisVoice(language: "en-US")

    func speak(_ text: String) {
        guard !text.isEmpty else { return }
        if UIAccessibility.isVoiceOverRunning {
            let announcement = NSAttributedString(string: text, attributes: [
                .accessibilitySpeechQueueAnnouncement: NSNumber(value: false),
                .accessibilitySpeechAnnouncementPriority: UIAccessibilityPriority.high.rawValue,
            ])
            UIAccessibility.post(notification: .announcement, argument: announcement)
        } else {
            if synthesizer.isSpeaking {
                synthesizer.stopSpeaking(at: .immediate)
            }
            let utterance = AVSpeechUtterance(string: text)
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.1
            utterance.volume = 1.0
            utterance.voice = voice
            synthesizer.speak(utterance)
        }
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }
}
