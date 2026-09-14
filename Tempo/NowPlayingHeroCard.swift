//
//  NowPlayingHeroCard.swift
//  Tempo
//
//  压力舒缓建议卡 — 压力分高时主屏自动弹出.
//  根据「已订阅 Apple Music」自动选 transport:订阅 → MusicKit 推荐;否则 → Tempo 内置音景.
//  仅推荐舒缓类(不让用户改 mood),可在同类舒缓中换一首/换氛围.
//

import SwiftUI
import MusicKit

struct NowPlayingHeroCard: View {
    let heartRate: Double
    var isElevated: Bool = false
    var currentStress: Int? = nil

    @State private var music = MusicService.shared
    @State private var soundscape = SoundscapeService.shared
    @AppStorage("user.hasAppleMusic") private var hasAppleMusic: Bool = false
    @State private var didSetupMusic = false

    private var useMusic: Bool { hasAppleMusic }

    private var primaryColor: Color {
        useMusic ? TempoTheme.accent : soundscape.current.color
    }

    private var headerTitle: String {
        isElevated ? "压力上行,试试舒缓" : "音乐 / 音景"
    }

    var body: some View {
        Group {
            if useMusic {
                expandedCard
            } else {
                compactSoundscapeButton
            }
        }
        .animation(.smooth, value: isElevated)
        .task {
            await setupOnAppear()
        }
        .onChange(of: hasAppleMusic) { _, _ in
            // 切换偏好 → 重新初始化
            didSetupMusic = false
            Task { await setupOnAppear() }
        }
    }

    private var expandedCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            content
        }
        .padding(isElevated ? 22 : 18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: isElevated
                            ? [primaryColor.opacity(0.32), primaryColor.opacity(0.08)]
                            : [primaryColor.opacity(0.18), Color.white],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(primaryColor.opacity(isElevated ? 0.45 : 0.20), lineWidth: isElevated ? 2 : 1)
                )
                .shadow(
                    color: isElevated ? primaryColor.opacity(0.30) : Color.black.opacity(0.05),
                    radius: isElevated ? 24 : 18,
                    x: 0, y: isElevated ? 12 : 6
                )
        )
    }

    private var compactSoundscapeButton: some View {
        Button {
            soundscape.toggle()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(soundscape.current.color.opacity(0.14))
                        .frame(width: 44, height: 44)
                    Text(soundscape.current.emoji)
                        .font(.system(size: 23))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("音景")
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(TempoTheme.primaryText)
                    Text(soundscape.isPlaying ? "\(soundscape.current.displayName) 播放中" : "未订阅 Apple Music,可用内置白噪声")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(TempoTheme.tertiaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
                Spacer(minLength: 0)
                Image(systemName: soundscape.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(soundscape.current.color))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.04), radius: 14, y: 5)
            )
        }
        .buttonStyle(.tempoPress)
    }

    private func setupOnAppear() async {
        if useMusic {
            music.refreshAuthorization()
            if music.authorization == .notDetermined {
                await music.requestAuthorization()
            }
            if music.authorization == .authorized && !didSetupMusic {
                await music.recommend(for: heartRate, preferredMood: .relax)
                didSetupMusic = true
            }
        } else {
            // 没订阅 → 默认舒缓音景(雨声),但**不自动播放**(等用户点)
            soundscape.switchTo(.rain)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: useMusic ? "music.note" : "leaf.fill")
                .font(.system(size: isElevated ? 15 : 13, weight: .bold))
                .foregroundStyle(primaryColor)
            Text(LocalizedStringKey(headerTitle))
                .font(.system(size: isElevated ? 15 : 13, weight: .heavy))
                .kerning(0.5)
                .foregroundStyle(TempoTheme.primaryText)
            Spacer()
            if isElevated, let stress = currentStress {
                HStack(spacing: 4) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 9, weight: .bold))
                    Text("\(stress)")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(primaryColor))
            } else {
                Text("Tempo 独占")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(primaryColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(primaryColor.opacity(0.15)))
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if useMusic {
            musicContent
        } else {
            soundscapeContent
        }
    }

    // MARK: - Music (订阅 Apple Music 用户)

    @ViewBuilder
    private var musicContent: some View {
        switch music.authorization {
        case .notDetermined:
            requestMusicAuth
        case .denied:
            musicDenied
        case .authorized:
            musicAuthorized
        }
    }

    private var requestMusicAuth: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("根据你的心率智能推荐舒缓的 Apple Music 曲目。")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(TempoTheme.secondaryText)
            Button {
                Task {
                    await music.requestAuthorization()
                    await setupOnAppear()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 13, weight: .bold))
                    Text("授权 Apple Music")
                        .font(.system(size: 14, weight: .heavy))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(Capsule().fill(TempoTheme.buttonGradient))
            }
            .buttonStyle(.tempoPress)
        }
    }

    private var musicDenied: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Apple Music 权限被拒")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(TempoTheme.primaryText)
            Text("到「设置 → 隐私 → 媒体与 Apple Music」打开,或在「我的 → 偏好设置」关掉 Apple Music 改用 Tempo 音景。")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(TempoTheme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var musicAuthorized: some View {
        VStack(alignment: .leading, spacing: 12) {
            songRow
            heartRateHint
            if let err = music.lastError, !music.isPlaying {
                errorRow(message: err)
            }
        }
    }

    @ViewBuilder
    private var songRow: some View {
        if music.isLoading {
            loadingRow
        } else if let track = music.currentRecommendation {
            playableRow(track: track)
        } else {
            emptyRow
        }
    }

    private func playableRow(track: MusicService.Track) -> some View {
        HStack(spacing: 14) {
            artwork(for: track.artworkURL)
            VStack(alignment: .leading, spacing: 4) {
                Text(track.title)
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(TempoTheme.primaryText)
                    .lineLimit(1)
                Text(track.artist)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(TempoTheme.tertiaryText)
                    .lineLimit(1)
            }
            Spacer()
            // 换一首
            Button {
                Task { await music.switchMood(.relax) }
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(TempoTheme.accent)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(TempoTheme.accentSoft))
            }
            .buttonStyle(.tempoPress)
            // 播放/暂停
            Button {
                Task { await music.togglePlayback() }
            } label: {
                Image(systemName: music.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(TempoTheme.accent))
                    .shadow(color: TempoTheme.accent.opacity(0.35), radius: 10, y: 6)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.tempoPress)
        }
    }

    private func artwork(for url: URL?) -> some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                LinearGradient(
                    colors: [TempoTheme.accent.opacity(0.5), TempoTheme.accent.opacity(0.2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                )
            }
        }
        .frame(width: 60, height: 60)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var loadingRow: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(TempoTheme.accent.opacity(0.15))
                .frame(width: 60, height: 60)
                .overlay(ProgressView().tint(TempoTheme.accent))
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(TempoTheme.tertiaryText.opacity(0.2))
                    .frame(width: 120, height: 14)
                RoundedRectangle(cornerRadius: 4)
                    .fill(TempoTheme.tertiaryText.opacity(0.15))
                    .frame(width: 80, height: 11)
            }
            Spacer()
        }
    }

    private var emptyRow: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(TempoTheme.accent.opacity(0.15))
                .frame(width: 60, height: 60)
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(TempoTheme.accent)
                )
            VStack(alignment: .leading, spacing: 4) {
                Text("暂无推荐").font(.system(size: 14, weight: .heavy))
                Text("点右侧刷新").font(.system(size: 11, weight: .medium)).foregroundStyle(TempoTheme.tertiaryText)
            }
            Spacer()
            Button {
                Task { await music.switchMood(.relax) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(TempoTheme.accent)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(TempoTheme.accentSoft))
            }
            .buttonStyle(.tempoPress)
        }
    }

    private var heartRateHint: some View {
        HStack(spacing: 6) {
            Image(systemName: "heart.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.pink)
            if heartRate > 0 {
                Text("当前心率 \(Int(heartRate)) bpm,推荐 50-75 BPM 节奏")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(TempoTheme.tertiaryText)
                    .lineLimit(1)
            } else {
                Text("等待 Watch 心率")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(TempoTheme.tertiaryText)
            }
            Spacer(minLength: 0)
        }
    }

    private func errorRow(message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(TempoTheme.warning)
                Text(LocalizedStringKey(playbackErrorHint(for: message)))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(TempoTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let url = music.openInAppleMusicURL {
                Link(destination: url) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.right.square.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text("在 Apple Music App 中打开")
                            .font(.system(size: 12, weight: .heavy))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(TempoTheme.accent))
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(TempoTheme.warningSoft.opacity(0.5))
        )
    }

    private func playbackErrorHint(for raw: String) -> String {
        let lowered = raw.lowercased()
        if lowered.contains("subscription") || lowered.contains("subscribe") || lowered.contains("entitle") {
            return "需要 Apple Music 订阅才能播放完整曲目"
        }
        if lowered.contains("network") || lowered.contains("connect") {
            return "网络异常,稍后再试"
        }
        return "播放失败"
    }

    // MARK: - Soundscape (无 Apple Music 订阅 fallback)

    private var soundscapeContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(soundscape.current.color.opacity(0.15))
                        .frame(width: 60, height: 60)
                    Text(soundscape.current.emoji).font(.system(size: 30))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(LocalizedStringKey(soundscape.current.displayName))
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(TempoTheme.primaryText)
                    Text("Tempo 内置 · 无需联网")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(TempoTheme.tertiaryText)
                }
                Spacer()
                // 换一个氛围(在舒缓类切换)
                Button {
                    soundscape.switchTo(nextRelaxingScape())
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(soundscape.current.color)
                        .frame(width: 38, height: 38)
                        .background(Circle().fill(soundscape.current.color.opacity(0.15)))
                }
                .buttonStyle(.tempoPress)
                // 播放/暂停
                Button {
                    soundscape.toggle()
                } label: {
                    Image(systemName: soundscape.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(soundscape.current.color))
                        .shadow(color: soundscape.current.color.opacity(0.35), radius: 10, y: 6)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.tempoPress)
            }
            HStack(spacing: 6) {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(TempoTheme.success)
                Text("订阅了 Apple Music?到「我的 → 偏好设置」切换为音乐推荐")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(TempoTheme.tertiaryText)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
        }
    }

    private func nextRelaxingScape() -> SoundscapeService.Soundscape {
        // 仅在舒缓 / 沉浸类切换;不到 cafe / focus 这种偏专注的
        let calmingScapes: [SoundscapeService.Soundscape] = [.rain, .ocean, .forest, .fire]
        let currentIndex = calmingScapes.firstIndex(of: soundscape.current) ?? -1
        return calmingScapes[(currentIndex + 1) % calmingScapes.count]
    }
}
