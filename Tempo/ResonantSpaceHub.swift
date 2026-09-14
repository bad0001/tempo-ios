//
//  ResonantSpaceHub.swift
//  Tempo
//
//  共振空间 hub:统一入口,容纳稳定的关怀、冥想和后续共振活动。
//

import SwiftUI

// MARK: - Hub View

struct ResonantSpaceHubView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showFriendsList = false
    @State private var showMeditation = false
    @State private var pendingActivity: ResonantActivity?
    @State private var friendsService = FriendsService.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header
                    activityList
                    privacyHint
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
            .scrollIndicators(.hidden)
            .background(TempoTheme.background)
            .navigationTitle("共振空间")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
            .sheet(isPresented: $showFriendsList) {
                FriendsListView()
            }
            .sheet(isPresented: $showMeditation) {
                MeditationFlow()
            }
            .sheet(item: $pendingActivity) { activity in
                ActivityPreviewSheet(activity: activity)
            }
            .task {
                if TempoSession.shared.isLoggedIn {
                    await friendsService.refreshPendingFriendRequests()
                    await friendsService.loadEncourages()
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "8B5CF6").opacity(0.18), Color(hex: "EC4899").opacity(0.10)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 180, height: 180)
                    .blur(radius: 30)
                Image(systemName: "person.2.wave.2.fill")
                    .font(.system(size: 64, weight: .light))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(hex: "8B5CF6"), Color(hex: "EC4899")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            VStack(spacing: 4) {
                Text("和你在意的人共振")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(TempoTheme.primaryText)
                Text("HealthKit 原始数据只留在本机")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(TempoTheme.tertiaryText)
            }
        }
    }

    // MARK: - Activity list

    private var activityList: some View {
        VStack(spacing: 12) {
            ForEach(ResonantActivity.all) { activity in
                Button {
                    handleActivityTap(activity)
                } label: {
                    ActivityCard(activity: activity, badge: badgeFor(activity))
                }
                .buttonStyle(.tempoPress)
            }
        }
    }

    private func badgeFor(_ activity: ResonantActivity) -> Int {
        if activity.id == "care" {
            return FriendsService.shared.unreadEncouragesCount
                + FriendsService.shared.pendingFriendRequestCount
        }
        return 0
    }

    private func handleActivityTap(_ activity: ResonantActivity) {
        guard activity.isLive else {
            pendingActivity = activity
            return
        }
        switch activity.id {
        case "care": showFriendsList = true
        case "meditation": showMeditation = true
        default: pendingActivity = activity
        }
    }

    // MARK: - Privacy hint

    private var privacyHint: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 14))
                .foregroundStyle(TempoTheme.success)
            Text("共振活动不会上传你和朋友的位置。共振关怀会发送压力摘要、关怀事件和推送所需信息;HRV 数值与时间仅在你单独开启同步后上传。")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(TempoTheme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(TempoTheme.successSoft.opacity(0.5))
        )
    }
}

// MARK: - Activity Model

struct ResonantActivity: Identifiable, Hashable {
    let id: String
    let icon: String
    let title: String
    let subtitle: String
    let detailedDescription: String
    let features: [String]
    let gradient: [Color]
    let status: Status
    let isLive: Bool

    enum Status: String {
        case live, beta, experimental, comingSoon

        var label: String {
            switch self {
            case .live: "已上线"
            case .beta: "内测中"
            case .experimental: "实验中"
            case .comingSoon: "敬请期待"
            }
        }

        var color: Color {
            switch self {
            case .live: TempoTheme.success
            case .beta: Color(hex: "F59E0B")
            case .experimental: Color(hex: "F97316")
            case .comingSoon: TempoTheme.tertiaryText
            }
        }
    }

    static let all: [ResonantActivity] = [
        // 共振呼吸 P2P 已废弃 — 改成在「共振关怀 → 关怀面板」里推送呼吸训练给密友(异步).
        ResonantActivity(
            id: "meditation",
            icon: "leaf.fill",
            title: "静坐冥想",
            subtitle: "5 / 10 / 15 / 20 分钟独自冥想",
            detailedDescription: "选一段时间安静坐着,跟随圆环呼吸。结束后会自动写入 Apple Health 的正念时长。\n\n双人同步冥想模式将在未来版本上线。",
            features: [
                "5 / 10 / 15 / 20 分钟可选",
                "全屏圆环倒计时,沉浸不分心",
                "完成后写入 Apple Health · 正念时长",
                "累计统计在「我的」页面显示"
            ],
            gradient: [Color(hex: "10B981"), Color(hex: "059669")],
            status: .live,
            isLive: true
        ),
        ResonantActivity(
            id: "care",
            icon: "heart.fill",
            title: "共振关怀",
            subtitle: "朋友压力高时收到提醒 · 一键发鼓励",
            detailedDescription: "通过 Tempo 共振 ID 跟家人 / 伴侣连接(无需通话)。对方压力上行或发来心跳时,你收到温柔提醒,可一键发预设鼓励语或自己写一句。",
            features: [
                "HealthKit 原始数据只留在本机",
                "压力摘要和关怀通知走 Tempo 后端",
                "8 条预设鼓励语 + 自由编写",
                "随时可在共振设置里静音或解除绑定"
            ],
            gradient: [Color(hex: "EC4899"), Color(hex: "F59E0B")],
            status: .live,
            isLive: true
        ),
        ResonantActivity(
            id: "challenge",
            icon: "flag.checkered",
            title: "共振挑战",
            subtitle: "和家人 / 朋友连续呼吸打卡",
            detailedDescription: "邀请最多 5 个人组建挑战小组,每天有人完成 3 分钟呼吸训练就算一次共振。连续打卡解锁徽章。",
            features: [
                "支持 2-5 人小组",
                "每日呼吸训练 ≥ 3 分钟即算共振",
                "连续 7 / 14 / 30 / 100 天 4 个徽章",
                "可看小组每个成员的连续天数"
            ],
            gradient: [Color(hex: "F59E0B"), Color(hex: "F97316")],
            status: .comingSoon,
            isLive: false
        )
    ]
}

// MARK: - Activity Card

private struct ActivityCard: View {
    let activity: ResonantActivity
    var badge: Int = 0

    var body: some View {
        HStack(spacing: 14) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: activity.gradient,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 50, height: 50)
                    Image(systemName: activity.icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                }
                if badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(minWidth: 16, minHeight: 16)
                        .padding(.horizontal, 4)
                        .background(Capsule().fill(Color.pink))
                        .overlay(Capsule().stroke(Color.white, lineWidth: 2))
                        .offset(x: 4, y: -4)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(LocalizedStringKey(activity.title))
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(TempoTheme.primaryText)
                    Text(LocalizedStringKey(activity.status.label))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(activity.status.color))
                }
                Text(LocalizedStringKey(activity.subtitle))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(TempoTheme.tertiaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            Spacer()

            Image(systemName: activity.isLive ? "chevron.right" : "lock.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(activity.isLive ? activity.gradient[0] : TempoTheme.tertiaryText)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.04), radius: 12, y: 4)
        )
        .opacity(activity.isLive ? 1.0 : 0.85)
    }
}

// MARK: - Activity Preview Sheet

private struct ActivityPreviewSheet: View {
    let activity: ResonantActivity
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: activity.gradient.map { $0.opacity(0.18) },
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 140, height: 140)
                            .blur(radius: 20)
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: activity.gradient,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 100, height: 100)
                            .shadow(color: activity.gradient[0].opacity(0.4), radius: 20, y: 10)
                        Image(systemName: activity.icon)
                            .font(.system(size: 42, weight: .light))
                            .foregroundStyle(.white)
                    }
                    .padding(.top, 16)

                    VStack(spacing: 6) {
                        Text(LocalizedStringKey(activity.title))
                            .font(.system(size: 26, weight: .heavy, design: .rounded))
                            .foregroundStyle(TempoTheme.primaryText)
                        Text(LocalizedStringKey(activity.status.label))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(activity.gradient[0])
                    }

                    Text(LocalizedStringKey(activity.detailedDescription))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(TempoTheme.secondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 24)

                    if !activity.features.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(activity.features, id: \.self) { feature in
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 18))
                                        .foregroundStyle(activity.gradient[0])
                                    Text(LocalizedStringKey(feature))
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(TempoTheme.primaryText)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(Color.white)
                                .shadow(color: Color.black.opacity(0.04), radius: 14, y: 4)
                        )
                        .padding(.horizontal, 20)
                    }

                    Text("即将通过 Tempo 1.x 更新推送")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(TempoTheme.tertiaryText)
                        .padding(.bottom, 20)
                }
                .padding(.horizontal, 20)
            }
            .background(TempoTheme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
