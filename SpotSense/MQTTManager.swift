//
//  ContentView.swift
//  SpotSense
//
//  Created by 小玉敦郎 on 2025/02/13.
//

import Foundation
import CocoaMQTT
import CocoaMQTTWebSocket
import SwiftUI
import UIKit

class MQTTManager: NSObject, CocoaMQTTDelegate, ObservableObject {
    
    private var mqtt: CocoaMQTT?
    weak var externalDelegate: CocoaMQTTDelegate? // 外部デリゲートを追加
    private var reconnectTimer: Timer?
    private var waitingMessage: (topic: String, message: String)?

    @Published var isConnected: Bool = false
    @Published var receivedMessage: String = ""

    func connect() {
        let clientID = "iPhoneClient-\(UUID().uuidString.prefix(8))"
        let mqttHost = UserData.shared.mqttHost
        let mqttPort = UserData.shared.mqttPort
        
        // WebSocket を使用するための CocoaMQTTWebSocket の設定
        //let websocket = CocoaMQTTWebSocket(uri: "/mqtt")  // 必要に応じて WebSocket のパスを指定
        //websocket.enableSSL = false  // 必要なら true に変更
        // WebSocket を使う MQTT インスタンスを作成
        //mqtt = CocoaMQTT(clientID: clientID, host: "192.168.50.199", port: 8080, socket: websocket)
        
        // 通常のMQTT
        mqtt = CocoaMQTT(clientID: clientID, host: mqttHost, port: UInt16(mqttPort))
        
        // Auto Reconnectしない
        mqtt?.autoReconnect = false
        
        // Keep Alive 設定
        mqtt?.keepAlive = 300 // 300秒ごとに PING を送信
        mqtt?.delegate = self // 内部デリゲート
        _ = mqtt?.connect()
        
    }

    func publish(topic: String, message: String) {
        startBackgroundTask()
        
        guard let mqtt = mqtt else {
            print("❌ MQTTクライアントが初期化されていません")
            endBackgroundTask()
            return
        }
        
        // 接続が切れている場合は再接続を試みる
        if mqtt.connState != .connected {
            print("⚠️ Not connected to MQTT broker. Reconnecting...")
            _ = mqtt.connect()
            waitingMessage = (topic, message)  // 再接続後に送信するメッセージを保存
            // ⏳ 3秒後に再試行（接続完了待ち）
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                self.retryPublishIfNeeded()
            }
            return
        }

        // 接続済みならそのまま publish
        mqtt.publish(topic, withString: message, qos: .qos1)
        print("MQTT publish topic \(topic), message \(message)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            self.endBackgroundTask() // ⏳ 5秒後にタスク終了（適宜調整）
        }
    }
    
    // 接続成功時に、保留中のメッセージを送信
    func mqtt(_ mqtt: CocoaMQTT, didConnectAck ack: CocoaMQTTConnAck) {
        print("✅ Connected to MQTT broker")
        DispatchQueue.main.async {
           self.isConnected = true
           print("isConnected:\(self.isConnected)")
        }
        // 保留中のメッセージがあれば送信
        retryPublishIfNeeded()
        if let delegate = externalDelegate {
            print("🔌 Calling externalDelegate: \(delegate)")
            delegate.mqtt(mqtt, didConnectAck: ack)
        } else {
            print("❌ externalDelegate is nil - Delegate not set properly at \(Date())")
        }
    }

    // 再試行処理（接続完了後に再送信）
    private func retryPublishIfNeeded() {
        guard let (topic, message) = waitingMessage else { return }
        
        waitingMessage = nil  // 送信後クリア
        publish(topic: topic, message: message)  // 再送信
    }

    func disconnect() {
        mqtt?.willMessage = nil // メッセージキューをクリア
        mqtt?.disconnect()
        mqtt?.delegate = nil
        //isConnected = false
        DispatchQueue.main.async {
            self.isConnected = false
            print("MQTTManager: isConnected set to \(self.isConnected)")
        }
    }
    
    // メッセージ送信時のコールバック
    func mqtt(_ mqtt: CocoaMQTT, didPublishMessage message: CocoaMQTTMessage, id: UInt16) {
        print("📤 Published message: \(message.string ?? "") with ID: \(id)")
    }

    // メッセージ送信完了時のコールバック
    func mqtt(_ mqtt: CocoaMQTT, didPublishAck id: UInt16) {
        print("✅ Successfully published message with ID: \(id)")
    }

    // メッセージ受信時のコールバック
    func mqtt(_ mqtt: CocoaMQTT, didReceiveMessage message: CocoaMQTTMessage, id: UInt16) {
        print("📩 Received message: \(message.string ?? "") with ID: \(id)")
        DispatchQueue.main.async {
            self.receivedMessage = message.string ?? ""
        }
    }

    // サブスクライブ成功・失敗時のコールバック
    func mqtt(_ mqtt: CocoaMQTT, didSubscribeTopics success: NSDictionary, failed: [String]) {
        print("✅ Subscribed topics: \(success.allKeys)")
        if !failed.isEmpty {
            print("❌ Failed to subscribe to: \(failed)")
        }
    }

    // サブスクライブ解除時のコールバック
    func mqtt(_ mqtt: CocoaMQTT, didUnsubscribeTopics topics: [String]) {
        print("✅ Unsubscribed from topics: \(topics)")
    }

    // PING 送信時のコールバック
    func mqttDidPing(_ mqtt: CocoaMQTT) {
        print("📡 MQTT Ping sent")
    }

    // PONG 受信時のコールバック
    func mqttDidReceivePong(_ mqtt: CocoaMQTT) {
        print("📡 MQTT Pong received")
    }

    // 切断時のコールバック(再接続リトライ付き)
    func mqttDidDisconnect(_ mqtt: CocoaMQTT, withError err: Error?) {
        DispatchQueue.main.async {
            self.isConnected = false
            print("isConnected:\(self.isConnected)")
        }
        print("🔌 externalDelegate=\(String(describing: externalDelegate))")
        externalDelegate?.mqttDidDisconnect(mqtt, withError: err) // 外部に通知
    }

    // (オプション) TLS 証明書の手動検証
    func mqtt(_ mqtt: CocoaMQTT, didReceive trust: SecTrust, completionHandler: @escaping (Bool) -> Void) {
        print("🔐 Received SSL/TLS trust request")
        completionHandler(true) // 信頼する場合は `true` を渡す
    }

    // (オプション) URL セッションの認証
    func mqttUrlSession(_ mqtt: CocoaMQTT, didReceiveTrust trust: SecTrust, didReceiveChallenge challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        print("🔐 Received URLSession trust request")
        completionHandler(.useCredential, URLCredential(trust: trust))
    }

    // (オプション) メッセージ送信完了時のコールバック
    func mqtt(_ mqtt: CocoaMQTT, didPublishComplete id: UInt16) {
        print("✅ Publish complete for ID: \(id)")
    }

    // (オプション) 接続状態が変わった時のコールバック
    func mqtt(_ mqtt: CocoaMQTT, didStateChangeTo state: CocoaMQTTConnState) {
        print("🔄 Connection state changed: \(state)")
    }
    
    // バックグラウンド動作
    var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    func startBackgroundTask() {
        endBackgroundTask() // 🔥 既存のタスクがあれば終了
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "MQTTBackgroundTask") {
            self.endBackgroundTask() // タイムアウト時に終了
        }
        
        if backgroundTask == .invalid {
            print("❌ Failed to start background task")
        } else {
            print("✅ Background task started: \(backgroundTask)")
        }
    }

    func endBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
            print("🔄 Background task ended")
        }
    }
    
}

