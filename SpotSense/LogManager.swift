//
//  LogManager.swift
//  SpotSense
//
//  Created by 小玉敦郎 on 2025/03/21.
//

import UIKit
import Combine

class LogManager: ObservableObject {
    public static let shared = LogManager()
    
    @Published var logs: [String] = [] // ログデータをPublishedで管理
    
    private let userDefaultsKey = "appLogs"
    
    private init() {
        // 初期化時にUserDefaultsからログを取得
        logs = retrieveLogsFromUserDefaults()
    }
    
    func saveLogToUserDefaults(_ message: String) {
        let defaults = UserDefaults.standard
        var logs = defaults.stringArray(forKey: userDefaultsKey) ?? []
        // タイムスタンプ生成
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy/MM/dd HH:mm:ss"
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        let japanTime = formatter.string(from: Date())
        logs.append("\(japanTime): \(message)")
        // ログの量が増えすぎないように最新100件に制限
        if logs.count > 100 {
            logs.removeFirst(logs.count - 100)
        }
        defaults.set(logs, forKey: userDefaultsKey)
        // メインスレッドで@Publishedを更新
        DispatchQueue.main.async {
            self.logs = logs
            //print("📝 LogManager: Logs updated on main thread: \(self.logs.count) entries")
        }
    }
    
    func retrieveLogsFromUserDefaults() -> [String] {
        return UserDefaults.standard.stringArray(forKey: userDefaultsKey) ?? []
    }
}
