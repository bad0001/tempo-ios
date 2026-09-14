//
//  TempoLog.swift
//  Tempo
//
//  统一 logging:基于 os.Logger,Release 包不写 user-readable stdout/syslog,
//  Debug 包仍可在 Console.app 看到。
//
//  用法替换 print:
//      print("[Friends] xxx")        →  TempoLog.friends.debug("xxx")
//      print("[Care] xxx")           →  TempoLog.care.debug("xxx")
//      print("[Watch] xxx")          →  TempoLog.watch.debug("xxx")
//
//  错误用 .error,info-level 用 .info,警告用 .warning。
//
//  ⚠️ 涉及用户隐私 / share URL / publicId 的内容,用 \(value, privacy: .private) 包,
//  这样 Console.app 看到 <private>,而不是明文。
//

import Foundation
import os

enum TempoLog {
    private static let subsystem = "com.ayipocket.tempo"

    static let friends    = Logger(subsystem: subsystem, category: "Friends")
    static let care       = Logger(subsystem: subsystem, category: "Care")
    static let session    = Logger(subsystem: subsystem, category: "Session")
    static let api        = Logger(subsystem: subsystem, category: "API")
    static let push       = Logger(subsystem: subsystem, category: "Push")
    static let health     = Logger(subsystem: subsystem, category: "Health")
    static let watch      = Logger(subsystem: subsystem, category: "Watch")
    static let breathing  = Logger(subsystem: subsystem, category: "Breathing")
    static let storage    = Logger(subsystem: subsystem, category: "Storage")
    static let ai         = Logger(subsystem: subsystem, category: "AI")
    static let app        = Logger(subsystem: subsystem, category: "App")
}
