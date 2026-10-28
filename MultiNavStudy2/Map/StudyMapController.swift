// StudyMapController.swift
// What the map screen needs from either kind of map, a route overview or an
// intersection: the drawing and touch handling, the player for what the map
// says about itself, and two callbacks for the visit.

import UIKit

@MainActor
protocol StudyMapController: MapScene, TactileCanvasDelegate {
    var canvas: TactileCanvasView? { get set }
    var player: DescriptionPlayer { get }
    /// What VoiceOver reads when the map opens, before the announcement.
    var canvasLabel: String { get }
    /// False keeps the screen dark; touch, sound and vibration still work.
    var showMap: Bool { get set }
    /// The participant's gesture for "ready to cross".
    var onFinishRequest: ((String) -> Void)? { get set }
    /// Every touch down, so the visit can time the first one and count them.
    var onTouchDown: (() -> Void)? { get set }
}
