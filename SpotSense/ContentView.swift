//
//  ContentView.swift
//  SpotSense
//
//  Created by 小玉敦郎 on 2025/02/22.
//

import SwiftUI
import CoreLocation

struct ContentView: View {
    @EnvironmentObject private var beaconManager: BeaconManager  // AppDelegateから取得
    private var mqttManager: MQTTManager { beaconManager.mqttManagerInstance } // BeaconManagerから取得
    @StateObject private var logmanager = LogManager.shared

    @ObservedObject var userData = UserData.shared
    
    @State private var showAlert = false // アラートの表示状態を管理
    
    // アプリのライフサイクルを監視
    @Environment(\.scenePhase) private var scenePhase
    // 画面遷移の時に使用するbool値
    @State private var isPresented: Bool = false
    
    @State private var isConfigured = false // 設定済みフラグ

    private var notificationutils = NotificationUtils.shared
    
    // 初期値　最初にここの値がuserDefaultsに保存される
    // あちこちに初期値があるが，ここの値がUserDefaultsに保存されるので、ここだけ修正すれば良い
    private var defaultUuidFields: [String] = ["00002a19", "0000", "1000", "8000", "00805f9b34fb"]
    //private var defaultMqttHost: String = "test.mosquitto.org"  // for test
    private var defaultMqttHost: String = "RD227-1021.intra.sharedom.net"
    private var defaultMqttPort: String = "1883"
    private var defaultRangingCount: String = "3"
    private var defaultNotificationFlg: Bool = true
    private var defaultLoggingFlg: Bool = false

    init() {
    }
    
    var body: some View {
        VStack (spacing: 1){
            Spacer()
            HStack{
                Spacer()
                Image("SpotSense")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 25, height: 25)
                    .padding()
                Text("SpotSense")
                    .font(.title2)
                Spacer()
                Button(action: { // 設定ボタンが押された
                    beaconManager.stopMonitoring()
                    isPresented = true
                }) {
                    Image(systemName: "gearshape")
                }
                .padding()
                .fullScreenCover(isPresented: $isPresented) {
                    SettingView(onDismiss: handleDismiss)
                }
            }
            List {
                Section {
                    ForEach(beaconManager.detectedBeacons, id:  \.uniqueID) { beacon in
                        VStack(alignment: .leading) {
                            Text("Major: \(beacon.major), Minor: \(beacon.minor)")
                                .font(.headline)
                            Text("Distance: \(String(format: "%.2f", beacon.accuracy)) m")
                                .font(.subheadline)
                        }
                    }
                } header: {
                    Text("Detected Beacons")
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .textCase(nil)
                }
            }
            .frame(height: 200)
            .padding()

            List {
                Section {
                    ForEach(logmanager.logs, id: \.self) { log in
                        Text(log)
                            .font(.body)
                            .foregroundColor(.primary)
                    }
                } header: {
                    Text("Log") // Header に "Log" を表示
                        .font(.subheadline) // 見出しのフォントスタイル
                        .foregroundColor(.primary) // テキストの色
                        .textCase(nil) // 大文字変換を無効にする
                }
            }
            .frame(height: 250) // リスト全体の高さを制限
            .id(UUID())
            .onAppear {
                logmanager.logs = logmanager.retrieveLogsFromUserDefaults()
            }
            .onChange(of: scenePhase) { oldPahse, newPhase in
                if newPhase == .active {
                    logmanager.logs = logmanager.retrieveLogsFromUserDefaults() // アプリがフォアグラウンドになったら更新
                    print("connect=",mqttManager.isConnected)
                }
            }
            .padding()
            Text("Your OA Number: \(userData.userId)")
            Text("Connection Status: \(mqttManager.isConnected ? "Connected" : "Disconnected")")
                .foregroundColor(mqttManager.isConnected ? .green : .red)
                .padding()
        }
        .onAppear {
            if !isConfigured {
                beaconManager.configure(with: mqttManager)
                          isConfigured = true
                      }
            beaconManager.requestLocationPermission(completion: { _ in })
            notificationutils.requestPermission()
            // UserDefaultsから保存されたIDを取得する
            if retrieveUserData() {
                beaconManager.startMonitoring()
                print("📡 ContentView appeared. BeaconManager started.")
            } else {
                showAlert = true
            }
        }
        .alert("OA番号が未設定です", isPresented: $showAlert) {
            Button("OK") {
            isPresented = true
            }
        } message: {
            Text("次に表示されるSettings画面で，OA番号を設定してください。")
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .active {
                // アプリ起動検知時にフラグ・通知・バッジをリセット
                UNUserNotificationCenter.current().setBadgeCount(0)
                UNUserNotificationCenter.current().removeAllDeliveredNotifications()
                UserDefaults.standard.set(true, forKey: "hasLaunchedSinceReboot")
                RebootDetector.shared.clearRebootFlag()
            }
        }
    }
    
    // コールバック用のクロージャを定義
    private func handleDismiss() {
        print("SettingViewが閉じました")
        if userData.userId == "" {
           showAlert = true
            return
        }
        beaconManager.startMonitoring()
        print("📡 SettingsView closed. BeaconManager started.")
    }
    
    // UserDefaultsから取り出し
    private func retrieveUserData() -> Bool {
        var id_ok = false
        
        if let storedId = UserDefaults.standard.string(forKey: "savedUserId") {
            userData.userId = storedId
            id_ok = true
        }
        
        if let storedBeaconUuid: [String] = UserDefaults.standard.array(forKey: "uuidFields") as? [String] {
            userData.beaconUuidString = String(storedBeaconUuid.joined(separator: "-"))
            //print(String(storedBeaconUuid.joined(separator: "-")))
        } else {
            UserDefaults.standard.set(defaultUuidFields, forKey: "uuidFields")
            userData.beaconUuidString = String(defaultUuidFields.joined(separator: "-"))
        }
        
        if let storedMqttHost = UserDefaults.standard.string(forKey: "mqttHost") {
            userData.mqttHost = storedMqttHost
        } else {
            UserDefaults.standard.set(defaultMqttHost, forKey: "mqttHost")
            userData.mqttHost = defaultMqttHost
        }
        
        if let storedMqttPort = UserDefaults.standard.string(forKey: "mqttPort") {
            userData.mqttPort = Int(storedMqttPort)!
        } else {
            UserDefaults.standard.set(defaultMqttPort, forKey: "mqttPort")
            userData.mqttPort = Int(defaultMqttPort)!
        }
        
        if let storedCount = UserDefaults.standard.string(forKey: "rangingCount") {
            userData.rangingCount = Int(storedCount)!
        } else {
            UserDefaults.standard.set(defaultRangingCount, forKey: "rangingCount")
            userData.rangingCount = Int(defaultRangingCount)!
        }
        
        if let flgValue = UserDefaults.standard.object(forKey: "notificationFlg") as? Bool {
            userData.notificationFlg = flgValue
        } else {
            UserDefaults.standard.set(defaultNotificationFlg, forKey: "notificationFlg")
            userData.notificationFlg = defaultNotificationFlg
        }
        
        if let logFlg = UserDefaults.standard.object(forKey: "loggingFlg") as? Bool {
            userData.loggingFlg = logFlg
        } else {
            UserDefaults.standard.set(defaultLoggingFlg, forKey: "loggingFlg")
            userData.loggingFlg = defaultLoggingFlg
        }
        print("id_ok=\(id_ok)")
        return (id_ok)
    }
}

#Preview {
    ContentView()
        .environmentObject(BeaconManager())
}

class UserData: ObservableObject {
    @Published var userId: String = ""
    @Published var beaconUuidString: String = ""
    @Published var mqttHost: String = ""
    @Published var mqttPort: Int = 0
    @Published var rangingCount: Int = 0
    @Published var isChanged: Bool = false
    @Published var notificationFlg: Bool = true
    @Published var loggingFlg: Bool = false
    static let shared = UserData() // シングルトンインスタンス
    private init() {} // プライベートな初期化でインスタンス化を制限
}
