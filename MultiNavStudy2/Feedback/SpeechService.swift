// SpeechService.swift
// Speaks map names the moment the finger reaches them. A phrase plays to the
// end unless something new is said or the screen changes.
// With VoiceOver on, speech goes through VoiceOver as an announcement so it
// uses the listener's own voice and rate. Default priority, not high: a high
// priority announcement cannot be interrupted once started, so it kept
// talking after the listener moved on or went back. Without VoiceOver, the
// system speech synthesiser is used.

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
                .accessibilitySpeechAnnouncementPriority: UIAccessibilityPriority.default.rawValue,
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

    /// Cuts off the system voice. A VoiceOver announcement is cut off by
    /// VoiceOver itself when it reads the screen the listener moves to.
    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }
}
