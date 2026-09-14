//
//  PreferencesStore.swift
//  Tempo
//
//  跨 view 共享的设置项,UserDefaults 持久化。
//  当前主要是 circadianEnabled(算法节律修正)+ 其他算法 toggle。
//

import Foundation
import Observation

@MainActor
@Observable
final class PreferencesStore {
    static let shared = PreferencesStore()

    private enum Keys {
        static let circadianEnabled = "algo.circadianEnabled"
        static let usePhasicHRV = "algo.usePhasicHRV"
        static let usePersonalModel = "algo.usePersonalModel"
    }

    var circadianEnabled: Bool {
        get {
            UserDefaults.standard.object(forKey: Keys.circadianEnabled) as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.circadianEnabled)
        }
    }

    var usePhasicHRV: Bool {
        get {
            UserDefaults.standard.object(forKey: Keys.usePhasicHRV) as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.usePhasicHRV)
        }
    }

    /// 是否在 stress score 中混合 PersonalStressModel 预测(默认 on,需要先训练)
    var usePersonalModel: Bool {
        get {
            UserDefaults.standard.object(forKey: Keys.usePersonalModel) as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Keys.usePersonalModel)
        }
    }

    private init() {}
}
