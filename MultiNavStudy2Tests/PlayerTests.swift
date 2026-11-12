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

    /// The two-finger double tap plays every item, first to last, each with
    /// its place after it (team, 11/09).
    @Test func twoFingerDoubleTapPlaysEveryItem() {
        let (p, voice) = player()
        var started = 0
        var heard: [InfoCategory] = []
        p.onDetailsStarted = { started += 1 }
        p.onItem = { heard.append($0.category) }
        p.toggleDetails(gesture: "Two-finger double tap")
        #expect(started == 1)
        for _ in items { hear(voice) }
        #expect(p.playing == nil)
        #expect(heard == InfoCategory.allCases)
        #expect(voice.spoken == items.enumerated().flatMap { [$1.text, "\($0 + 1) of 6"] })
        #expect(voice.said.isEmpty, "nothing else is said")
    }

    /// Each item ends with its place, counting only the items that play.
    @Test func itemsSayTheirPlace() {
        let (p, voice) = player()
        p.step(forward: true, gesture: "Two-finger swipe down")
        #expect(voice.current == "Item about Intersection geometry.")
        voice.finish()
        #expect(voice.current == "1 of 6")
        voice.finish()
        p.setItems([items[0], items[1], items[3], items[5]])
        p.toggleDetails(gesture: "Two-finger double tap")
        for _ in 0..<4 { hear(voice) }
        #expect(voice.spoken.suffix(8) == [
            "Item about Intersection geometry.", "1 of 4", "Item about Traffic direction.", "2 of 4",
            "Item about Pedestrian signals.", "3 of 4", "Item about Truncated domes and curb cuts.", "4 of 4",
        ])
    }

    /// The place follows the item's words after a short pause, and a swipe
    /// in the pause moves on without it.
    @Test func placeFollowsAfterAPause() async throws {
        let (p, voice) = player()
        p.placePause = 0.05
        p.step(forward: true, gesture: "Two-finger swipe down")
        voice.finish()
        #expect(voice.current == nil, "a pause before the place")
        #expect(p.playing == .item(0), "map names stay held back in the pause")
        try await Task.sleep(nanoseconds: 150_000_000)
        #expect(voice.current == "1 of 6")
        voice.finish()
        #expect(p.playing == nil)

        p.step(forward: true, gesture: "Two-finger swipe down")
        voice.finish()
        p.step(forward: true, gesture: "Two-finger swipe down")
        try await Task.sleep(nanoseconds: 150_000_000)
        #expect(voice.current == items[2].text)
        #expect(!voice.spoken.contains("2 of 6"), "the skipped item's place is never said")
    }

    /// Shorter than the half second of build 6 (team, 11/09).
    @Test func pauseIsShort() {
        #expect(DescriptionPlayer(announcement: "", items: [], speaker: FakeSpeaker()).placePause == 0.25)
    }

    @Test func twoFingerDoubleTapStopsAndThenStartsOver() {
        let (p, voice) = player()
        p.toggleDetails(gesture: "Two-finger double tap")
        hear(voice)
        hear(voice)
        #expect(p.playing == .item(2))
        p.toggleDetails(gesture: "Two-finger double tap")
        #expect(p.playing == nil)
        #expect(voice.said.last == "Stopped.")
        p.toggleDetails(gesture: "Two-finger double tap")
        #expect(p.playing == .item(0), "starts over from the first item")
    }

    /// A swipe reads one item and nothing after it, even during a full play.
    @Test func swipesReadOneItemAtATime() {
        let (p, voice) = player()
        p.toggleDetails(gesture: "Two-finger double tap")
        #expect(p.step(forward: true, gesture: "Two-finger swipe down"))
        #expect(p.step(forward: true, gesture: "Two-finger swipe down"))
        #expect(p.playing == .item(2))
        #expect(p.step(forward: false, gesture: "Two-finger swipe up"))
        #expect(p.playing == .item(1))
        hear(voice)
        #expect(p.playing == nil, "does not carry on to the next item")
        #expect(voice.current == nil)
        #expect(p.step(forward: true, gesture: "Two-finger swipe down"))
        #expect(p.playing == .item(2))
    }

    /// The list reads from the top: a swipe down starts it, up before the
    /// first says "Start of details." and down past the last "End of
    /// details." (team, 11/09).
    /// The list reads from the top: a swipe down starts it. Past either end
    /// the map says "Start of details." or "End of details." every time, with
    /// the boundary sound, cutting off an item still being read (team, 11/12).
    @Test func swipesStopAtTheEnds() {
        let (p, voice) = player()
        #expect(!p.step(forward: false, gesture: "Two-finger swipe up"), "already at the top")
        #expect(voice.boundaries == 1)
        #expect(voice.said == ["Start of details."])
        #expect(p.step(forward: true, gesture: "Two-finger swipe down"), "a swipe down reads the first item")
        #expect(p.playing == .item(0))
        #expect(!p.step(forward: false, gesture: "Two-finger swipe up"), "nothing before the first item")
        #expect(voice.boundaries == 2)
        #expect(voice.said.last == "Start of details.", "said even while the first item plays")
        #expect(voice.said.count == 2)
        #expect(p.playing == nil, "the words cut the item off")
        #expect(voice.current == nil, "nothing follows them")
        for _ in 1..<items.count {
            #expect(p.step(forward: true, gesture: "Two-finger swipe down"))
        }
        #expect(p.playing == .item(items.count - 1))
        #expect(!p.step(forward: true, gesture: "Two-finger swipe down"))
        #expect(voice.said.last == "End of details.", "said even while the last item plays")
        #expect(p.playing == nil)
        #expect(!p.step(forward: true, gesture: "Two-finger swipe down"))
        #expect(voice.said.suffix(2) == ["End of details.", "End of details."], "and again after it")
        #expect(voice.boundaries == 4)
        #expect(p.step(forward: false, gesture: "Two-finger swipe up"))
        #expect(p.playing == .item(items.count - 2))
    }

    /// The double tap plays every item to the end; a swipe down after the
    /// last says "End of details." at once, during its place too.
    @Test func endOfDetailsAfterPlayingThemAll() {
        let (p, voice) = player()
        p.toggleDetails(gesture: "Two-finger double tap")
        for _ in 0..<(items.count - 1) { hear(voice) }
        voice.finish()
        #expect(voice.current == "6 of 6")
        #expect(!p.step(forward: true, gesture: "Two-finger swipe down"))
        #expect(voice.said == ["End of details."])
        #expect(p.playing == nil)
    }

    @Test func announcementAndDetailsCutEachOtherOff() {
        let (p, voice) = player()
        p.playAnnouncement(gesture: "Map opened", repeated: false)
        p.toggleDetails(gesture: "Two-finger double tap")
        #expect(p.playing == .item(0))
        p.toggleAnnouncement(gesture: "Double tap")
        #expect(p.playing == .announcement)
        voice.finish()
        #expect(p.playing == nil, "the items do not resume after the announcement")
    }

    @Test func settingsChangeRestartsTheItems() {
        let (p, voice) = player()
        p.toggleDetails(gesture: "Two-finger double tap")
        hear(voice)
        p.setItems(Array(items.prefix(2)))
        #expect(p.playing == nil)
        #expect(p.position == nil)
        p.toggleDetails(gesture: "Two-finger double tap")
        hear(voice)
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
        p.playAnnouncement(gesture: "Double tap", repeated: false)
        #expect(!p.step(forward: true, gesture: "Two-finger swipe down"))
        #expect(voice.said.last == "No details are turned on.", "said every time")
        #expect(voice.boundaries == 1)
    }

    @Test func speakingColumn() {
        let (p, _) = player()
        #expect(p.speaking == "")
        p.playAnnouncement(gesture: "Map opened", repeated: false)
        #expect(p.speaking == "Announcement")
        p.toggleDetails(gesture: "Two-finger double tap")
        #expect(p.speaking == "Item 1, Intersection geometry")
        p.step(forward: true, gesture: "Two-finger swipe down")
        #expect(p.speaking == "Item 2, Traffic direction")
    }
}
