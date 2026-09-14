//
//  MentalHealthSurveyView.swift
//  Tempo
//
//  GAD-7 / PHQ-9 / PSS-10 自评量表 UI。结果存本机 SwiftData,绝不上传。
//

import SwiftUI
import SwiftData
import TempoCore

/// MentalHealthHub @Query cutoff:量表历史最多看 2 年(用户回看跨年变化)
private let mentalHealthCutoff: Date = Date.now.addingTimeInterval(-730 * 86400)

// MARK: - Hub View

struct MentalHealthHubView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<MentalHealthSurveyResult> { $0.timestamp > mentalHealthCutoff },
           sort: \MentalHealthSurveyResult.timestamp, order: .reverse) private var allResults: [MentalHealthSurveyResult]
    @State private var startingKind: SurveyKind?

    private func latestResult(for kind: SurveyKind) -> MentalHealthSurveyResult? {
        allResults.first(where: { $0.kind == kind })
    }

    private func daysSince(_ date: Date) -> Int {
        let interval = Date().timeIntervalSince(date)
        return Int(interval / 86400)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    SettingsSheetHeader(
                        icon: "brain.head.profile",
                        color: Color.purple,
                        title: "心理健康自评",
                        subtitle: "GAD-7 / PHQ-9 / PSS-10 学术量表"
                    )

                    VStack(spacing: 0) {
                        ForEach(SurveyKind.allCases, id: \.self) { kind in
                            surveyRow(kind: kind)
                            if kind != SurveyKind.allCases.last {
                                Divider().padding(.leading, 64)
                            }
                        }
                    }
                    .settingsPanel()

                    SettingsFootnoteCard(
                        icon: "lock.fill",
                        color: TempoTheme.success,
                        text: "自评结果只保存在你的设备本机,绝不上传服务器。建议每月做一次,在「数据导出」可以导出 JSON 给医生看。"
                    )

                    SettingsFootnoteCard(
                        icon: "exclamationmark.triangle.fill",
                        color: TempoTheme.warning,
                        text: "本评估仅供个人参考,不替代专业医疗诊断。若评分较高或有自伤念头,请尽快联系专业心理医生或拨打 24h 心理援助热线 400-161-9995。"
                    )

                    if !allResults.isEmpty {
                        recentHistorySection
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 34)
            }
            .scrollIndicators(.hidden)
            .background(TempoTheme.background)
            .navigationTitle("心理健康自评")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .sheet(item: $startingKind) { kind in
                SurveyQuestionnaireView(kind: kind)
            }
        }
    }

    private func surveyRow(kind: SurveyKind) -> some View {
        let latest = latestResult(for: kind)
        return Button {
            startingKind = kind
        } label: {
            HStack(spacing: 14) {
                SoftIconBubble(
                    systemName: icon(for: kind),
                    color: color(for: kind),
                    size: 44
                )
                VStack(alignment: .leading, spacing: 4) {
                    Text(LocalizedStringKey(kind.displayName))
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(TempoTheme.primaryText)
                    if let l = latest {
                        Text("上次 \(daysSince(l.timestamp)) 天前 · 分数 \(l.score) · \(kind.interpretation(score: l.score).label)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(severityColor(l.severity))
                    } else {
                        Text("还没做过 · \(kind.subtitle)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(TempoTheme.tertiaryText)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(TempoTheme.tertiaryText)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .buttonStyle(.tempoPress)
    }

    private func icon(for kind: SurveyKind) -> String {
        switch kind {
        case .gad7: "tornado"
        case .phq9: "cloud.rain.fill"
        case .pss10: "wind"
        }
    }

    private func color(for kind: SurveyKind) -> Color {
        switch kind {
        case .gad7: TempoTheme.warning
        case .phq9: Color(hex: "8B5CF6")
        case .pss10: TempoTheme.accent
        }
    }

    private func severityColor(_ severity: SurveySeverity) -> Color {
        switch severity {
        case .minimal: TempoTheme.success
        case .mild: TempoTheme.accent
        case .moderate: TempoTheme.warning
        case .severe: TempoTheme.danger
        }
    }

    private var recentHistorySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("最近记录")
                    .font(.system(size: 13, weight: .heavy))
                    .kerning(0.5)
                    .foregroundStyle(TempoTheme.tertiaryText)
                Spacer()
            }
            VStack(spacing: 0) {
                ForEach(allResults.prefix(8)) { r in
                    historyRow(r)
                    if r != allResults.prefix(8).last {
                        Divider().padding(.leading, 56)
                    }
                }
            }
            .settingsPanel()
        }
    }

    private func historyRow(_ r: MentalHealthSurveyResult) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(severityColor(r.severity))
                .frame(width: 8, height: 8)
            Text(LocalizedStringKey(r.kind.displayName))
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(TempoTheme.primaryText)
            Spacer()
            Text("\(r.score) · \(r.kind.interpretation(score: r.score).label)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(severityColor(r.severity))
            Text(dateString(r.timestamp))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(TempoTheme.tertiaryText)
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func dateString(_ d: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return formatter.string(from: d)
    }
}

// MARK: - Questionnaire View

struct SurveyQuestionnaireView: View {
    let kind: SurveyKind
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var answers: [Int]
    @State private var note: String = ""
    @State private var showResult: Bool = false
    @State private var savedResult: MentalHealthSurveyResult?

    init(kind: SurveyKind) {
        self.kind = kind
        let questionCount = SurveyQuestions.questions(for: kind).count
        self._answers = State(initialValue: Array(repeating: -1, count: questionCount))
    }

    private var allAnswered: Bool {
        !answers.contains(-1)
    }

    private var currentScore: Int {
        // 把 -1 当 0 算预览分数
        let safe = answers.map { $0 < 0 ? 0 : $0 }
        return SurveyQuestions.computeScore(answers: safe, kind: kind)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    headerBox

                    ForEach(Array(SurveyQuestions.questions(for: kind).enumerated()), id: \.offset) { idx, q in
                        questionCard(index: idx, question: q)
                    }

                    noteEditor

                    saveButton
                    Spacer(minLength: 30)
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
            .background(TempoTheme.background)
            .navigationTitle(Text(LocalizedStringKey(kind.displayName)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
            .sheet(isPresented: $showResult, onDismiss: { dismiss() }) {
                if let result = savedResult {
                    SurveyResultView(result: result)
                }
            }
        }
    }

    private var headerBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(LocalizedStringKey(kind.subtitle))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(TempoTheme.secondaryText)
            HStack(spacing: 8) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 11, weight: .bold))
                Text("约 \(estimatedMinutes) 分钟")
                    .font(.system(size: 11, weight: .heavy))
            }
            .foregroundStyle(TempoTheme.tertiaryText)
        }
        .padding(.bottom, 6)
    }

    private var estimatedMinutes: Int {
        switch kind {
        case .gad7: 2
        case .phq9: 3
        case .pss10: 3
        }
    }

    private func questionCard(index: Int, question: String) -> some View {
        let answer = answers[index]
        let labels = SurveyQuestions.answerLabels(for: kind)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                Text("\(index + 1)")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(TempoTheme.accent))
                Text(LocalizedStringKey(question))
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(TempoTheme.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 8) {
                ForEach(0..<labels.count, id: \.self) { v in
                    Button {
                        answers[index] = v
                    } label: {
                        HStack {
                            Image(systemName: answer == v ? "circle.inset.filled" : "circle")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(answer == v ? TempoTheme.accent : TempoTheme.tertiaryText)
                            Text(LocalizedStringKey(labels[v]))
                                .font(.system(size: 14, weight: answer == v ? .heavy : .semibold))
                                .foregroundStyle(answer == v ? TempoTheme.primaryText : TempoTheme.secondaryText)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(answer == v ? TempoTheme.accentSoft : Color.white)
                        )
                    }
                    .buttonStyle(.tempoPress)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
        )
    }

    private var noteEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("一句话(可选)")
                .font(.system(size: 12, weight: .heavy))
                .kerning(0.5)
                .foregroundStyle(TempoTheme.tertiaryText)
            TextField("最近怎么样?", text: $note, axis: .vertical)
                .font(.system(size: 14))
                .lineLimit(2, reservesSpace: true)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white)
                )
        }
    }

    private var saveButton: some View {
        Button {
            save()
        } label: {
            Text(allAnswered ? "提交并查看结果" : "请先回答全部 \(answers.count) 题")
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    Capsule()
                        .fill(allAnswered ? TempoTheme.accent : TempoTheme.tertiaryText)
                )
        }
        .buttonStyle(.tempoPress)
        .disabled(!allAnswered)
    }

    private func save() {
        guard allAnswered else { return }
        let score = SurveyQuestions.computeScore(answers: answers, kind: kind)
        let interpretation = kind.interpretation(score: score)
        let result = MentalHealthSurveyResult(
            kind: kind,
            score: score,
            answers: answers,
            severity: interpretation.severity,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        context.insert(result)
        try? context.save()
        savedResult = result
        showResult = true
    }
}

// MARK: - Result View

struct SurveyResultView: View {
    let result: MentalHealthSurveyResult
    @Environment(\.dismiss) private var dismiss

    private var interpretation: SurveyInterpretation {
        result.kind.interpretation(score: result.score)
    }

    private var severityColor: Color {
        switch result.severity {
        case .minimal: TempoTheme.success
        case .mild: TempoTheme.accent
        case .moderate: TempoTheme.warning
        case .severe: TempoTheme.danger
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .center, spacing: 24) {
                    scoreBubble
                    interpretationCard
                    if result.severity == .severe || result.severity == .moderate {
                        helpCard
                    }
                    actionsRow
                    Spacer(minLength: 30)
                }
                .padding(.horizontal, 24)
                .padding(.top, 30)
            }
            .scrollIndicators(.hidden)
            .background(TempoTheme.background)
            .navigationTitle(Text(LocalizedStringKey(result.kind.displayName)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private var scoreBubble: some View {
        VStack(spacing: 6) {
            Text("得分")
                .font(.system(size: 12, weight: .heavy))
                .kerning(0.5)
                .foregroundStyle(TempoTheme.tertiaryText)
            Text("\(result.score)")
                .font(.system(size: 72, weight: .black, design: .rounded))
                .foregroundStyle(severityColor)
            Text("/ \(result.kind.scoreMax)")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(TempoTheme.tertiaryText)
            Text(LocalizedStringKey(interpretation.label))
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(severityColor)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Capsule().fill(severityColor.opacity(0.15)))
        }
    }

    private var interpretationCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "text.book.closed.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(TempoTheme.accent)
                Text("解读")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(TempoTheme.primaryText)
            }
            Text(LocalizedStringKey(interpretation.advice))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(TempoTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tempoCard(radius: 18, padding: 16)
    }

    private var helpCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "phone.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(TempoTheme.danger)
                Text("需要帮助")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(TempoTheme.primaryText)
            }
            Text("如果你正在经历持续低落或自伤念头,请拨打 24 小时心理援助热线,与专业人员谈谈:")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(TempoTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 6) {
                hotlineButton(label: "希望 24 热线", number: "400-161-9995")
                hotlineButton(label: "北京危机干预", number: "010-82951332")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tempoCard(radius: 18, padding: 16)
    }

    private func hotlineButton(label: String, number: String) -> some View {
        Button {
            #if canImport(UIKit)
            let urlString = "tel://" + number.replacingOccurrences(of: "-", with: "")
            if let url = URL(string: urlString) {
                UIApplication.shared.open(url)
            }
            #endif
        } label: {
            HStack {
                Image(systemName: "phone.fill")
                    .font(.system(size: 12, weight: .bold))
                Text(LocalizedStringKey(label))
                    .font(.system(size: 13, weight: .heavy))
                Spacer()
                Text(number)
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .monospacedDigit()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Capsule().fill(TempoTheme.danger))
        }
        .buttonStyle(.tempoPress)
    }

    private var actionsRow: some View {
        HStack {
            Text("结果只保存在你的设备本机")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(TempoTheme.tertiaryText)
            Spacer()
        }
    }
}

// MARK: - UIKit import for tel:// dial

#if canImport(UIKit)
import UIKit
#endif
