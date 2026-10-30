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
// which is ignored when the new phrase has the same words. Two safeguards
// keep a description from hanging, which would leave the map silent: if
// VoiceOver is switched on or off, whatever was waiting counts as cut off,
// and a phrase VoiceOver never reports on counts as cut off after a time
// well beyond its slowest reading.

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
    private var announcements: [(id: Int, text: String, completion: Completion?)] = []
    private var nextID = 0
    /// Announcements just cut off whose end report is still to come.
    private var cutOff: [(text: String, until: TimeInterval)] = []
    /// Every utterance until the synthesiser reports its end, held so its
    /// identifier cannot be reused by a newer one in the meantime.
    private var utterances: [ObjectIdentifier: (utterance: AVSpeechUtterance, completion: Completion?)] = [:]
    private var observers: [NSObjectProtocol] = []

    /// Whether VoiceOver is speaking for the app, and how an announcement
    /// reaches it. The tests replace both.
    var voiceOverRunning: () -> Bool = { UIAccessibility.isVoiceOverRunning }
    var postAnnouncement: (NSAttributedString) -> Void = {
        UIAccessibility.post(notification: .announcement, argument: $0)
    }

    override init() {
        super.init()
        synthesizer.delegate = self
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: UIAccessibility.announcementDidFinishNotification, object: nil, queue: .main
        ) { [weak self] note in
            let text = note.userInfo?[UIAccessibility.announcementStringValueUserInfoKey] as? String ?? ""
            let success = (note.userInfo?[UIAccessibility.announcementWasSuccessfulUserInfoKey] as? NSNumber)?.boolValue ?? false
            self?.announcementFinished(text, success: success)
        })
        observers.append(center.addObserver(
            forName: UIAccessibility.voiceOverStatusDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.stop()
        })
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    /// Longest a phrase is waited on: far past the slowest VoiceOver reading.
    var timeout: (String) -> TimeInterval = { text in
        6 + Double(text.split(separator: " ").count) * 1.2
    }

    /// Speaks `text`, cutting off whatever is being said. A queued phrase
    /// waits for the current speech instead, for example the announcement
    /// after VoiceOver has read the name of a new screen.
    func speak(_ text: String, queued: Bool = false, completion: Completion? = nil) {
        guard !text.isEmpty else {
            completion?(false)
            return
        }
        if voiceOverRunning() {
            if !queued {
                let now = CACurrentMediaTime()
                cutOff.removeAll { $0.until < now }
                let pending = announcements
                announcements.removeAll()
                for entry in pending {
                    cutOff.append((entry.text, now + 0.8))
                    entry.completion?(false)
                }
            }
            nextID += 1
            let id = nextID
            announcements.append((id, text, completion))
            if completion != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + timeout(text)) { [weak self] in
                    self?.giveUp(on: id)
                }
            }
            postAnnouncement(NSAttributedString(string: text, attributes: [
                .accessibilitySpeechQueueAnnouncement: NSNumber(value: queued),
                .accessibilitySpeechAnnouncementPriority: UIAccessibilityPriority.default.rawValue,
            ]))
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
        let pending = announcements
        announcements.removeAll()
        let now = CACurrentMediaTime()
        cutOff += pending.map { ($0.text, now + 0.8) }
        pending.forEach { $0.completion?(false) }
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    /// VoiceOver never said this phrase ended: count it as cut off, so
    /// whatever waits on it stops waiting.
    private func giveUp(on id: Int) {
        guard let index = announcements.firstIndex(where: { $0.id == id }) else { return }
        let entry = announcements.remove(at: index)
        cutOff.append((entry.text, CACurrentMediaTime() + 2))
        entry.completion?(false)
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
        let earlier = announcements[..<index]
        let done = announcements[index]
        announcements.removeSubrange(...index)
        earlier.forEach { $0.completion?(false) }
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
