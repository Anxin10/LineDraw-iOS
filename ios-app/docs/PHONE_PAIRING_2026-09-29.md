# LineDraw 1.1.0 build 6：手機首次配對

## 交付範圍

簽署並安裝 LineDraw 與 DeviceRunner 後，在 iOS 27 的 LineDraw 按「開始手機配對」，由手機自己的系統設定完成 Remote Pairing。日常啟動沿用鑰匙圈內的憑證、驗證或下載 DDI，經 LocalDevVPN 啟動本機 Runner。此路徑不呼叫 Mac companion、USB 配對工具、xcodebuild 或遠端配對伺服器。

目前仍需在手機安裝並開啟 **LocalDevVPN**；本版未內嵌 VPN。App 與 Runner 的簽署、安裝及續簽仍是前置條件，沒有消除 Apple 簽章有效期，也沒有聲稱能上架 App Store。首次 Developer Mode、開發者信任、VPN、本機網路及系統 PIN 確認由使用者在手機執行。

## 使用步驟

1. 完成 App / DeviceRunner 的簽署安裝與開發者信任，開啟開發者模式，手機連上 Wi-Fi，開啟 LocalDevVPN。
2. LineDraw → 設定 → 手機自主模式 → 開始手機配對。已有配對時按鈕為「重新在手機配對」，原憑證先保留。
3. 允許本機網路，到 iPhone 設定 → 隱私權與安全性 → 開發者模式 → **Pair with LineDraw**（系統語言可能顯示「與 LineDraw 配對」）。
4. App 顯示六位 PIN，並以即時動態／動態島顯示。長按動態島讀取 PIN，輸入系統配對視窗。未允許即時動態時可切回 App 查看，再回設定輸入。**不需把 PIN 傳給任何人。**
5. 手機透過 LocalDevVPN 驗證新憑證與本機裝置身分，成功才更新鑰匙圈，接著自動準備 DDI。
6. 回到 LineDraw 按「檢查啟動（不抽選）」；通過後即可選活動並開始。配對或檢查啟動不會自動進行抽選。

後續啟動不重做配對。重開機後解鎖、恢復 Wi-Fi / VPN，再檢查啟動；只有憑證失效才由使用者重新配對。系統更新、DDI 不相容、簽章過期等情況會回報失敗，不會反覆抽選或靜默建立新配對。

## 實作

- `DeviceBridge/src/phone_pairing.rs`：使用已固定 MIT idevice 的 `PairableHost` / `RpPairingSocket::new_device`，生成本次獨立主機金鑰及六位隨機 PIN，保持 `allows_pinless_pairing=false`。
- Swift `NetService` 發佈 `_remotepairing-pairable-host._tcp.`；TXT 資料來自函式庫。使用本機網路權限，不引入 multicast 特殊 entitlement。
- 配對 TCP listener 只在按開始後存在，僅接受當前手機自己的 IPv4 介面位址。PIN 握手與系統確認期間保持 listener / Bonjour，結束才關閉，避免設定誤判端點消失。Rust 整段配對上限 240 秒；取消／失敗／結束均清除 listener 與一次性狀態。
- 配對後經 `10.7.0.1:49152` 執行 pair-verify、加密通道、RSD / Lockdown `UniqueDeviceID` 比對；不掛 DDI、不開 Runner、不試點座標。驗證失敗不輸出可保存的配對資料。
- `ld_pair_status` 只回傳階段、短期 PIN 與公開廣播資料，不包含私鑰。長期憑證透過獨立一次性 buffer 取出，由 `DeviceSecrets.save` 原子更新 Keychain，使用 `WhenUnlockedThisDeviceOnly`。不寫 Documents、UserDefaults 或診斷。暫存傳輸 buffer 使用 zeroize / Data reset。
- 配對與既有 WDA session 在 FFI 鎖層互斥；App 同步鎖住批次、匯入與移除操作。
- `App/PhonePairing.swift`：使用者啟動、有結束點的 BGContinuedProcessingTask 維持切到系統設定時的配對。系統取消就結束。PIN 同時由 `PairingActivity` extension 與系統背景工作字幕顯示，避免動態島切換另一項活動時看不到；結束清除字幕並移除活動；強制關閉後再開 App 清理舊活動。不使用背景定位／音訊保活。
- `remote.rs` 共用加密連線建立邏輯；Runner 執行期間保留控制連線生命週期，既有 USB 匯入的 Remote Pairing 憑證仍可使用。
- 手動匯入配對檔與 DDI 移到「進階與修復」，舊 Mac 路徑保留。Android / 網站未更動。

## 驗證紀錄

- Rust 9 項通過：輸入與裝置綁定、禁止 pinless、秘密一次性讀取、小 buffer 不消耗、非本機來源拒絕、配對／Runner 互斥、取消後埠關閉、握手失敗不產生憑證、握手期間端點保持可連線。
- Swift Core 42 項通過；清單、抽選狀態機與 DDI 邏輯沒有變更。
- 原生 UI 6 項通過，含手機配對入口與取消後仍未配對；UI 測試使用獨立資料庫與模擬等待，不建立真實 listener、不操作 Keychain。最後排版調整另跑兩項相關測試。
- Debug 實機簽署建置通過，包含新增 PairingActivity 描述檔。已安裝到原測試 iPhone。既有憑證啟動檢查於 2026-09-29 10:47 台北時間通過，WDA 已正常結束，沒有抽選；Mac companion / Appium 監聽埠均未啟動。手機以本機網路連線，USB 未參與此次啟動檢查。

build 5 第一次實機嘗試：2026-09-29 10:49 台北時間，Bonjour 已發佈，進入 `starting → advertising → handshake → pin`，但未保存新憑證。使用者確認在設定輸入手機密碼後，PIN 對話框消失並顯示連線中斷，動態島也未見 PIN。檢查程式發現 PIN 階段提早取消 Bonjour 並關閉監聽端點；build 6 改為配對結束才釋放，並將 PIN 同時寫入系統背景工作的字幕。此原因與現象吻合；修正後的實機結果如下。失敗期間舊配對憑證保留。

**build 6 手機配對實測通過。** 2026-09-29 10:57:13 台北時間，手機紀錄為 `starting → advertising → pin → verifying → complete → filesReady`，`bonjourPublished=true`、`recordSaved=true`、`success=true`，`code=PAIR_COMPLETE`。使用者也回覆「完成配對」。新憑證由手機本次產生，經本機 VPN / RSD 驗證後保存；此流程沒有執行電腦配對工具或匯入電腦檔案。沒有抽選操作。

使用者已回報：重新開機、解鎖並恢復 Wi-Fi / LocalDevVPN 後，從手機執行「檢查啟動」成功。最新讀回的啟動檢查紀錄為 2026-09-29 11:03:03 台北時間，`passed=true`。在使用者這段驗收期間，Xcode 已關閉、Mac companion / Appium 已停止，沒有執行 Mac 裝置命令；完成後才恢復讀取紀錄。

這支持此指定手機的「重開機後沿用手機新配對並啟動」流程。現有檢查報告沒有逐步記錄 DDI 掛載，因此不能藉此判定是 DDI 跨重開機仍存在，或由 App 在這輪重新掛載；全新空白 DDI 的裝置仍需獨立驗證。隨後速度驗證的 `GET source` 逾時另見 [build 8 修正報告](SNAPSHOT_TIMEOUT_2026-09-29.md)。

另外仍須擴大驗證：其他機型／系統版本、錯誤 PIN、VPN 中斷、簽章到期，以及從未連過開發電腦的新裝置初次顯示開發者模式。不得把這支已開啟開發者模式、已安裝 Runner 的手機測試外推成所有首次安裝條件皆已驗證。

診斷：手機 `Documents/phone-pairing-report.json` 僅含時間、階段代碼、是否發佈 Bonjour／保存憑證／完成及結束原因／錯誤說明，不含 PIN、UDID、名稱、配對金鑰。Debug 的 `device-check-report.json` 保留啟動檢查結果。原始紀錄留在 `.runtime/`，不納入來源發行。

## 建置與授權

重新執行 `scripts/build-device-bridge.sh`、`scripts/generate-project.rb`。App 與 PairingActivity 選擇同一 Signing Team，extension bundle ID 必須以 App bundle ID 加點號為前綴。新增 extension 首次需要 Xcode 已登入帳號取得描述檔；對使用者而言這屬於前置簽署，不是每次配對需求。

自有程式維持 PolyForm Noncommercial 1.0.0。沒有納入 StikPair、StikDebug 或 TouchSynthesis 的程式碼；協定由既有 MIT idevice 提供。新增直接依賴 zeroize 原已在鎖定依賴圖內，授權聲明已重新收集。

原始參考：[idevice responder](https://github.com/jkcoxson/idevice/blob/d32c8189c51c2789496b0768039419c3705498c3/idevice/src/remote_pairing/responder.rs)、[Apple Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)、[Apple NetService](https://developer.apple.com/documentation/foundation/netservice)。上游參考不代表本機已通過實測。
