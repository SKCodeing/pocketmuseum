// L10n.swift
// 多语言字符串辅助，统一入口

import Foundation

/// 简写：L10n.str("key") 或 L10n.str("key.format", arg1, arg2)
enum L10n {
    static func str(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }
    static func str(_ key: String, _ args: CVarArg...) -> String {
        String(format: NSLocalizedString(key, comment: ""), arguments: args)
    }
}
