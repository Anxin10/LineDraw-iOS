# 自動準備 DDI 與抽選速度改善

日期：2026-09-29（台北），版本：1.1.0 build 4。

## 交付

已簽署並安裝至原測試 iPhone。保留原有資料、配對與 DeviceRunner，沒有變動 Android、網站或 Mac 佇列。新測試使用獨立記憶體紀錄，不寫入正式參加紀錄。

### 必要檔案自動準備

按開始／檢查啟動時自動執行，也可在「設定 → 手機自主模式 → 準備必要檔案」先完成：

1. 檢查既有五個 DDI 檔案，驗證 iOS Cryptex 身分及 manifest 的 SHA-384 digest。
2. 沒有完整快取時，優先載入私人建置隨附的本機 Xcode 映像。
3. 沒有隨附映像時，從 `doronz88/DeveloperDiskImage` 社群鏡像下載五個檔案，約 16.70 MB。固定 commit `7e29c5905cf3c53870a26854127cce9496ec6480`，每個檔案另驗證程式內固定的大小及 SHA-256，不自動追蹤 `main`。
4. 下載使用 HTTPS、拒絕重新導向、限制大小與逾時；完整驗證之後才原子替換快取。取消、斷線、損毀或格式錯誤不會先刪掉原本快取。
5. 檔案留在 Application Support，排除備份；私人建置的 Apple 映像不納入原始碼 ZIP。

本機 Xcode 映像 build 為 `27A266a`；鏡像下載為 `27A5228h`。兩者不能因檔名相同就混用。實測分別在空白暫存目錄完成自動載入與全套下載驗證；未替換手機原本可用的 DDI。

Cryptex identity 使用 `Ap,TargetType=ioscryptex` 與 `DeviceClass=ioscryptexap`。**不能把 manifest 的 legacy SupportedProductTypes 清單當成 Cryptex 新機型必須出現的條件**；本次測試曾發現這會錯誤拒絕原本的 Xcode 映像，已修正並加入平台辨識測試。檔案格式與 digest 通過不等於已證明所有機型可掛載；Apple TSS／裝置掛載結果才是執行依據。

仍需首次完成：開發者模式、配對、DeviceRunner 簽署／信任、LocalDevVPN。這些不是可直接下載取代的設定。重開機後首次掛載，及本次下載映像在未掛載裝置上的實際掛載，仍待後續實測；本輪沒有重開使用者手機。

### 速度改動

- 去除每筆開網址後固定 1 秒等待；畫面尚未完成時繼續輪詢。
- 輪詢間隔 0.4 → 0.2 秒，仍需觀察到兩次穩定的新畫面。
- WDA `waitForIdleTimeout`、`animationCoolOffTimeout` 設為 0，停止等待 LINE 動畫自然靜止。
- 畫面尺寸與 activeAppDetectionPoint 不再每次重查／重設；畫面來源中的 application frame 改變時更新。
- 保留剛取得的畫面。原生按鈕在兩次穩定觀察後，僅於最後畫面小於 0.2 秒且未有其他操作時重用；重新確認前景 App、唯一按鈕、位置、文字及無對話框。超時、OCR 目標或任何操作後都重新讀取。只重用小於 0.3 秒的終態畫面來關閉目前優惠券頁。
- OCR 避免在短暫空白載入頁立即執行；相同來源短暫重用辨識文字，但真正 OCR 點擊前重新辨識。
- 使用 NWPathMonitor 判斷連線路徑，移除逐筆對來源清單網站發 HEAD 請求。路徑可用不等於 LINE 網際網路可用；後者仍由載入期限處理。
- 成功點擊回應即接下一筆，不等待中獎結果。兩次各 30 秒的慢載入處理、60 秒無路徑等待、先落盤操作意圖，以及回應不明不重送維持。
- 診斷新增佇列耗時、畫面查詢次數及耗時；不記錄 URL、帳號或畫面內容。

## 驗證結果

環境同前一輪：iPhone 18 Pro Max、iOS 27.0、LINE 26.15、LocalDevVPN 1.3.0。USB 連線用於安裝、啟動測試及讀回報告；操作迴圈、DDI 下載與 WDA 啟動皆在手機。**這輪沒有重新做拔線驗收**，先前 build 3 的 20 次拔線測試見另一份報告。

| 測試 | 修改前／基準 | build 4 | 說明 |
| --- | ---: | ---: | --- |
| 同一本機五筆抽選流程 | 27.3742 秒 | 21.2024 秒 | 佇列耗時少 6.1718 秒（22.55%）；排除下載及 Runner 啟動時間；各測一次，非統計效能保證 |
| 五筆操作確認 | 5／5 | 5／5 | 每個測試頁只收到一次操作，皆記 SUBMITTED |
| 查尺寸 | 20 次 | 1 次 | 同一本機五筆流程 |
| 設 WDA 參數 | 21 次 | 2 次 | 同一本機五筆流程 |
| 原五筆 LINE 已抽結果複查 | 22.2456 秒 | 22.4686 秒 | 均 5／5；本組未量得明顯提速，不能宣稱所有 LINE 頁面都快 23% |
| 自動載入隨附 DDI | 手動匯入 | 通過 | 空目錄，自動載入、完整性驗證 |
| 手機直接下載五檔 | 無 | 通過 | 固定 HTTPS 來源、SHA-256、manifest SHA-384；獨立目錄 |
| Core | — | 42 項通過 | 含殘留舊頁、短暫按鈕、慢載入、重複送出保護與 DDI 損毀／錯平台／symlink／原子替換 |
| 原生 UI | — | 5 項通過 | iOS 27 模擬器 |
| Debug／Release 建置 | — | 通過 | Debug 簽署安裝；Release 無簽章編譯 |
| 測試後清理 | — | 通過 | DeviceRunner／WDA 無殘留程序；已開回一般 App |

基準版由修改前 `LocalWDA.swift`、`DeviceBatch.swift` 建立隔離副本，配上相同測試頁與耗時欄位；未改寫正式來源回舊版。測試後已裝回 build 4。第一輪新版本機流程（尚未減少最後一步重複查詢）為 22.5066 秒；最終版本 21.2024 秒。

原五笔複查依序為 ALREADY、ALREADY、COMPLETE、ALREADY、ALREADY；未按抽選／兌換。第一輪調校中的 LINE 複查為 25.7711 秒，最終為 22.4686 秒，網路與畫面讀取有波動，沒有挑最快結果當作真實新抽選速度。

使用者表示之後提供未抽過的新連結。**本機測試證明佇列及點擊流程改善，尚未驗收真實新抽選送出速度；不把點擊回應當作中獎或遠端抽選成功。**

## 檔案及證據

主要程式：`App/DDIManager.swift`、`App/DDIDownloadCatalog.swift`、`Core/Sources/LineDrawCore/DDIPackage.swift`、`App/LocalWDA.swift`、`Core/Sources/LineDrawCore/DeviceBatch.swift`；入口、設定與診斷在 AppModel／DeviceSetupView。建置產生器自動準備私人 DDI 資源；來源 ZIP 解開後先重跑產生器，以依本機環境重建資源參照。

本機證據（不進來源 ZIP）：

- `.runtime/device-speed-baseline.json`、`device-speed-final.json`、`device-speed-initial.json`
- `.runtime/review-before-optimization.json`、`review-after-optimization.json`、`review-after-optimization-final.json`
- `.runtime/core-build4.log`、`Build4UITestsFinal.xcresult`
- `.runtime/build4-phone.log`、`build4-release-final.log`、`build4-processes-after.json`

## 資料查證

使用 smart-search 的 OpenCLI GitHub code search 1 次：`DDI repo:StikDebug/StikDebug`；另外以 web 搜尋 GitHub 上游資料 2 個 query（StikDebug DDI download／idevice DDI download 27），並直接讀取固定 revision 的原始碼與檔案。無搜尋或傳送私有配對資料。

- [DDI 鏡像固定版本](https://github.com/doronz88/DeveloperDiskImage/tree/7e29c5905cf3c53870a26854127cce9496ec6480/PersonalizedImages/Xcode_iOS_DDI_Cryptex)：檔案來源、實際下載驗證。
- [idevice](https://github.com/jkcoxson/idevice)：既有 MIT 裝置服務與 Cryptex/TSS 實作。
- [StikDebug 的 DDI 來源配置](https://github.com/StikDebug/StikDebug/blob/4bdfc92aa7cebd7a534f1e1ef56415f5727402de/StikDebug/Services/DeveloperDiskImageService.swift)：僅用於確認公開檔案位置，沒有複製 AGPL 程式碼。

自有程式維持 PolyForm Noncommercial 1.0.0；沒有對外發布或上架。
