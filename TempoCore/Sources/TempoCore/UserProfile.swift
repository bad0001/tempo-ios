//
//  UserProfile.swift
//  TempoCore
//
//  本机用户画像 — 用于个性化算法(Strain maxHR、HRV 性别偏移、告警阈值等)。
//  绝不上传服务器。Tempo 客户端 `UserProfileStore` 从 UserDefaults 加载。
//

import Foundation

public struct UserProfile: Codable, Hashable, Sendable {
    public let age: Int
    public let gender: Gender
    public let heightCm: Int
    public let weightKg: Int
    public let conditions: Set<String>

    public init(
        age: Int = 30,
        gender: Gender = .unspecified,
        heightCm: Int = 170,
        weightKg: Int = 65,
        conditions: Set<String> = []
    ) {
        // Clamp 到合理范围
        self.age = max(12, min(100, age))
        self.gender = gender
        self.heightCm = max(100, min(220, heightCm))
        self.weightKg = max(30, min(200, weightKg))
        self.conditions = conditions
    }

    public enum Gender: String, Codable, Sendable, CaseIterable {
        case unspecified
        case male
        case female
        case other

        public var displayName: String {
            switch self {
            case .unspecified: "不愿透露"
            case .male: "男"
            case .female: "女"
            case .other: "其他"
            }
        }
    }

    // MARK: - Derived helpers

    /// 估算 max heart rate(Tanaka 公式比 220-age 略精确;>40 岁差异明显)
    /// `208 - 0.7 × age` — 适用于成人,误差 ±10bpm
    public var estimatedMaxHR: Double {
        max(140, 208 - 0.7 * Double(age))
    }

    /// RHR baseline 性别微调(没有实测时用):
    /// 女性平均 RHR 比男性高 3-5bpm
    public var rhrGenderAdjustment: Double {
        switch gender {
        case .female: 3
        case .male: 0
        case .other, .unspecified: 1.5
        }
    }

    /// 是否声明了「心血管相关」健康状况
    public var hasCardiacCondition: Bool {
        !conditions.isDisjoint(with: ["arrhythmia", "hypertension"])
    }

    public var isPregnant: Bool {
        conditions.contains("pregnancy")
    }

    /// 是否填了「基本完整」资料(用于决定要不要弹「完善资料」引导)
    public var isFilledIn: Bool {
        age != 30 || gender != .unspecified || heightCm != 170 || weightKg != 65
    }

    public static let `default` = UserProfile()
}
