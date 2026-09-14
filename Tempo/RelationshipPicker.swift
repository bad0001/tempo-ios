//
//  RelationshipPicker.swift
//  Tempo
//
//  让用户给密友设置关系标签:宝贝(情侣) / 妈妈 / 爸爸 / 哥哥 / 妹妹 / 朋友 / 自定义
//

import SwiftUI

struct RelationshipPickerSheet: View {
    let friend: Friend
    @Environment(\.dismiss) private var dismiss
    @State private var customText: String = ""
    @State private var service = FriendsService.shared

    private let presets: [(emoji: String, label: String)] = [
        ("💖", "宝贝"),
        ("👩", "妈妈"),
        ("👨", "爸爸"),
        ("👧", "女儿"),
        ("👦", "儿子"),
        ("👵", "奶奶"),
        ("👴", "爷爷"),
        ("👫", "哥哥"),
        ("👫", "弟弟"),
        ("👭", "姐姐"),
        ("👭", "妹妹"),
        ("🧑‍🤝‍🧑", "朋友"),
        ("💼", "同事"),
        ("🌿", "闺蜜"),
        ("🤝", "兄弟"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("给 \(friend.displayName) 设个称呼,让关怀更有温度。")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(TempoTheme.tertiaryText)
                        .padding(.top, 4)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("常用关系")
                            .font(.system(size: 12, weight: .heavy))
                            .kerning(0.5)
                            .foregroundStyle(TempoTheme.tertiaryText)
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                        ], spacing: 10) {
                            ForEach(presets, id: \.label) { item in
                                Button {
                                    select(item.label)
                                } label: {
                                    HStack(spacing: 6) {
                                        Text(item.emoji)
                                            .font(.system(size: 14))
                                        Text(LocalizedStringKey(item.label))
                                            .font(.system(size: 13, weight: .heavy))
                                            .foregroundStyle(TempoTheme.primaryText)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(Color.white)
                                    )
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.tempoPress)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("自定义")
                            .font(.system(size: 12, weight: .heavy))
                            .kerning(0.5)
                            .foregroundStyle(TempoTheme.tertiaryText)
                        HStack(spacing: 10) {
                            TextField("写一个称呼", text: $customText)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 11)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color.white)
                                )
                            Button {
                                let trimmed = customText.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !trimmed.isEmpty { select(trimmed) }
                            } label: {
                                Text("应用")
                                    .font(.system(size: 13, weight: .heavy))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 11)
                                    .background(Capsule().fill(TempoTheme.accent))
                            }
                            .buttonStyle(.tempoPress)
                            .disabled(customText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }

                    if service.relationship(for: friend) != nil {
                        Button {
                            service.setRelationship(nil, for: friend)
                            dismiss()
                        } label: {
                            HStack {
                                Image(systemName: "trash")
                                Text("清除关系")
                            }
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundStyle(TempoTheme.danger)
                        }
                        .buttonStyle(.tempoPress)
                        .padding(.top, 12)
                    }

                    Spacer(minLength: 30)
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
            }
            .scrollIndicators(.hidden)
            .background(TempoTheme.background)
            .navigationTitle("设置关系")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private func select(_ label: String) {
        service.setRelationship(label, for: friend)
        dismiss()
    }
}
