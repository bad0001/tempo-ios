import Foundation
import TempoCore

enum WidgetLocalization {
    private static var usesEnglish: Bool {
        let code = Locale.autoupdatingCurrent.language.languageCode?.identifier ?? "zh"
        return code.hasPrefix("en")
    }

    static func stressLevel(_ level: StressLevel) -> String {
        usesEnglish ? level.displayNameEnglish : level.displayName
    }

    static func recoveryLevel(_ level: RecoveryLevel?) -> String {
        guard let level else { return "—" }
        return usesEnglish ? level.displayNameEnglish : level.displayName
    }

    static func strainLevel(_ level: StrainLevel?) -> String {
        guard let level else { return "" }
        return usesEnglish ? level.displayNameEnglish : level.displayName
    }
}
