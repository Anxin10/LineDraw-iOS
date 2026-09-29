# LineDraw 內建本機 VPN 可行性與實作方案

日期：2026-09-29。基準：LineDraw iOS 1.1.0 build 9。

## 結論與驗證邊界

可以開發用來取代外部 LocalDevVPN App 的內建 Packet Tunnel Extension。LocalDevVPN 的公開原始碼已提供本機虛擬介面、特定目標路由、封包位址互換與重新注入的實作證據；目前 LineDraw 使用相同類型的本機通道連上自己的 Remote Pairing 服務。

本次完成來源與簽署設定查核，沒有新增 target、修改現有 VPN 設定、安裝 VPN 描述或移除 LocalDevVPN。內建版本尚未在本機 iPhone 上驗證，不能把外部 LocalDevVPN 已通過的結果當成內建版本驗收。

兩個前提：

1. **簽署資格。**目前 build 9 使用 `LocalProvision=true`、有效期七天的免費 Personal Team 描述檔，App 未含 Network Extensions 或 Personal VPN entitlement。Apple 的 iOS capability 表顯示 Network extensions／Personal VPN 支援付費 ADP／ADEP，免費 Apple Developer 欄不支援。需要由有資格的 Team 簽署 App 與 extension 並產生相符 profile；不能只新增 entitlement plist。
2. **平台支援範圍。**Apple 公開提供 Packet Tunnel API，但 TN3120 說明封包重新注入等用途不屬於建議的標準使用方式，也不建議將 packet tunnel provider 用來託管 listener/proxy server。本計畫沿用開發者工具的本機通道方式，是指定 iOS 版本需實測的 POC，不是 Apple 對此用途或未來版本的保證。

## 擬議架構

```text
LineDraw App
  ├─ LocalTunnelController（VPN 設定、啟停、狀態）
  ├─ PhonePairing（既有手機首次配對）
  ├─ DeviceRuntime / DDIManager / Rust idevice
  └─ 既有清單、批次、紀錄
        │
        ├─ 系統管理的 LineDrawTunnel.appex
        │    └─ NEPacketTunnelProvider：本機虛擬介面與最小路由
        │
        └─ Remote Pairing → RSD / testmanagerd → DeviceRunner → LINE
```

主 App 使用 `NETunnelProviderManager` 管理嵌入的 extension；extension 跑在獨立程序，不能依賴主 App 在前景持續處理封包。本功能不需外部 VPN 主機。VPN extension 只承擔通道職責，不將抽選邏輯、配對私鑰或背景保活功能搬進 VPN。

這只減少 LocalDevVPN 這個安裝項目；DeviceRunner 的簽署與安裝仍然存在。開發者模式、信任、手機配對 PIN 與第一次新增 VPN 的系統確認也仍需使用者完成。

## 改動範圍

| 部分 | 預計變更 |
|---|---|
| `Tunnel/PacketTunnelProvider.swift`（新增） | 設定虛擬 IPv4 介面、限定 peer 路由、封包處理、啟停及錯誤回報；拒絕不合法／不支援封包，避免迴圈與不受限記憶體累積 |
| `Tunnel/Info.plist`、entitlements（新增） | `com.apple.networkextension.packet-tunnel` extension point、相符 bundle identifier 與 Network Extensions 能力 |
| `App/LocalTunnelController.swift`（新增） | 載入／儲存本 App VPN 設定、啟停連線、觀察 VPN 狀態、連線期限、取消與重複開始防護 |
| `App/DeviceRuntime.swift` | 啟動前等待通道連線及本機服務可達；VPN 中斷時停止佇列；先結束 WDA／RSD，再處理本 App 的通道 |
| `App/PhonePairing.swift` | 配對前準備本機通道，沿用既有 PIN、驗證、Keychain 原子替換與失敗保留舊憑證流程 |
| `DeviceBridge/src/remote.rs`、`lib.rs` | 將目前硬編碼 `10.7.0.1` 的設定集中化，必要時經受限配置傳入；仍只連本機並核對裝置身分 |
| `DeviceSetupView.swift`、`SettingsView.swift` | 顯示「本機連線」的未授權、連線中、可用、中斷、錯誤狀態；由 App 引導首次 VPN 系統確認 |
| `scripts/generate-project.rb` | 新增並嵌入 extension、設定 target 依賴、簽署與 capability；保留可建置的外部 VPN 版本 |
| 診斷／測試 | 記錄通道生命週期、服務探測、取消與停止原因，不記錄封包內容、配對私鑰、PIN 或聊天 |

權限以實際使用 API 為準：核心是 `com.apple.developer.networking.networkextension = [packet-tunnel-provider]`。LocalDevVPN 的主 App 同時宣告 Personal VPN；本案會核對選定 API 與簽署 profile 是否需要該能力，不盲目複製所有 entitlement。

## 使用者流程

1. 開啟 LineDraw，點「設定本機連線」。
2. 第一次由系統顯示新增 VPN 設定確認；拒絕時停在說明畫面，不執行配對或抽選。
3. App 等待通道 connected，再以本機 Remote Pairing／裝置身分探測確認真正可用；不能只依 VPN 圖示宣告成功。
4. 尚未配對者沿用手機 PIN 流程；已配對者直接準備 DDI、啟動 Runner。
5. 選擇活動並開始。後續需要通道時，App 啟動自己的 VPN 設定。
6. 中止或完成先保存紀錄並停止 Runner。只停止本次由 LineDraw 啟動的 VPN，不修改別人的設定。

不靜默切斷使用者的其他 VPN。遇到不相容的 VPN／路由狀態時，顯示需使用者切換的原因；也不自動移除 LocalDevVPN。初期只宣稱目前已測的 Wi-Fi 路徑，不將整合 VPN 等同於行動網路已支援。

## 路由與資料範圍

以相容現有 Remote Pairing peer 的最小 host route 為起點，避免接管預設路由、DNS 或一般 LINE／Safari 上網。驗證包含 source/destination、IP header 長度、協定、分片與 IPv6 邊界；對不支援封包明確拒絕，不把任意系統流量轉送到開發者服務。

配對憑證維持主 App 的 ThisDeviceOnly Keychain。能透過 provider configuration 傳入非機密網路參數時，不新增共享 Keychain 或 App Group；真有跨程序狀態需求才增加最小共享範圍。

## 簽署與公開分發的影響

簽署方需有 Network Extensions 資格。使用者拿到已用適當 profile 簽好的 App，不等於每人都必須購買開發者會員；但仍受該分發方式的裝置、有效期與更新限制。

若公開來源讓使用者以免費 Apple ID 自行重簽／編譯，內建 Network Extension 無法視為可用。因此建議有兩個可選建置配置：

- 內建通道版：給具備適當簽署資格的建置／分發。
- 外部通道版：保留目前 LocalDevVPN 路徑，供免費 Team 使用者。

兩者共用 App、配對、DDI、WDA、佇列與紀錄；不要讓新增 extension 使既有免費 Team 版本直接無法建置。

LocalDevVPN 現行 LICENSE 是附加署名與再發布條件的 StosVPN License，不是單純標準 MIT。本案可自行實作狹窄的通道元件；若引用上游程式，需保留其授權與顯著來源聲明，第三方部分不能一律改標 LineDraw 的 PolyForm Noncommercial。

## 實作與驗收順序

1. 確認可用的付費 Team／App ID／extension profile；先證明最小 extension 可簽署、安裝及取得系統允許。
2. 僅驗證本機 VPN、服務可達、正確裝置身分及正常網路可用，不抽選。
3. 接回既有 WDA，執行啟動檢查、五筆與二十筆本機 fixture。確認一次一筆、逾時重查不重送點擊。
4. 測拒絕授權、VPN 手動斷線、另一個 VPN、背景／前景切換、停止與重新開始、Wi-Fi 中斷、extension 結束與描述檔失效。
5. 手機重新啟動後，由使用者只用手機恢復連線、啟動 WDA、完成 fixture；Mac 停止參與。
6. 驗證首次手機配對也能使用內建通道。全部通過後，才將內建版的 LocalDevVPN 安裝步驟移除。

## 一手來源

- [Apple NEPacketTunnelProvider](https://developer.apple.com/documentation/networkextension/nepackettunnelprovider)
- [Apple Network Extensions entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.networking.networkextension)
- [Apple iOS 支援能力表](https://developer.apple.com/help/account/reference/supported-capabilities-ios)（本次另外核對 HTML 的 ADP／ADEP／免費欄位，避免純文字轉換遺漏勾選圖示）
- [Apple NETunnelProviderManager](https://developer.apple.com/documentation/networkextension/netunnelprovidermanager)
- [Apple TN3120：Packet Tunnel 的用途限制](https://developer.apple.com/documentation/technotes/tn3120-expected-use-cases-for-network-extension-packet-tunnel-providers)
- [LocalDevVPN PacketTunnelProvider](https://github.com/jkcoxson/LocalDevVPN/blob/main/TunnelProv/PacketTunnelProvider.swift)
- [LocalDevVPN 主 App entitlements](https://github.com/jkcoxson/LocalDevVPN/blob/main/LocalDevVPN/LocalDevVPN.entitlements)
- [LocalDevVPN LICENSE](https://github.com/jkcoxson/LocalDevVPN/blob/main/LICENSE)

## 搜尋摘要

smart-search 已完成 OpenCLI registry 預檢；registry 沒有 Apple／GitHub adapter，改用網頁搜尋與官方 URL 直接讀取，未向其他 AI 傳送專案資料。

網頁搜尋兩輪：Apple 相關查詢為 Network Extension／Personal Team／paid entitlement 與 packet-tunnel-provider／vpn.api；LocalDevVPN 相關查詢為 GitHub／loopback VPN／packet tunnel。之後直接核對 Apple 文件、HTML／Markdown、GitHub raw source 與本機簽署資料，未根據搜尋摘要就宣稱實機通過。
