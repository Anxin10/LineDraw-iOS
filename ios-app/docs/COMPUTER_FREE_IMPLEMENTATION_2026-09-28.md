# LineDraw 1.1.0 手機自主模式：實作與驗證紀錄

## 目前結果（2026-09-29 更新）

手機自主 POC 已簽署安裝，版本 1.1.0（build 3）。**手機自行啟動 WDA、Safari 20 次操作、LINE 五筆已抽結果複查已通過；拔 USB 後由手機手動啟動並完成 20 次操作也已通過（150.30 秒），重開機驗收仍待完成。** 詳細證據見 [9/29 驗證報告](COMPUTER_FREE_VALIDATION_2026-09-29.md)。

使用者確認 Wi-Fi 與 LocalDevVPN 後，classic TCP 62078 的 QueryType 仍立即斷線，尚未進入配對驗證。新版改為 Remote Pairing → TLS-PSK → RSD，已在相同手機走通。原本 `EnableWifiDebugging` 的暫時實驗設定已還原，這次成功不依赖保持該設定開啟。

iOS 27 的 DDI 是 Cryptex；舊 `LookupImage("Personalized")` 會誤判未掛載。新版先確認 RSD 中的 XCTest／dtservicehub，缺少時走 Cryptex 掛載流程。當前手機原已有 Xcode 的 DDI，因此**尚未實測清空／重開機後由手機重新掛載**。

本輪沒有送出真實 LINE 抽選、沒有兌換優惠券。Mac 原始 15 筆紀錄與備份相同。原 Mac 模式程式保留；其控制台及 Appium 已停止，使用者隨後完成拔線驗證。

## 已寫入程式

- `DeviceBridge/`：LineDraw 自有 Rust C ABI，固定 idevice commit `d32c8189c51c2789496b0768039419c3705498c3`，`Cargo.lock` 固定依賴。使用上游 MIT，沒有複製 TouchSynthesis / StikDebug / StikPair 程式碼。
- `scripts/build-device-bridge.sh`：建置 arm64 iPhone、Apple Silicon simulator 靜態 XCFramework。先建 bridge，再開 Xcode 建 App；XCFramework 是生成物，不放來源包。
- `App/DeviceRuntime.swift`：前景手動啟動 `BGContinuedProcessingTask`，確認背景工作獲准才啟動 Runner。包含 timeout、取消、heartbeat / session 清理。配對檔用 ThisDeviceOnly Keychain，DDI 儲存在不備份的 App Support。
- `App/LocalWDA.swift`：iPhone 自己呼叫 localhost WDA，直接 URL、畫面 XML、底部按鈕與 Vision OCR；每次點擊前重新確認前景及目標。沒有把整套 Appium 搬進 App。
- `Core/DeviceScreen.swift`：移植實際 LINE 底部按鈕、已領券、已結束、中獎／未中獎、原生 WebView 可見性例外；不驗店名、活動名，不操作使用優惠券。
- `Core/DeviceBatch.swift`：依序執行、先持久化意圖再點擊、回應成功直接下一筆，不等待抽獎結果；回應不明寫 REVIEW 並停止。30 秒載入重開一次，60 秒斷網上限，暫停／略過／取消，最多 3 輪新活動接續。
- `AppModel`：可切換手機自主／Mac 輔助；凍結設定檔、清單、篩選條件；重啟時未確認意圖改為 REVIEW，不自動重送。保留原 Mac 程式與原始 15 筆紀錄。
- `DeviceSetupView`：沿用 iOS 27 原生玻璃 UI；配對匯入／移除、DDI 五檔匯入、目前狀態、取消啟動與「檢查啟動（不抽選）」按鈕。無登入、無 VIP。
- Debug-only `DeviceProbeServer`：127.0.0.1 隨機埠＋隨機路徑的 Safari 合成抽選頁，用來測背景與點擊；不連 LINE。Release 不含此 server 或啟動參數。

## 目前架構與重要限制

```text
SwiftUI（手機）
  └─ BGContinuedProcessingTask（獲准後才啟動）
      ├─ Rust / idevice → LocalDevVPN → Remote Pairing → TLS-PSK → RSD → DDI → XCTest
      └─ Swift 本機批次 → localhost WDA → LINE
```

這版先把控制端放在有期限、可取消的 continued processing 工作內，**尚未把整個抽選引擎搬進 WDA Runner**。系統結束背景工作就停止；已實測 Safari 前景約 147 秒與 LINE 已抽頁面複查約 36 秒；尚未驗證長時間、大量真實抽選。不要宣稱 runner 自主運作、鎖屏排程或重開機後無人值守。

已將 MIT idevice 固定版本放入 `DeviceBridge/vendor/idevice`，新增 `XCUITestService::run_rsd` 入口，直接使用已驗證的 Remote Pairing 通道，與原入口共享 XCTest 生命週期。RSD 安裝資料、裝置識別、DDI 與 testmanagerd 都走同一條本機通道，不再先依賴 TCP 62078。

Remote Pairing 憑證與 classic USB plist 不相同。首次設定透過受信任 USB 建立獨立憑證，綁定目標 UDID，0600 儲存；手機只做 pair-verify，失敗立即停止，不自動 pair-setup 或猜 PIN。Swift 儲存前與 Rust 啟動前都使用同一解析器驗證格式，含公私鑰對應及裝置綁定。上游會列印配對 plist 的 debug 行已移除；App 不初始化第三方 debug logger。

參考來源：[idevice XCTest 原始碼](https://github.com/jkcoxson/idevice/blob/d32c8189c51c2789496b0768039419c3705498c3/idevice/src/services/dvt/xctest/mod.rs)、[LocalDevVPN 預設位址](https://github.com/jkcoxson/LocalDevVPN/blob/main/LocalDevVPN/Constants.swift)。其他專案也記錄 iOS 27 網路 lockdown 第一個請求即關閉的情況，但這不代替本機的根因驗證：[SideInstaller 工程紀錄](https://github.com/FrizzleM/SideInstaller/blob/main/NOTES.md)。

## 建置與首次安裝

```sh
cd ios-app
bash scripts/build-device-bridge.sh
ruby scripts/generate-project.rb
swift test --package-path Core
# Xcode 開啟 LineDraw.xcodeproj，選 LineDraw、自己的 Signing Team、實機。
```

獨立 Runner（先完成 `ios-wda` 依賴設定，WDA 固定 16.12.10）：

```sh
python3 scripts/prepare-device-runner.py
LINEDRAW_TEAM_ID='<自己的 Team>' LINEDRAW_DEVICE_ID='<這支 iPhone>' \
  bash scripts/build-device-runner.sh
```

Runner bundle 是 `com.beybladehunter.linedraw.DeviceRunner.xctrunner`，與舊的 `WebDriverAgentRunner.xctrunner` 分開。衍生來源位於 `.runtime/DeviceRunnerSource`；只對它關閉本機模式 MJPEG broadcaster。HTTP 由 `USE_IP=127.0.0.1` 限定，隨機高埠。預裝 artifact 處理只作用於 `.runtime/DeviceRunner-Preinstalled.app`，不更動舊 WDA。

這支手機使用免費 Apple Team，已有舊 WDA、新 DeviceRunner、LineDraw 三個 App；另外安裝 fixture 被 Apple 拒絕。故實機 fixture 改用 Safari 的本機頁，沒有移除原 WDA。

iOS 27 Remote Pairing 首次配對（只在初次設定使用 USB）：

```sh
cargo run --manifest-path DeviceBridge/Cargo.toml --locked --features host-setup \
  --bin linedraw-pair-usb -- '<這支 iPhone UDID>' \
  '<本機受保護路徑>/device-rp-pairing.plist'
```

輸出路徑的父目錄請設成 0700。工具只選明確 UDID 的 USB 裝置、90 秒逾時、不覆寫既有檔案、檔案為 0600，不列印私鑰。原 `export-device-pairing.py` 保留作 classic 路徑相容工具，但此次 iOS 27 的本機 QueryType 不通，應使用上面的 Remote Pairing。host-setup feature 不包含在手機建置。
平常從手機設定頁匯入。僅 Debug 開發測試可將這個檔案送入自己的 App Documents，再用 `--import-device-setup` 啟動；成功後立即刪除暫存檔，憑證進 Keychain。不要將配對檔、簽章、UDID 或 `.runtime` 加入公開來源包。

DDI：iOS 27 使用自己安裝的 Xcode Cryptex 映像，首次設定工具只整理本機五個檔案，不下載或分發 Apple 映像：

```sh
python3 scripts/prepare-device-ddi.py \
  --restore-dir /Library/Developer/DeveloperDiskImages/iOS_DDI/Restore \
  --output '<本機受保護路徑>/LineDraw-DDI'
```

匯入 `Image.dmg`、`Image.dmg.trustcache`、`Image.dmg.cryptex_info`、`Image.dmg.root_hash`、`BuildManifest.plist`。實機已匯入；四個 payload digest 均與 Apple manifest 一致。Debug 開發可把此目錄送至 Documents/device-ddi 並用 `--import-device-ddi`，成功後暫存目錄會移除。普通使用者從設定頁選取五個檔案。

## 驗證證據

- Core 36 項、Rust 3 項、原生 UI 5 項通過，共 44 項。
- arm64 iPhone／simulator bridge、iOS 27 Simulator、實機簽署建置成功。
- 手機端 Remote Pairing、RSD、XCTest、WDA HTTP ready 成功，可重複啟動。
- Safari fixture 20／20 次跨 App 操作，147.21 秒，21 個本機 HTTP 請求（含一次自我檢查），每筆確認點擊後結果，結束清理成功。
- 原五筆 LINE 已抽頁面唯讀複查 5／5，35.95 秒；4 筆 ALREADY、1 筆 COMPLETE，沒有點擊抽選／兌換，沒有寫入正式紀錄。
- 拔線後使用者從手機啟動：20／20、150.30 秒，使用者回覆與實機報告一致。
- 重開機 DDI、斷 VPN、數百筆／長跑：待驗證。

開發者證據放在 `.runtime`，不進公開來源包。配對資料與 Apple DDI 位於私有目錄／手機 Keychain 和 App Support，不在診斷、Git 或來源 ZIP。
