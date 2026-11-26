import Foundation
import AVFoundation

/// Synthesizes ambient focus sounds (brown noise, pink noise, rain, ocean) in real time
/// using AVAudioEngine with zero external audio asset dependencies.
@MainActor
public final class AmbientSoundEngine: ObservableObject {
    public static let shared = AmbientSoundEngine()

    @Published public private(set) var currentSound: FocusAmbientSound = .none
    @Published public var volume: Float = 0.35 {
        didSet {
            engine.mainMixerNode.outputVolume = max(0, min(1, volume))
        }
    }

    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private let dspState = DSPState()

    private final class DSPState: @unchecked Sendable {
        var mode: FocusAmbientSound = .none
        var brownLast: Float = 0
        var b0: Float = 0, b1: Float = 0, b2: Float = 0, b3: Float = 0, b4: Float = 0, b5: Float = 0, b6: Float = 0
        var oceanPhase: Float = 0
        var rainDropEnv: Float = 0
        var rngState: UInt64 = 0x1234_5678_9ABC_DEF0

        func nextWhite() -> Float {
            rngState ^= rngState >> 12
            rngState ^= rngState << 25
            rngState ^= rngState >> 27
            let val = rngState &* 0x2545F4914F6CDD1D
            return (Float(val & 0xFFFFFF) / Float(0x800000)) - 1.0
        }
    }

    public init() {
        engine.mainMixerNode.outputVolume = volume
    }

    public func play(_ sound: FocusAmbientSound) {
        if sound == .none {
            stop()
            return
        }
        currentSound = sound
        dspState.mode = sound

        if sourceNode == nil {
            let format = engine.outputNode.inputFormat(forBus: 0)
            let sampleRate = Float(format.sampleRate > 0 ? format.sampleRate : 44100)
            let state = dspState

            let node = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
                let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
                for frame in 0..<Int(frameCount) {
                    let white = state.nextWhite()
                    var sample: Float = 0

                    switch state.mode {
                    case .none:
                        sample = 0
                    case .brownNoise:
                        state.brownLast = (state.brownLast + (0.02 * white)) / 1.02
                        sample = state.brownLast * 3.5
                    case .pinkNoise:
                        state.b0 = 0.99886 * state.b0 + white * 0.0555179
                        state.b1 = 0.99332 * state.b1 + white * 0.0750759
                        state.b2 = 0.96900 * state.b2 + white * 0.1538520
                        state.b3 = 0.86650 * state.b3 + white * 0.3104856
                        state.b4 = 0.55000 * state.b4 + white * 0.5329522
                        state.b5 = -0.7616 * state.b5 - white * 0.0168980
                        sample = (state.b0 + state.b1 + state.b2 + state.b3 + state.b4 + state.b5 + state.b6 + white * 0.5362) * 0.11
                        state.b6 = white * 0.115926
                    case .rain:
                        state.b0 = 0.99 * state.b0 + white * 0.08
                        if abs(white) > 0.985 { state.rainDropEnv = 0.25 }
                        state.rainDropEnv *= 0.997
                        sample = (state.b0 * 0.7 + white * 0.12 + white * state.rainDropEnv)
                    case .ocean:
                        state.oceanPhase += (2.0 * Float.pi * 0.11) / sampleRate
                        if state.oceanPhase > 2.0 * Float.pi { state.oceanPhase -= 2.0 * Float.pi }
                        let swell = 0.35 + 0.65 * (0.5 + 0.5 * sinf(state.oceanPhase))
                        state.brownLast = (state.brownLast + (0.025 * white)) / 1.025
                        sample = state.brownLast * 3.2 * swell
                    }

                    sample = max(-0.95, min(0.95, sample))
                    for buffer in ablPointer {
                        let ptr = buffer.mData?.assumingMemoryBound(to: Float.self)
                        ptr?[frame] = sample
                    }
                }
                return noErr
            }

            sourceNode = node
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
        }

        if !engine.isRunning {
            try? engine.start()
        }
    }

    public func stop() {
        currentSound = .none
        dspState.mode = .none
        if engine.isRunning {
            engine.stop()
        }
    }
}
