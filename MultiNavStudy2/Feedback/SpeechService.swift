// SpeechService.swift
// Speaks map names the moment the finger reaches them, and the intersection
// descriptions one item at a time. A phrase plays to the end unless
// something new is said or the screen changes.
// With VoiceOver on, speech goes through VoiceOver as an announcement so it
// uses the listener's own voice and rate. Default priority, not high: a high
// priority announcement cannot be interrupted once started, so it kept
// talking after the listener moved on or went back. Without VoiceOver, the
// system speech synthesiser is used at the speed chosen on the first screen.
//
// A caller can ask to hear when its phrase ends: finished (true) or cut off
// (false). VoiceOver reports the end of each announcement by its text; an
// announcement that is cut off by a new one reports false a moment later,
// which is ignored when the new phrase has the same words.

import AVFoundation
import UIKit

// Used only on the main thread: the synthesiser's callbacks hop back to it.
final class SpeechService: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    typealias Completion = (Bool) -> Void

    private let synthesizer = AVSpeechSynthesizer()
    private let voice = AVSpeechSynthesisVoice(language: "en-US")

    /// Multiplier on the default rate of the system voice.
    var rateMultiplier: Float = 1.1

    /// VoiceOver announcements still being spoken or waiting, oldest first.
    private var announcements: [(text: String, completion: Completion?)] = []
    /// Announcements just cut off whose end report is still to come.
    private var cutOff: [(text: String, until: TimeInterval)] = []
    /// Every utterance until the synthesiser reports its end, held so its
    /// identifier cannot be reused by a newer one in the meantime.
    private var utterances: [ObjectIdentifier: (utterance: AVSpeechUtterance, completion: Completion?)] = [:]
    private var observer: NSObjectProtocol?

    override init() {
        super.init()
        synthesizer.delegate = self
        observer = NotificationCenter.default.addObserver(
            forName: UIAccessibility.announcementDidFinishNotification, object: nil, queue: .main
        ) { [weak self] note in
            let text = note.userInfo?[UIAccessibility.announcementStringValueUserInfoKey] as? String ?? ""
            let success = (note.userInfo?[UIAccessibility.announcementWasSuccessfulUserInfoKey] as? NSNumber)?.boolValue ?? false
            self?.announcementFinished(text, success: success)
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// Speaks `text`, cutting off whatever is being said. A queued phrase
    /// waits for the current speech instead, for example the announcement
    /// after VoiceOver has read the name of a new screen.
    func speak(_ text: String, queued: Bool = false, completion: Completion? = nil) {
        guard !text.isEmpty else {
            completion?(false)
            return
        }
        if UIAccessibility.isVoiceOverRunning {
            if !queued {
                let now = CACurrentMediaTime()
                cutOff.removeAll { $0.until < now }
                for pending in announcements {
                    cutOff.append((pending.text, now + 0.8))
                    pending.completion?(false)
                }
                announcements.removeAll()
            }
            announcements.append((text, completion))
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
            utterances[ObjectIdentifier(utterance)] = (utterance, completion)
            synthesizer.speak(utterance)
        }
    }

    /// Cuts off the system voice. A VoiceOver announcement is cut off by
    /// VoiceOver itself when it reads the screen the listener moves to; until
    /// then nothing waits on it.
    func stop() {
        for pending in announcements {
            pending.completion?(false)
        }
        if !announcements.isEmpty {
            let now = CACurrentMediaTime()
            cutOff += announcements.map { ($0.text, now + 0.8) }
            announcements.removeAll()
        }
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    private func announcementFinished(_ text: String, success: Bool) {
        let now = CACurrentMediaTime()
        cutOff.removeAll { $0.until < now }
        if let index = cutOff.firstIndex(where: { $0.text == text }) {
            cutOff.remove(at: index)
            return
        }
        guard let index = announcements.firstIndex(where: { $0.text == text }) else { return }
        // Anything queued before it has been dropped by VoiceOver.
        for earlier in announcements[..<index] {
            earlier.completion?(false)
        }
        let done = announcements[index]
        announcements.removeSubrange(...index)
        done.completion?(success)
    }

    // MARK: AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in self?.utteranceEnded(utterance, finished: true) }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in self?.utteranceEnded(utterance, finished: false) }
    }

    private func utteranceEnded(_ utterance: AVSpeechUtterance, finished: Bool) {
        let key = ObjectIdentifier(utterance)
        guard let entry = utterances[key], entry.utterance === utterance else { return }
        utterances.removeValue(forKey: key)
        entry.completion?(finished)
    }
}
