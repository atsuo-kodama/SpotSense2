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
}
