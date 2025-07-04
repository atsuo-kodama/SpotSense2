//
//  SpotSenseApp.swift
//  SpotSense
//
//  Created by 小玉敦郎 on 2025/02/22.
//


import SwiftUI

@main
struct SpotSense: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appDelegate.beaconManager)
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    let beaconManager = BeaconManager()
    @ObservedObject var userData = UserData.shared
    
    override init() {
            super.init()
            print("AppDelegate initialized")
            beaconManager.logToFile("AppDelegate initialized")
    }
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        
        print("Launch options: \(String(describing: launchOptions))")
        beaconManager.logToFile("Launch options: \(String(describing: launchOptions))")
        
        // iBeacon監視を起動
        beaconManager.startMonitoring()
        
        // 再起動チェック
        //_ = RebootDetector.shared.checkForReboot()
        
        // 再起動時すでにリージョン内にいるか
        beaconManager.logToFile("AppDelegate didFinishLaunchingWithOptions")
        if RebootDetector.shared.checkForReboot() {
            beaconManager.logToFile("Detected Reboot!")
            UserDefaults.standard.set(false, forKey: "hasLaunchedSinceReboot") // 再起動後アプリ起動フラグをリセット
            // リージョンの状態チェック
            beaconManager.requestCurrentRegionState()
        }
        return true
    }

}
