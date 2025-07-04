//
//  SettingView.swift
//  SettingView
//
//  Created by 小玉敦郎 on 2025/03/11.
//

import SwiftUI

struct SettingView: View {
    @State private var idNumber: String = ""
    @State private var uuidFields: [String] = ["00002a19", "0000", "1000", "8000", "00805f9b34fb"]
    //@State private var uuidFields: [String] = ["E0EC4313", "5A62", "46D3", "A0A9", "9305DBD4A63E"]
    @State private var mqttHost: String = "test.mosquitto.org"
    @State private var mqttPort: String = "1883"
    @State private var mqttQos: String = "1"
    @State private var mqttKeepAlive: String = "300"
    @State private var rangingCount: String = "10"
    @State private var notificationFlg: Bool = true
    @State private var loggingFlg : Bool = false
    @State private var showAlert: Bool = false
    @State private var alertMessage: String = ""
    @FocusState private var isIdNumberFocused: Bool
    @FocusState private var isMqttPortFocused: Bool
    @FocusState private var isRangingCountFocused: Bool
    
    // 画面を閉じるための環境変数
    @Environment(\.dismiss) private var dismiss
    let onDismiss: () -> Void
    
    private let uuidMaxLengths = [8, 4, 4, 4, 12]
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("OA Number (7 digits)")) {
                    HStack {
                        TextField("e.g., 1234567", text: $idNumber)
                            .keyboardType(.numberPad)
                            .font(.system(size: 16))
                            .focused($isIdNumberFocused)
                        
                        Button(action: {
                            isIdNumberFocused = false
                        }) {
                            Image(systemName: "keyboard.chevron.compact.down")
                                .foregroundColor(.gray)
                        }
                    }
                }
                
                Section(header: Text("iBeacon UUID")) {
                    HStack(spacing: 5) {
                        TextField("UUID 1", text: Binding(
                            get: { uuidFields[0] },
                            set: { newValue in
                                let filtered = newValue.filter { $0.isHexDigit }
                                if filtered.count <= uuidMaxLengths[0] {
                                    uuidFields[0] = filtered
                                }
                            }
                        ))
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 16))
                        
                        Text("-")
                            .font(.system(size: 16))
                        
                        TextField("UUID 2", text: Binding(
                            get: { uuidFields[1] },
                            set: { newValue in
                                let filtered = newValue.filter { $0.isHexDigit }
                                if filtered.count <= uuidMaxLengths[1] {
                                    uuidFields[1] = filtered
                                }
                            }
                        ))
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 16))
                        
                        Text("-")
                            .font(.system(size: 16))
                        
                        TextField("UUID 3", text: Binding(
                            get: { uuidFields[2] },
                            set: { newValue in
                                let filtered = newValue.filter { $0.isHexDigit }
                                if filtered.count <= uuidMaxLengths[2] {
                                    uuidFields[2] = filtered
                                }
                            }
                        ))
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 16))
                    }
                    
                    HStack(spacing: 5) {
                        Text("-")
                            .font(.system(size: 16))
                        
                        TextField("UUID 4", text: Binding(
                            get: { uuidFields[3] },
                            set: { newValue in
                                let filtered = newValue.filter { $0.isHexDigit }
                                if filtered.count <= uuidMaxLengths[3] {
                                    uuidFields[3] = filtered
                                }
                            }
                        ))
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 16))
                        
                        Text("-")
                            .font(.system(size: 16))
                        
                        TextField("UUID 5", text: Binding(
                            get: { uuidFields[4] },
                            set: { newValue in
                                let filtered = newValue.filter { $0.isHexDigit }
                                if filtered.count <= uuidMaxLengths[4] {
                                    uuidFields[4] = filtered
                                }
                            }
                        ))
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 16))
                    }
                }
                
                Section(header: Text("MQTT Broker / Port / QOS / KEEP ALIVE")) {
                    TextField("Host or IP", text: $mqttHost)
                        .font(.system(size: 16))
                    
                    HStack {
                        TextField("Port", text: $mqttPort)
                            .keyboardType(.numberPad)
                            .font(.system(size: 16))
                            .focused($isMqttPortFocused)
                        // 縦のセパレーター
                                Rectangle()
                                    .frame(width: 1, height: 24)
                                    .foregroundColor(.gray)
                                    .padding(.horizontal, 4)
                        TextField("QoS", text: $mqttQos)
                            .keyboardType(.numberPad)
                            .font(.system(size: 16))
                            .focused($isMqttPortFocused)
                            .frame(width:30)
                        // 縦のセパレーター
                                Rectangle()
                                    .frame(width: 1, height: 24)
                                    .foregroundColor(.gray)
                                    .padding(.horizontal, 4)
                        TextField("KeepAlive", text: $mqttKeepAlive)
                            .keyboardType(.numberPad)
                            .font(.system(size: 16))
                            .focused($isMqttPortFocused)

                        Button(action: {
                            isMqttPortFocused = false
                        }) {
                            Image(systemName: "keyboard.chevron.compact.down")
                                .foregroundColor(.gray)
                        }
                    }
                }
                
                Section (header: Text("Beacon Ranging Count")) {
                    HStack {
                        TextField("Count", text: $rangingCount)
                            .keyboardType(.numberPad)
                            .font(.system(size: 16))
                            .focused($isRangingCountFocused)
                        Button(action: {
                            isRangingCountFocused = false
                        }) {
                            Image(systemName: "keyboard.chevron.compact.down")
                                .foregroundColor(.gray)
                        }
                    }
                }
                Section (header: Text("Notifications and Logs")) {
                    Toggle("iBeacon Region Notifications", isOn: $notificationFlg)
                        .font(.system(size: 14))
                        .toggleStyle(SwitchToggleStyle(tint: .green))
                    Toggle("Log Debug Information", isOn: $loggingFlg)
                        .font(.system(size: 14))
                        .toggleStyle(SwitchToggleStyle(tint: .green))
                }
                }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        dismiss()
                        onDismiss() // 閉じた後にコールバックを実行
                    }) {
                        Text("Cancel")
                            .font(.system(size: 18))
                            .foregroundColor(.blue)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        isIdNumberFocused = false
                        isMqttPortFocused = false
                        saveToUserDefaults()
                    }) {
                        Text("Save")
                            .font(.system(size: 18))
                            .foregroundColor(.blue)
                    }
                }
            }
            .alert(isPresented: $showAlert) {
                Alert(
                    title: Text("Error"),
                    message: Text(alertMessage),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
        .onAppear {
            loadFromUserDefaults()
            UserData.shared.isChanged = false
        }
    }
    
    private func saveToUserDefaults() {
        // 識別番号のチェック
        if idNumber.count != 7 || Int(idNumber) == nil {
            alertMessage = "OA Number must be a 7-digit number."
            showAlert = true
            return
        }
        
        // UUIDのチェック
        for (index, field) in uuidFields.enumerated() {
            if field.count != uuidMaxLengths[index] || !field.allSatisfy({ $0.isHexDigit }) {
                alertMessage = "UUID field \(index + 1) must be a \(uuidMaxLengths[index])-character hexadecimal value."
                showAlert = true
                return
            }
        }
        
        // MQTTポート番号のチェック
        if let port = Int(mqttPort), port >= 1 && port <= 65535 {
            // 正常な場合、何もしない
        } else {
            alertMessage = "Port must be a number between 1 and 65535."
            showAlert = true
            return
        }
        
        // MQTT Qosのチェック
        if let qos = Int(mqttQos), qos >= 0 && qos <= 2 {
            // 正常な場合、何もしない
        } else {
            alertMessage = "QoS must be a number between 0 and 2."
            showAlert = true
            return
        }
        
        // MQTT KeepAliveのチェック
        if let keepalive = Int(mqttKeepAlive), keepalive >= 0 && keepalive <= 65535 {
            // 正常な場合、何もしない
        } else {
            alertMessage = "KeepAlive must be a number between 0 and 65535."
            showAlert = true
            return
        }
        
        // レンジング回数のチェック
        if let rcount = Int(rangingCount), rcount >= 1 && rcount <= 60 {
            // 正常な場合、何もしない
        } else {
            alertMessage = "Count must be a number between 1 and 60."
            showAlert = true
            return
        }
        UserDefaults.standard.set(idNumber, forKey: "savedUserId")
        UserData.shared.userId = idNumber
        UserDefaults.standard.set(uuidFields, forKey: "uuidFields")
        UserData.shared.beaconUuidString = uuidFields.joined(separator: "-")
        UserDefaults.standard.set(mqttHost, forKey: "mqttHost")
        UserData.shared.mqttHost = mqttHost
        UserDefaults.standard.set(mqttPort, forKey: "mqttPort")
        UserData.shared.mqttPort = Int(mqttPort)!
        UserDefaults.standard.set(mqttQos, forKey: "mqttQos")
        UserData.shared.mqttQos = Int(mqttQos)!
        UserDefaults.standard.set(mqttKeepAlive, forKey: "mqttKeepAlive")
        UserData.shared.mqttKeepAlive = Int(mqttKeepAlive)!
        UserDefaults.standard.set(rangingCount, forKey: "rangingCount")
        UserData.shared.rangingCount = Int(rangingCount)!
        UserDefaults.standard.set(notificationFlg, forKey: "notificationFlg")
        UserData.shared.notificationFlg = notificationFlg
        UserDefaults.standard.set(loggingFlg, forKey: "loggingFlg")
        UserData.shared.loggingFlg = loggingFlg
        print("Saved successfully: \(idNumber), \(uuidFields.joined(separator: "-")), \(mqttHost):\(mqttPort):\(mqttQos):\(mqttKeepAlive), \(rangingCount)")
        UserData.shared.isChanged = true
        dismiss()
        onDismiss() // 閉じた後にコールバックを実行
    }
    
    private func loadFromUserDefaults() {
        if let savedId = UserDefaults.standard.string(forKey: "savedUserId") {
            idNumber = savedId
            print("idNumber=",idNumber)
        }
        if let savedUuid = UserDefaults.standard.array(forKey: "uuidFields") as? [String] {
            uuidFields = savedUuid
        }
        if let savedHost = UserDefaults.standard.string(forKey: "mqttHost") {
            mqttHost = savedHost
            print("mqttHost=",mqttHost)
        }
        if let savedPort = UserDefaults.standard.string(forKey: "mqttPort") {
            mqttPort = savedPort
        }
        if let savedQos = UserDefaults.standard.string(forKey: "mqttQos") {
            mqttQos = savedQos
        }
        if let savedKeepAlive = UserDefaults.standard.string(forKey: "mqttKeepAlive") {
            mqttKeepAlive = savedKeepAlive
        }
        if let savedCount = UserDefaults.standard.string(forKey: "rangingCount") {
            rangingCount = savedCount
        }
        if UserDefaults.standard.object(forKey: "notificationFlg") != nil {
            notificationFlg = UserDefaults.standard.bool(forKey: "notificationFlg")
        }
        if UserDefaults.standard.object(forKey: "loggingFlg") != nil {
            loggingFlg = UserDefaults.standard.bool(forKey: "loggingFlg")
        }
    }
}

#Preview {
    SettingView(onDismiss: {})
}
