# LineDraw 手機自主模式實機驗證

更新：2026-09-29（Asia/Taipei），本頁保留 1.1.0 build 3 拔線驗收。後續 build 4 自動 DDI 與速度測試見 [更新報告](AUTO_DDI_AND_SPEED_2026-09-29.md)。

## 已測到的結果

目標 iPhone：iPhone 18 Pro Max，iOS 27.0（24A437），LINE 26.15，LocalDevVPN 1.3.0；Wi-Fi、開發者模式已啟用。首次配對、簽署、安裝允許使用 Mac。

| 驗證 | 結果 | 證據 |
| --- | --- | --- |
| Classic lockdown 經 VPN | 失敗 | QueryType 即斷線；尚未進入憑證驗證，不能解讀為憑證過期 |
| 獨立 Remote Pairing 憑證 | 成功 | 受信任 USB 首次建立、綁定裝置、公私鑰一致性檢查、Keychain 保存 |
| 手機建立加密通道、啟動 XCTest／WDA | 成功 | 手機 Rust bridge → 10.7.0.1:49152 → RSD；WDA 只聽 localhost 隨機埠 |
| Safari 本機頁 20 次操作 | **20／20，147.21 秒** | 每筆辨識底部按鈕、重新核對目標、點擊並確認結果；手機自行執行，Mac 沒有逐筆送指令 |
| 原五筆 LINE 已抽結果複查 | **5／5，35.95 秒** | 依原順序：ALREADY、ALREADY、COMPLETE、ALREADY、ALREADY；相鄰畫面需穩定，不點抽選或使用優惠券 |
| 拔除 USB 後由手機手動啟動 | **20／20，150.30 秒** | 使用者確認拔線測試通過；重新接線讀取報告為 passed，21 個本機 HTTP 請求 |
| 結束清理 | 成功 | 新 DeviceRunner 已退出；結束後流程沒有繼續操作 |
| 建置 | 成功 | Debug 已簽署安裝到實機；Release 無簽章編譯成功（非發行 IPA） |
| 程式／原生 UI | 44 項通過 | Core 36、Rust 3、XCUITest 5；UI 沒有配對時不得啟動 |
| 原始資料保留 | 成功 | Mac 15 筆紀錄與工作前備份相等 |

第一輪 Safari 與 LINE 複查時 USB 仍連著。其後使用者依拔線流程從手機啟動第二輪 Safari 驗證，已確認通過；重新接線讀回的報告亦為 20／20。**目前已證明本次條件下可以拔線自行啟動並執行；重開機後重新掛載 DDI 尚未驗證。** LINE 複查沒有送出新的抽選。

## 已修正的實機問題

1. iOS 27 的本機 TCP lockdown 首次請求即中斷：改為 Remote Pairing 直接建立 RSD，無需依賴 classic 網路入口。
2. Cryptex DDI 被 Personalized LookupImage 誤判為缺少：先驗證 RSD 的 DDI 服務，未就緒時使用 Cryptex 流程；五個映像檔已匯入，payload digest 與 manifest 一致。首次掛載分支尚未在未掛載裝置上驗證。
3. Debug 測試頁在 NWListener ready 前被打開：等待 ready，先用本機 HTTP 自我檢查，再進 Safari；排除把網頁尚未啟動誤判成按鈕辨識失敗。

## 拔線驗收：已通過

Mac 控制台（4780）與 Appium（4725）已停止，舊 WDA 殘留程序也已結束；保留安裝與全部程式。裝置上的新 App 可直接啟動。

1. 拔除 USB，保持 Wi-Fi、LocalDevVPN 連線及解鎖。
2. 在手機開 LineDraw → 設定 → 手機自主模式。
3. 按「離線實機驗證（20 筆，不抽選）」；這個按鈕僅 Debug POC 可見。
4. 等約 3 分鐘，回此頁查看是否顯示「手機端離線畫面驗證通過，20 次操作。」
5. 如需開發者讀取證據，完成後再接 USB。`Documents/device-probe.json` 留存結果，沒有配對憑證。

使用者最初回覆失敗／卡住，隨後更正為「其實是顯示通過」。讀取實機報告亦確認成功：台北時間 2026-09-29 00:18:18.182 完成，耗時 150.30 秒。Mac 控制程序於 00:14:02.754 已停止，早於這輪約 00:15:47.884 的開始時間；本輪沒有從 Mac 重新啟動 WDA 或送出操作指令。這次更正不涉及程式碼修復。

後續仍需測試重開機後重新啟動／DDI、斷 VPN、使用者取消、鎖屏及長批次；不承諾 App Store、無人值守排程或所有 iOS 版本。

## 開發證據索引（不放來源 ZIP）

- `.runtime/rp-device-probe.json`：第一輪 20 次 fixture 成功。
- `.runtime/standalone-user-result.json`：使用者拔線啟動後 20／20、150.30 秒；重新接線後唯讀取得。
- `.runtime/rp-device-review.json`：LINE 五筆已抽結果成功。
- `.runtime/rp-processes-after.json`：工作結束程序狀態。
- `.runtime/mac-controllers-stopped.json`：停止 Mac 控制程序時間。
- `.runtime/rp-bridge-tests.log`、`rp-core-tests.log`、`RemotePairingUITests-final.xcresult`。
- `.runtime/rp-phone-build.log`、`rp-bridge-build.log`、`rp-install.log`。

MIT idevice 來源固定於 d32c8189c51c2789496b0768039419c3705498c3，局部變更列在 `DeviceBridge/vendor/idevice/LINEDRAW_CHANGES.md`。LineDraw 自有程式維持 PolyForm Noncommercial 1.0.0；未複製 StikDebug／StikPair／TouchSynthesis 程式碼。
