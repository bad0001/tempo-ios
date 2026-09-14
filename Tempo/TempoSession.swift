//
//  TempoSession.swift
//  Tempo
//
//  Session token + 当前 user 持久化.token 存 Keychain(私密),user 信息存 UserDefaults.
//

import Foundation
import os
import Observation
import Security

@MainActor
@Observable
final class TempoSession {
    static let shared = TempoSession()

    private(set) var sessionToken: String?
    private(set) var userId: String?
    private(set) var displayName: String?
    private(set) var publicId: String?
    private(set) var hasEmail: Bool = false

    /// 持久化 device ID(每安装一份,uninstall 后重新生成)
    var deviceId: String {
        if let cached = UserDefaults.standard.string(forKey: "tempo.deviceId") {
            return cached
        }
        let new = UUID().uuidString
        UserDefaults.standard.set(new, forKey: "tempo.deviceId")
        return new
    }

    private init() {
        loadFromStorage()
    }

    var isLoggedIn: Bool { sessionToken != nil }

    // MARK: - Load / Save

    private func loadFromStorage() {
        sessionToken = Keychain.read("tempo.sessionToken")
        userId = UserDefaults.standard.string(forKey: "tempo.userId")
        displayName = UserDefaults.standard.string(forKey: "tempo.displayName")
        publicId = UserDefaults.standard.string(forKey: "tempo.publicId")
        hasEmail = UserDefaults.standard.bool(forKey: "tempo.hasEmail")
    }

    func storeAuth(token: String, user: APIUser) {
        Keychain.write("tempo.sessionToken", value: token)
        sessionToken = token
        userId = user.userId
        displayName = user.displayName
        publicId = user.publicId
        hasEmail = user.hasEmail
        UserDefaults.standard.set(user.userId, forKey: "tempo.userId")
        if let name = user.displayName {
            UserDefaults.standard.set(name, forKey: "tempo.displayName")
            UserDefaults.standard.set(name, forKey: "user.displayName")
        }
        if let pid = user.publicId {
            UserDefaults.standard.set(pid, forKey: "tempo.publicId")
        }
        UserDefaults.standard.set(user.hasEmail, forKey: "tempo.hasEmail")
    }

    /// 重新拉取最新 user 信息(用于 publicId 等更新)
    func refreshFromServer() async {
        do {
            let resp = try await TempoAPIClient.shared.getMe()
            self.displayName = resp.user.displayName
            self.publicId = resp.user.publicId
            self.hasEmail = resp.user.hasEmail
            if let pid = resp.user.publicId {
                UserDefaults.standard.set(pid, forKey: "tempo.publicId")
            }
            if let name = resp.user.displayName {
                UserDefaults.standard.set(name, forKey: "tempo.displayName")
                UserDefaults.standard.set(name, forKey: "user.displayName")
            }
        } catch {
            TempoLog.session.debug("refresh failed: \(error)")
        }
    }

    func updateDisplayName(_ name: String) {
        displayName = name
        UserDefaults.standard.set(name, forKey: "tempo.displayName")
        UserDefaults.standard.set(name, forKey: "user.displayName")
    }

    /// 退出当前 Tempo 账号。先解绑本设备 APNs 路由,再清本地 session;
    /// 即使网络失败也会完成本地退出,下一次登录会用同一个 deviceId 覆盖路由。
    @discardableResult
    func logout() async -> Bool {
        let currentDeviceId = deviceId
        var deviceDetached = true
        if sessionToken != nil {
            do {
                try await TempoAPIClient.shared.unregisterDevice(deviceId: currentDeviceId)
            } catch {
                deviceDetached = false
                TempoLog.session.debug("device unregister during logout failed: \(error)")
            }
        }
        clear()
        return deviceDetached
    }

    func clear() {
        Keychain.delete("tempo.sessionToken")
        sessionToken = nil
        userId = nil
        displayName = nil
        publicId = nil
        hasEmail = false
        UserDefaults.standard.removeObject(forKey: "tempo.userId")
        UserDefaults.standard.removeObject(forKey: "tempo.displayName")
        UserDefaults.standard.removeObject(forKey: "user.displayName")
        UserDefaults.standard.removeObject(forKey: "tempo.publicId")
        UserDefaults.standard.removeObject(forKey: "tempo.hasEmail")
        // 一并清 server 关联的本地状态
        FriendsService.shared.clearServerState()
    }
}

// MARK: - Keychain helpers

private enum Keychain {
    static func write(_ key: String, value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func read(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let s = String(data: data, encoding: .utf8) else {
            return nil
        }
        return s
    }

    static func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
