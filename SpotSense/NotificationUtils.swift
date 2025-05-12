//
//  NotificationUtils.swift
//  SpotSense
//
//  Created by 小玉敦郎 on 2025/03/10.
//

import UIKit

class NotificationUtils {
    public static let shared = NotificationUtils()
    // 通知の許可リクエスト
    func requestPermission() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge]) { (granted, _) in
                print("Permission granted: \(granted)")
            }
    }
    
    // ローカル通知を送信
    func triggerLocalNotification(title: String, body: String) {
        DispatchQueue.main.async {
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    print("ローカル通知の送信に失敗しました: \(error)")
                }
            }
        }
    }
    
    // iBeaconリージョン入場時の通知をスケジュール
    func scheduleBeaconNotification() {
        let content = UNMutableNotificationContent()
        content.title = "SpotSenseを起動してください"
        content.body = "iPhoneの再起動を検知しました。SpotSenseを起動してください。"
        content.sound = .default
        content.categoryIdentifier = "beacon"
        content.badge = 1 // バッジを追加して注意を引く
        
        // アクションを追加（「今すぐ起動」ボタン）
        let action = UNNotificationAction(identifier: "open", title: "今すぐ起動", options: [.foreground])
        let category = UNNotificationCategory(identifier: "beacon", actions: [action], intentIdentifiers: [], options: [.customDismissAction])
        UNUserNotificationCenter.current().setNotificationCategories([category])
        
        // 即時通知（例：5秒後）
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to schedule notification: \(error)")
            }
        }
    }
}

class RebootDetector {
    static let shared = RebootDetector()
    
    private let defaults = UserDefaults.standard
    
    func checkForReboot() -> Bool {
        let currentUptime = ProcessInfo.processInfo.systemUptime
        let lastUptime = defaults.double(forKey: "lastUptime")
        
        let didReboot = currentUptime < lastUptime && lastUptime > 0
        
        defaults.set(currentUptime, forKey: "lastUptime")
        defaults.set(didReboot, forKey: "didReboot")
        
        return didReboot
    }

    func wasRebooted() -> Bool {
        return UserDefaults.standard.bool(forKey: "didReboot")
    }

    func clearRebootFlag() {
        UserDefaults.standard.set(false, forKey: "didReboot")
    }

}
