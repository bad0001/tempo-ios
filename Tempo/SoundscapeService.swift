//
//  SoundscapeService.swift
//  Tempo
//
//  Tempo 自家音景:不依赖 Apple Music,实时合成白 / 粉 / 棕色噪声.
//  国内用户和无 Apple Music 订阅用户的离线方案.
//
//  实现:AVAudioEngine + AVAudioSourceNode 提供 audio buffer,
//  使用简化 DSP(随机 + 低通滤波器 / 棕色 random walk)生成不同氛围.
//

import Foundation
import AVFoundation
import SwiftUI
import os

@MainActor
@Observable
final class SoundscapeService {
    static let shared = SoundscapeService()

    enum Soundscape: String, CaseIterable, Identifiable, Sendable {
        case rain
        case ocean
        case forest
        case cafe
        case focus
        case fire

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .rain: "雨声"
            case .ocean: "海浪"
            case .forest: "森林"
            case .cafe: "咖啡厅"
            case .focus: "专注白噪"
            case .fire: "篝火"
            }
        }

        var emoji: String {
            switch self {
            case .rain: "🌧️"
            case .ocean: "🌊"
            case .forest: "🌲"
            case .cafe: "☕️"
            case .focus: "📚"
            case .fire: "🔥"
            }
        }

        var color: Color {
            switch self {
            case .rain: TempoTheme.accent
            case .ocean: Color(hex: "0EA5E9")
            case .forest: TempoTheme.success
            case .cafe: Color(hex: "92400E")
            case .focus: Color(hex: "8B5CF6")
            case .fire: Color(hex: "F97316")
            }
        }
    }

    var isPlaying: Bool = false
    var current: Soundscape = .rain
    var volume: Float = 0.5
    var lastError: String?

    @ObservationIgnored
    private let engine = AVAudioEngine()
    @ObservationIgnored
    private var sourceNode: AVAudioSourceNode?

    @ObservationIgnored
    private let modeStorage = OSAllocatedUnfairLock<Soundscape>(initialState: .rain)
    @ObservationIgnored
    private let volumeStorage = OSAllocatedUnfairLock<Float>(initialState: 0.5)

    private init() {
        setupAudioGraph()
    }

    // MARK: - Setup

    private func setupAudioGraph() {
        // standardFormatWithSampleRate 在 Apple 文档明确"对 44.1 / 48 / 16 kHz 永不返回 nil",
        // 但 ! 仍然是审计 P2-11 关注的代码味道 — 用 fallback 防御性写法。
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1) else {
            return
        }

        // closure-local DSP state(单 audio thread 访问,无需 lock)
        var brown: Float = 0
        var lp1: Float = 0
        var lp2: Float = 0
        var oceanPhase: Float = 0

        // 引用读取 main-thread set 的 mode / volume
        let modeRef = modeStorage
        let volRef = volumeStorage

        let source = AVAudioSourceNode { _, _, frameCount, audioBufferList in
            let mode = modeRef.withLock { $0 }
            let vol = volRef.withLock { $0 }

            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for buffer in buffers {
                guard let ptr = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                for frame in 0..<Int(frameCount) {
                    let white = Float.random(in: -1...1)
                    var sample: Float = 0

                    switch mode {
                    case .rain:
                        // 粉红风格:重度低通 + 二阶
                        lp1 = lp1 * 0.96 + white * 0.04
                        lp2 = lp2 * 0.92 + lp1 * 0.08
                        sample = lp2 * 8
                    case .ocean:
                        // 棕色噪声 + 慢调制制造潮汐感(0.05Hz)
                        brown = (brown + 0.02 * white) / 1.02
                        oceanPhase += 0.05 / 44100 * 2 * .pi
                        if oceanPhase > 2 * .pi { oceanPhase -= 2 * .pi }
                        let env = 0.6 + 0.4 * sin(oceanPhase)
                        sample = brown * 3.0 * env
                    case .forest:
                        // 中低通 + 偶尔尖噪点(鸟叫感)
                        lp1 = lp1 * 0.93 + white * 0.07
                        let chirp: Float = (Float.random(in: 0...1) > 0.999) ? Float.random(in: -0.4...0.4) : 0
                        sample = lp1 * 5 + chirp
                    case .cafe:
                        // 白噪声 + 轻低通(轻微沉闷感)
                        lp1 = lp1 * 0.85 + white * 0.15
                        sample = lp1 * 3.2
                    case .focus:
                        // 接近粉红,音量平衡
                        lp1 = lp1 * 0.94 + white * 0.06
                        sample = lp1 * 5.5
                    case .fire:
                        // 棕色 + 偶尔火星爆裂
                        brown = (brown + 0.03 * white) / 1.03
                        let pop: Float = (Float.random(in: 0...1) > 0.997) ? Float.random(in: -0.5...0.5) : 0
                        sample = brown * 2.5 + pop
                    }

                    // soft clip
                    if sample > 1 { sample = 1 }
                    if sample < -1 { sample = -1 }
                    ptr[frame] = sample * vol
                }
            }
            return noErr
        }

        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        sourceNode = source
    }

    // MARK: - Playback

    func play() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            if !engine.isRunning {
                try engine.start()
            }
            isPlaying = true
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            isPlaying = false
        }
    }

    func stop() {
        engine.pause()
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        isPlaying = false
    }

    func toggle() {
        if isPlaying { stop() } else { play() }
    }

    // MARK: - Mode / Volume

    func switchTo(_ sc: Soundscape) {
        current = sc
        modeStorage.withLock { $0 = sc }
    }

    func setVolume(_ v: Float) {
        let clamped = max(0, min(1, v))
        volume = clamped
        volumeStorage.withLock { $0 = clamped }
    }
}
