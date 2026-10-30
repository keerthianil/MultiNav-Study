// SpeechTests.swift
// The VoiceOver side of speech, which the simulator cannot run: phrases are
// posted one at a time, each item waits for VoiceOver to finish the last,
// a phrase cut off never starts the next, and nothing is left waiting.

import Foundation
import Testing
import UIKit
@testable import MultiNavStudy2

/// The player's voice, through a real SpeechService in VoiceOver mode.
@MainActor
final class ServiceSpeaker: DescriptionSpeaker {
    let service: SpeechService
    init(_ service: SpeechService) { self.service = service }
    func speakTracked(_ text: String, queued: Bool, completion: @escaping (Bool) -> Void) {
        service.speak(text, queued: queued, completion: completion)
    }
    func speak(_ text: String, queued: Bool) { service.speak(text, queued: queued) }
    func boundary() {}
    func confirm() {}
}

@MainActor
@Suite(.serialized)
final class SpeechTests {
    private let service = SpeechService()
    private var posted: [String] = []

    init() {
        service.voiceOverRunning = { true }
        service.postAnnouncement = { [unowned self] in self.posted.append($0.string) }
    }

    /// VoiceOver reports that it finished (or was cut off reading) `text`.
    private func voiceOverFinished(_ text: String, _ success: Bool) async throws {
        NotificationCenter.default.post(name: UIAccessibility.announcementDidFinishNotification, object: nil,
                                        userInfo: [UIAccessibility.announcementStringValueUserInfoKey: text,
                                                   UIAccessibility.announcementWasSuccessfulUserInfoKey: NSNumber(value: success)])
        try await Task.sleep(nanoseconds: 30_000_000)
    }

    @Test func aFinishedPhraseReportsItsEnd() async throws {
        var result: Bool?
        service.speak("Item one.") { result = $0 }
        #expect(posted == ["Item one."])
        #expect(result == nil)
        try await voiceOverFinished("Item one.", true)
        #expect(result == true)
    }

    @Test func aNewPhraseCutsTheOldOneOff() async throws {
        var first: Bool?
        var second: Bool?
        service.speak("Pear Street") { first = $0 }
        service.speak("Apple Street") { second = $0 }
        #expect(first == false, "cut off at once, so nothing waits on it")
        try await voiceOverFinished("Pear Street", false)
        #expect(second == nil)
        try await voiceOverFinished("Apple Street", true)
        #expect(second == true)
    }

    @Test func theSameWordsAgainAreToldApart() async throws {
        var first: Bool?
        var second: Bool?
        service.speak("Median") { first = $0 }
        service.speak("Median") { second = $0 }
        #expect(first == false)
        try await voiceOverFinished("Median", false)   // the report for the one cut off
        #expect(second == nil)
        try await voiceOverFinished("Median", true)
        #expect(second == true)
    }

    @Test func aQueuedPhraseWaitsItsTurn() async throws {
        var name: Bool?
        var announcement: Bool?
        service.speak("Intersection map") { name = $0 }
        service.speak("You are at the intersection.", queued: true) { announcement = $0 }
        #expect(name == nil && announcement == nil)
        try await voiceOverFinished("Intersection map", true)
        #expect(name == true && announcement == nil)
        try await voiceOverFinished("You are at the intersection.", true)
        #expect(announcement == true)
    }

    @Test func switchingVoiceOverEndsWhatWasWaiting() async throws {
        var result: Bool?
        service.speak("Item two.") { result = $0 }
        NotificationCenter.default.post(name: UIAccessibility.voiceOverStatusDidChangeNotification, object: nil)
        try await Task.sleep(nanoseconds: 30_000_000)
        #expect(result == false)
    }

    @Test func aPhraseVoiceOverNeverReportsStopsWaiting() async throws {
        service.timeout = { _ in 0.05 }
        var result: Bool?
        service.speak("Item three.") { result = $0 }
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(result == false)
        try await voiceOverFinished("Item three.", true)   // too late: ignored
        #expect(result == false)
    }

    /// The six items through VoiceOver: each posted only after the last one
    /// finished, in order, and a stop leaves nothing to follow.
    @Test func itemsPlayOneAtATimeAndStopCleanly() async throws {
        let items = InfoCategory.allCases.map { InfoItem(category: $0, text: "About \($0.title).") }
        let player = DescriptionPlayer(announcement: "You are here.", items: items, speaker: ServiceSpeaker(service))
        player.toggleDetails(gesture: "Double tap")
        for (n, item) in items.enumerated() {
            #expect(posted.last == item.text)
            #expect(posted.count == n + 1, "the next item is posted only after this one finishes")
            try await voiceOverFinished(item.text, true)
        }
        #expect(player.playing == nil)

        posted.removeAll()
        player.toggleDetails(gesture: "Double tap")
        try await voiceOverFinished(items[0].text, true)
        #expect(posted == [items[0].text, items[1].text])
        player.toggleDetails(gesture: "Double tap")      // stop while item 2 plays
        #expect(posted.last == "Stopped.")
        try await voiceOverFinished(items[1].text, false)
        try await voiceOverFinished("Stopped.", true)
        #expect(player.playing == nil)
        #expect(posted == [items[0].text, items[1].text, "Stopped."], "nothing follows a stop")
    }
}
