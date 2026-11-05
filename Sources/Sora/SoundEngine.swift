import AVFoundation

/// 雨・風・雷の環境音をノイズから合成する（音源ファイル不要）
final class SoundEngine {
    static let shared = SoundEngine()

    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode!
    private var running = false

    // レンダースレッドから読む値（多少の競合は音に影響しない）
    private var rainAmp: Float = 0
    private var windAmp: Float = 0
    private var thunderEnv: Float = 0

    private var lpRain: Float = 0, lpWind: Float = 0, lpWind2: Float = 0, lpThunder: Float = 0
    private var windPhase: Float = 0

    private init() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        source = AVAudioSourceNode(format: format) { [unowned self] _, _, frameCount, abl in
            let buffers = UnsafeMutableAudioBufferListPointer(abl)
            for f in 0..<Int(frameCount) {
                let n = Float.random(in: -1...1)
                lpRain += (n - lpRain) * 0.35
                lpWind += (n - lpWind) * 0.02
                lpWind2 += (lpWind - lpWind2) * 0.05
                lpThunder += (n - lpThunder) * 0.004
                windPhase += 0.00003
                let gust = 0.6 + 0.4 * sin(windPhase * 6.28)
                thunderEnv *= 0.99996
                let v = lpRain * rainAmp * 0.5 + lpWind2 * windAmp * 6 * gust + lpThunder * thunderEnv * 14
                for b in buffers {
                    b.mData!.assumingMemoryBound(to: Float.self)[f] = max(-1, min(1, v))
                }
            }
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.5
    }

    func update(_ p: WeatherParams, enabled: Bool, intensity: Double) {
        if enabled && !running {
            do { try engine.start(); running = true } catch { return }
        } else if !enabled && running {
            engine.pause(); running = false
        }
        let k = Float(0.4 + 0.6 * intensity)
        rainAmp = Float(p.rain) * k
        windAmp = Float(min(1, abs(p.wind) + p.snow * 0.15)) * k * 0.6
    }

    func thunder() {
        guard running else { return }
        thunderEnv = Float.random(in: 0.5...1)
    }
}
