# SpotSense
##・2024/10/2 初期テスト版リリース
https://github.com/davidgyoung/OverflowAreaBeaconRef
をベースに在室検知向けに修正したものです。
###修正内容：
　　OA番号入力のUI追加
　　入力したOA番号の保存
　　OA番号の上3桁をMajor、下4桁をMinorに設定
　　受信処理はコメントアウト

##・2025/02/10 ユーザーテストの結果を反映した修正
###修正内容：
　　WelcomeView追加、Step By Stepでbluetooth、位置情報、通知の許可ダイアログを設定
　　ContentView修正、デバッグ用にログ表示追加、全体レイアウト見直し
　　iBeacon受信をトリガーとしてBLE信号発信の処理追加、ソフトウェアアップデート等でiPhoneが再起動した後、自動的にBLE信号を発信できるようにした
　　ローカル通知でiBeaconの検知やBLE信号の発信状態を表示

##・2025/04/18 iBeaconを使った検知方式へ変更
###修正内容：
　　全面修正
　　iBeaconを受信して，受信したmajor,minor,RSSIをMDL所管のMQTTbrokerへ送信する方式へ変更
  　MQTTクライアントライブラリとしてcocoaMQTTを使用。ただし最新版はバグがあり、2.1.6を使用(XcodeのPackage Dependenciesで指定)
