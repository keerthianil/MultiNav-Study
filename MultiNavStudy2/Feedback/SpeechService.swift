// SpeechService.swift
// Speaks map names the moment the finger reaches them. A phrase plays to the
// end unless something new is said or the screen changes.
// With VoiceOver on, speech goes through VoiceOver as an announcement so it
// uses the listener's own voice and rate. Default priority, not high: a high
// priority announcement cannot be interrupted once started, so it kept
// talking after the listener moved on or went back. Without VoiceOver, the
// system speech synthesiser is used at the speed chosen on the setup screen.

import AVFoundation
import UIKit

final class SpeechService {
    private let synthesizer = AVSpeechSynthesizer()
    private let voice = AVSpeechSynthesisVoice(language: "en-US")

    /// Multiplier on the default rate of the system voice.
    var rateMultiplier: Float = 1.1

    /// Speaks `text`, cutting off whatever is being said. A queued phrase
    /// waits for the current speech instead, for example a route overview
    /// after VoiceOver has read the name of a new screen.
    func speak(_ text: String, queued: Bool = false) {
        guard !text.isEmpty else { return }
        if UIAccessibility.isVoiceOverRunning {
            let announcement = NSAttributedString(string: text, attributes: [
                .accessibilitySpeechQueueAnnouncement: NSNumber(value: queued),
                .accessibilitySpeechAnnouncementPriority: UIAccessibilityPriority.default.rawValue,
            ])
            UIAccessibility.post(notification: .announcement, argument: announcement)
        } else {
            if !queued, synthesizer.isSpeaking {
                synthesizer.stopSpeaking(at: .immediate)
            }
            let utterance = AVSpeechUtterance(string: text)
            utterance.rate = min(AVSpeechUtteranceMaximumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * rateMultiplier)
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
