//
//  AppLanguage.swift
//  Tempo
//
//  In-app language selection shared by the SwiftUI root and date formatters.
//

import SwiftUI
import TempoCore

enum TempoAppLanguage: String, CaseIterable, Identifiable {
    static let storageKey = "tempo.appLanguage"

    case system
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    var id: String { rawValue }

    var locale: Locale {
        switch self {
        case .system:
            return .autoupdatingCurrent
        case .simplifiedChinese:
            return Locale(identifier: "zh-Hans")
        case .english:
            return Locale(identifier: "en")
        }
    }

    var titleKey: LocalizedStringKey {
        switch self {
        case .system: "跟随系统"
        case .simplifiedChinese: "简体中文"
        case .english: "English"
        }
    }

    var subtitleKey: LocalizedStringKey? {
        switch self {
        case .system: "使用 iPhone 的语言"
        case .simplifiedChinese: nil
        case .english: nil
        }
    }

    static var selected: TempoAppLanguage {
        let rawValue = UserDefaults.standard.string(forKey: storageKey) ?? TempoAppLanguage.system.rawValue
        return TempoAppLanguage(rawValue: rawValue) ?? .system
    }

    static var currentLocale: Locale {
        selected.locale
    }

    static var usesEnglish: Bool {
        currentLocale.tempoUsesEnglish
    }

    var localizedName: String {
        switch self {
        case .system:
            return String(localized: "跟随系统", locale: TempoAppLanguage.currentLocale)
        case .simplifiedChinese:
            return String(localized: "简体中文", locale: TempoAppLanguage.currentLocale)
        case .english:
            return "English"
        }
    }
}

extension Locale {
    var tempoUsesEnglish: Bool {
        let code = language.languageCode?.identifier ?? identifier
        return code.hasPrefix("en")
    }
}

enum TempoLocalization {
    static func string(_ key: String, locale: Locale) -> String {
        let language = locale.tempoUsesEnglish ? "en" : "zh-Hans"
        guard let path = Bundle.main.path(forResource: language, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return key
        }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }
}

extension StressLevel {
    var tempoDisplayName: String {
        TempoAppLanguage.usesEnglish ? displayNameEnglish : displayName
    }
}

extension RecoveryLevel {
    var tempoDisplayName: String {
        TempoAppLanguage.usesEnglish ? displayNameEnglish : displayName
    }
}

extension StrainLevel {
    var tempoDisplayName: String {
        TempoAppLanguage.usesEnglish ? displayNameEnglish : displayName
    }
}

struct LanguageSettingsView: View {
    @AppStorage(TempoAppLanguage.storageKey) private var selectedLanguage = TempoAppLanguage.system.rawValue
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    SettingsSheetHeader(
                        icon: "globe.asia.australia.fill",
                        color: TempoTheme.accent,
                        title: String(localized: "显示语言", locale: activeLanguage.locale),
                        subtitle: String(localized: "选择 Tempo 的显示语言", locale: activeLanguage.locale)
                    )

                    VStack(spacing: 0) {
                        ForEach(Array(TempoAppLanguage.allCases.enumerated()), id: \.element.id) { index, language in
                            if index > 0 {
                                Divider().padding(.leading, 68)
                            }

                            Button {
                                selectedLanguage = language.rawValue
                            } label: {
                                HStack(spacing: 14) {
                                    SoftIconBubble(
                                        systemName: language == .system ? "iphone" : "character.book.closed.fill",
                                        color: language == .english ? Color.indigo : TempoTheme.accent,
                                        size: 42
                                    )

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(language.titleKey)
                                            .font(.system(size: 15, weight: .heavy))
                                            .foregroundStyle(TempoTheme.primaryText)

                                        if let subtitleKey = language.subtitleKey {
                                            Text(subtitleKey)
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundStyle(TempoTheme.tertiaryText)
                                        }
                                    }

                                    Spacer()

                                    if selectedLanguage == language.rawValue {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 20, weight: .bold))
                                            .foregroundStyle(TempoTheme.accent)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.tempoPress)
                        }
                    }
                    .settingsPanel()

                    SettingsFootnoteCard(
                        icon: "checkmark.circle.fill",
                        color: TempoTheme.success,
                        text: String(localized: "更改后立即生效", locale: activeLanguage.locale)
                    )
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 34)
            }
            .scrollIndicators(.hidden)
            .background(TempoTheme.background)
            .navigationTitle("语言")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private var activeLanguage: TempoAppLanguage {
        TempoAppLanguage(rawValue: selectedLanguage) ?? .system
    }
}
