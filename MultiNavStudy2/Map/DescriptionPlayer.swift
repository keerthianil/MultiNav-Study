// DescriptionPlayer.swift
// Plays what a map says about itself, the way the research team asked:
//
//   The announcement (the intersection and the route's crossings, or on an
//   overview the route overview) plays when the map opens. A two-finger
//   double tap plays it again; the same gesture while it plays stops it.
//
//   The information items play with a double tap, one after another. A
//   three-finger swipe up skips to the next item and down goes back one,
//   and playing carries on from there. A double tap while they play stops
//   them; the next double tap starts over from the first item.
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
    /// The item last played, where the swipes carry on from.
    private(set) var position: Int?

    /// Called each time the announcement starts; `repeated` is false for
    /// the play when the map opens.
    var onAnnouncement: ((_ repeated: Bool) -> Void)?
    /// Called when a double tap starts the items from the first.
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

    /// New items after the researcher changes the settings. Anything playing
    /// stops, and the next double tap starts from the first item.
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

    /// The two-finger double tap: stops the announcement while it plays,
    /// otherwise plays it again from the start.
    func toggleAnnouncement(gesture: String) {
        if playing == .announcement {
            stopWithWord(gesture: gesture)
        } else {
            playAnnouncement(gesture: gesture, repeated: true)
        }
    }

    // MARK: The information items

    /// The double tap: stops the items while they play, otherwise plays them
    /// all from the first.
    func toggleDetails(gesture: String) {
        if case .item = playing {
            stopWithWord(gesture: gesture)
            return
        }
        guard !items.isEmpty else {
            cutOffCurrent(by: "a double tap")
            log.event(.description, "No items to play", detail: gesture)
            feedback.speak("No details are turned on.", queued: false)
            return
        }
        log.event(.description, "Details started", detail: gesture)
        onDetailsStarted?()
        play(item: 0, gesture: gesture)
    }

    /// A three-finger swipe: the next or previous item, then on through the
    /// rest. Returns false when there is no item that way. With VoiceOver,
    /// VoiceOver plays its own boundary sound then; otherwise the map does.
    @discardableResult
    func step(forward: Bool, gesture: String, voiceOverScroll: Bool = false) -> Bool {
        guard !items.isEmpty else {
            log.event(.description, "No items to play", detail: gesture)
            if !voiceOverScroll { feedback.boundary() }
            if !isPlaying { feedback.speak("No details are turned on.", queued: false) }
            return false
        }
        var target = position.map { $0 + (forward ? 1 : -1) } ?? 0
        if target >= items.count {
            log.event(.description, "No next item", detail: gesture)
            if !voiceOverScroll { feedback.boundary() }
            if !isPlaying { feedback.speak("End of details.", queued: false) }
            return false
        }
        if target < 0 {
            // Back from the first item: hear it again, unless it is playing now.
            if playing == .item(0) {
                log.event(.description, "No previous item", detail: gesture)
                if !voiceOverScroll { feedback.boundary() }
                return false
            }
            target = 0
        }
        feedback.confirm()
        play(item: target, gesture: gesture)
        return true
    }

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
            let name = "Item \(item.category.number)"
            if finished {
                self.log.event(.description, "\(name) finished", detail: item.category.title)
                self.playing = nil
                if index + 1 < self.items.count {
                    self.play(item: index + 1, gesture: "Continued")
                } else {
                    self.log.event(.description, "Details finished")
                }
            } else {
                self.playing = nil
                self.log.event(.description, "\(name) cut off", detail: item.category.title)
            }
        }
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
