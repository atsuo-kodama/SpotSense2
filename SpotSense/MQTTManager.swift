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
    
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 5 // 最大リトライ回数
    private var lastReconnectAttemptTime: Double = 0
    private let reconnectCooldown: Double = 3600 // 1時間
    
    private var waitingMessage: (topic: String, message: String)?

    @Published var isConnected: Bool = false
    @Published var receivedMessage: String = ""

    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    
//    override init() {
//        super.init()
//        connect()
//    }
    
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
        
        mqtt?.autoReconnect = true // 自動再接続を有効化
        mqtt?.autoReconnectTimeInterval = 5 // 初回5秒
        mqtt?.maxAutoReconnectTimeInterval = 60 // 最大60秒
        
        // Keep Alive 設定
        mqtt?.keepAlive = 300 // 300秒ごとに PING を送信
        
        mqtt?.delegate = self // 内部デリゲート
        
        startBackgroundTask()
        _ = mqtt?.connect()
        print("🔌 MQTT接続試行: host=\(mqttHost), port=\(mqttPort)")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.endBackgroundTask()
        }
    }

    func disconnect() {
        startBackgroundTask()
        mqtt?.willMessage = nil // メッセージキューをクリア
        mqtt?.disconnect()
        mqtt?.delegate = nil
        //isConnected = false
        DispatchQueue.main.async {
            self.isConnected = false
            print("MQTTManager: isConnected set to \(self.isConnected)")
        }
        endBackgroundTask()
    }
    
    func publishBeaconData(beaconData: [[String: Any]], mqttTopic: String) {
        guard !beaconData.isEmpty else {
            print("⚠️ No beacon data to publish")
            return
        }
        
        ensureConnection()
        guard isConnected else {
            print("❌ MQTT接続がないため送信スキップ")
            return
        }
        
        let dataLog = beaconData.map { "(major=\($0["major"]!), minor=\($0["minor"]!), avgRSSI=\($0["avgRSSI"]!))" }.joined(separator: ", ")
        print("📤 Publishing beacon data: [\(dataLog)]")
        
        startBackgroundTask()
        if let jsonData = try? JSONSerialization.data(withJSONObject: beaconData, options: []) {
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                mqtt?.publish(mqttTopic, withString: jsonString, qos: .qos1)
                print("MQTT publish topic \(mqttTopic), message \(jsonString)")
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.endBackgroundTask()
        }
    }
    
    func publish(topic: String, message: String) {
        ensureConnection()
        guard isConnected else {
            print("❌ MQTT接続がないため送信スキップ")
            waitingMessage = (topic, message)
            return
        }
        
        startBackgroundTask()
        mqtt?.publish(topic, withString: message, qos: .qos1)
        print("MQTT publish topic \(topic), message \(message)")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.endBackgroundTask()
        }
    }
    
    private func ensureConnection() {
        guard !isConnected else {
            print("🔌 MQTT接続済み")
            return
        }
        
        let currentTime = Date().timeIntervalSince1970
        guard currentTime - lastReconnectAttemptTime >= reconnectCooldown else {
            print("⏳ 再接続クールダウン中（残り: \(Int(reconnectCooldown - (currentTime - lastReconnectAttemptTime)))秒）")
            return
        }
        
        if reconnectAttempts >= maxReconnectAttempts {
            print("⚠️ 最大リトライ回数（\(maxReconnectAttempts)回）に達したため再接続を停止")
            mqtt?.autoReconnect = false
            return
        }
        
        startBackgroundTask()
        print("🔌 MQTT接続が切れているため再接続を試みます（試行\(reconnectAttempts + 1)/\(maxReconnectAttempts)）")
        _ = mqtt?.connect()
        reconnectAttempts += 1
        lastReconnectAttemptTime = currentTime
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.endBackgroundTask()
        }
    }
    
    // 再試行処理（接続完了後に再送信）
    private func retryPublishIfNeeded() {
        guard let (topic, message) = waitingMessage else { return }
        waitingMessage = nil
        publish(topic: topic, message: message)
    }
    
    // CocoaMQTTDelegate
    func mqtt(_ mqtt: CocoaMQTT, didConnectAck ack: CocoaMQTTConnAck) {
        print("✅ Connected to MQTT broker")
        DispatchQueue.main.async {
           self.isConnected = true
        }
        reconnectAttempts = 0
        lastReconnectAttemptTime = 0
        retryPublishIfNeeded()
        externalDelegate?.mqtt(mqtt, didConnectAck: ack)
    }

    func mqtt(_ mqtt: CocoaMQTT, didDisconnectWithError err: Error?) {
        print("❌ MQTT切断: \(err?.localizedDescription ?? "不明なエラー")")
        DispatchQueue.main.async {
            self.isConnected = false
        }
        if UIApplication.shared.applicationState == .background {
            print("⚠️ バックグラウンドでの切断検知")
            if reconnectAttempts < maxReconnectAttempts {
                ensureConnection()
            } else {
                print("⚠️ バックグラウンドでの最大リトライ回数に達したため再接続を停止")
                mqtt.autoReconnect = false
            }
        }
        externalDelegate?.mqttDidDisconnect(mqtt, withError: err)
    }
    
    // メッセージ送信時のコールバック
    func mqtt(_ mqtt: CocoaMQTT, didPublishMessage message: CocoaMQTTMessage, id: UInt16) {
        print("📤 Published message: \(message.string ?? "") with ID: \(id)")
        externalDelegate?.mqtt(mqtt, didPublishMessage: message, id: id)
    }

    // メッセージ送信完了時のコールバック
    func mqtt(_ mqtt: CocoaMQTT, didPublishAck id: UInt16) {
        print("✅ Successfully published message with ID: \(id)")
        externalDelegate?.mqtt(mqtt, didPublishAck: id)
    }

    // メッセージ受信時のコールバック
    func mqtt(_ mqtt: CocoaMQTT, didReceiveMessage message: CocoaMQTTMessage, id: UInt16) {
        print("📩 Received message: \(message.string ?? "") with ID: \(id)")
        DispatchQueue.main.async {
            self.receivedMessage = message.string ?? ""
        }
        externalDelegate?.mqtt(mqtt, didReceiveMessage: message, id: id)
    }

    // サブスクライブ成功・失敗時のコールバック
    func mqtt(_ mqtt: CocoaMQTT, didSubscribeTopics success: NSDictionary, failed: [String]) {
        print("✅ Subscribed topics: \(success.allKeys)")
        if !failed.isEmpty {
            print("❌ Failed to subscribe to: \(failed)")
        }
        externalDelegate?.mqtt(mqtt, didSubscribeTopics: success, failed: failed)
    }

    // サブスクライブ解除時のコールバック
    func mqtt(_ mqtt: CocoaMQTT, didUnsubscribeTopics topics: [String]) {
        print("✅ Unsubscribed from topics: \(topics)")
        externalDelegate?.mqtt(mqtt, didUnsubscribeTopics: topics)
    }

    // PING 送信時のコールバック
    func mqttDidPing(_ mqtt: CocoaMQTT) {
        print("📡 MQTT Ping sent")
        externalDelegate?.mqttDidPing(mqtt)
    }

    // PONG 受信時のコールバック
    func mqttDidReceivePong(_ mqtt: CocoaMQTT) {
        print("📡 MQTT Pong received")
        externalDelegate?.mqttDidReceivePong(mqtt)
    }

    // (オプション) TLS 証明書の手動検証
    func mqtt(_ mqtt: CocoaMQTT, didReceive trust: SecTrust, completionHandler: @escaping (Bool) -> Void) {
        print("🔐 Received SSL/TLS trust request")
        completionHandler(true) // 信頼する場合は `true` を渡す
        externalDelegate?.mqtt?(mqtt, didReceive: trust, completionHandler: completionHandler)
    }
    
    // (オプション) URL セッションの認証
    func mqttUrlSession(_ mqtt: CocoaMQTT, didReceiveTrust trust: SecTrust, didReceiveChallenge challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
         print("🔐 Received URLSession trust request")
         completionHandler(.useCredential, URLCredential(trust: trust))
         externalDelegate?.mqttUrlSession?(mqtt, didReceiveTrust: trust, didReceiveChallenge: challenge, completionHandler: completionHandler)
     }
    
     // (オプション) メッセージ送信完了時のコールバック
    func mqtt(_ mqtt: CocoaMQTT, didPublishComplete id: UInt16) {
        print("✅ Publish complete for ID: \(id)")
        externalDelegate?.mqtt?(mqtt, didPublishComplete: id)
    }

    // (オプション) 接続状態が変わった時のコールバック
    func mqtt(_ mqtt: CocoaMQTT, didStateChangeTo state: CocoaMQTTConnState) {
        print("🔄 Connection state changed: \(state)")
        externalDelegate?.mqtt?(mqtt, didStateChangeTo: state)
    }
   
    
    func resetReconnectAttempts() {
        reconnectAttempts = 0
        lastReconnectAttemptTime = 0
        mqtt?.autoReconnect = true
        print("🔄 リトライカウントをリセット")
        ensureConnection()
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

    // バックグラウンド動作
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

