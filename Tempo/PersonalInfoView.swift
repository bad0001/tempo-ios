//
//  PersonalInfoView.swift
//  Tempo
//
//  个人信息页:昵称走 Tempo server;身体与健康偏好只保存在本机。
//

import SwiftUI

struct PersonalInfoView: View {
    @AppStorage("user.age") private var age: Int = 25
    @AppStorage("user.genderRaw") private var genderRaw: String = "unspecified"
    @AppStorage("user.heightCm") private var heightCm: Int = 170
    @AppStorage("user.weightKg") private var weightKg: Int = 65
    @AppStorage("user.conditions") private var conditionsCSV: String = ""

    @Environment(\.dismiss) private var dismiss
    @State private var session = TempoSession.shared
    @State private var displayNameDraft = ""
    @State private var isSavingName = false
    @State private var saveMessage: String?

    private var trimmedDisplayName: String {
        displayNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSaveName: Bool {
        session.isLoggedIn
        && !trimmedDisplayName.isEmpty
        && trimmedDisplayName != (session.displayName ?? "")
        && !isSavingName
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    SettingsSheetHeader(
                        icon: "person.text.rectangle.fill",
                        color: Color.pink,
                        title: "个人信息",
                        subtitle: "昵称、身体和健康偏好"
                    )

                    accountCard
                    bodyMetricsCard
                    healthConditionsCard

                    SettingsFootnoteCard(
                        icon: "lock.fill",
                        color: TempoTheme.success,
                        text: "年龄、身高、体重和健康状况只保存在本机。昵称用于密友列表和关怀通知。"
                    )
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 34)
            }
            .scrollIndicators(.hidden)
            .background(TempoTheme.background)
            .navigationTitle("个人信息")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear {
                displayNameDraft = session.displayName ?? ""
            }
            .onChange(of: age) { _, _ in syncProfileToStore() }
            .onChange(of: genderRaw) { _, _ in syncProfileToStore() }
            .onChange(of: heightCm) { _, _ in syncProfileToStore() }
            .onChange(of: weightKg) { _, _ in syncProfileToStore() }
            .onChange(of: conditionsCSV) { _, _ in syncProfileToStore() }
        }
    }

    /// 任何字段变动时同步到 UserProfileStore 并 invalidate baseline cache —
    /// 这样 Strain.maxHR / 告警推荐阈值都会即时刷新。
    private func syncProfileToStore() {
        UserProfileStore.shared.reload()
        HealthKitService.shared.invalidateBaselineCache()
    }

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                SoftIconBubble(
                    systemName: session.isLoggedIn ? "person.crop.circle.badge.checkmark" : "person.crop.circle.badge.exclamationmark",
                    color: session.isLoggedIn ? TempoTheme.success : TempoTheme.warning,
                    size: 42
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tempo 昵称")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(TempoTheme.primaryText)
                    Text(session.publicId.map { "共振 ID \($0)" } ?? "登录后同步")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(TempoTheme.tertiaryText)
                }
                Spacer()
            }

            HStack(spacing: 10) {
                TextField("显示给密友的名字", text: $displayNameDraft)
                    .font(.system(size: 15, weight: .semibold))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 14)
                    .frame(height: 46)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(hex: "F8FAFC"))
                    )
                    .disabled(!session.isLoggedIn || isSavingName)

                Button {
                    Task { await saveDisplayName() }
                } label: {
                    if isSavingName {
                        ProgressView()
                            .frame(width: 48, height: 46)
                    } else {
                        Text("保存")
                            .font(.system(size: 14, weight: .heavy))
                            .foregroundStyle(.white)
                            .frame(width: 54, height: 46)
                            .background(Capsule().fill(canSaveName ? TempoTheme.accent : TempoTheme.tertiaryText))
                    }
                }
                .buttonStyle(.tempoPress)
                .disabled(!canSaveName)
            }

            if let saveMessage {
                Text(saveMessage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(saveMessage.contains("失败") ? TempoTheme.danger : TempoTheme.secondaryText)
            }
        }
        .tempoCard(radius: 22, padding: 16)
    }

    private var bodyMetricsCard: some View {
        VStack(spacing: 0) {
            ProfileStepperRow(
                icon: "number.circle.fill",
                iconColor: TempoTheme.accent,
                title: "年龄",
                value: $age,
                range: 12...100,
                unit: "岁"
            )
            Divider().padding(.leading, 68)
            GenderPickerRow(selection: $genderRaw)
            Divider().padding(.leading, 68)
            ProfileStepperRow(
                icon: "ruler.fill",
                iconColor: TempoTheme.success,
                title: "身高",
                value: $heightCm,
                range: 100...220,
                unit: "cm"
            )
            Divider().padding(.leading, 68)
            ProfileStepperRow(
                icon: "scalemass.fill",
                iconColor: TempoTheme.warning,
                title: "体重",
                value: $weightKg,
                range: 30...200,
                unit: "kg"
            )
        }
        .settingsPanel()
    }

    private var healthConditionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                SoftIconBubble(systemName: "cross.case.fill", color: Color.pink, size: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text("健康状况")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(TempoTheme.primaryText)
                    Text("可多选")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(TempoTheme.tertiaryText)
                }
                Spacer()
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
                ConditionChip(label: "高血压", id: "hypertension", csv: $conditionsCSV)
                ConditionChip(label: "焦虑", id: "anxiety", csv: $conditionsCSV)
                ConditionChip(label: "失眠", id: "insomnia", csv: $conditionsCSV)
                ConditionChip(label: "抑郁", id: "depression", csv: $conditionsCSV)
                ConditionChip(label: "心律不齐", id: "arrhythmia", csv: $conditionsCSV)
                ConditionChip(label: "孕期", id: "pregnancy", csv: $conditionsCSV)
            }
        }
        .tempoCard(radius: 22, padding: 16)
    }

    @MainActor
    private func saveDisplayName() async {
        guard canSaveName else { return }
        isSavingName = true
        saveMessage = nil
        defer { isSavingName = false }

        do {
            let response = try await TempoAPIClient.shared.updateMe(displayName: trimmedDisplayName)
            session.updateDisplayName(response.user.displayName ?? trimmedDisplayName)
            displayNameDraft = response.user.displayName ?? trimmedDisplayName
            await FriendsService.shared.publishLatestStressSnapshotIfPossible()
            saveMessage = "昵称已更新"
        } catch {
            saveMessage = "保存失败:\(error.localizedDescription)"
        }
    }
}

private struct ProfileStepperRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let unit: String

    var body: some View {
        Stepper(value: $value, in: range) {
            HStack(spacing: 14) {
                SoftIconBubble(systemName: icon, color: iconColor, size: 42)
                Text(title)
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(TempoTheme.primaryText)
                Spacer()
                Text("\(value) \(unit)")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(iconColor)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

private struct GenderPickerRow: View {
    @Binding var selection: String

    private var label: String {
        switch selection {
        case "male": "男"
        case "female": "女"
        case "other": "其他"
        default: "不愿透露"
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            SoftIconBubble(systemName: "figure.stand", color: Color.pink, size: 42)
            Text("性别")
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(TempoTheme.primaryText)
            Spacer()
            Picker("性别", selection: $selection) {
                Text("不愿透露").tag("unspecified")
                Text("男").tag("male")
                Text("女").tag("female")
                Text("其他").tag("other")
            }
            .pickerStyle(.menu)
            .tint(TempoTheme.secondaryText)
            Text(label)
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(TempoTheme.tertiaryText)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

private struct ConditionChip: View {
    let label: String
    let id: String
    @Binding var csv: String

    private var isSelected: Bool {
        Set(csv.split(separator: ",").map(String.init)).contains(id)
    }

    var body: some View {
        Button {
            var items = Set(csv.split(separator: ",").map(String.init))
            if isSelected {
                items.remove(id)
            } else {
                items.insert(id)
            }
            csv = items.sorted().joined(separator: ",")
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12, weight: .bold))
                Text(label)
                    .font(.system(size: 12, weight: .heavy))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? Color.pink : TempoTheme.secondaryText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(isSelected ? Color.pink.opacity(0.12) : Color(hex: "F8FAFC"))
            )
        }
        .buttonStyle(.tempoPress)
    }
}

#Preview {
    PersonalInfoView()
}
