// DescriptionPlayer.swift
// Plays what a map says about itself, the way the research team asked:
//
//   The announcement (the intersection and the route's crossings, or on an
//   overview the route overview) plays with a double tap, never by itself
//   (team, 11/12); the same gesture while it plays stops it.
//
//   The information items are a list read from the top (team, 11/09). A
//   two-finger double tap plays them all, the first to the last; the same
//   gesture while they play stops them, and the next one starts over. A
//   two-finger swipe down reads the next item and a swipe up the one before,
//   on its own, and nothing follows it (team, 11/05). Past the last item the
//   map says "End of details.", before the first "Start of details.", every
//   time, cutting off whatever is being read (team, 11/12). After
//   a short pause each item is followed by its place among the items played
//   ("2 of 6"; in Trial 2 only the items switched on are counted).
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

    let announcement: String
    /// The items this map plays, in order (only those switched on in Trial 2).
    private(set) var items: [InfoItem]
    private(set) var playing: Part?
    /// The item last played, which the next swipe moves on from; nil before
    /// the first.
    private(set) var position: Int?
    /// Silence between an item's words and its place, so "2 of 6" stands
    /// apart from them (team, 11/05), kept short (team, 11/09).
    var placePause: TimeInterval = 0.25

    /// Called each time the announcement starts; `repeated` is false for
    /// the play when the map opens.
    var onAnnouncement: ((_ repeated: Bool) -> Void)?
    /// Called when a two-finger double tap starts the items from the first.
    var onDetailsStarted: (() -> Void)?
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
    /// read stops, and the next swipe down starts from the first item.
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

    /// The two-finger double tap: stops the items while they play, otherwise
    /// plays them all from the first.
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
        log.event(.description, "Details started", detail: gesture)
        onDetailsStarted?()
        play(item: 0, gesture: gesture, continuing: true)
    }

    /// A two-finger swipe: reads the next item (down) or the one before
    /// (up), and only that one. Returns false, after the boundary sound and
    /// the words for the end, when there is no item that way.
    @discardableResult
    func step(forward: Bool, gesture: String) -> Bool {
        guard !items.isEmpty else {
            atEnd("No items to play", saying: "No details are turned on.", gesture: gesture)
            return false
        }
        // Before any item the list is at its top: the next is the first.
        let target = position.map { $0 + (forward ? 1 : -1) } ?? (forward ? 0 : -1)
        if target >= items.count {
            atEnd("No next item", saying: "End of details.", gesture: gesture)
            return false
        }
        if target < 0 {
            atEnd("No previous item", saying: "Start of details.", gesture: gesture)
            return false
        }
        feedback.confirm()
        play(item: target, gesture: gesture, continuing: false)
        return true
    }

    /// A swipe past either end of the items: the boundary sound and the words,
    /// every time. They cut off whatever is being read, so they are heard
    /// even while the first or last item still plays (team, 11/12).
    private func atEnd(_ event: String, saying words: String, gesture: String) {
        cutOffCurrent(by: words)
        log.event(.description, event, detail: gesture)
        feedback.boundary()
        feedback.speak(words, queued: false)
    }

    /// One item: its words, a pause, then its place; then the next item when
    /// `continuing` (the two-finger double tap), otherwise nothing.
    private func play(item index: Int, gesture: String, continuing: Bool) {
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
                    self?.sayPlace(of: index, token: mine, continuing: continuing)
                }
            } else {
                self.sayPlace(of: index, token: mine, continuing: continuing)
            }
        }
    }

    private func sayPlace(of index: Int, token mine: Int, continuing: Bool) {
        guard token == mine else { return }
        feedback.speakTracked(place(index), queued: false) { [weak self] finished in
            guard let self, self.token == mine else { return }
            self.itemEnded(index, finished: finished)
            guard finished, continuing else { return }
            if index + 1 < self.items.count {
                self.play(item: index + 1, gesture: "Continued", continuing: true)
            } else {
                self.log.event(.description, "Details finished")
            }
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
