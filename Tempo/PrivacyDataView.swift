//
//  PrivacyDataView.swift
//  Tempo
//
//  隐私、数据导出与法律入口。
//

import SwiftUI
import TempoCore

struct PrivacyDataView: View {
    let allEntries: [StressEntry]
    @Environment(\.dismiss) private var dismiss

    private var sortedEntries: [StressEntry] {
        allEntries.sorted { $0.timestamp < $1.timestamp }
    }

    private var dateRangeText: String {
        guard let first = sortedEntries.first?.timestamp,
              let last = sortedEntries.last?.timestamp else {
            return "暂无记录"
        }
        let f = DateFormatter()
        f.locale = TempoAppLanguage.currentLocale
        f.dateFormat = "M/d"
        return "\(f.string(from: first)) - \(f.string(from: last))"
    }

    private var averageStressText: String {
        guard !allEntries.isEmpty else { return "—" }
        let avg = allEntries.reduce(0) { $0 + $1.scoreValue } / allEntries.count
        return "\(avg)"
    }

    private var appVersionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    SettingsSheetHeader(
                        icon: "shield.lefthalf.filled",
                        color: TempoTheme.success,
                        title: "隐私与数据",
                        subtitle: "导出、法律和本地数据"
                    )

                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                        spacing: 10
                    ) {
                        SettingsStatTile(title: "记录", value: "\(allEntries.count)", unit: "条", color: TempoTheme.accent)
                        SettingsStatTile(title: "平均压力", value: averageStressText, unit: "/100", color: TempoTheme.warning)
                        SettingsStatTile(title: "范围", value: dateRangeText, unit: "", color: TempoTheme.success)
                        SettingsStatTile(title: "版本", value: appVersionText, unit: "", color: TempoTheme.tertiaryText)
                    }

                    VStack(spacing: 0) {
                        if let csvURL = DataExportService.exportCSV(entries: allEntries) {
                            ShareLink(item: csvURL) {
                                SettingsNavigationRow(
                                    icon: "tablecells.fill",
                                    iconColor: TempoTheme.success,
                                    title: "导出 CSV",
                                    subtitle: "表格分析"
                                )
                            }
                            .buttonStyle(.tempoPress)
                        }

                        if !allEntries.isEmpty {
                            Divider().padding(.leading, 68)
                        }

                        if let jsonURL = DataExportService.exportJSON(entries: allEntries) {
                            ShareLink(item: jsonURL) {
                                SettingsNavigationRow(
                                    icon: "curlybraces.square.fill",
                                    iconColor: TempoTheme.accent,
                                    title: "导出 JSON",
                                    subtitle: "完整结构"
                                )
                            }
                            .buttonStyle(.tempoPress)
                        }

                        if allEntries.isEmpty {
                            EmptySettingsRow(icon: "tray.fill", title: "暂无压力记录")
                        }
                    }
                    .settingsPanel()

                    VStack(spacing: 0) {
                        Link(destination: URL(string: "https://tempo.tiyicard.cn/privacy")!) {
                            SettingsNavigationRow(
                                icon: "hand.raised.fill",
                                iconColor: TempoTheme.success,
                                title: "隐私政策",
                                subtitle: "数据使用说明"
                            )
                        }
                        .buttonStyle(.tempoPress)

                        Divider().padding(.leading, 68)

                        Link(destination: URL(string: "https://tempo.tiyicard.cn/terms")!) {
                            SettingsNavigationRow(
                                icon: "doc.text.magnifyingglass",
                                iconColor: TempoTheme.accent,
                                title: "服务条款",
                                subtitle: "订阅与使用规则"
                            )
                        }
                        .buttonStyle(.tempoPress)
                    }
                    .settingsPanel()

                    SettingsFootnoteCard(
                        icon: "lock.shield.fill",
                        color: TempoTheme.success,
                        text: "HealthKit 原始采样默认保留在 iPhone。开启联网功能后,Tempo 会同步压力摘要、趋势摘要、关怀事件、漂流瓶内容和内容安全所需信息。"
                    )
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 34)
            }
            .scrollIndicators(.hidden)
            .background(TempoTheme.background)
            .navigationTitle("隐私与数据")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
