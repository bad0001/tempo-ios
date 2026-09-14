//
//  DriftBottleView.swift
//  Tempo
//
//  压力漂流瓶 — 高压时把一句心事放进海面,别人主动接住并回一句。
//

import SwiftUI
import TempoCore
#if canImport(UIKit)
import UIKit
#endif

struct DriftBottleView: View {
    @Environment(\.locale) private var locale
    let initialBottleID: String?
    let initialReplyID: String?

    @State private var session = TempoSession.shared
    @State private var seaBottles: [StressBottle] = []
    @State private var myBottles: [StressBottle] = []
    @State private var selectedBottle: StressBottle?
    @State private var selectedOwnBottle: StressBottle?
    @State private var message = ""
    @State private var selectedMood: BottleMood = .tired
    @State private var anonymous = true
    @State private var currentStress: StressScore?
    @State private var isLoading = false
    @State private var bottleState: TempoLoadState = .idle
    @State private var isSending = false
    @State private var statusText: String?
    @State private var showSelfHarmHotline = false
    @State private var handledInitialBottle = false
    @State private var seenReplyIDs: Set<String> = {
        Set(UserDefaults.standard.stringArray(forKey: "bottles.seenReplyIDs") ?? [])
    }()

    /// 标识"我有几条没看过的回复"用作 mine card badge
    private var unreadReplyCount: Int {
        myBottles.compactMap { $0.reply?.replyId }.filter { !seenReplyIDs.contains($0) }.count
    }

    private var trimmedMessage: String {
        message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canThrowBottle: Bool {
        session.isLoggedIn && trimmedMessage.count >= 4 && !isSending
    }

    private var messageProgressText: String {
        if locale.tempoUsesEnglish {
            if trimmedMessage.isEmpty { return "At least 4 characters · Up to 3 bottles per day" }
            if trimmedMessage.count < 4 { return "Add \(4 - trimmedMessage.count) more characters" }
            return "\(trimmedMessage.count)/500 · Ready to send"
        }
        if trimmedMessage.isEmpty { return "至少 4 个字 · 每天最多 3 个" }
        if trimmedMessage.count < 4 { return "还差 \(4 - trimmedMessage.count) 个字就可以放进海里" }
        return "\(trimmedMessage.count)/500 · 可以放进海里"
    }

    init(initialBottleID: String? = nil, initialReplyID: String? = nil) {
        self.initialBottleID = initialBottleID
        self.initialReplyID = initialReplyID
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                TempoTheme.background
                    .ignoresSafeArea()
                coastBackdrop

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 16) {
                            DriftBottleHeroCard(
                                currentStress: currentStress,
                                bottles: seaBottles,
                                isLoading: isLoading,
                                onRefresh: {
                                    Task { await loadBottles() }
                                }
                            )
                            .accessibilityElement(children: .contain)

                            TempoDataStateView(
                                state: bottleState,
                                loadingTitle: "正在连接回声海岸",
                                emptyTitle: "海面暂时很安静",
                                emptyDetail: "现在没有新的瓶子，你仍然可以先放下一句心事。",
                                cachedTitle: "正在显示离线海岸",
                                showsEmpty: false,
                                onRetry: { Task { await loadBottles() } }
                            )
                            .padding(.horizontal, 20)

                            composerCard
                                .padding(.horizontal, 20)
                                .onChange(of: statusText) { _, new in
                                    // 投瓶成功后(statusText 含"放进海里")自动滚到「我的回声」
                                    if let new, new.contains("放进海里") {
                                        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                            proxy.scrollTo("mineCard", anchor: .top)
                                        }
                                    }
                                }

                            seaCard.padding(.horizontal, 20)
                            mineCard.padding(.horizontal, 20)
                            safetyCard.padding(.horizontal, 20)
                            Spacer(minLength: 100)
                        }
                        .padding(.top, 0)
                    }
                    .scrollIndicators(.hidden)
                    .scrollDismissesKeyboard(.interactively)
                    .refreshable {
                        await loadContext()
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .task {
                await loadContext()
            }
            .sheet(item: $selectedBottle) { bottle in
                BottleReplySheet(
                    bottle: bottle,
                    onReply: { text in
                        await reply(to: bottle, message: text)
                    },
                    onReport: { reason in
                        await report(bottle, reason: reason)
                    },
                    onBlock: {
                        await blockAuthor(of: bottle)
                    }
                )
            }
            .sheet(item: $selectedOwnBottle) { bottle in
                MyBottleDetailSheet(
                    bottle: bottle,
                    onDelete: {
                        await deleteMyBottle(bottle)
                    },
                    onReportReply: { reason in
                        await reportReply(in: bottle, reason: reason)
                    },
                    onBlockReplier: {
                        await blockReplier(in: bottle)
                    }
                )
            }
            .sheet(isPresented: $showSelfHarmHotline) {
                SelfHarmHotlineSheet()
            }
        }
    }

    private var coastBackdrop: some View {
        GeometryReader { proxy in
            Image("EchoCoastBackground")
                .resizable()
                .scaledToFill()
                .frame(width: proxy.size.width, height: 690, alignment: .top)
                .clipped()
                .overlay(alignment: .top) {
                    LinearGradient(
                        colors: [.white.opacity(0.18), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 210)
                }
                .overlay(alignment: .bottom) {
                    LinearGradient(
                        stops: [
                            .init(color: TempoTheme.background.opacity(0), location: 0),
                            .init(color: TempoTheme.background.opacity(0.50), location: 0.48),
                            .init(color: TempoTheme.background, location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 270)
                }
        }
        .frame(height: 690)
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var composerCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                SoftIconBubble(systemName: "water.waves", color: TempoTheme.accent, size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text("写下此刻")
                        .font(.system(size: 17, weight: .heavy))
                        .foregroundStyle(TempoTheme.primaryText)
                    Text("每天 3 次 · 每次只收一条回声")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(TempoTheme.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            moodPicker

            ZStack(alignment: .topLeading) {
                TextEditor(text: $message)
                    .scrollContentBackground(.hidden)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(TempoTheme.primaryText)
                    .frame(minHeight: 118)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(hex: "F8FAFC"))
                    )
                if message.isEmpty {
                    Text("写下现在最想被接住的一句话...")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(TempoTheme.tertiaryText)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 18)
                        .allowsHitTesting(false)
                }
            }

            HStack {
                Text(messageProgressText)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(canThrowBottle ? TempoTheme.success : TempoTheme.tertiaryText)
                Spacer()
            }
            .accessibilityLabel(messageProgressText)

            HStack(spacing: 10) {
                Toggle(isOn: $anonymous) {
                    Text("匿名")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(TempoTheme.secondaryText)
                }
                .toggleStyle(.switch)

                Spacer()

                Button {
                    Task { await throwBottle() }
                } label: {
                    Group {
                        if isSending {
                            ProgressView().tint(.white)
                        } else {
                            Label("放进海里", systemImage: "paperplane.fill")
                                .font(.system(size: 13, weight: .heavy))
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(height: 44)
                    .background(
                        Capsule().fill(canThrowBottle ? TempoTheme.buttonGradient : LinearGradient(colors: [TempoTheme.tertiaryText], startPoint: .leading, endPoint: .trailing))
                    )
                }
                .buttonStyle(.tempoPress(.medium))
                .disabled(!session.isLoggedIn || isSending)
                .accessibilityLabel("投放漂流瓶")
                .accessibilityHint(canThrowBottle ? TempoLocalization.string("把你写的心事放到海面", locale: locale) : messageProgressText)
            }

            if !session.isLoggedIn {
                Button {
                    NotificationCenter.default.post(name: .tempoOpenResonantSettings, object: nil, userInfo: [:])
                } label: {
                    Label("登录后才能投瓶和回复", systemImage: "person.crop.circle.badge.checkmark")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(TempoTheme.accent)
                }
                .buttonStyle(.tempoPress)
                .accessibilityLabel("登录")
                .accessibilityHint("用 Apple ID 登录后才能投瓶和回复")
            }

            if let statusText {
                Text(statusText)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(
                        statusText.contains("失败")
                        || statusText.contains("不能")
                        || statusText.contains("还差")
                        || statusText.contains("请先")
                        ? TempoTheme.danger : TempoTheme.success
                    )
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tempoCard(radius: 22, padding: 16)
    }

    private var moodPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(BottleMood.allCases) { mood in
                    Button {
                        selectedMood = mood
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: mood.icon)
                                .font(.system(size: 11, weight: .bold))
                            Text(LocalizedStringKey(mood.rawValue))
                                .font(.system(size: 12, weight: .heavy))
                        }
                        .foregroundStyle(selectedMood == mood ? .white : mood.color)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(selectedMood == mood ? mood.color : mood.color.opacity(0.10))
                        )
                    }
                    .buttonStyle(.tempoPress)
                    .accessibilityLabel("\(TempoLocalization.string(mood.rawValue, locale: locale)) \(locale.tempoUsesEnglish ? "mood" : "心情标签")")
                    .accessibilityHint(TempoLocalization.string(selectedMood == mood ? "已选" : "点击选择", locale: locale))
                    .accessibilityAddTraits(selectedMood == mood ? .isSelected : [])
                }
            }
        }
    }

    private var seaCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("海面", systemImage: "sparkles")
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(TempoTheme.primaryText)
                Spacer()
                Button {
                    Task { await loadBottles() }
                } label: {
                    Image(systemName: isLoading ? "hourglass" : "arrow.clockwise")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(TempoTheme.accent)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(TempoTheme.accentSoft))
                }
                .buttonStyle(.tempoPress)
                .accessibilityLabel("刷新海面")
                .accessibilityHint("捞一批新的漂流瓶")
            }

            if seaBottles.isEmpty {
                EmptySeaView(isLoading: isLoading)
            } else {
                VStack(spacing: 10) {
                    ForEach(seaBottles.prefix(4)) { bottle in
                        Button {
                            selectedBottle = bottle
                        } label: {
                            BottleRow(bottle: bottle, compact: false)
                        }
                        .buttonStyle(.tempoPress)
                        .accessibilityLabel("\(bottle.moodTag) 标签的漂流瓶,来自 \(bottle.authorName)")
                        .accessibilityHint("点击查看完整内容并回复一句")
                    }
                }
            }
        }
        .tempoCard(radius: 22, padding: 16)
    }

    private var mineCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Label("我的回声", systemImage: "tray.full.fill")
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(TempoTheme.primaryText)
                if unreadReplyCount > 0 {
                    Text("\(unreadReplyCount) 条新回复")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.pink))
                        .accessibilityLabel("有 \(unreadReplyCount) 条新回复")
                }
                Spacer()
                if unreadReplyCount > 0 {
                    Button("全部标已读") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            markRepliesAsSeen()
                        }
                    }
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(TempoTheme.accent)
                    .buttonStyle(.tempoPress)
                    .accessibilityHint("把所有新回复标记为已读")
                }
            }

            if myBottles.isEmpty {
                    Text("你投出的瓶子和收到的回声。")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(TempoTheme.tertiaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 10) {
                    ForEach(myBottles.prefix(4)) { bottle in
                        Button {
                            openMyBottle(bottle)
                        } label: {
                            BottleRow(
                                bottle: bottle,
                                compact: true,
                                isReplyUnread: bottle.reply.map { !seenReplyIDs.contains($0.replyId) } ?? false
                            )
                        }
                        .buttonStyle(.tempoPress)
                        .accessibilityLabel("\(bottle.moodTag)漂流瓶,\(bottle.reply == nil ? "还在等待回声" : "已收到回声")")
                        .accessibilityHint("打开详情,可查看回复或删除这个瓶子")
                    }
                }
            }
        }
        .tempoCard(radius: 22, padding: 16)
        .id("mineCard")    // 让 ScrollViewReader 投瓶后能滚到这里
    }

    private var safetyCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(TempoTheme.success)
            Text("漂流瓶不是紧急求助或医疗服务。遇到人身危险、自伤冲动或持续极端痛苦,请立即联系身边可信的人或当地紧急救助。")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(TempoTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .tempoCard(radius: 16, padding: 14)
    }

    private func loadContext() async {
        await loadCurrentStress()
        await loadBottles()
    }

    private func loadCurrentStress() async {
        let hr = (try? await HealthKitService.shared.fetchLatestHeartRate()) ?? 0
        let hrv = try? await HealthKitService.shared.fetchLatestHRV()
        guard hr > 0 || hrv != nil else {
            currentStress = nil
            return
        }
        let evaluated = await HealthKitService.shared.evaluateCurrentStress(hr: hr, hrv: hrv)
        currentStress = evaluated.score
    }

    private func loadBottles() async {
        guard session.isLoggedIn else {
            seaBottles = []
            myBottles = []
            bottleState = .empty
            return
        }
        if seaBottles.isEmpty, myBottles.isEmpty, let cached = readBottleCache() {
            seaBottles = cached.sea
            myBottles = cached.mine
            bottleState = .cached(cached.updatedAt)
        } else if seaBottles.isEmpty && myBottles.isEmpty {
            bottleState = .loading
        }
        isLoading = true
        defer { isLoading = false }
        do {
            async let sea = TempoAPIClient.shared.seaBottles(limit: 8)
            async let mine = TempoAPIClient.shared.myBottles(limit: 12)
            let result = try await (sea, mine)
            seaBottles = result.0.bottles
            myBottles = result.1.bottles
            let now = Date()
            writeBottleCache(sea: seaBottles, mine: myBottles, updatedAt: now)
            bottleState = seaBottles.isEmpty && myBottles.isEmpty ? .empty : .ready(now)
            if statusText?.hasPrefix("海面暂时连不上") == true {
                statusText = nil
            }
            openInitialBottleIfNeeded()
        } catch {
            let message = TempoErrorCopy.message(for: error)
            if !seaBottles.isEmpty || !myBottles.isEmpty {
                bottleState = .cached(readBottleCache()?.updatedAt)
            } else {
                bottleState = .failed(message)
            }
        }
    }

    private struct BottleCacheEnvelope: Codable {
        let sea: [StressBottle]
        let mine: [StressBottle]
        let updatedAt: Date
    }

    private var bottleCacheKey: String? {
        guard let userId = session.userId, !userId.isEmpty else { return nil }
        return "bottles.snapshot.\(userId)"
    }

    private func readBottleCache() -> BottleCacheEnvelope? {
        guard let key = bottleCacheKey,
              let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(BottleCacheEnvelope.self, from: data)
    }

    private func writeBottleCache(sea: [StressBottle], mine: [StressBottle], updatedAt: Date) {
        guard let key = bottleCacheKey,
              let data = try? JSONEncoder().encode(
                BottleCacheEnvelope(
                    sea: Array(sea.prefix(20)),
                    mine: Array(mine.prefix(20)),
                    updatedAt: updatedAt
                )
              ) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private func throwBottle() async {
        guard session.isLoggedIn else {
            statusText = "请先登录后再投瓶。"
            return
        }
        guard trimmedMessage.count >= 4 else {
            statusText = trimmedMessage.isEmpty
                ? "至少写 4 个字,再放进海里。"
                : "还差 \(4 - trimmedMessage.count) 个字,再放进海里。"
            #if canImport(UIKit)
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            #endif
            return
        }
        guard !isSending else { return }
        let trimmed = trimmedMessage
        isSending = true
        statusText = nil
        defer { isSending = false }
        do {
            _ = try await TempoAPIClient.shared.createStressBottle(
                stressScore: currentStress?.value,
                stressLevel: currentStress?.level.rawValue,
                moodTag: selectedMood.rawValue,
                message: trimmed,
                anonymous: anonymous
            )
            #if canImport(UIKit)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            #endif
            message = ""
            statusText = "已经放进海里,你的瓶子在「我的回声」里。"
            await loadBottles()
        } catch {
            handleBottleError(error, prefix: "投瓶失败")
        }
    }

    /// 统一错误处理:识别 self_harm code 弹热线 sheet,其他普通错误展示 statusText
    private func handleBottleError(_ error: Error, prefix: String) {
        #if canImport(UIKit)
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        #endif
        if let apiError = error as? APIError, apiError.serverCode == "self_harm" {
            showSelfHarmHotline = true
            statusText = nil
            return
        }
        statusText = "\(prefix):\((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
    }

    private func reply(to bottle: StressBottle, message: String) async {
        do {
            _ = try await TempoAPIClient.shared.replyToBottle(bottle.bottleId, message: message)
            #if canImport(UIKit)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            #endif
            selectedBottle = nil
            await loadBottles()
        } catch {
            handleBottleError(error, prefix: "回复失败")
        }
    }

    /// 标已读:把当前 myBottles 所有 reply.replyId 加入 seen set,清零 badge
    func markRepliesAsSeen() {
        for bottle in myBottles {
            if let id = bottle.reply?.replyId { seenReplyIDs.insert(id) }
        }
        UserDefaults.standard.set(Array(seenReplyIDs), forKey: "bottles.seenReplyIDs")
    }

    private func openMyBottle(_ bottle: StressBottle) {
        selectedOwnBottle = bottle
        if let replyID = bottle.reply?.replyId {
            seenReplyIDs.insert(replyID)
            UserDefaults.standard.set(Array(seenReplyIDs), forKey: "bottles.seenReplyIDs")
        }
    }

    private func openInitialBottleIfNeeded() {
        guard !handledInitialBottle else { return }
        guard let initialBottleID, !initialBottleID.isEmpty else {
            handledInitialBottle = true
            return
        }
        guard let bottle = myBottles.first(where: { $0.bottleId == initialBottleID }) else {
            handledInitialBottle = true
            statusText = "这条回声已经不在我的瓶子里了。"
            return
        }
        handledInitialBottle = true
        if let initialReplyID,
           let reply = bottle.reply,
           reply.replyId == initialReplyID {
            seenReplyIDs.insert(initialReplyID)
            UserDefaults.standard.set(Array(seenReplyIDs), forKey: "bottles.seenReplyIDs")
        }
        selectedOwnBottle = bottle
    }

    private func deleteMyBottle(_ bottle: StressBottle) async -> Bool {
        do {
            try await TempoAPIClient.shared.deleteBottle(bottle.bottleId)
            myBottles.removeAll { $0.bottleId == bottle.bottleId }
            seaBottles.removeAll { $0.bottleId == bottle.bottleId }
            if let replyID = bottle.reply?.replyId {
                seenReplyIDs.remove(replyID)
                UserDefaults.standard.set(Array(seenReplyIDs), forKey: "bottles.seenReplyIDs")
            }
            selectedOwnBottle = nil
            statusText = "这个瓶子已从海面和我的回声中删除。"
            #if canImport(UIKit)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            #endif
            return true
        } catch {
            handleBottleError(error, prefix: "删除失败")
            return false
        }
    }

    private func report(_ bottle: StressBottle, reason: String) async {
        do {
            try await TempoAPIClient.shared.reportBottle(bottle.bottleId, reason: reason)
            #if canImport(UIKit)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            #endif
            selectedBottle = nil
            seaBottles.removeAll { $0.id == bottle.id }
            statusText = "已收到举报,这个瓶子不会再显示给你。"
        } catch {
            statusText = "举报失败:\(error.localizedDescription)"
        }
    }

    private func blockAuthor(of bottle: StressBottle) async {
        do {
            try await TempoAPIClient.shared.blockBottleAuthor(bottle.bottleId)
            #if canImport(UIKit)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            #endif
            selectedBottle = nil
            seaBottles.removeAll { $0.authorUserId == bottle.authorUserId }
            statusText = "已屏蔽这个用户。"
        } catch {
            statusText = "屏蔽失败:\(error.localizedDescription)"
        }
    }

    private func reportReply(in bottle: StressBottle, reason: String) async -> Bool {
        do {
            try await TempoAPIClient.shared.reportBottleReply(bottle.bottleId, reason: reason)
            if let replyID = bottle.reply?.replyId {
                seenReplyIDs.remove(replyID)
                UserDefaults.standard.set(Array(seenReplyIDs), forKey: "bottles.seenReplyIDs")
            }
            selectedOwnBottle = nil
            await loadBottles()
            statusText = "已举报并收起这条回声。"
            #if canImport(UIKit)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            #endif
            return true
        } catch {
            handleBottleError(error, prefix: "举报回声失败")
            return false
        }
    }

    private func blockReplier(in bottle: StressBottle) async -> Bool {
        do {
            try await TempoAPIClient.shared.blockBottleReplier(bottle.bottleId)
            if let replyID = bottle.reply?.replyId {
                seenReplyIDs.remove(replyID)
                UserDefaults.standard.set(Array(seenReplyIDs), forKey: "bottles.seenReplyIDs")
            }
            selectedOwnBottle = nil
            await loadBottles()
            statusText = "已屏蔽并收起这个用户的回声。"
            #if canImport(UIKit)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            #endif
            return true
        } catch {
            handleBottleError(error, prefix: "屏蔽失败")
            return false
        }
    }
}

private enum BottleMood: String, CaseIterable, Identifiable {
    case tired = "疲惫"
    case anxious = "焦虑"
    case wronged = "委屈"
    case insomnia = "失眠"
    case lonely = "想被抱抱"
    case overloaded = "撑不住"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .tired: "battery.25"
        case .anxious: "waveform.path.ecg"
        case .wronged: "cloud.rain.fill"
        case .insomnia: "moon.zzz.fill"
        case .lonely: "heart.fill"
        case .overloaded: "bolt.trianglebadge.exclamationmark.fill"
        }
    }

    var color: Color {
        switch self {
        case .tired: TempoTheme.accent
        case .anxious: TempoTheme.warning
        case .wronged: Color(hex: "38BDF8")
        case .insomnia: Color(hex: "7C3AED")
        case .lonely: Color.pink
        case .overloaded: TempoTheme.danger
        }
    }
}

private struct DriftBottleHeroCard: View {
    let currentStress: StressScore?
    let bottles: [StressBottle]
    let isLoading: Bool
    let onRefresh: () -> Void

    var body: some View {
        sceneChrome
            .frame(height: 500)
    }

    private var sceneChrome: some View {
        VStack {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("回声海岸")
                        .font(.system(size: 31, weight: .black, design: .rounded))
                        .foregroundStyle(Color(hex: "0F172A"))
                    Text("把这一刻放进海里。")
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(Color(hex: "155E75").opacity(0.82))
                        .fixedSize(horizontal: false, vertical: true)

                    Button(action: onRefresh) {
                        HStack(spacing: 6) {
                            Image(systemName: isLoading ? "hourglass" : "arrow.clockwise")
                                .font(.system(size: 11, weight: .black))
                            Text(LocalizedStringKey(isLoading ? "正在看海面" : "换一批"))
                                .font(.system(size: 11, weight: .heavy))
                        }
                        .foregroundStyle(Color(hex: "075985"))
                        .padding(.horizontal, 11)
                        .frame(height: 34)
                        .background(Capsule().fill(.white.opacity(0.64)))
                        .overlay(Capsule().stroke(.white.opacity(0.72), lineWidth: 1))
                    }
                    .buttonStyle(.tempoPress)
                    .accessibilityLabel("刷新海面瓶子")
                }
                Spacer()
            }
            .padding(.leading, 20)
            .padding(.trailing, 20)
            .padding(.top, 24)

            Spacer()

            HStack(spacing: 10) {
                heroMetric(title: "当前压力", value: currentStress.map { "\($0.value)" } ?? "—", unit: "/100")
                heroMetric(title: "海面", value: "\(bottles.count)", unit: "个")
                heroMetric(title: "频率上限", value: "3", unit: "每天")
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
        }
    }

    private func heroMetric(title: String, value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 9, weight: .heavy))
                .foregroundStyle(Color(hex: "075985").opacity(0.62))
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(Color(hex: "0F172A"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(LocalizedStringKey(unit))
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(Color(hex: "075985").opacity(0.72))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(0.62))
                .shadow(color: Color(hex: "075985").opacity(0.08), radius: 10, y: 4)
        )
    }
}

private struct BottleRow: View {
    let bottle: StressBottle
    let compact: Bool
    var isReplyUnread: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(moodColor.opacity(0.14))
                    .frame(width: 44, height: 44)
                Image(systemName: "message.badge.waveform.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(moodColor)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(LocalizedStringKey(bottle.moodTag))
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(moodColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(moodColor.opacity(0.11)))
                    if let score = bottle.stressScore {
                        Text("压力 \(score)")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(TempoTheme.secondaryText)
                    }
                    // 隐藏 / 删除 状态标签(让作者知道为什么这个瓶不出现在 sea)
                    if bottle.status == "hidden" {
                        statusPill(label: "被举报隐藏", color: TempoTheme.warning)
                    } else if bottle.status == "expired" {
                        statusPill(label: "已过期", color: TempoTheme.tertiaryText)
                    } else if bottle.status == "replied" {
                        statusPill(label: "已被接住", color: TempoTheme.success)
                    }
                    Spacer(minLength: 0)
                    Text(bottle.formattedTime)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(TempoTheme.tertiaryText)
                }

                Text(bottle.message)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(TempoTheme.primaryText)
                    .lineLimit(compact ? 2 : 3)
                    .fixedSize(horizontal: false, vertical: true)

                if let reply = bottle.reply {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(TempoTheme.accent.opacity(0.8))
                            .padding(.top, 2)
                        Text("回声: \(reply.message)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(TempoTheme.accent)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        if isReplyUnread {
                            Circle()
                                .fill(Color.pink)
                                .frame(width: 7, height: 7)
                                .padding(.top, 4)
                                .accessibilityLabel("未读")
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(hex: "F8FAFC"))
        )
    }

    private func statusPill(label: String, color: Color) -> some View {
        Text(LocalizedStringKey(label))
            .font(.system(size: 9, weight: .heavy))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.12)))
    }

    private var moodColor: Color {
        BottleMood(rawValue: bottle.moodTag)?.color ?? TempoTheme.accent
    }
}

private struct EmptySeaView: View {
    let isLoading: Bool

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: isLoading ? "hourglass" : "water.waves")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(TempoTheme.accent)
            Text(LocalizedStringKey(isLoading ? "正在看海面" : "现在海面很安静"))
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(TempoTheme.primaryText)
            Text("只有来到海岸的人会看见这些瓶子。")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(TempoTheme.tertiaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(hex: "F8FAFC"))
        )
    }
}

private struct MyBottleDetailSheet: View {
    let bottle: StressBottle
    let onDelete: () async -> Bool
    let onReportReply: (String) async -> Bool
    let onBlockReplier: () async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var deleteError: String?
    @State private var showReplyReport = false
    @State private var showBlockConfirmation = false
    @State private var isModeratingReply = false
    @State private var moderationError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    BottleRow(bottle: bottle, compact: false)
                    echoStateCard
                    deleteCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 36)
            }
            .scrollIndicators(.hidden)
            .background(TempoTheme.background)
            .navigationTitle("我的瓶子")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .font(.system(size: 14, weight: .heavy))
                }
            }
            .confirmationDialog(
                "删除这个瓶子?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("删除瓶子和回声", role: .destructive) {
                    Task {
                        isDeleting = true
                        deleteError = nil
                        let deleted = await onDelete()
                        isDeleting = false
                        if deleted { dismiss() }
                        else { deleteError = "删除没有完成,请稍后重试。" }
                    }
                }
                Button("保留", role: .cancel) {}
            } message: {
                Text("删除后不再出现在海面或“我的回声”中。")
            }
            .confirmationDialog("为什么举报这条回声?", isPresented: $showReplyReport, titleVisibility: .visible) {
                Button("骚扰或广告") { moderateReply(reason: "spam") }
                Button("攻击、辱骂或歧视") { moderateReply(reason: "abuse") }
                Button("色情或不适内容") { moderateReply(reason: "sexual") }
                Button("自伤或紧急危险内容") { moderateReply(reason: "self_harm") }
                Button("其他原因") { moderateReply(reason: "other") }
                Button("取消", role: .cancel) {}
            }
            .confirmationDialog("屏蔽这个回声用户?", isPresented: $showBlockConfirmation, titleVisibility: .visible) {
                Button("屏蔽并收起回声", role: .destructive) {
                    Task {
                        isModeratingReply = true
                        moderationError = nil
                        let completed = await onBlockReplier()
                        isModeratingReply = false
                        if completed { dismiss() }
                        else { moderationError = "屏蔽没有完成,请稍后重试。" }
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("以后你不会再看到这个用户的漂流瓶,这条回声也会立即收起。")
            }
        }
    }

    @ViewBuilder
    private var echoStateCard: some View {
        if let reply = bottle.reply {
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(.white.opacity(0.84))
                            .frame(width: 42, height: 42)
                        Image(systemName: "sparkles")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(Color(hex: "0E7490"))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("有人接住了你")
                            .font(.system(size: 17, weight: .heavy))
                            .foregroundStyle(Color(hex: "164E63"))
                        Text("\(reply.fromName) · \(replyDateText(reply.createdAt))")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(hex: "155E75").opacity(0.72))
                    }
                }
                Text(reply.message)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(hex: "164E63"))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(15)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .fill(.white.opacity(0.72))
                    )
                Text("这条回声到这里就收束,不会自动变成陌生人聊天。")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(hex: "155E75").opacity(0.72))
                HStack(spacing: 10) {
                    Button {
                        showReplyReport = true
                    } label: {
                        Label("举报回声", systemImage: "exclamationmark.bubble.fill")
                            .frame(maxWidth: .infinity)
                    }
                    Button {
                        showBlockConfirmation = true
                    } label: {
                        Label("屏蔽用户", systemImage: "hand.raised.fill")
                            .frame(maxWidth: .infinity)
                    }
                }
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(Color(hex: "155E75"))
                .buttonStyle(.tempoPress)
                .disabled(isModeratingReply)
                if isModeratingReply {
                    ProgressView("正在处理...")
                        .font(.system(size: 11, weight: .semibold))
                        .tint(Color(hex: "0E7490"))
                }
                if let moderationError {
                    Text(moderationError)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(TempoTheme.danger)
                }
            }
            .padding(17)
            .background(
                LinearGradient(
                    colors: [Color(hex: "DFF5FF"), Color(hex: "E8F7F2"), Color(hex: "FFF5E5")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 23, style: .continuous)
                    .stroke(.white.opacity(0.82), lineWidth: 1)
            )
        } else if bottle.status == "replied" {
            HStack(alignment: .top, spacing: 12) {
                SoftIconBubble(systemName: "eye.slash.fill", color: TempoTheme.secondaryText, size: 42)
                VStack(alignment: .leading, spacing: 4) {
                    Text("这条回声已收起")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(TempoTheme.primaryText)
                    Text("它不会重新出现在这里,瓶子也不会回到海面。")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(TempoTheme.secondaryText)
                }
            }
            .tempoCard(radius: 20, padding: 16)
        } else {
            HStack(alignment: .top, spacing: 12) {
                SoftIconBubble(systemName: "water.waves", color: TempoTheme.accent, size: 42)
                VStack(alignment: .leading, spacing: 4) {
                    Text("还在海面上")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(TempoTheme.primaryText)
                    Text("只有主动打开回声海岸的人才会看到,不会推送轰炸别人。")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(TempoTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tempoCard(radius: 20, padding: 16)
        }
    }

    private var deleteCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("管理这个瓶子")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(TempoTheme.primaryText)
            Text("你可以随时删除自己的内容。删除会同时收起该瓶子下的回声。")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(TempoTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                showDeleteConfirmation = true
            } label: {
                Group {
                    if isDeleting {
                        ProgressView().tint(TempoTheme.danger)
                    } else {
                        Label("删除这个瓶子", systemImage: "trash.fill")
                    }
                }
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(TempoTheme.danger)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(Capsule().fill(TempoTheme.dangerSoft))
            }
            .buttonStyle(.tempoPress)
            .disabled(isDeleting)
            if let deleteError {
                Text(deleteError)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(TempoTheme.danger)
            }
        }
        .tempoCard(radius: 20, padding: 16)
    }

    private func replyDateText(_ milliseconds: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(milliseconds) / 1000)
        return DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .short)
    }

    private func moderateReply(reason: String) {
        Task {
            isModeratingReply = true
            moderationError = nil
            let completed = await onReportReply(reason)
            isModeratingReply = false
            if completed { dismiss() }
            else { moderationError = "举报没有完成,请稍后重试。" }
        }
    }
}

private struct BottleReplySheet: View {
    let bottle: StressBottle
    let onReply: (String) async -> Void
    let onReport: (String) async -> Void
    let onBlock: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var replyText = ""
    @State private var isSending = false
    @State private var showReport = false

    private var canReply: Bool {
        replyText.trimmingCharacters(in: .whitespacesAndNewlines).count >= 4 && !isSending
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    BottleRow(bottle: bottle, compact: false)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("回一句就好")
                            .font(.system(size: 17, weight: .heavy))
                            .foregroundStyle(TempoTheme.primaryText)
                        TextEditor(text: $replyText)
                            .scrollContentBackground(.hidden)
                            .font(.system(size: 14, weight: .semibold))
                            .frame(minHeight: 112)
                            .padding(10)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color(hex: "F8FAFC"))
                            )
                        Text("回复后这个瓶子会收束,不会自动开启长聊天。")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(TempoTheme.tertiaryText)
                    }
                    .tempoCard(radius: 20, padding: 16)

                    HStack(spacing: 10) {
                        Button {
                            showReport = true
                        } label: {
                            Label("举报", systemImage: "exclamationmark.bubble.fill")
                                .font(.system(size: 13, weight: .heavy))
                                .foregroundStyle(TempoTheme.danger)
                                .frame(maxWidth: .infinity)
                                .frame(height: 46)
                                .background(Capsule().fill(TempoTheme.dangerSoft))
                        }
                        .buttonStyle(.tempoPress)
                        .accessibilityLabel("举报这个瓶子")
                        .accessibilityHint("打开举报理由菜单")

                        Button {
                            Task {
                                await onBlock()
                            }
                        } label: {
                            Label("屏蔽", systemImage: "hand.raised.fill")
                                .font(.system(size: 13, weight: .heavy))
                                .foregroundStyle(TempoTheme.secondaryText)
                                .frame(maxWidth: .infinity)
                                .frame(height: 46)
                                .background(Capsule().fill(TempoTheme.tertiaryText.opacity(0.12)))
                        }
                        .buttonStyle(.tempoPress)
                        .accessibilityLabel("屏蔽这个用户")
                        .accessibilityHint("以后看不到这个用户的任何瓶子")
                    }
                }
                .padding(20)
            }
            .background(TempoTheme.background)
            .navigationTitle("接住瓶子")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                        .accessibilityLabel("关闭")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            isSending = true
                            await onReply(replyText.trimmingCharacters(in: .whitespacesAndNewlines))
                            isSending = false
                        }
                    } label: {
                        if isSending {
                            ProgressView()
                        } else {
                            Text("发送")
                                .font(.system(size: 14, weight: .heavy))
                        }
                    }
                    .disabled(!canReply)
                    .accessibilityLabel("发送回复")
                    .accessibilityHint("把你写的一句回声送给瓶子作者")
                }
            }
            .confirmationDialog("为什么举报?", isPresented: $showReport, titleVisibility: .visible) {
                Button("骚扰或广告") { Task { await onReport("spam") } }
                Button("攻击、辱骂或歧视") { Task { await onReport("abuse") } }
                Button("色情或不适内容") { Task { await onReport("sexual") } }
                Button("自伤或紧急危险内容") { Task { await onReport("self_harm") } }
                Button("其他原因") { Task { await onReport("other") } }
                Button("取消", role: .cancel) {}
            }
        }
    }
}

// MARK: - Self-harm hotline sheet
// 当 server contentSafety 返回 code='self_harm' 时弹出.
// Apple Guideline 1.1.6 + 健康类 app 越来越严:漂流瓶 / UGC 必须给真实救助资源,不能只有文字提示.
private struct SelfHarmHotlineSheet: View {
    @Environment(\.dismiss) private var dismiss

    private struct Hotline: Identifiable {
        let id = UUID()
        let name: String
        let number: String
        let region: String
        let note: String
    }

    private let hotlines: [Hotline] = [
        Hotline(name: "北京心理危机研究与干预中心",
                number: "010-82951332",
                region: "中国大陆",
                note: "24 小时,免费"),
        Hotline(name: "希望 24 热线",
                number: "400-161-9995",
                region: "中国大陆",
                note: "24 小时,免费"),
        Hotline(name: "Lifeline / 988",
                number: "988",
                region: "美国",
                note: "Suicide & Crisis Lifeline,24/7"),
        Hotline(name: "Samaritans",
                number: "116123",
                region: "英国",
                note: "24/7"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    headerCard
                    hotlineList
                    bottomTip
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
            .background(TempoTheme.background)
            .navigationTitle("立即获得帮助")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                        .accessibilityLabel("关闭求助界面")
                }
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(TempoTheme.danger)
                Text("你现在最重要的事是和真人说话")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(TempoTheme.primaryText)
            }
            Text("漂流瓶不能处理紧急危机。这些热线 24 小时有专业人员,免费。请选一个打过去。")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(TempoTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tempoCard(radius: 18, padding: 16)
    }

    private var hotlineList: some View {
        VStack(spacing: 10) {
            ForEach(hotlines) { hotline in
                hotlineRow(hotline)
            }
        }
    }

    private func hotlineRow(_ hotline: Hotline) -> some View {
        Button {
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            let cleaned = hotline.number.replacingOccurrences(of: "-", with: "")
            if let url = URL(string: "tel://\(cleaned)") {
                UIApplication.shared.open(url)
            }
            #endif
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(TempoTheme.danger.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: "phone.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(TempoTheme.danger)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(LocalizedStringKey(hotline.name))
                        .font(.system(size: 14, weight: .heavy))
                        .foregroundStyle(TempoTheme.primaryText)
                    Text("\(hotline.number)  ·  \(hotline.region)")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(TempoTheme.danger)
                    Text(LocalizedStringKey(hotline.note))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(TempoTheme.tertiaryText)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(TempoTheme.tertiaryText)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(TempoTheme.cardBackground)
                    .shadow(color: Color.black.opacity(0.04), radius: 12, y: 4)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.tempoPress(.medium))
        .accessibilityLabel("\(hotline.name),\(hotline.region) \(hotline.number)")
        .accessibilityHint("点击拨打")
    }

    private var bottomTip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 13))
                    .foregroundStyle(TempoTheme.success)
                Text("身边有人吗?")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(TempoTheme.primaryText)
            }
            Text("如果身边有家人或朋友,立刻告诉 Ta 你现在的感受。即使只是一句话:「我很难受,陪我一下」。")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(TempoTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(TempoTheme.successSoft.opacity(0.5))
        )
    }
}

#Preview {
    DriftBottleView()
}
