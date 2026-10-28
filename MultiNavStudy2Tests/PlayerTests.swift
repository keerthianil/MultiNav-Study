// PlayerTests.swift
// The description player, step by step, with a stand-in voice that finishes
// each phrase only when the test says so.

import Foundation
import Testing
@testable import MultiNavStudy2

/// Records what the player says; `finish` ends the phrase being spoken.
@MainActor
final class FakeSpeaker: DescriptionSpeaker {
    var spoken: [String] = []
    var said: [String] = []
    var boundaries = 0
    private var pending: [(text: String, completion: (Bool) -> Void)] = []

    func speakTracked(_ text: String, queued: Bool, completion: @escaping (Bool) -> Void) {
        if !queued { cutOff() }
        spoken.append(text)
        pending.append((text, completion))
    }

    func speak(_ text: String, queued: Bool) {
        cutOff()
        said.append(text)
    }

    func boundary() { boundaries += 1 }
    func confirm() {}

    /// The phrase being spoken plays to its end.
    func finish() {
        guard !pending.isEmpty else { return }
        pending.removeFirst().completion(true)
    }

    var current: String? { pending.first?.text }

    private func cutOff() {
        let cut = pending
        pending.removeAll()
        cut.forEach { $0.completion(false) }
    }
}

@MainActor
struct PlayerTests {
    private let items = InfoCategory.allCases.map { InfoItem(category: $0, text: "Item about \($0.title).") }

    private func player() -> (DescriptionPlayer, FakeSpeaker) {
        let speaker = FakeSpeaker()
        return (DescriptionPlayer(announcement: "You are at the intersection.", items: items, speaker: speaker), speaker)
    }

    @Test func announcementPlaysAndStopsWithItsGesture() {
        let (p, voice) = player()
        var plays: [Bool] = []
        p.onAnnouncement = { plays.append($0) }
        p.playAnnouncement(gesture: "Map opened", repeated: false)
        #expect(p.playing == .announcement)
        p.toggleAnnouncement(gesture: "Two-finger double tap")
        #expect(p.playing == nil)
        #expect(voice.said == ["Stopped."])
        p.toggleAnnouncement(gesture: "Two-finger double tap")
        #expect(p.playing == .announcement)
        voice.finish()
        #expect(p.playing == nil)
        #expect(plays == [false, true])
        #expect(voice.spoken == Array(repeating: "You are at the intersection.", count: 2))
    }

    @Test func detailsPlayInOrderToTheEnd() {
        let (p, voice) = player()
        var started = 0
        var heard: [InfoCategory] = []
        p.onDetailsStarted = { started += 1 }
        p.onItem = { heard.append($0.category) }
        p.toggleDetails(gesture: "Double tap")
        for _ in items { voice.finish() }
        #expect(p.playing == nil)
        #expect(started == 1)
        #expect(heard == InfoCategory.allCases)
        #expect(voice.spoken == items.map(\.text))
    }

    @Test func doubleTapStopsAndThenStartsOver() {
        let (p, voice) = player()
        p.toggleDetails(gesture: "Double tap")
        voice.finish()
        voice.finish()
        #expect(p.playing == .item(2))
        p.toggleDetails(gesture: "Double tap")
        #expect(p.playing == nil)
        #expect(voice.said.last == "Stopped.")
        p.toggleDetails(gesture: "Double tap")
        #expect(p.playing == .item(0), "starts over from the first item")
    }

    @Test func swipesMoveBetweenItemsAndCarryOn() {
        let (p, voice) = player()
        p.toggleDetails(gesture: "Double tap")
        #expect(p.step(forward: true, gesture: "Three-finger swipe up"))
        #expect(p.step(forward: true, gesture: "Three-finger swipe up"))
        #expect(p.playing == .item(2))
        #expect(p.step(forward: false, gesture: "Three-finger swipe down"))
        #expect(p.playing == .item(1))
        voice.finish()
        #expect(p.playing == .item(2), "carries on after a swipe")
        #expect(voice.current == items[2].text)
    }

    @Test func swipesStopAtTheEnds() {
        let (p, voice) = player()
        #expect(p.step(forward: true, gesture: "Three-finger swipe up"), "a swipe starts the items")
        #expect(p.playing == .item(0))
        #expect(!p.step(forward: false, gesture: "Three-finger swipe down"), "nothing before the first item")
        #expect(voice.boundaries == 1)
        for _ in 1..<items.count { #expect(p.step(forward: true, gesture: "Three-finger swipe up")) }
        #expect(!p.step(forward: true, gesture: "Three-finger swipe up"))
        #expect(p.playing == .item(items.count - 1), "the last item keeps playing")
        voice.finish()
        #expect(!p.step(forward: true, gesture: "VoiceOver three-finger swipe up", voiceOverScroll: true))
        #expect(voice.boundaries == 2, "VoiceOver plays its own boundary sound")
        #expect(voice.said.last == "End of details.")
        #expect(p.step(forward: false, gesture: "Three-finger swipe down"))
        #expect(p.playing == .item(items.count - 2))
    }

    @Test func announcementAndDetailsCutEachOtherOff() {
        let (p, voice) = player()
        p.playAnnouncement(gesture: "Map opened", repeated: false)
        p.toggleDetails(gesture: "Double tap")
        #expect(p.playing == .item(0))
        p.toggleAnnouncement(gesture: "Two-finger double tap")
        #expect(p.playing == .announcement)
        voice.finish()
        #expect(p.playing == nil, "the items do not resume after the announcement")
    }

    @Test func settingsChangeRestartsTheItems() {
        let (p, voice) = player()
        p.toggleDetails(gesture: "Double tap")
        voice.finish()
        p.setItems(Array(items.prefix(2)))
        #expect(p.playing == nil)
        #expect(p.position == nil)
        p.toggleDetails(gesture: "Double tap")
        voice.finish()
        voice.finish()
        #expect(p.playing == nil)
        #expect(voice.spoken.suffix(2) == items.prefix(2).map(\.text))
    }

    @Test func noItemsSaysSo() {
        let voice = FakeSpeaker()
        let p = DescriptionPlayer(announcement: "Overview.", items: [], speaker: voice)
        p.toggleDetails(gesture: "Double tap")
        #expect(p.playing == nil)
        #expect(voice.said == ["No details are turned on."])
        #expect(!p.step(forward: true, gesture: "Three-finger swipe up"))
    }

    @Test func speakingColumn() {
        let (p, _) = player()
        #expect(p.speaking == "")
        p.playAnnouncement(gesture: "Map opened", repeated: false)
        #expect(p.speaking == "Announcement")
        p.toggleDetails(gesture: "Double tap")
        p.step(forward: true, gesture: "Three-finger swipe up")
        #expect(p.speaking == "Item 2, Traffic direction")
    }
}
