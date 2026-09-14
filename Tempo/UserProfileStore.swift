//
//  UserProfileStore.swift
//  Tempo
//
//  从 UserDefaults(PersonalInfoView 写入)读取 UserProfile,
//  缓存在内存,供算法 helper 调用。绝不上传服务器。
//

import Foundation
import Observation
import TempoCore

@MainActor
@Observable
final class UserProfileStore {
    static let shared = UserProfileStore()

    private(set) var current: UserProfile = .default

    /// 用户改了 PersonalInfo 之后调一下,刷新缓存并广播 invalidate 信号给依赖方
    func reload() {
        let defaults = UserDefaults.standard
        let age = defaults.object(forKey: "user.age") as? Int ?? 30
        let genderRaw = defaults.string(forKey: "user.genderRaw") ?? "unspecified"
        let heightCm = defaults.object(forKey: "user.heightCm") as? Int ?? 170
        let weightKg = defaults.object(forKey: "user.weightKg") as? Int ?? 65
        let conditionsCSV = defaults.string(forKey: "user.conditions") ?? ""
        let conditions = Set(
            conditionsCSV
                .split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        )
        let gender = UserProfile.Gender(rawValue: genderRaw) ?? .unspecified

        current = UserProfile(
            age: age,
            gender: gender,
            heightCm: heightCm,
            weightKg: weightKg,
            conditions: conditions
        )

        // 通知监听方
        NotificationCenter.default.post(name: .tempoUserProfileChanged, object: nil)
    }

    private init() {
        reload()
    }
}

extension Notification.Name {
    /// PersonalInfo 改了之后发的信号 — 告警阈值推荐、Strain 重算依赖此
    static let tempoUserProfileChanged = Notification.Name("tempo.userProfile.changed")
}
