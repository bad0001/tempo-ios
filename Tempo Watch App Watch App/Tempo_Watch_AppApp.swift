//
//  Tempo_Watch_AppApp.swift
//  Tempo Watch App Watch App
//
//  Created by 刘辰奕 on 2026/4/26.
//

import SwiftUI

@main
struct Tempo_Watch_App_Watch_AppApp: App {
    init() {
        WatchSessionManager.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
