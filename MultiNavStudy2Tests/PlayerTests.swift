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

    /// A player whose place follows an item at once, so each step can be checked.
    private func player() -> (DescriptionPlayer, FakeSpeaker) {
        let speaker = FakeSpeaker()
        let p = DescriptionPlayer(announcement: "You are at the intersection.", items: items, speaker: speaker)
        p.placePause = 0
        return (p, speaker)
    }

    /// One item heard to the end: its words, then its place.
    private func hear(_ voice: FakeSpeaker) {
        voice.finish()
        voice.finish()
    }

    @Test func announcementPlaysAndStopsWithItsGesture() {
        let (p, voice) = player()
        var plays: [Bool] = []
        p.onAnnouncement = { plays.append($0) }
        p.playAnnouncement(gesture: "Map opened", repeated: false)
        #expect(p.playing == .announcement)
        p.toggleAnnouncement(gesture: "Double tap")
        #expect(p.playing == nil)
        #expect(voice.said == ["Stopped."])
        p.toggleAnnouncement(gesture: "Double tap")
        #expect(p.playing == .announcement)
        voice.finish()
        #expect(p.playing == nil)
        #expect(plays == [false, true])
        #expect(voice.spoken == Array(repeating: "You are at the intersection.", count: 2))
    }

    /// The two-finger double tap says "Description mode." and reads no item
    /// (team, 11/05); each swipe then reads one item and stops.
    @Test func descriptionModeReadsOneItemPerSwipe() {
        let (p, voice) = player()
        var started = 0
        var heard: [InfoCategory] = []
        p.onDescriptionMode = { started += 1 }
        p.onItem = { heard.append($0.category) }
        p.toggleDetails(gesture: "Two-finger double tap")
        #expect(voice.said == ["Description mode."])
        #expect(voice.spoken.isEmpty, "no item is read until a swipe")
        #expect(p.playing == nil)
        #expect(started == 1)
        for n in items.indices {
            #expect(p.step(forward: true, gesture: "Two-finger swipe up"))
            #expect(voice.current == items[n].text)
            voice.finish()
            #expect(voice.current == "\(n + 1) of 6")
            voice.finish()
            #expect(p.playing == nil, "item \(n + 1) is read on its own")
            #expect(voice.current == nil, "nothing follows it")
        }
        #expect(heard == InfoCategory.allCases)
        #expect(voice.spoken == items.enumerated().flatMap { [$1.text, "\($0 + 1) of 6"] })
    }

    /// Each item ends with its place, counting only the items that play.
    @Test func itemsSayTheirPlace() {
        let (p, voice) = player()
        p.step(forward: true, gesture: "Two-finger swipe up")
        #expect(voice.current == "Item about Intersection geometry.")
        voice.finish()
        #expect(voice.current == "1 of 6")
        voice.finish()
        p.setItems([items[0], items[1], items[3], items[5]])
        for _ in 0..<4 {
            p.step(forward: true, gesture: "Two-finger swipe up")
            hear(voice)
        }
        #expect(voice.spoken.suffix(8) == [
            "Item about Intersection geometry.", "1 of 4", "Item about Traffic direction.", "2 of 4",
            "Item about Pedestrian signals.", "3 of 4", "Item about Truncated domes and curb cuts.", "4 of 4",
        ])
    }

    /// The place follows the item's words after a pause, and a swipe in the
    /// pause moves on without it.
    @Test func placeFollowsAfterAPause() async throws {
        let (p, voice) = player()
        p.placePause = 0.05
        p.step(forward: true, gesture: "Two-finger swipe up")
        voice.finish()
        #expect(voice.current == nil, "a pause before the place")
        #expect(p.playing == .item(0), "map names stay held back in the pause")
        try await Task.sleep(nanoseconds: 150_000_000)
        #expect(voice.current == "1 of 6")
        voice.finish()
        #expect(p.playing == nil)

        p.step(forward: true, gesture: "Two-finger swipe up")
        voice.finish()
        p.step(forward: true, gesture: "Two-finger swipe up")
        try await Task.sleep(nanoseconds: 150_000_000)
        #expect(voice.current == items[2].text)
        #expect(!voice.spoken.contains("2 of 6"), "the skipped item's place is never said")
    }

    @Test func twoFingerDoubleTapStopsAnItemAndStartsOver() {
        let (p, voice) = player()
        p.toggleDetails(gesture: "Two-finger double tap")
        p.step(forward: true, gesture: "Two-finger swipe up")
        hear(voice)
        p.step(forward: true, gesture: "Two-finger swipe up")
        #expect(p.playing == .item(1))
        p.toggleDetails(gesture: "Two-finger double tap")
        #expect(p.playing == nil)
        #expect(voice.said.last == "Stopped.")
        p.toggleDetails(gesture: "Two-finger double tap")
        #expect(voice.said.last == "Description mode.")
        #expect(p.position == nil)
        p.step(forward: true, gesture: "Two-finger swipe up")
        #expect(p.playing == .item(0), "starts over from the first item")
    }

    @Test func swipesMoveBetweenItemsOneAtATime() {
        let (p, voice) = player()
        p.toggleDetails(gesture: "Two-finger double tap")
        #expect(p.step(forward: true, gesture: "Two-finger swipe up"))
        #expect(p.step(forward: true, gesture: "Two-finger swipe up"))
        #expect(p.step(forward: true, gesture: "Two-finger swipe up"))
        #expect(p.playing == .item(2))
        #expect(p.step(forward: false, gesture: "Two-finger swipe down"))
        #expect(p.playing == .item(1))
        hear(voice)
        #expect(p.playing == nil, "does not carry on to the next item")
        #expect(voice.current == nil)
        #expect(p.step(forward: true, gesture: "Two-finger swipe up"))
        #expect(p.playing == .item(2))
    }

    @Test func swipesStopAtTheEnds() {
        let (p, voice) = player()
        #expect(p.step(forward: true, gesture: "Two-finger swipe up"), "a swipe reads the first item")
        #expect(p.playing == .item(0))
        #expect(!p.step(forward: false, gesture: "Two-finger swipe down"), "nothing before the first item")
        #expect(voice.boundaries == 1)
        for _ in 1..<items.count { #expect(p.step(forward: true, gesture: "Two-finger swipe up")) }
        #expect(!p.step(forward: true, gesture: "Two-finger swipe up"))
        #expect(p.playing == .item(items.count - 1), "the last item keeps playing")
        #expect(voice.boundaries == 2)
        hear(voice)
        #expect(!p.step(forward: true, gesture: "Two-finger swipe up"))
        #expect(voice.boundaries == 3, "the map plays the boundary sound")
        #expect(voice.said.last == "End of details.")
        #expect(p.step(forward: false, gesture: "Two-finger swipe down"))
        #expect(p.playing == .item(items.count - 2))
    }

    @Test func announcementAndDetailsCutEachOtherOff() {
        let (p, voice) = player()
        p.playAnnouncement(gesture: "Map opened", repeated: false)
        p.toggleDetails(gesture: "Two-finger double tap")
        #expect(p.playing == nil, "description mode cuts the announcement off")
        #expect(voice.said.last == "Description mode.")
        p.step(forward: true, gesture: "Two-finger swipe up")
        #expect(p.playing == .item(0))
        p.toggleAnnouncement(gesture: "Double tap")
        #expect(p.playing == .announcement)
        voice.finish()
        #expect(p.playing == nil, "the items do not resume after the announcement")
    }

    @Test func settingsChangeRestartsTheItems() {
        let (p, voice) = player()
        p.step(forward: true, gesture: "Two-finger swipe up")
        hear(voice)
        p.step(forward: true, gesture: "Two-finger swipe up")
        p.setItems(Array(items.prefix(2)))
        #expect(p.playing == nil)
        #expect(p.position == nil)
        p.step(forward: true, gesture: "Two-finger swipe up")
        hear(voice)
        p.step(forward: true, gesture: "Two-finger swipe up")
        hear(voice)
        #expect(p.playing == nil)
        #expect(voice.spoken.suffix(4) == [items[0].text, "1 of 2", items[1].text, "2 of 2"])
    }

    @Test func noItemsSaysSo() {
        let voice = FakeSpeaker()
        let p = DescriptionPlayer(announcement: "Overview.", items: [], speaker: voice)
        p.toggleDetails(gesture: "Two-finger double tap")
        #expect(p.playing == nil)
        #expect(voice.said == ["No details are turned on."])
        #expect(!p.step(forward: true, gesture: "Two-finger swipe up"))
    }

    @Test func speakingColumn() {
        let (p, _) = player()
        #expect(p.speaking == "")
        p.playAnnouncement(gesture: "Map opened", repeated: false)
        #expect(p.speaking == "Announcement")
        p.toggleDetails(gesture: "Two-finger double tap")
        #expect(p.speaking == "")
        p.step(forward: true, gesture: "Two-finger swipe up")
        #expect(p.speaking == "Item 1, Intersection geometry")
        p.step(forward: true, gesture: "Two-finger swipe up")
        #expect(p.speaking == "Item 2, Traffic direction")
    }
}
