//
//  BeaconManager.swift
//  SpotSense
//
//  Created by 小玉敦郎 on 2025/02/23.
//

import Foundation
import CoreLocation
import CocoaMQTT
import UIKit

class BeaconManager: NSObject, ObservableObject, CLLocationManagerDelegate , CocoaMQTTDelegate {
    
    static let shared = BeaconManager() // シングルトンインスタンス
    @Published var detectedBeacons: [CLBeacon] = []  // ContentView に渡す
    
    private var locationManager: CLLocationManager
    private var mqttManager: MQTTManager
    
    private var beaconUUID = UUID(uuidString: "E0EC4313-5A62-46D3-A0A9-9305DBD4A63E")! //初期値
   
    private let mqttTopic = "beacon/data"
    
    private var scanTime: TimeInterval = 5  // Ranging時間(sec)
    private var sleepTime: TimeInterval = 55 // 休止時間(sec)
    private var rangingThreshold = 5  // 何回 Range したら publish するか
    
    private var isStartMonitoring = false
    private var isRanging = false
    private var isConnectedToMQTT = false  // MQTT接続状態を管理
    private var isInRegion = false
    private var rangingTask: DispatchWorkItem? // タイマーを管理
    
    private var notification = NotificationUtils.shared
    private var log = LogManager.shared
    
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    
    private let stabilityThreshold: Double = 5.0
    private var isStable: Bool = false
    
    private var userId: Int = 9999999 // OA番号
    
    private var lastStrongestBeacon: (major: NSNumber?, minor: NSNumber?)? // 前回の最強ビーコン
    
    private var isFirstEnterReasion: Bool = true
    
    func configure(with mqttManager: MQTTManager) {
        self.mqttManager = mqttManager
    }
    
    private var skipCounter = 0
    private var lastStaySent: Date?
    
    override init() {
        self.mqttManager = MQTTManager()
        self.locationManager = CLLocationManager()
        super.init()
        self.locationManager.delegate = self
        self.locationManager.allowsBackgroundLocationUpdates = true
        self.locationManager.pausesLocationUpdatesAutomatically = false
        self.locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        self.locationManager.distanceFilter = 3000.0
        self.mqttManager.externalDelegate = self // デリゲート設定
        print("⚠️ BeaconManager initialized, mqttManager=\(String(describing: mqttManager)), externalDelegate=\(String(describing: mqttManager.externalDelegate))")
    }
    
    var mqttManagerInstance: MQTTManager {
        return mqttManager
    }
    
    func startMonitoring() {
        guard !isStartMonitoring else { return } // 既に開始済み
        if !retrieveUserData() {
           return // パラメータ設定されていない場合は何もしない
        }
        
        print("*** startMonitoriing ***")
        
        // 既存の監視を一旦停止（リージョンをクリア）
        stopMonitoring()
        
        // バラメータ設定
        rangingThreshold = Int(exactly: UserData.shared.rangingCount)!
        scanTime = TimeInterval(UserData.shared.rangingCount)
        sleepTime = TimeInterval(60 - scanTime)
        beaconUUID = UUID(uuidString: UserData.shared.beaconUuidString)!
        userId = Int(UserData.shared.userId)!
        print("rangingThreshold: \(rangingThreshold), scanTime: \(scanTime), sleepTime: \(sleepTime)")
        print("beaconUUID: \(beaconUUID), userId: \(userId)")
        
        let region = CLBeaconRegion(uuid: beaconUUID, identifier: "BeaconRegion")
        region.notifyEntryStateOnDisplay = true // ユーザーがデバイスのロック画面を解除した時点でリージョンの状態が確認される
        region.notifyOnEntry = true
        region.notifyOnExit = true
        locationManager.startMonitoring(for: region)
        locationManager.requestState(for: region) // 初回の状態確認
        print("Beaconmanager : startMonitoring")
        log.saveLogToUserDefaults("Beaconmanager : startMonitoring")
        logToFile("Beaconmanager : startMonitoring")
    }
    
    func stopMonitoring() {
        // 全ての監視中のリージョンを停止
        for region in locationManager.monitoredRegions {
            locationManager.stopMonitoring(for: region)
        }
        stopRanging()
        disconnectMQTT()
        isInRegion = false
        isRanging = false
        isStartMonitoring = false
    }
    
    /// ** MQTTブローカーに接続**
    private func connectMQTT() {
        print("🔌 connectMQTT: isConnectedToMQTT=\(isConnectedToMQTT), mqttManager.isConnected=\(String(describing: mqttManager.isConnected))")
        if mqttManager.isConnected == true && !isConnectedToMQTT {
            disconnectMQTT()
            print("🔌 状態不整合のため強制切断")
        } else if isConnectedToMQTT {
            print("🔌 既にMQTTに接続済み")
            return
        }
        // connect前にデリゲートを再設定（念のため）
        mqttManager.externalDelegate = self
        print("🔌 externalDelegateを再設定: \(String(describing: mqttManager.externalDelegate))")
        mqttManager.connect()
        print("🔌 MQTTブローカーに接続試行")
        //log.saveLogToUserDefaults("Connecting MQTT broker")
    }
    
    /// ** MQTTブローカーとの接続を切断**
    private func disconnectMQTT() {
        guard isConnectedToMQTT else { return } // 既に切断済み
        mqttManager.disconnect()
        mqttManager.externalDelegate = nil
        //mqttManager = nil
        isConnectedToMQTT = false
        print("🔌 MQTTブローカーとの接続を切断")
        log.saveLogToUserDefaults("Disconnected MQTT broker")
    }
    
    // iBeaconのレンジングを開始
    private func startRangingCycle() {
        guard !isRanging else { return }
        isRanging = true
        rangingCounter = 0    // 初期化
        rssiBuffer.removeAll() // 初期化
        print("🔍 Start ranging")
        locationManager.startRangingBeacons(satisfying: CLBeaconIdentityConstraint(uuid: beaconUUID))

        DispatchQueue.main.asyncAfter(deadline: .now() + scanTime) { [weak self] in
            self?.stopRangingCycle()
            self?.scheduleNextRanging()
        }
    }

    private func stopRangingCycle() {
        print("🛑 Stop ranging")
        isRanging = false
        locationManager.stopRangingBeacons(satisfying: CLBeaconIdentityConstraint(uuid: beaconUUID))
    }

    private var sleepTimer: Timer?
    private func scheduleNextRanging() {
        print("⏳ Schedule next ranging in \(sleepTime) seconds")
        sleepTimer?.invalidate()
        sleepTimer = Timer.scheduledTimer(withTimeInterval: sleepTime, repeats: false) { [weak self] _ in
            self?.startRangingCycle()
        }
        RunLoop.main.add(sleepTimer!, forMode: .common)
    }
   
    // レンジングを完全に停止する
    func stopRanging() {
        guard isRanging else { return }
        isRanging = false
        let constraint = CLBeaconIdentityConstraint(uuid: beaconUUID)
        locationManager.stopRangingBeacons(satisfying: constraint)
        // 受信データをクリア
        self.detectedBeacons = []
        self.rssiBuffer.removeAll()
        self.rangingCounter = 0
        print("🚫 iBeaconレンジング完全停止")
    }
    
    // 信号安定性を評価する関数
    private func calculateRSSIStability(for beaconKey: CLBeaconIdentityConstraint) -> Bool {
        guard let rssiValues = rssiBuffer[beaconKey], rssiValues.count >= 3 else {
            return false
        }
        let mean = Double(rssiValues.reduce(0, +)) / Double(rssiValues.count)
        let variance = rssiValues.map { pow(Double($0) - mean, 2) }.reduce(0, +) / Double(rssiValues.count)
        let standardDeviation = sqrt(variance)
        let retval: Bool = standardDeviation < stabilityThreshold
        print("📊 RSSI安定度: beacon=\(beaconKey), stdDev=\(standardDeviation), retval=\(retval)")
        return retval
    }
    
    private var rangingCounter = 0
    private var rssiBuffer: [CLBeaconIdentityConstraint: [Int]] = [:]  // 各 iBeacon の rssi を保存
    
    func locationManager(_ manager: CLLocationManager, didRange beacons: [CLBeacon], satisfying constraint: CLBeaconIdentityConstraint) {
        guard !beacons.isEmpty else {
            self.detectedBeacons = []
            return
        }
        print("📡 Received beacons: \(beacons.map { "major=\($0.major), minor=\($0.minor), rssi=\($0.rssi)" })")
        //let currentTime = Date()
        //logToFile("📍 didRange called at: \(currentTime), constraint: UUID=\(constraint.uuid), major=\(constraint.major?.description ?? "nil"), minor=\(constraint.minor?.description ?? "nil"), beacons: \(beacons.count)")
        DispatchQueue.main.async {
            //print("📡 Updating detectedBeacons: \(beacons.count) beacons")
            self.detectedBeacons = beacons // ContentView に反映
        }
        // 全ビーコンのRSSIをバッファに追加
        for beacon in beacons {
            logToFile("📡 Beacon: UUID=\(beacon.uuid), major=\(beacon.major), minor=\(beacon.minor), rssi=\(beacon.rssi)")
            let beaconKey = CLBeaconIdentityConstraint(
                uuid: beacon.uuid,
                major: CLBeaconMajorValue(truncating: beacon.major),
                minor: CLBeaconMinorValue(truncating: beacon.minor)
            )
            let rssiValue = beacon.rssi
            
            // rssi の履歴を保存
            if rssiBuffer[beaconKey] == nil {
                rssiBuffer[beaconKey] = []
            }
            rssiBuffer[beaconKey]?.append(rssiValue)
            
            // 保存する rssi の数を制限（無限に増えないように）
            if rssiBuffer[beaconKey]!.count > rangingThreshold {
                rssiBuffer[beaconKey]?.removeFirst()
            }
        }
        print("📡 Beacon Ranging: \(beacons.count) beacons found, rangingCounter=\(rangingCounter + 1)")
        logToFile("Beacon Ranging: \(beacons.count) beacons found, rangingCounter=\(rangingCounter + 1)")
        rangingCounter += 1
        
        // rangingThreshold回ごとに処理
        if rangingCounter >= rangingThreshold {
            // 平均RSSIを計算し、最強ビーコンを決定
            var averageRSSI: [CLBeaconIdentityConstraint: Double] = [:]
            for (key, rssiValues) in rssiBuffer {
                let avg = Double(rssiValues.reduce(0, +)) / Double(rssiValues.count)
                // 小数点以下1桁に丸める
                let roundedAvg = (avg * 10).rounded() / 10
                averageRSSI[key] = roundedAvg
            }
            guard let strongestBeaconKey = averageRSSI.max(by: { $0.value < $1.value })?.key else {
                return
            }
            let strongestMajor = NSNumber(value: strongestBeaconKey.major!)
            let strongestMinor = NSNumber(value: strongestBeaconKey.minor!)
            let strongestRSSI = averageRSSI[strongestBeaconKey]!
            print("📊 Average RSSI calculated: major=\(strongestMajor), minor=\(strongestMinor), avgRSSI=\(strongestRSSI)")
            
            // hasChangedを判定
            let hasBeaconChanged = updateStrongestBeaconHistory(major: strongestMajor, minor: strongestMinor)
            print("📡 最強ビーコン (平均): major=\(strongestMajor), minor=\(strongestMinor), avgRSSI=\(strongestRSSI), changed=\(hasBeaconChanged)")
            
            // publish処理
            if hasBeaconChanged || isFirstEnterReasion {
                var beaconData: [[String: Any]] = []
                for (key, avgRSSI) in averageRSSI {
                    let beaconDict: [String: Any] = [
                        "major": NSNumber(value: key.major!),
                        "minor": NSNumber(value: key.minor!),
                        "avgRSSI": Int(round(avgRSSI)),
                        "id": userId
                    ]
                    beaconData.append(beaconDict)
                }
                mqttManager.publishBeaconData(beaconData: beaconData, mqttTopic: mqttTopic)
                isFirstEnterReasion = false
                sleepTime = 65 - scanTime
                print("📤 部屋移動検出: MQTT送信 \(beaconData)")
                logToFile("部屋移動検出: MQTT送信 \(beaconData)")
                skipCounter = 0  // カウンターをリセット
            } else {
                print("⏸️ 部屋変更なし: 送信スキップ")
                logToFile("部屋変更なし: 送信スキップ")
                if !hasBeaconChanged && rangingCounter >= rangingThreshold {
                    sleepTime = 125 - scanTime
                    print("💤 同一部屋滞在: sleepTimeを\(sleepTime)秒に延長")
                }
                skipCounter += 1
                print("skipCounter:\(skipCounter)")
                logToFile("⏸️ No change: skipCounter=\(skipCounter), sleepTime=\(sleepTime)")
                if skipCounter >= 5 { // 部屋変更なしが続いたら生存確認のためpublishする
                    if lastStaySent != nil {
                        let cycleTime = Date().timeIntervalSince(lastStaySent!)
                        logToFile("✅ Cycle completed: \(cycleTime) seconds")
                        lastStaySent = Date()
                    }
                    var beaconData: [[String: Any]] = []
                    let beaconDict: [String: Any] = [
                        "major": strongestMajor,
                        "minor": strongestMinor,
                        "avgRSSI": Int(round(strongestRSSI)),
                        "id": userId
                    ]
                    beaconData.append(beaconDict)
                    mqttManager.publishBeaconData(beaconData: beaconData, mqttTopic: mqttTopic) // 最強のbeaconのデータだけpublish
                    //skipPublish()
                    skipCounter = 0
                }
            }
            rangingCounter = 0
            // rssibufferをクリア
            rssiBuffer.removeAll()
        }
    }
    
    // 安定かつ最強のBeaconを判定する
    private var strongestBeaconHistory: [(major: NSNumber?, minor: NSNumber?, count: Int)] = []
    
    func updateStrongestBeaconHistory(major: NSNumber?, minor: NSNumber?) -> Bool {
        // 履歴に現在のビーコンを追加または更新
        if let index = strongestBeaconHistory.firstIndex(where: { $0.major == major && $0.minor == minor }) {
            strongestBeaconHistory[index].count += 1
        } else {
            strongestBeaconHistory.append((major: major, minor: minor, count: 1))
            if strongestBeaconHistory.count > 10 {
                strongestBeaconHistory.removeFirst()
            }
        }
        // ログ出力
        let historyLog = strongestBeaconHistory.map { "(\($0.major ?? 0), \($0.minor ?? 0), count: \($0.count))" }.joined(separator: ", ")
        print("📜 strongestBeaconHistory: [\(historyLog)]")
        let lastLog = lastStrongestBeacon != nil ? "(\(lastStrongestBeacon!.major ?? 0), \(lastStrongestBeacon!.minor ?? 0))" : "nil"
        print("📌 lastStrongestBeacon: \(lastLog)")
        // 初回は変化なしとして初期化
        if lastStrongestBeacon == nil {
            lastStrongestBeacon = (major: major, minor: minor)
            print("➡️ Initializing lastStrongestBeacon to (\(major ?? 0), \(minor ?? 0))")
            return true // 初回は部屋移動とみなす（必要に応じてfalseも可）
        }
        // 最強ビーコンがstayThreshold回連続同じの時，部屋移動なし
        let stayThreshold = 4
        if let stableBeacon = strongestBeaconHistory.max(by: { $0.count < $1.count }) {
            print("stableBeacon.count: \(stableBeacon.count)")
            if stableBeacon.count >= stayThreshold && stableBeacon.major == major && stableBeacon.minor == minor {
                // 部屋の変化なし
                lastStrongestBeacon = (major: major, minor: minor)
                print("ℹ️ Stable beacon (\(major ?? 0), \(minor ?? 0)) confirmed for \(stayThreshold) times, no change")
                return false
            }
            // 部屋移動あり
            if stableBeacon.count < stayThreshold {
                lastStrongestBeacon = (major: major, minor: minor)
                print("➡️ Less than \(stayThreshold) consecutive detections, treating as change")
                return true
            }
        }
        // それ以外は部屋が変わったと判定
        let hasChanged = lastStrongestBeacon?.major != major || lastStrongestBeacon?.minor != minor
        if hasChanged {
            lastStrongestBeacon = (major: major, minor: minor)
            strongestBeaconHistory.removeAll() // 部屋が変わったので履歴をリセット
            strongestBeaconHistory.append((major: major, minor: minor, count: 1)) // 新しいビーコンを追加
            print("➡️ Updated lastStrongestBeacon to (\(major ?? 0), \(minor ?? 0)) due to change")
        }
        return hasChanged // 変更時はtrue、同一時はfalseを返す
    }
    
    // データ送信スキップ
    private func skipPublish() {
        // バックグラウンドタスクを開始
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "SkipPublish") { [weak self] in
            guard let strongSelf = self else { return }
            strongSelf.disconnectMQTT()
            UIApplication.shared.endBackgroundTask(strongSelf.backgroundTaskID)
            strongSelf.backgroundTaskID = .invalid
        }
        
        mqttManager.publish(topic: mqttTopic, message: "{\"id\": \"\(userId)\",\"event\": \"stay\"}")
        
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
            //self.disconnectMQTT()
            if self.backgroundTaskID != .invalid {
                UIApplication.shared.endBackgroundTask(self.backgroundTaskID)
                self.backgroundTaskID = .invalid
            }
        }
    }
    
    // ** 領域に入った場合**
    func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        print("🔵 Entered beacon region: \(region.identifier)")
        log.saveLogToUserDefaults("Entered beacon region")
        logToFile("Entered beacon region: \(region.identifier)")
        isInRegion = true
        strongestBeaconHistory.removeAll() // 履歴をリセット
        handleEnterRegion()
    }
    
    
    private var lastProcessedEventTime: Date? // 単一リージョン用の最後のイベント処理時間
    private let eventCooldownTime: TimeInterval = 15 // 15秒間の重複を無視
    
    func handleEnterRegion() {
        
        let now = Date()
        if let lastEventTime = lastProcessedEventTime, now.timeIntervalSince(lastEventTime) < eventCooldownTime {
            print("handleEnterReasion: 重複イベントを無視: 前回から \(now.timeIntervalSince(lastEventTime))秒")
            logToFile("handleEnterReasion: 重複イベントを無視: 前回から \(now.timeIntervalSince(lastEventTime))秒")
            return
        }
        // 今回のイベント時間を記録
        lastProcessedEventTime = now
        
        // 再起動後の入場かチェック
        let hasLaunched = UserDefaults.standard.bool(forKey: "hasLaunchedSinceReboot")
        let wasRebooted = RebootDetector.shared.wasRebooted()
        logToFile("*** wasRebooted: \(wasRebooted) hasLaunched: \(hasLaunched) ***")
        if wasRebooted || !hasLaunched {
            // 通知とバッジ表示
            NotificationUtils.shared.scheduleBeaconNotification()
            //UIApplication.shared.applicationIconBadgeNumber = 1
            UNUserNotificationCenter.current().setBadgeCount(1) //{ error in
        }
        
        let notificationFlg = UserData.shared.notificationFlg
        if notificationFlg {
            notification.triggerLocalNotification(title: "SpotSense", body: "iBeacon領域に入りました")
        }
        
        if backgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskID)
            backgroundTaskID = .invalid
        }
        
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "HandleEnterRegion") { [weak self] in
            guard let self = self else { return }
            self.stopRanging()
            self.disconnectMQTT()
            UIApplication.shared.endBackgroundTask(self.backgroundTaskID)
            self.backgroundTaskID = .invalid
        }
        
        connectMQTT()
        
        DispatchQueue.global().asyncAfter(deadline: .now() + 5.0) {
            if self.isConnectedToMQTT {
                //self.startRangingWithInterval()
                self.startRangingCycle()
                self.mqttManager.publish(topic: self.mqttTopic, message: "{\"id\": \"\(self.userId)\",\"event\": \"enter\"}")
                self.isFirstEnterReasion = true
                print("✅ レンジング開始(初回)")
                self.logToFile("レンジング開始(初回)")
            } else {
                print("❌ MQTT接続に失敗")
                self.logToFile("MQTT接続に失敗")
            }
            // ここではタスクを終了しない（領域内にいる間継続）
            if self.backgroundTaskID != .invalid {
                UIApplication.shared.endBackgroundTask(self.backgroundTaskID)
                self.backgroundTaskID = .invalid
                print("🔄 HandleEnterRegion background task ended")
                self.logToFile("HandleEnterRegion background task ended")
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard isInRegion else { return }
        print("⚪ Exited beacon region: \(region.identifier)")
        log.saveLogToUserDefaults("Exited beacon region")
        isInRegion = false
        handleExitRegion(region: region)
    }
    
    func handleExitRegion(region: CLRegion) {
        let notificationFlg = UserData.shared.notificationFlg
        if notificationFlg {
            notification.triggerLocalNotification(title: "SpotSense", body: "iBeacon領域から出ました")
        }
        stopRanging()
        
        // 領域退出時に履歴を初期化
        strongestBeaconHistory.removeAll()
        lastStrongestBeacon = nil
        print("🗑️ Cleared strongestBeaconHistory and lastStrongestBeacon on region exit")
        
        guard isConnectedToMQTT else {
            print("⚠️ MQTT未接続のため、メッセージを送信できません")
            if backgroundTaskID != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTaskID)
                backgroundTaskID = .invalid
            }
            return
        }
        
        mqttManager.publish(topic: mqttTopic, message: "{\"id\": \"\(userId)\",\"event\": \"exit\"}")
        
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
            self.disconnectMQTT()
            if self.backgroundTaskID != .invalid {
                UIApplication.shared.endBackgroundTask(self.backgroundTaskID)
                self.backgroundTaskID = .invalid
            }
        }
    }
    
    // 現在リージョン内かどうか
    func requestCurrentRegionState() {
        let region = CLBeaconRegion(uuid: beaconUUID, identifier: "BeaconRegion")
        locationManager.requestState(for: region)
    }
    
    // ** すでに領域内だった場合**
    func locationManager(_ manager: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
        if state == .inside {
            guard !isInRegion else { return } // すでにdidEnterRegionが実行されていたら何もしない
            print("📡 すでにビーコン領域内")
            logToFile("📡 すでにビーコン領域内")
            isInRegion = true
            handleEnterRegion()
        } else if state == .outside {
            guard isInRegion else { return } // すでにdidExitRegionが実行されていたら何もしない
            print("🚫 ビーコン領域外")
            isInRegion = false
            handleExitRegion(region: region)
        }
    }
    
    private var completion: ((Bool) -> Void)?
    func requestLocationPermission(completion: @escaping (Bool) -> Void) {
        self.completion = completion
        print("***** requestLocationPermission called *****")
        
        // `CLLocationManager.authorizationStatus()` をバックグラウンドスレッドで呼ぶ
        DispatchQueue.global(qos: .background).async {
            let manager = CLLocationManager()
            let status = manager.authorizationStatus
            print("***** requestlocationPermission status: \(status)")
            
            switch status {
            case .notDetermined:
                print("Requesting location permission...")
                self.locationManager.requestAlwaysAuthorization()
            case .authorizedAlways, .authorizedWhenInUse:
                completion(true) // すでに許可されている場合は即完了（メインスレッドで）
            default:
                completion(false) // 拒否されている場合もメインスレッドで完了
            }
        }
    }
    
    // CLLocationManagerDelegateのメソッド
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            print("位置情報の許可が得られました")
            locationManager.startUpdatingLocation() // レンジングを始める前にロケーション更新を開始しておく
        case .denied, .restricted:
            print("位置情報が拒否されました")
        case .notDetermined:
            print("許可がまだ決定していません")
        @unknown default:
            break
        }
    }
    
    // CocoaMQTTDelegateの実装
    func mqtt(_ mqtt: CocoaMQTT, didConnectAck ack: CocoaMQTTConnAck) {
        isConnectedToMQTT = true
        print("🔌 BeaconManager: MQTT接続成功: \(ack), isConnectedToMQTT=\(isConnectedToMQTT)")
        log.saveLogToUserDefaults("Connected MQTT broker")
    }
    
    func mqttDidDisconnect(_ mqtt: CocoaMQTT, withError err: Error?) {
        isConnectedToMQTT = false
        print("🔌 BeaconManager: MQTT切断: \(err?.localizedDescription ?? "不明"), isConnectedToMQTT=\(isConnectedToMQTT)")
        log.saveLogToUserDefaults("Disconnected MQTT broker")
    }
    
    // その他のデリゲートメソッドを実装（必要に応じて）
    func mqtt(_ mqtt: CocoaMQTT, didReceiveMessage message: CocoaMQTTMessage, id: UInt16) {}
    func mqtt(_ mqtt: CocoaMQTT, didPublishMessage message: CocoaMQTTMessage, id: UInt16) {}
    func mqtt(_ mqtt: CocoaMQTT, didSubscribeTopics success: NSDictionary, failed: [String]) {}
    func mqtt(_ mqtt: CocoaMQTT, didUnsubscribeTopics topics: [String]) {}
    func mqtt(_ mqtt: CocoaMQTT, didPublishAck id: UInt16) {}
    func mqttDidPing(_ mqtt: CocoaMQTT) {}
    func mqttDidReceivePong(_ mqtt: CocoaMQTT) {}
    
    // デバッグ用のログ出力
    func logToFile(_ message: String) {
        guard UserData.shared.loggingFlg else { return }
        let date = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        let jstDateString = formatter.string(from: date)
        let logMessage = "[\(jstDateString)] \(message)\n"
        let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("app.log")
        
        // ログメッセージをData型に変換
        guard let data = logMessage.data(using: .utf8) else {
            print("❌ Failed to convert log message to Data")
            return
        }
        
        do {
            // ファイルが存在するかチェック
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
                if let fileSize = attributes[.size] as? Int, fileSize > 100_000 { // 100KB超
                    try FileManager.default.removeItem(at: fileURL)
                    try data.write(to: fileURL)
                } else {
                    // 既存ファイルに追記
                    let fileHandle = try FileHandle(forWritingTo: fileURL)
                    try fileHandle.seekToEnd()
                    //try fileHandle.write(data)
                    fileHandle.write(data)  // write()メソッドはエラーをスローしなくなった
                    try fileHandle.close()
                }
            } else {
                // 新規ファイルを作成
                try data.write(to: fileURL)
            }
        } catch {
            print("❌ Failed to write to log file: \(error)")
        }
    }
    
    // UserDefaultsから取り出し
    private func retrieveUserData() -> Bool {
        
        if let storedId = UserDefaults.standard.string(forKey: "savedUserId") {
            UserData.shared.userId = storedId
        } else {
            return false
        }
        
        if let storedBeaconUuid: [String] = UserDefaults.standard.array(forKey: "uuidFields") as? [String] {
            UserData.shared.beaconUuidString = String(storedBeaconUuid.joined(separator: "-"))
        } else {
            return false
        }
        
        if let storedCount = UserDefaults.standard.string(forKey: "rangingCount") {
            UserData.shared.rangingCount = Int(storedCount)!
        } else {
            return false
        }
        
        if let storedMqttHost = UserDefaults.standard.string(forKey: "mqttHost") {
            UserData.shared.mqttHost = storedMqttHost
        } else {
            return false
        }
        
        if let storedMqttPort = UserDefaults.standard.string(forKey: "mqttPort") {
            UserData.shared.mqttPort = Int(storedMqttPort)!
        } else {
            return false
        }
        
        if let flgValue = UserDefaults.standard.object(forKey: "notificationFlg") as? Bool {
            UserData.shared.notificationFlg = flgValue
        } else {
            return false
        }
        
        return true
    }
}
