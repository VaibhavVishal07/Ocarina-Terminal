import AVFoundation

/// The click a button makes.
///
/// Synthesised rather than shipped as a file: a click is a few milliseconds of
/// noise under a steep envelope, which is less code than loading an asset and
/// weighs nothing in the bundle. It is also not one of the system alert
/// sounds — those are chimes, and announce that something is *wrong*, which is
/// the opposite of what pressing a switch should say.
///
/// Two clicks, because a real button makes two: a sharp one going down and a
/// quieter, duller one coming back up.
@MainActor
final class TactileClick {
    static let shared = TactileClick()

    enum Stroke {
        case down, up
    }

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var buffers: [ObjectIdentifier: AVAudioPCMBuffer] = [:]
    private let down: AVAudioPCMBuffer?
    private let up: AVAudioPCMBuffer?
    private var isRunning = false
    private var idle: Task<Void, Never>?

    /// How long the engine stays up after a click, waiting for the next one.
    /// Long enough that a run of presses does not restart it each time, short
    /// enough that an idle terminal is not holding an audio device open.
    private static let linger = Duration.seconds(2)

    private init() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)
        if let format {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            // Down is brighter and louder; up is the spring returning, which
            // is always the softer of the two.
            down = Self.render(format: format, gain: 0.42, decay: 340, tone: 2_600)
            up = Self.render(format: format, gain: 0.17, decay: 460, tone: 1_650)
        } else {
            down = nil
            up = nil
        }
    }

    func play(_ stroke: Stroke) {
        guard let buffer = stroke == .down ? down : up else { return }
        if !isRunning {
            engine.prepare()
            // A machine with no output device, or one that refuses the engine,
            // simply gets a silent switch rather than a crash.
            guard (try? engine.start()) != nil else { return }
            isRunning = true
            player.play()
        }
        // `.interrupts` so a fast double-press clicks twice instead of
        // queueing a click to be heard after the finger has gone.
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        deferShutdown()
    }

    /// A running `AVAudioEngine` holds the output device open, and coreaudiod
    /// takes a `PreventUserIdleSystemSleep` assertion on behalf of whoever is
    /// holding one. Left running, a single click on the keep-awake switch
    /// quietly kept the machine awake by a completely different route — in the
    /// one app that has no business taking a power assertion nobody asked for.
    /// So the engine goes away again once the clicking stops.
    private func deferShutdown() {
        idle?.cancel()
        idle = Task { [weak self] in
            try? await Task.sleep(for: Self.linger)
            guard !Task.isCancelled else { return }
            self?.shutDown()
        }
    }

    private func shutDown() {
        guard isRunning else { return }
        player.stop()
        engine.stop()
        isRunning = false
    }

    /// White noise under an exponential decay, with a damped tone under it for
    /// body. Noise alone is a hiss; the tone alone is a beep. The pair is what
    /// reads as something small and hard striking something else.
    private static func render(
        format: AVAudioFormat,
        gain: Double,
        decay: Double,
        tone: Double
    ) -> AVAudioPCMBuffer? {
        let rate = format.sampleRate
        let frames = AVAudioFrameCount(rate * 0.035)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let samples = buffer.floatChannelData?[0]
        else { return nil }
        buffer.frameLength = frames

        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        for i in 0..<Int(frames) {
            // Cheap deterministic noise: the click is identical every press,
            // which is what stops repeated taps sounding like a rattle.
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let noise = Double(Int64(bitPattern: seed >> 11)) / Double(1 << 52) - 1

            let t = Double(i) / rate
            let envelope = exp(-t * decay)
            let body = sin(2 * .pi * tone * t)
            samples[i] = Float((noise * 0.62 + body * 0.38) * envelope * gain)
        }
        return buffer
    }
}
