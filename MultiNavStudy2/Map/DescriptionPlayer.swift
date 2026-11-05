// DescriptionPlayer.swift
// Plays what a map says about itself, the way the research team asked:
//
//   The announcement (the intersection and the route's crossings, or on an
//   overview the route overview) plays when the map opens. A double tap
//   plays it again; the same gesture while it plays stops it.
//
//   The information items are heard one at a time (team, 11/05). A
//   two-finger double tap starts description mode: it says "Description
//   mode." and nothing more, and the next swipe starts from the first item.
//   Each two-finger swipe up reads the next item and a swipe down the one
//   before, on its own; after a short pause comes its place among the items
//   played ("2 of 6"; in Trial 2 only the items switched on are counted),
//   and then nothing until the next swipe. A two-finger double tap while an
//   item is read stops it.
//
// Stopping says "Stopped." That is how a VoiceOver announcement is cut
// off, and it tells the participant the gesture worked. The map stays live
// the whole time: touches vibrate and sound as usual, and the controllers
// hold back map names while something plays so they do not cut it off.

import Foundation

/// What the player needs to be heard. FeedbackManager in the app; the tests
/// use a stand-in that finishes each phrase when told to.
@MainActor
protocol DescriptionSpeaker: AnyObject {
    func speakTracked(_ text: String, queued: Bool, completion: @escaping (Bool) -> Void)
    func speak(_ text: String, queued: Bool)
    func boundary()
    func confirm()
}

extension FeedbackManager: DescriptionSpeaker {}

@MainActor
final class DescriptionPlayer {
    enum Part: Equatable {
        case announcement
        case item(Int)
    }

    /// What a two-finger double tap says.
    static let modeWords = "Description mode."

    let announcement: String
    /// The items this map plays, in order (only those switched on in Trial 2).
    private(set) var items: [InfoItem]
    private(set) var playing: Part?
    /// The item last played, which the next swipe moves on from; nil before
    /// the first, and again after a two-finger double tap.
    private(set) var position: Int?
    /// Silence between an item's words and its place, so "2 of 6" stands
    /// apart from them (team, 11/05).
    var placePause: TimeInterval = 0.5

    /// Called each time the announcement starts; `repeated` is false for
    /// the play when the map opens.
    var onAnnouncement: ((_ repeated: Bool) -> Void)?
    /// Called when a two-finger double tap starts description mode.
    var onDescriptionMode: (() -> Void)?
    var onItem: ((InfoItem) -> Void)?

    private var token = 0
    private let feedback: DescriptionSpeaker
    private let log = StudyLog.shared

    init(announcement: String, items: [InfoItem], speaker: DescriptionSpeaker? = nil) {
        self.announcement = announcement
        self.items = items
        feedback = speaker ?? FeedbackManager.shared
    }

    var isPlaying: Bool { playing != nil }

    /// What is being spoken, for the touch log.
    var speaking: String {
        switch playing {
        case .announcement: return "Announcement"
        case .item(let i): return "Item \(items[i].category.number), \(items[i].category.title)"
        case nil: return ""
        }
    }

    /// New items after the researcher changes the settings. An item being
    /// read stops, and the next swipe starts from the first item.
    func setItems(_ newItems: [InfoItem]) {
        guard newItems != items else { return }
        if case .item = playing { stop(reason: "Settings changed") }
        items = newItems
        position = nil
    }

    // MARK: The announcement

    /// Plays the announcement from the start. `queued` waits for VoiceOver to
    /// finish reading the new screen's name first.
    func playAnnouncement(gesture: String, repeated: Bool, queued: Bool = false) {
        cutOffCurrent(by: "announcement")
        token += 1
        let mine = token
        playing = .announcement
        log.event(.description, "Announcement started", detail: gesture)
        onAnnouncement?(repeated)
        feedback.speakTracked(announcement, queued: queued) { [weak self] finished in
            guard let self, self.token == mine else { return }
            self.playing = nil
            self.log.event(.description, finished ? "Announcement finished" : "Announcement cut off")
        }
    }

    /// The double tap: stops the announcement while it plays, otherwise
    /// plays it again from the start.
    func toggleAnnouncement(gesture: String) {
        if playing == .announcement {
            stopWithWord(gesture: gesture)
        } else {
            playAnnouncement(gesture: gesture, repeated: true)
        }
    }

    // MARK: The information items

    /// The two-finger double tap: stops the item being read, otherwise
    /// starts description mode, which reads nothing until a swipe.
    func toggleDetails(gesture: String) {
        if case .item = playing {
            stopWithWord(gesture: gesture)
            return
        }
        guard !items.isEmpty else {
            cutOffCurrent(by: gesture)
            log.event(.description, "No items to play", detail: gesture)
            feedback.speak("No details are turned on.", queued: false)
            return
        }
        cutOffCurrent(by: "description mode")
        position = nil
        log.event(.description, "Description mode", detail: gesture)
        onDescriptionMode?()
        feedback.speak(Self.modeWords, queued: false)
    }

    /// A two-finger swipe: reads the next or previous item, and only that
    /// one. Returns false, after the boundary sound, when there is no item
    /// that way.
    @discardableResult
    func step(forward: Bool, gesture: String) -> Bool {
        guard !items.isEmpty else {
            log.event(.description, "No items to play", detail: gesture)
            feedback.boundary()
            if !isPlaying { feedback.speak("No details are turned on.", queued: false) }
            return false
        }
        var target = position.map { $0 + (forward ? 1 : -1) } ?? 0
        if target >= items.count {
            log.event(.description, "No next item", detail: gesture)
            feedback.boundary()
            if !isPlaying { feedback.speak("End of details.", queued: false) }
            return false
        }
        if target < 0 {
            // Back from the first item: hear it again, unless it is playing now.
            if playing == .item(0) {
                log.event(.description, "No previous item", detail: gesture)
                feedback.boundary()
                return false
            }
            target = 0
        }
        feedback.confirm()
        play(item: target, gesture: gesture)
        return true
    }

    /// One item: its words, a pause, then its place. Nothing follows it.
    private func play(item index: Int, gesture: String) {
        cutOffCurrent(by: "item \(items[index].category.number)")
        token += 1
        let mine = token
        playing = .item(index)
        position = index
        let item = items[index]
        log.event(.description, "Item \(item.category.number) started", detail: "\(item.category.title), \(gesture)")
        onItem?(item)
        feedback.speakTracked(item.text, queued: false) { [weak self] finished in
            guard let self, self.token == mine else { return }
            guard finished else {
                self.itemEnded(index, finished: false)
                return
            }
            if self.placePause > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + self.placePause) { [weak self] in
                    self?.sayPlace(of: index, token: mine)
                }
            } else {
                self.sayPlace(of: index, token: mine)
            }
        }
    }

    private func sayPlace(of index: Int, token mine: Int) {
        guard token == mine else { return }
        feedback.speakTracked(place(index), queued: false) { [weak self] finished in
            guard let self, self.token == mine else { return }
            self.itemEnded(index, finished: finished)
        }
    }

    private func itemEnded(_ index: Int, finished: Bool) {
        playing = nil
        let category = items[index].category
        log.event(.description, "Item \(category.number) \(finished ? "finished" : "cut off")", detail: category.title)
    }

    /// An item's place among the items played, said after its words: "1 of 6".
    func place(_ index: Int) -> String {
        "\(index + 1) of \(items.count)"
    }

    // MARK: Stopping

    /// Stops what is playing, for leaving the map or opening the settings.
    func stop(reason: String) {
        guard let current = playing else { return }
        token += 1
        playing = nil
        log.event(.description, "\(name(of: current)) stopped", detail: reason)
    }

    /// The participant's stop: says "Stopped.", which also cuts VoiceOver off.
    private func stopWithWord(gesture: String) {
        guard let current = playing else { return }
        token += 1
        playing = nil
        log.event(.description, "\(name(of: current)) stopped", detail: gesture)
        feedback.speak("Stopped.", queued: false)
    }

    /// Something new is starting over what is playing.
    private func cutOffCurrent(by what: String) {
        guard let current = playing else { return }
        token += 1
        playing = nil
        log.event(.description, "\(name(of: current)) cut off", detail: "By \(what)")
    }

    private func name(of part: Part) -> String {
        switch part {
        case .announcement: return "Announcement"
        case .item(let i): return "Item \(items[i].category.number)"
        }
    }
}
