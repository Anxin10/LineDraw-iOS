# 新 iPhone 安裝手冊

版本：LineDraw 1.1.8（31），2026/10/09。最低部署目標 iOS 26.0；iPhone 16 Pro／iOS 26.0 尚未完成本版實機驗收。手機型號相容不等於簽署允許安裝。

## 準備與簽署

目前需 **LineDraw、DeviceRunner、LocalDevVPN** 三個 App。LineDraw 的 PairingActivity 已包含在主程式 IPA 內；DeviceRunner 仍為獨立 IPA。

1. 用 USB 接上新手機並解鎖，選擇信任 Mac。Xcode → Settings → Apple Accounts 登入自己的 Apple Account。
2. 讓 Xcode 辨識新手機並完成裝置註冊。LineDraw、PairingActivity 與 Runner 都需要適用這支手機、尚未過期的簽署。僅下載 GitHub IPA 不會將新手機加進描述檔。
3. 若新手機不在既有簽署清單，依 [完整原始碼建置教學](../README.md#build-app) 重新建置；Xcode 的 LineDraw／PairingActivity 選擇同一個 Team，Runner 也用自己的 Team 建置。保持 Runner Bundle ID 與 App 的 DeviceRuntime.runner 一致。
4. 使用自己的 Bundle ID 時，須一起修改主程式、extension、背景工作識別碼、Runner 與其建置腳本；詳細位置見 [識別碼設定](../README.md#identifiers)。不要只在 IPA 外層改名。
5. 專案產生器可使用 `LINEDRAW_TEAM_ID=你的TeamID ruby ios-app/scripts/generate-project.rb`；沒有提供時不寫入個人 Team，產生後在 Xcode 選擇自己的 Team。

Apple 說明：[裝置註冊與 IPA 發佈](https://developer.apple.com/documentation/xcode/distributing-your-app-to-registered-devices)。免費 Personal Team 可用 Xcode 開發安裝，資格與到期日以實際簽署結果為準；不能把別人的描述檔當作所有手機通用簽署。

## 安裝

1. 先停止原手機的抽選；更新既有手機時使用相同 Bundle ID 覆蓋安裝，避免刪除 App 而失去紀錄。
2. 已有適用簽署的 IPA：Mac 的 Apple Configurator 選取新手機，拖入 `LineDraw.ipa` 與 `DeviceRunner.ipa`。也可直接用 Xcode 建置安裝。不能在 iPhone「檔案」App 點 IPA 完成安裝。
3. iPhone → 設定 → 隱私權與安全性 → 開發者模式，依提示重新啟動並確認；找不到選項時先讓 Xcode 辨識手機。
4. 若出現開發者不受信任提示，到設定 → 一般 → VPN 與裝置管理確認對應開發者。
5. 開啟 LineDraw，設定頁與診斷頁應顯示 **1.1.8（31）**。「PolyForm Noncommercial 1.0.0」是授權版本，並非 App 舊版。

Apple 說明：[Configurator 加入 IPA](https://support.apple.com/en-au/guide/apple-configurator-mac/cad4cd08c03/mac)、[開發者模式](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)。

## 每支新手機都要重新準備

1. 安裝並登入 LINE，核對帳號。
2. 從 App Store 安裝 [LocalDevVPN](https://apps.apple.com/tw/app/localdevvpn/id6755608044)，允許 VPN 設定、連線並保持 Wi-Fi 開啟。
3. LineDraw → 設定 → 執行方式 → 手機自主模式，進入手機自主模式設定，按「開始手機配對」。依畫面提示，在系統開發者模式內選擇 Pair with LineDraw，輸入該手機當次 PIN。
4. 返回 App，確認本機配對已保存，按「準備必要檔案」。不要複製其他手機的配對檔或 PIN。
5. 按「檢查啟動（不抽選）」。成功後才選活動並開始抽選。精簡決策查詢需搭配本包新版 Runner。

單純同步 Funbox／陀螺獵人清單只需手機連網，不需 Mac 或 Runner。實際手機自主抽選仍需要有效簽署、配對、DDI、Wi-Fi、VPN 與解鎖；初次安裝和簽署更新可能需要 Mac。

## 遇到問題

| 問題 | 處理 |
|---|---|
| IPA 無法安裝 | 確認新手機已在描述檔中、簽署未到期；重新簽署兩個 IPA |
| Mac 偵測不到手机 | 暫停 VPN，重新接 USB、解鎖並信任；安裝完成後再開 VPN |
| Runner 工作階段無法啟動 | 先檢查啟動；1.1.7 起僅在抽獎開始前最多重試一次，仍失敗時分享診斷與版本 |
| 同步清單有活動但 0 筆可抽選 | 檢查活動有效期、篩選、已送出紀錄與待確認店家 |

本版不能保證每筆 3 秒內，也未提供 App Store／TestFlight 安裝。
