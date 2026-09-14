//
//  MusicService.swift
//  Tempo
//
//  节奏匹配音乐:根据实时心率 + 心情,推荐节奏匹配的 Apple Music 曲目。
//
//  注意:Apple Music 不公开 BPM 元数据。这里改用「心率 → 心情 → 曲风」的映射:
//   - 心率低 → calm / ambient 关键词搜索
//   - 心率中 → focus / instrumental
//   - 心率高 → energy / upbeat
//  对用户体验等于"BPM 匹配",但合规、可工程化。
//

import Foundation
import SwiftUI
import MusicKit
import Combine

@MainActor
@Observable
final class MusicService {
    static let shared = MusicService()

    @ObservationIgnored
    private var stateCancellable: AnyCancellable?

    enum Authorization {
        case notDetermined, denied, authorized
    }

    var authorization: Authorization = .notDetermined
    var currentRecommendation: Track?
    var recommendedMood: Mood = .focus
    var isLoading: Bool = false
    var isPlaying: Bool = false
    var lastError: String?

    private init() {
        observePlaybackState()
    }

    private func observePlaybackState() {
        let player = ApplicationMusicPlayer.shared
        stateCancellable = player.state.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.isPlaying = player.state.playbackStatus == .playing
            }
    }

    private var cachedSearchResults: [Mood: [Song]] = [:]
    private var lastFetchAt: [Mood: Date] = [:]

    // MARK: - Mood

    enum Mood: String, CaseIterable, Identifiable {
        case relax, focus, energize

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .relax: "舒缓"
            case .focus: "专注"
            case .energize: "活力"
            }
        }

        var symbolName: String {
            switch self {
            case .relax: "moon.fill"
            case .focus: "target"
            case .energize: "bolt.fill"
            }
        }

        var color: Color {
            switch self {
            case .relax: TempoTheme.accent
            case .focus: TempoTheme.success
            case .energize: Color(hex: "F97316")
            }
        }

        // 搜索关键词:对应曲风
        fileprivate var searchTerm: String {
            switch self {
            case .relax: "calm ambient lofi"
            case .focus: "focus instrumental piano"
            case .energize: "upbeat energy workout"
            }
        }

        // 估算 BPM 区间(给 UI 显示用,非真实 BPM 读取)
        var estimatedBPMRange: ClosedRange<Int> {
            switch self {
            case .relax: 50...75
            case .focus: 75...100
            case .energize: 100...140
            }
        }
    }

    // MARK: - Authorization

    func refreshAuthorization() {
        switch MusicAuthorization.currentStatus {
        case .authorized: authorization = .authorized
        case .denied, .restricted: authorization = .denied
        case .notDetermined: authorization = .notDetermined
        @unknown default: authorization = .notDetermined
        }
    }

    func requestAuthorization() async {
        let status = await MusicAuthorization.request()
        switch status {
        case .authorized: authorization = .authorized
        case .denied, .restricted: authorization = .denied
        case .notDetermined: authorization = .notDetermined
        @unknown default: authorization = .notDetermined
        }
    }

    // MARK: - Recommendation

    /// 根据当前心率挑 mood,然后挑曲。
    func recommend(for heartRate: Double, preferredMood: Mood? = nil) async {
        let mood = preferredMood ?? Self.mood(forHeartRate: heartRate)
        recommendedMood = mood
        await fetchRecommendation(mood: mood)
    }

    /// 用户手动切 mood
    func switchMood(_ mood: Mood) async {
        recommendedMood = mood
        await fetchRecommendation(mood: mood)
    }

    private func fetchRecommendation(mood: Mood) async {
        guard authorization == .authorized else { return }
        isLoading = true
        defer { isLoading = false }

        // 1 小时内同 mood 用缓存,避免重复请求
        if let last = lastFetchAt[mood],
           Date().timeIntervalSince(last) < 3600,
           let cached = cachedSearchResults[mood],
           !cached.isEmpty {
            currentRecommendation = cached.randomElement().map(Track.init)
            await syncPlayerQueueIfPlaying()
            return
        }

        do {
            var request = MusicCatalogSearchRequest(term: mood.searchTerm, types: [Song.self])
            request.limit = 25
            let response = try await request.response()
            let songs = Array(response.songs)
            cachedSearchResults[mood] = songs
            lastFetchAt[mood] = Date()
            currentRecommendation = songs.randomElement().map(Track.init)
            lastError = nil
            await syncPlayerQueueIfPlaying()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// 切换推荐曲后,如果当前在播放,把新曲设进 queue 并继续播.
    /// 否则只 reset queue 等用户点 ▶️.
    private func syncPlayerQueueIfPlaying() async {
        guard let song = currentRecommendation?.song else { return }
        let player = ApplicationMusicPlayer.shared
        let wasPlaying = player.state.playbackStatus == .playing
        if wasPlaying {
            player.stop()
        }
        player.queue = [song]
        if wasPlaying {
            try? await player.play()
            isPlaying = true
        } else {
            // 不在播放:queue 已 reset,等下次 togglePlayback 自动用新曲
            isPlaying = false
        }
    }

    // MARK: - Heart rate → Mood mapping

    static func mood(forHeartRate heartRate: Double) -> Mood {
        switch heartRate {
        case ..<70: .relax
        case 70..<95: .focus
        default: .energize
        }
    }

    // MARK: - Playback

    /// 切换播放 / 暂停.每次都 sync queue 跟 currentRecommendation 一致,避免播旧曲.
    func togglePlayback() async {
        let player = ApplicationMusicPlayer.shared
        if player.state.playbackStatus == .playing {
            player.pause()
            isPlaying = false
            return
        }
        // 强制把 currentRecommendation 设进 queue(覆盖旧曲)
        if let song = currentRecommendation?.song {
            player.stop()  // 清当前 queue 状态
            player.queue = [song]
        }
        do {
            try await player.play()
            isPlaying = true
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func stop() {
        let player = ApplicationMusicPlayer.shared
        player.stop()
        isPlaying = false
    }

    /// 跳转 Apple Music App
    var openInAppleMusicURL: URL? {
        currentRecommendation?.appleMusicURL
    }

    // MARK: - Track wrapper

    struct Track: Identifiable {
        let id: String
        let title: String
        let artist: String
        let artworkURL: URL?
        let appleMusicURL: URL?
        fileprivate let song: Song

        init(_ song: Song) {
            self.song = song
            self.id = song.id.rawValue
            self.title = song.title
            self.artist = song.artistName
            self.artworkURL = song.artwork?.url(width: 600, height: 600)
            self.appleMusicURL = song.url
        }
    }
}
