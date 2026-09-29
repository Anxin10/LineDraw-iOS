# iOS 免電腦抽選：上游查證與下一階段 POC

日期：2026-09-28。這是一份技術評估，不是本專案已完成的實機能力。此輪沒有啟動實機 WDA、安裝 VPN、匯入配對檔或送出真實抽選。

## 結論

其他 AI 提出的主力方向有實際上游依據，值得做 POC。先前「一定需要電腦或外接硬體」的說法過於絕對：一般 iOS App 的公開 API 不能跨 App 點擊，但透過開發者服務、有效配對、DDI、回環 VPN 與 XCTest，存在研究中的手機端啟動途徑。它仍不是一般 App 安裝後直接可用的能力。

本專案目前由 Mac 執行 `ios-wda/src/engine.mjs` 的頁面判斷、依序開連結、點擊、重試與紀錄。電腦**不只是 WDA 啟動器**。因此不能只替換啟動方式就宣布移植完成。

## 查證結果

| 建議中的主張 | 本次查證 | 對 LineDraw 的含義 |
|---|---|---|
| idevice 已有 XCTest / WDA 啟動 | README 列出 `xctest`、`wda` 及 `xctest --bridge`；FFI Cargo 也含 `wda` 功能。 | 可用來驗證另一條啟動路徑；仍需移植完整佇列與畫面判斷。 |
| StikDebug 證明手機回連開發服務 | 官方 README 記載配對檔、LocalDevVPN，以及首次配對後免電腦 JIT。 | 證明相關通道有使用案例；不是我們 LINE 抽選流程的驗收。 |
| iOS 27 可手機端配對 | StikPair 官方 README 明列 iOS 27+、開發者模式內輸入 Live Activity PIN 的流程。 | 可望減少首次配對對電腦的依賴，但不處理安裝、簽署與更新全部問題。 |
| AltStore Classic 2.3 已官方確認 | 所附 PR 是 `gapul/dotfiles`，是使用者環境設定，不是 AltStore 官方 repo。 | 不用這筆作正式相容性依據。 |
| iOS 27 devicectl 備援停用 | Appium 文件明列 iOS/tvOS 27+ 限制及 RemoteXPC 要求。 | 不應用普通啟動 App 取代建立 XCTest session。 |
| DDI 缺失通常一週補齊 | Issue #464 證明有人遇到 iOS 27 DDI 掛載失敗；沒有普遍一週保證。 | 把機型、OS build、DDI 配對列入實測條件。 |
| 已有商業產品，所以可直接量產 | AScript HID 文件說明 ESP32、錄屏與輔助觸控；EasyClick 頁本次憑證錯誤、Agent 頁讀取失敗。 | 可當線索，不能替代我們對目前手機與授權分發的驗證。 |

主要依據：[idevice README](https://github.com/jkcoxson/idevice)、[idevice FFI features](https://raw.githubusercontent.com/jkcoxson/idevice/master/ffi/Cargo.toml)、[StikDebug](https://github.com/StikDebug/StikDebug)、[StikPair](https://github.com/StikDebug/StikPair)、[Appium 預裝 WDA](https://appium.github.io/appium-xcuitest-driver/latest/guides/run-preinstalled-wda/)。對來源強度的核對：[個人 dotfiles PR](https://github.com/gapul/dotfiles/pull/846)、[DDI issue #464](https://github.com/StikDebug/StikDebug/issues/464)。

## 架構需要補上的關鍵

1. **把批次交給 runner 執行是合理方向，但還不夠。** 控制台被 iOS 暫停後，負責 RemoteXPC tunnel、testmanagerd session、心跳的程序也必須仍然存活。如果這些都放在控制台 App 裡，搬了抽選迴圈仍可能中途失效。這是架構推論，需要刻意把控制台切到背景，測試超過一般背景寬限時間。
2. 控制台負責同步、篩選、紀錄與明確開始；runner 取得完整、凍結的工作清單後自主處理，逐筆先保存操作意圖，再點擊。控制台被暫停不影響進度。重啟、重新激活都不可自動重送不確定的操作。
3. POC 優先使用 LocalDevVPN，縮小驗證面。自帶 NetworkExtension 是後續部署選項，需要實際能簽署的 entitlement 與 extension 生命週期設計；不是往 plist 加兩行就能啟用。
4. 配對檔含裝置信任資訊，不可進 Git、診斷或來源包。放本機安全儲存；控制 API 需有一次配對及授權，不能將未驗證的 WDA 端口公開到區域網路。
5. 需分開驗證「啟動一次後可拔線」、「重開機後免電腦重啟」與「首次安裝到更新都不用電腦」。三者是不同驗收標準。

## 建議的驗證順序與停止條件

### A. 保留目前可工作的 Xcode / Mac 路線

凍結現有已驗證的 WDA。另建實驗目錄，固定 idevice commit 與依賴版本。先用離線 fixture，不直接重抽既有優惠券。

在 Mac 上依上游 CLI 驗證：

```text
idevice-tools --udid <測試裝置> xctest --bridge <另外簽署的Runner.xctrunner>
```

具體命令先以該版本 `--help` 為準。檢查 HTTP ready、session、讀元素、開 fixture、一次點擊與完整停止。Appium 要求移除內嵌 XCTest framework 的說明適用於預裝啟動路徑；應在獨立產物操作並重新檢查簽章，不修改目前可工作的 WDA。

### B. 手機端啟動與背景存活

最小控制台：idevice FFI → 匯入既有配對 → LocalDevVPN → 掛載對應 DDI → 建立 XCTest session。先不做手機端首次配對、不做抽選功能。控制台進背景、fixture 前景持續 20 分鐘，重複讀取與點擊；中斷 VPN／Wi-Fi、停止與重開機各測一次。若 session 隨控制台暫停而結束，先解決通道生命週期。

### C. runner 內的抽選引擎

移植順序、底部按鈕判斷、加好友、已中獎／未中獎／已結束跳過、30 秒載入重開一次、60 秒斷網暫停、停止與持久紀錄。保留 `SUBMITTED` 與「確定完成」區別，不等待結果、不點兌換。以 fixture 驗證後，再用新有效連結做小批實機測試。

### D. 免電腦重新激活與首次配對

證明 B/C 能持續執行後，再接 idevice 的手機端配對。驗收：iPhone 重開機後只用手機恢復、完成 5 筆；隨後重開舊券確認中獎／未中獎都接續。分別記錄是否需 Wi-Fi、開發者模式、VPN、重新簽署、手動信任。最終才能決定是否達到一般使用者可用程度。

## 其他路線與授權

- **ESP32 HID**：保留為備案。AScript 原廠文件確有 HID 模式，依赖錄屏與輔助觸控；我們還需自己解決可靠定位、不同版面、畫面回饋、停止及背景執行。不能保證 iOS 更新完全不影響。[原廠文件](https://www.ascript.cn/docs/ios/download/hid-mode/)
- **TrollStore**：官方目前列 14.0 beta 2～16.6.1、16.7 RC、17.0，不適用現在的 iOS 27 手機。沒有必要把主產品建立在這條路上。Dopamine 3.0 發布等附帶說法本輪未獲官方驗證，不作決策依據。[TrollStore](https://github.com/opa334/TrollStore)
- **授權**：idevice 是 MIT；StikDebug 是 AGPL-3.0，不能直接把上游整份改標成我們的非商業授權。StikPair 的 LICENSE 是加入非商業限制的自訂 MIT 變體，也不能視為標準 MIT。建議直接使用 idevice，自己實作界面與流程，保留上游 notice。[StikPair LICENSE](https://raw.githubusercontent.com/StikDebug/StikPair/main/LICENSE)
- LineDraw 自有程式碼依已選定的 PolyForm Noncommercial 1.0.0 發布；用語採「公開原始碼、限非商業使用」。

## 搜尋摘要與限制

- 已執行 smart-search 的 OpenCLI live registry / help 預檢。沒有 GitHub 站點 adapter；改用使用者提供的官方網頁與 raw source 直接讀取。沒有呼叫其他 AI 搜尋。
- GitHub：直接核對 idevice、StikDebug、StikPair、TrollStore，以及指定 issue / PR；關鍵字搜尋 0 次。
- Appium：直接讀取 Run Preinstalled WDA；關鍵字搜尋 0 次。
- AScript：直接讀取 HID 文件；Agent 文件初次讀取失敗，直接請求亦逾時。關鍵字搜尋 0 次。
- EasyClick：指定網址讀取失敗，直接請求證實 TLS 主機名不符；沒有繞過憑證檢查。關鍵字搜尋 0 次。
- 沒有把開發文件、廠商宣稱或 issue 關閉視為我們的實機測試通過。

## 補充：TouchSynthesis、CoreDevice HID 與 continued processing

使用者再提供的資料，增加了一個值得保留的 self-runner 研究路線。本次已直接讀取以下程式碼，沒有編譯或啟動它。

- `SelfRunner.swift` 確有設定 XCTest 環境、建立 testmanagerd control/test session、載入 XCTest 與啟動 automation 的流程；也確認啟動時會點 `(195,400)`，而 tap 回報錯誤只寫 warning，之後仍顯示 ready。POC 應移除初始化點擊，並以 fixture 的可觀測變化、明確錯誤與停止能力驗收。[SelfRunner 原始碼](https://raw.githubusercontent.com/willfaust/TouchSynthesis/main/TouchSynthesis/TestManager/SelfRunner.swift)
- 作者 README 寫實測 iPhone 13 Pro / iOS 26.3。原始用途是 TCP 遠端畫面串流與控制，不能把它當成已有完整元素定位、抽選清單與手機自主批次。需特別注意「fire-and-forget」回應不能当成完成觸控的證據。[TouchSynthesis](https://github.com/willfaust/TouchSynthesis)
- `BackgroundKeepAlive.swift` 確認使用背景定位更新，回呼不處理位置；我們目前的抽選產品不需要定位，所以不直接搬這段保活設計。[背景程式碼](https://raw.githubusercontent.com/willfaust/TouchSynthesis/main/TouchSynthesis/Util/BackgroundKeepAlive.swift)
- **新增的授權缺口**：截至本次檢查，repo 根目錄、完整 main tree 與 README 沒有找到 LICENSE。公開可讀不等於獲得重製、修改與分發授權。不能因為它依賴 MIT 的 idevice，就把 TouchSynthesis 本身當作 MIT。接入公開的 LineDraw 前，需取得作者授權或自行實作，不能直接複製進 PolyForm 專案。[專案檔案樹](https://github.com/willfaust/TouchSynthesis)
- `core_device/hid.rs` 確有輸入控制；檔頭明確說必須同時有 displayservice media stream，否則服務收到事件也不會變成系統輸入。這是第二階段候選；不代表手機自己回連自己已測通。[HID 原始碼](https://raw.githubusercontent.com/jkcoxson/idevice/master/idevice/src/services/core_device/hid.rs)
- `idevice` 的 `wda.rs` 確實還有 client 操作；README 將它定位為 bootstrap 層，不等於已涵蓋現有 Appium 流程所有功能。需按固定 commit 逐一列出缺少的查詢、逾時、取消和 transport 行為。[WDA 原始碼](https://raw.githubusercontent.com/jkcoxson/idevice/master/idevice/src/services/wda.rs)
- Apple 的 `BGContinuedProcessingTaskRequest` 要從前景、因使用者操作提交；`BGContinuedProcessingTask` 要回報進度，可被使用者取消，也可能因執行時條件被系統終止。因此可測「手動開始的一段有終點任務」，不能當任意常駐、準點排程、跨 App 點擊權限或 App Store 可上架證明。[Apple task](https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtask)、[Apple request](https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtaskrequest)。本次透過同站 DocC JSON 核對文件正文。

本專案已確認這類 LIFF 優惠券會跳 LINE／桌面 QR，不再重複把 Safari 當主方案。抽選邏輯也維持使用者指定的「送出後下一筆」，不採補充文章中的等待中獎結果流程。TouchSynthesis 暫列有授權前提的替代技術參考；主線仍建議先驗證 idevice＋現有 WDA，並把 session 存活、控制台背景及重開機後啟動分开測試。

補充搜尋摘要：GitHub 直接讀取 TouchSynthesis README、SelfRunner、BackgroundKeepAlive、完整 main tree，以及 idevice WDA/HID；Apple Developer 直接讀取 task/request 與 DocC 正文。關鍵字搜尋均為 0 次；無實機相容性宣稱。
