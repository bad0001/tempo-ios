//
//  AICoachView.swift
//  Tempo
//

import SwiftUI
import SwiftData
import TempoCore

/// AICoachView @Query cutoff:周报 / 月报最多看 1 年数据,够了
private let aiCoachCutoff: Date = Date.now.addingTimeInterval(-365 * 86400)

struct AICoachView: View {
    @Query(filter: #Predicate<StressEntry> { $0.timestamp > aiCoachCutoff },
           sort: \StressEntry.timestamp, order: .reverse) private var entries: [StressEntry]
    @State private var question: String = ""
    @State private var conversation: [ChatMessage] = []
    @State private var isLoading = false

    private let suggestedQuestions = [
        "我最近压力如何?",
        "什么时候压力最高?",
        "我该做哪种呼吸训练?",
        "我的恢复怎么样?",
        "今天该休息还是冲刺?"
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if conversation.isEmpty {
                        AICoachEmptyView()
                    }
                    ForEach(conversation) { message in
                        ChatBubble(message: message)
                    }
                    if isLoading {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("思考中...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.leading, 8)
                    }
                }
                .padding()
            }

            if conversation.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestedQuestions, id: \.self) { q in
                            Button {
                                question = q
                                Task { await ask() }
                            } label: {
                                Text(q)
                                    .font(.caption)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(.regularMaterial, in: Capsule())
                            }
                            .buttonStyle(.tempoPress)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 8)
            }

            HStack(spacing: 8) {
                TextField("问点什么...", text: $question)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.send)
                    .onSubmit { Task { await ask() } }

                Button {
                    Task { await ask() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(
                            question.isEmpty
                            ? AnyShapeStyle(.secondary)
                            : AnyShapeStyle(LinearGradient(
                                colors: [.pink, .orange],
                                startPoint: .leading,
                                endPoint: .trailing
                            ))
                        )
                }
                .disabled(question.isEmpty || isLoading)
            }
            .padding()
            .background(.thinMaterial)
        }
        .navigationTitle("AI 教练")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func ask() async {
        let q = question.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, !isLoading else { return }
        question = ""
        conversation.append(ChatMessage(role: .user, content: q))
        isLoading = true
        defer { isLoading = false }

        let contextSummary = AICoachContextBuilder.summary(from: entries)
        do {
            let answer = try await AICoachService.shared.ask(q, contextSummary: contextSummary)
            conversation.append(ChatMessage(role: .coach, content: answer))
        } catch {
            let fallback = """
            AI 暂时无法回答:\(error.localizedDescription)

            可能原因:
            • 设备 iOS 版本不支持 Apple Intelligence(需 iOS 26+ 兼容机型)
            • 模型首次加载需要等待

            稍后再试,或重启 App。
            """
            conversation.append(ChatMessage(role: .coach, content: fallback))
        }
    }
}

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: Role
    let content: String

    enum Role { case user, coach }
}

struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if message.role == .coach {
                Image(systemName: "sparkles")
                    .font(.callout)
                    .foregroundStyle(LinearGradient(
                        colors: [.pink, .orange],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 24)
                    .padding(.top, 10)
            }

            Text(message.content)
                .font(.callout)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(message.role == .user
                              ? AnyShapeStyle(Color.pink.opacity(0.15))
                              : AnyShapeStyle(.regularMaterial))
                )
                .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)

            if message.role == .user {
                Image(systemName: "person.crop.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
                    .padding(.top, 10)
            }
        }
    }
}

struct AICoachEmptyView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 60))
                .foregroundStyle(LinearGradient(
                    colors: [.pink, .orange],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .padding(.top, 40)

            Text("AI 教练")
                .font(.title.weight(.semibold))

            Text("基于你过去 30 天的健康数据,我会给出个性化建议。\n所有 AI 处理在你的 iPhone 上完成,数据不会上传任何服务器。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 24)
    }
}

#Preview {
    NavigationStack {
        AICoachView()
    }
}
