//
//  AppleSignInView.swift
//  Tempo
//
//  Sign in with Apple — 用 UIKit ASAuthorizationController 直接驱动,
//  避免 SwiftUI SignInWithAppleButton 的 onCompletion 在 iOS 26 偶发不触发的 quirk.
//

import SwiftUI
import os
import AuthenticationServices

struct AppleSignInButton: View {
    let onSuccess: () -> Void

    @State private var coordinator = SignInCoordinator()
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 8) {
            Button {
                start()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "applelogo")
                        .font(.system(size: 16, weight: .semibold))
                    Text(loading ? "正在登录…" : "通过 Apple 登录")
                        .font(.system(size: 15, weight: .heavy))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Capsule().fill(Color.black))
                .opacity(loading ? 0.6 : 1.0)
            }
            .buttonStyle(.tempoPress)
            .disabled(loading)

            if let err = error {
                Text(err)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(TempoTheme.danger)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func start() {
        loading = true
        error = nil

        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = coordinator
        controller.presentationContextProvider = coordinator
        coordinator.onCompletion = { result in
            Task { @MainActor in
                await handle(result)
            }
        }
        controller.performRequests()
    }

    @MainActor
    private func handle(_ result: Result<ASAuthorization, Error>) async {
        defer { loading = false }
        switch result {
        case .failure(let e):
            let nsErr = e as NSError
            // canceled / unknown(用户主动关 sheet)不算错
            if nsErr.code != ASAuthorizationError.canceled.rawValue,
               nsErr.code != ASAuthorizationError.unknown.rawValue {
                self.error = "登录失败:\(e.localizedDescription)"
                TempoLog.session.debug("failure code=\(nsErr.code) domain=\(nsErr.domain) desc=\(e.localizedDescription)")
            } else {
                TempoLog.session.debug("user canceled / unknown(\(nsErr.code))")
            }
            return

        case .success(let auth):
            guard let cred = auth.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = cred.identityToken,
                  let token = String(data: tokenData, encoding: .utf8) else {
                self.error = "无法读取 Apple 凭证"
                return
            }
            TempoLog.session.debug("got identityToken length=\(token.count) sub=\(cred.user, privacy: .private)")

            let displayName: String? = {
                if let n = cred.fullName {
                    let parts = [n.familyName, n.givenName].compactMap { $0 }.filter { !$0.isEmpty }
                    if !parts.isEmpty { return parts.joined() }
                }
                return nil
            }()

            do {
                let resp = try await TempoAPIClient.shared.authenticateApple(idToken: token, displayName: displayName)
                TempoLog.session.debug("server auth ok, userId=\(resp.user.userId, privacy: .private)")
                TempoSession.shared.storeAuth(token: resp.sessionToken, user: resp.user)
                if let apnsToken = APNsTokenStore.shared.token {
                    try? await TempoAPIClient.shared.registerDevice(
                        deviceId: TempoSession.shared.deviceId,
                        apnsToken: apnsToken
                    )
                }
                onSuccess()
            } catch let e as APIError {
                self.error = e.localizedDescription
                TempoLog.session.debug("server error: \(e.localizedDescription)")
            } catch let e {
                self.error = "登录失败:\(e.localizedDescription)"
                TempoLog.session.debug("unexpected: \(e)")
            }
        }
    }
}

// MARK: - Coordinator(UIKit ASAuthorizationController delegate / presentation provider)

@MainActor
final class SignInCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    var onCompletion: ((Result<ASAuthorization, Error>) -> Void)?

    nonisolated func authorizationController(controller: ASAuthorizationController,
                                             didCompleteWithAuthorization authorization: ASAuthorization) {
        Task { @MainActor in
            self.onCompletion?(.success(authorization))
            self.onCompletion = nil
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController,
                                             didCompleteWithError error: Error) {
        Task { @MainActor in
            self.onCompletion?(.failure(error))
            self.onCompletion = nil
        }
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // iOS 26 推荐用 UIWindowScene 拿 keyWindow
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first {
            return window
        }
        return UIWindow()
    }
}

// MARK: - APNs token store(AppDelegate 拿到 token 后存这里)

@MainActor
final class APNsTokenStore {
    static let shared = APNsTokenStore()
    private(set) var token: String?

    func store(_ deviceToken: Data) {
        let s = deviceToken.map { String(format: "%02x", $0) }.joined()
        self.token = s
        UserDefaults.standard.set(s, forKey: "tempo.apnsToken")
        if TempoSession.shared.isLoggedIn {
            Task {
                try? await TempoAPIClient.shared.registerDevice(
                    deviceId: TempoSession.shared.deviceId,
                    apnsToken: s
                )
            }
        }
    }

    private init() {
        self.token = UserDefaults.standard.string(forKey: "tempo.apnsToken")
    }
}
