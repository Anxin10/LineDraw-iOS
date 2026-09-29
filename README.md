# LineDraw iOS

原生 iPhone LINE 抽選工具，採 SwiftUI 與 iOS 27 Liquid Glass。同步活動清單、依地區與狀態多選篩選、依序執行抽選，並在手機保存參加紀錄。無網站登入、無 VIP 驗證。

目前版本：**1.1.0（build 15），實驗版本**。自有程式碼採 **PolyForm Noncommercial 1.0.0**，公開原始碼、限非商業使用；商業使用須另取得授權。第三方元件保留各自授權。

<p>
  <img src="ios-app/docs/screenshots/catalog-selected-light.png" width="250" alt="離線示範的抽選清單與玻璃分頁列">
  <img src="ios-app/docs/screenshots/multi-select-filters.png" width="250" alt="地區與活動狀態多選篩選">
  <img src="ios-app/docs/screenshots/history-light.png" width="250" alt="本機抽選紀錄">
</p>

以上為離線示範畫面。歷史版本截圖與實機驗證分開記錄。

## 執行方式

| 方式 | 如何運作 | 必要條件 |
|---|---|---|
| 手機自主模式（預設） | iPhone 自行配對、準備 DDI、啟動 WDA 並執行本次清單 | 已簽署安裝的 LineDraw／DeviceRunner、開發者模式、Wi-Fi、LocalDevVPN、手機解鎖 |
| Mac 輔助模式 | 手機管理清單，Mac 透過 Appium／WDA 執行 | Mac 持續運作，完成 USB／WDA 連線及 App 配對 |

**免電腦指簽署安裝完成後的手機配對與日常執行。** 本倉庫提供原始碼，建置、簽署、安裝及續簽仍需自行準備。本版依然使用 LocalDevVPN，沒有內建 VPN，也未提供 App Store 版本。

## 功能

- 同步 [Funbox 抽選清單](https://uxux11.github.io/funbox-line/)，保留來源順序與既有紀錄。
- 地區／活動狀態多選、搜尋、全選可抽選、Asia/Taipei 時間判斷。
- 依序開啟 LINE 活動；可設定自動加入好友。
- 優先定位底部原生按鈕，以即時位置點擊；必要時使用 Vision OCR。
- 點擊收到成功回應並保存紀錄後直接載入下一筆，不等待中獎結果。
- 已參加、已領取、未中獎、已結束等已知畫面自動接續；不兌換優惠券。
- 暫停、繼續、停止、略過、慢速載入處理、批次後增量同步。
- 本機設定檔與紀錄、手動完成／撤銷、診斷、五連結測試區及離線示範。

「已送出」表示點擊指令成功回應，不等於確認中獎。回應不明時保存「待確認」並停止，不自動重送。

## 開始使用

1. 依 [建置與安裝指南](docs/BUILDING.md) 建置、簽署並安裝 App 與 DeviceRunner。
2. 在手機開啟開發者模式、完成開發者信任，連上 Wi-Fi 並開啟 LocalDevVPN。
3. LineDraw → 設定 → 手機自主模式 → 開始手機配對；在系統「開發者模式 → Pair with LineDraw」輸入即時動態顯示的 PIN。
4. 回到 App 執行「檢查啟動（不抽選）」。通過後，同步並選擇要參加的活動，再開始本次批次。

完整說明：[手機首次配對](ios-app/docs/PHONE_PAIRING_2026-09-29.md)、[iPhone App](ios-app/README.md)、[Mac 輔助程式](ios-wda/README.md)。

## 相容性與驗證範圍

目前以 Xcode 27、iOS 27 開發；Rust bridge 支援 arm64 iPhone 與 Apple Silicon 模擬器。指定 iPhone 已完成手機配對、拔線後 20 次操作及重開機後啟動檢查。其他機型、系統版本與大量長時間批次仍需驗證。

build 14 的本機 Core 測試、LINE 已抽頁面複查及受控原生／OCR 測試詳見 [驗證報告](ios-app/docs/DIRECT_HANDOFF_BUILD14_2026-09-29.md)。build 15 僅更新五連結測試清單；未以這五筆新券量測真實抽選速度，詳見 [清單更新](ios-app/docs/TEST_LINKS_BUILD15_2026-09-29.md)。模擬器／合成頁通過不代表所有 LINE 實機情境皆通過。

手機執行期間需保持解鎖，系統取消背景工作時會停止。本版未提供鎖屏無人值守、每日準點喚醒或驗證碼自動處理。

## 專案結構

```text
ios-app/                  原生 iPhone App
  App/                    SwiftUI、配對、手機自主執行與 OCR
  Core/                   清單、狀態機、儲存與單元測試
  DeviceBridge/           Rust / idevice 與 C ABI
  PairingActivity/        配對 PIN 即時動態
  scripts/                建置、專案產生與 Runner 準備工具
  docs/                   各版設計與驗證紀錄
ios-wda/                  Mac 輔助程式、控制台與測試
docs/BUILDING.md           從乾淨原始碼建置與安裝
```

## 授權與發行範圍

[LICENSE](LICENSE) 為 PolyForm Noncommercial 1.0.0 全文。這是附非商業限制的公開原始碼授權，不是 OSI 定義的開源授權；商業使用請先聯絡倉庫維護者。

第三方授權：[SwiftSoup](ios-app/Resources/THIRD_PARTY_NOTICES.txt)、[Rust 依賴](ios-app/Resources/Rust-THIRD_PARTY_NOTICES.txt)、[idevice](ios-app/DeviceBridge/vendor/idevice/LICENSE.txt)、[Mac 依賴](ios-wda/THIRD_PARTY_NOTICES.md)。

本倉庫包含 iOS 與 Mac 輔助程式來源。Android、網站後端、個人簽章、配對憑證、實機原始資料、Apple DDI 及建置產物不在此來源發行中。
