// AudioService.swift
// The map sounds, synthesised once and played from one audio engine:
//   ding      1120 Hz bell, 0.16 s, for intersections, turns and crosswalk ends
//   click     short soft click, 12 ms, repeated over crosswalks
//   chime     two soft notes falling a fifth (784 then 523 Hz), 0.32 s,
//             repeated at the centre of an intersection, which has no vibration
//   boundary  a low 330 Hz thud, 0.09 s, when there is no item further that way
// The session uses the playback category so both are heard with the ringer
// switch off, and mixes with VoiceOver and other audio.

import AVFoundation

final class AudioService {
    private let engine = AVAudioEngine()
    private let dingPlayer = AVAudioPlayerNode()
    private let clickPlayer = AVAudioPlayerNode()
    private let tonePlayer = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private lazy var dingBuffer = makeDing()
    private lazy var clickBuffer = makeClick()
    private lazy var chimeBuffer = makeChime()
    private lazy var boundaryBuffer = makeBoundary()
    private var observers: [NSObjectProtocol] = []

    var onError: ((String) -> Void)?

    init() {
        configureSession()
        engine.attach(dingPlayer)
        engine.attach(clickPlayer)
        engine.attach(tonePlayer)
        engine.connect(dingPlayer, to: engine.mainMixerNode, format: format)
        engine.connect(clickPlayer, to: engine.mainMixerNode, format: format)
        engine.connect(tonePlayer, to: engine.mainMixerNode, format: format)
        clickPlayer.volume = 0.64
        startEngine()
        observe()
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    private func configureSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            onError?("Audio session setup failed: \(error.localizedDescription)")
        }
    }

    private func startEngine() {
        guard !engine.isRunning else { return }
        do {
            engine.prepare()
            try engine.start()
        } catch {
            onError?("Audio engine failed to start: \(error.localizedDescription)")
        }
    }

    private func observe() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine,
                                            queue: .main) { [weak self] _ in
            self?.startEngine()
        })
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil,
                                            queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
            self?.configureSession()
            self?.startEngine()
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil,
                                            queue: .main) { [weak self] _ in
            self?.configureSession()
            self?.startEngine()
        })
    }

    func resume() {
        configureSession()
        startEngine()
    }

    func ding() {
        play(dingBuffer, on: dingPlayer)
    }

    func click() {
        play(clickBuffer, on: clickPlayer)
    }

    func chime() {
        play(chimeBuffer, on: tonePlayer)
    }

    func boundary() {
        play(boundaryBuffer, on: tonePlayer)
    }

    func stop() {
        dingPlayer.stop()
        clickPlayer.stop()
        tonePlayer.stop()
    }

    private func play(_ buffer: AVAudioPCMBuffer?, on player: AVAudioPlayerNode) {
        guard let buffer else { return }
        startEngine()
        guard engine.isRunning else { return }
        player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        if !player.isPlaying { player.play() }
    }

    private func makeDing() -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let duration = 0.16
        let frames = AVAudioFrameCount(sampleRate * duration)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let samples = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        for i in 0..<Int(frames) {
            let t = Double(i) / sampleRate
            let attack = min(t / 0.008, 1.0)
            let decay = exp(-max(t - 0.008, 0) * 18)
            samples[i] = Float(sin(2 * .pi * 1_120 * t) * attack * decay * 0.88)
        }
        return buffer
    }

    /// Two soft bell notes, the second a fifth below the first.
    private func makeChime() -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let note = 0.16
        let frames = AVAudioFrameCount(sampleRate * note * 2)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let samples = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        for i in 0..<Int(frames) {
            let t = Double(i) / sampleRate
            let second = t >= note
            let local = second ? t - note : t
            let frequency = second ? 523.25 : 783.99
            let attack = min(local / 0.01, 1.0)
            let decay = exp(-local * 14)
            let tone = sin(2 * .pi * frequency * local) + 0.25 * sin(2 * .pi * frequency * 2 * local)
            samples[i] = Float(tone * attack * decay * 0.55)
        }
        return buffer
    }

    /// A short low thud.
    private func makeBoundary() -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let frames = AVAudioFrameCount(sampleRate * 0.09)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let samples = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        for i in 0..<Int(frames) {
            let t = Double(i) / sampleRate
            let attack = min(t / 0.004, 1.0)
            let decay = exp(-t * 38)
            samples[i] = Float(sin(2 * .pi * 330 * t) * attack * decay * 0.6)
        }
        return buffer
    }

    private func makeClick() -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let frames = AVAudioFrameCount(sampleRate * 0.012)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let samples = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        for i in 0..<Int(frames) {
            let t = Double(i) / sampleRate
            let envelope = exp(-t * 280)
            let body = sin(2 * .pi * 820 * t)
            let snap = sin(2 * .pi * 1_640 * t) * exp(-t * 520)
            samples[i] = Float((body * 0.6 + snap * 0.4) * envelope * 0.14)
        }
        return buffer
    }
}
