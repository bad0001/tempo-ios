//
//  MoodLogView.swift
//  Tempo
//
//  主动 mood log:HomeView 上的「感受记录」卡 + 弹出 sheet 详细输入.
//

import SwiftUI
import SwiftData
import TempoCore

/// MoodLogView @Query cutoff:今天 mood 最多回看 7 天
private let moodCardCutoff: Date = Date.now.addingTimeInterval(-7 * 86400)

// MARK: - Home Card

struct MoodCard: View {
    @Query(filter: #Predicate<MoodEntry> { $0.timestamp > moodCardCutoff },
           sort: \MoodEntry.timestamp, order: .reverse) private var allEntries: [MoodEntry]
    @State private var showSheet = false
    @State private var quickMood: MoodLevel?

    private var latestToday: MoodEntry? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return allEntries.first(where: { calendar.startOfDay(for: $0.timestamp) == today })
    }

    var body: some View {
        Button {
            quickMood = nil
            showSheet = true
        } label: {
            content
        }
        .buttonStyle(.tempoPress)
        .sheet(isPresented: $showSheet) {
            MoodLogView(initialMood: quickMood)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let entry = latestToday {
            existingMoodView(entry: entry)
        } else {
            quickPickerView
        }
    }

    private func existingMoodView(entry: MoodEntry) -> some View {
        HStack(spacing: 14) {
            Text(entry.mood.emoji)
                .font(.system(size: 28))
                .frame(width: 50, height: 50)
                .background(Circle().fill(TempoTheme.accent.opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text("今日感受")
                    .font(.system(size: 12, weight: .bold))
                    .kerning(0.5)
                    .foregroundStyle(TempoTheme.tertiaryText)
                HStack(spacing: 6) {
                    Text(LocalizedStringKey(entry.mood.displayName))
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(TempoTheme.primaryText)
                    if !entry.moodTags.isEmpty {
                        Text(entry.moodTags.prefix(3).map { $0.emoji }.joined())
                            .font(.system(size: 14))
                    }
                }
            }
            Spacer()
            Text("再记一次")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(TempoTheme.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(TempoTheme.accentSoft))
        }
        .tempoCard(radius: 22, padding: 18)
    }

    private var quickPickerView: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("感受记录")
                        .font(.system(size: 12, weight: .bold))
                        .kerning(0.5)
                        .foregroundStyle(TempoTheme.tertiaryText)
                    Text("你现在的感受如何?")
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundStyle(TempoTheme.primaryText)
                }
                Spacer()
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(TempoTheme.accent)
            }

            HStack(spacing: 6) {
                ForEach(MoodLevel.allCases) { level in
                    Button {
                        quickMood = level
                        showSheet = true
                    } label: {
                        Text(level.emoji)
                            .font(.system(size: 24))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(
                                Circle()
                                    .fill(TempoTheme.background)
                            )
                    }
                    .buttonStyle(.tempoPress)
                }
            }
        }
        .tempoCard(radius: 22, padding: 18)
    }
}

// MARK: - Sheet

struct MoodLogView: View {
    let initialMood: MoodLevel?
    @State private var selectedMood: MoodLevel = .neutral
    @State private var selectedTags: Set<MoodTag> = []
    @State private var note: String = ""
    @State private var borgSubjective: Double = 5   // 0-10
    @State private var hasSetBorg: Bool = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    init(initialMood: MoodLevel? = nil) {
        self.initialMood = initialMood
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    moodPicker
                    borgSlider
                    tagsPicker
                    noteEditor
                    Spacer(minLength: 40)
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
            .background(TempoTheme.background)
            .navigationTitle("记录感受")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: save) {
                        Text("保存")
                            .font(.system(size: 14, weight: .heavy))
                    }
                }
            }
            .onAppear {
                if let initialMood {
                    selectedMood = initialMood
                }
            }
        }
    }

    // MARK: - Mood

    private var moodPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("此刻心情")
                .font(.system(size: 13, weight: .heavy))
                .kerning(0.5)
                .foregroundStyle(TempoTheme.tertiaryText)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 10) {
                ForEach(MoodLevel.allCases) { level in
                    moodChip(level: level)
                }
            }
        }
    }

    private func moodChip(level: MoodLevel) -> some View {
        let selected = selectedMood == level
        return Button {
            selectedMood = level
        } label: {
            VStack(spacing: 6) {
                Text(level.emoji).font(.system(size: 30))
                Text(LocalizedStringKey(level.displayName))
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(selected ? TempoTheme.accent : TempoTheme.primaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(selected ? TempoTheme.accent : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.tempoPress)
    }

    // MARK: - Borg CR-10 subjective slider

    private var borgSlider: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("身体感受")
                    .font(.system(size: 13, weight: .heavy))
                    .kerning(0.5)
                    .foregroundStyle(TempoTheme.tertiaryText)
                Spacer()
                Text("帮算法学习你的反应")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(TempoTheme.tertiaryText)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(Int(borgSubjective))")
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .foregroundStyle(borgColor(for: Int(borgSubjective)))
                        .contentTransition(.numericText())
                        .monospacedDigit()
                    Text("/ 10")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(TempoTheme.tertiaryText)
                    Spacer()
                    Text(borgLabel(for: Int(borgSubjective)))
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(borgColor(for: Int(borgSubjective)))
                }
                Slider(value: $borgSubjective, in: 0...10, step: 1) { editing in
                    if editing { hasSetBorg = true }
                }
                .tint(borgColor(for: Int(borgSubjective)))
                HStack {
                    Text("完全平静")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(TempoTheme.tertiaryText)
                    Spacer()
                    Text("极度紧张")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(TempoTheme.tertiaryText)
                }
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white)
            )
        }
    }

    private func borgLabel(for v: Int) -> String {
        switch v {
        case 0: "完全平静"
        case 1: "极轻"
        case 2: "很轻"
        case 3: "轻松"
        case 4: "稍紧"
        case 5: "中等"
        case 6: "略累"
        case 7: "比较累"
        case 8: "很紧绷"
        case 9: "几乎极限"
        default: "极限"
        }
    }

    private func borgColor(for v: Int) -> Color {
        switch v {
        case 0...3: TempoTheme.success
        case 4...5: TempoTheme.accent
        case 6...7: TempoTheme.warning
        default: TempoTheme.danger
        }
    }

    // MARK: - Tags

    private var tagsPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("可能的影响(可多选)")
                .font(.system(size: 13, weight: .heavy))
                .kerning(0.5)
                .foregroundStyle(TempoTheme.tertiaryText)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 8)], spacing: 8) {
                ForEach(MoodTag.allCases) { tag in
                    tagChip(tag: tag)
                }
            }
        }
    }

    private func tagChip(tag: MoodTag) -> some View {
        let selected = selectedTags.contains(tag)
        return Button {
            if selected { selectedTags.remove(tag) }
            else { selectedTags.insert(tag) }
        } label: {
            HStack(spacing: 4) {
                Text(tag.emoji)
                Text(LocalizedStringKey(tag.displayName))
                    .font(.system(size: 12, weight: .heavy))
                    .lineLimit(1)
            }
            .foregroundStyle(selected ? .white : TempoTheme.primaryText)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .background(
                Capsule().fill(selected ? TempoTheme.accent : Color.white)
            )
        }
        .buttonStyle(.tempoPress)
    }

    // MARK: - Note

    private var noteEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("一两句话(可选)")
                .font(.system(size: 13, weight: .heavy))
                .kerning(0.5)
                .foregroundStyle(TempoTheme.tertiaryText)
            TextField("发生了什么?", text: $note, axis: .vertical)
                .font(.system(size: 14))
                .lineLimit(3, reservesSpace: true)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.white)
                )
        }
    }

    // MARK: - Save

    private func save() {
        // 先创建一条 entry,立刻 dismiss 让 UI 流畅 — feature snapshot 异步补
        let entry = MoodEntry(
            timestamp: .now,
            mood: selectedMood,
            tags: selectedTags.map { $0.rawValue },
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            borgSubjective: hasSetBorg ? Int(borgSubjective.rounded()) : nil
        )
        context.insert(entry)
        try? context.save()
        let entryID = entry.persistentModelID
        dismiss()

        // 后台抓 feature snapshot,写回同一条 MoodEntry。
        Task.detached(priority: .utility) {
            let snap = await HealthKitService.shared.snapshotForML()
            await MainActor.run {
                if let target = try? context.fetch(
                    FetchDescriptor<MoodEntry>(predicate: #Predicate { $0.persistentModelID == entryID })
                ).first {
                    target.hrAtLog = snap.hr
                    target.hrvAtLog = snap.hrv
                    target.rrAtLog = snap.rr
                    target.stressScoreAtLog = snap.stressScore
                    target.activityRawAtLog = snap.activityRaw
                    target.wasAsleepRecently = snap.wasAsleepRecently
                    target.ageAtLog = snap.age
                    target.genderRawAtLog = snap.genderRaw
                    target.algorithmVersionAtLog = snap.algorithmVersion
                    try? context.save()
                }
            }
        }
    }
}
