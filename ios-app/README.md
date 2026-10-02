# LineDraw iPhone 1.1.0 build 18 — device POC

build 18 支援「抽獎期間已結束」的內文、停用按鈕與已知提示框，確認後接續下一筆；不點確認或兌換。詳見[修正與測試](docs/ENDED_NOTICE_BUILD18_2026-10-02.md)。

build 17 修正 Funbox 純販售列造成整頁解析失敗，新增首頁「Funbox 原站／陀螺獵人」來源切換、獨立快取及同步時間。同一張券共用完成紀錄，手機自主與新版 Mac 模式都固定沿用開始時來源。詳見[更新與驗證](docs/CATALOG_SOURCES_BUILD17_2026-10-02.md)。

build 16 移除換頁時關閉舊優惠券、收合動態島與頂部 OCR 的流程。抽選指令成功回應並保存紀錄後，直接送出下一筆網址；LINE 沒有暴露網址時，以新的穩定畫面確認底部按鈕或結果，不要求讀到舊券關閉。系統進度遮住右上角不再因此停止。詳見[修正與驗證](docs/DIRECT_LINK_BUILD16_2026-10-02.md)。

build 15 更新五連結測試區，依序為 Qd5hJVq、QGhOsnX、XnMZVTX、W0zn6z4、yz7xFEWc，截止台北時間 2026/10/31 23:59。升級封存上一組內建活動並保留參加紀錄，自訂清單不覆蓋。抽選引擎沿用 build 14，本次不執行抽選，交由使用者手動測試。詳見[清單更新紀錄](docs/TEST_LINKS_BUILD15_2026-09-29.md)。

build 14 在點擊回應及紀錄保存後直接開下一筆，減少原生按鈕重複讀取，查詢失敗後本輪退回完整辨識，並新增一般模式分段耗時。新頁確認失敗時使用關閉復原；不使用固定螢幕座標。成功畫面讀取也更新系統工作進度，避免慢載入被判定停滯；通知遮擋時有界等待。Core 93 項、最終 LINE 五筆唯讀複查、原生按鈕逾時復原及取消測試通過；強制 OCR 備援最終 5/5 通過，仍屬較慢的備援路徑，偶發 WDA 失效元素仍會停止。尚未以未抽過的 LINE 新券量測本版真實抽選速度。詳見[實作與驗證](docs/DIRECT_HANDOFF_BUILD14_2026-09-29.md)。

build 13 更新內建五筆測試連結為 o2HccT8、OTyB3Jk、97hZCi0、SES3j9s、S4sB6XO，截止時間維持台北時間 2026/10/31 23:59。升級會封存上一組內建活動並保留參加紀錄；自行匯入的清單不會被取代。本次為清單更新，未執行這五筆真實抽選。詳見[清單更新紀錄](docs/TEST_LINKS_BUILD13_2026-09-29.md)。

build 12 加入按鈕直接定位、動態尺寸、底部裁切 OCR 與查詢成本比較；直接查詢較慢時改用完整辨識。本輪五筆真實抽選已送出並保存紀錄，效果與限制見[驗證報告](docs/BUTTON_LOOKUP_VALIDATION_2026-09-29.md)。各版的歷史證據分開保留，不將本機 fixture 當作真實 LINE 抽選。長逾時疊加 OCR 的壓力測試仍有背景工作被結束的限制，尚未通過整批完成驗收。

**手機自主 POC 已通過手機端 WDA 啟動、20 次跨 App 操作與 LINE 五筆已抽結果複查。拔線後由使用者從手機重新啟動也已通過 20／20；指定手機重開機後的啟動檢查也由使用者完成並回報通過。** 詳見[實作與驗證紀錄](docs/COMPUTER_FREE_IMPLEMENTATION_2026-09-28.md)。原 Mac 模式保留。

原生 SwiftUI App，採 iOS 27 Liquid Glass、系統分頁／導覽、繁體中文介面。手機管理網站清單與本機紀錄；預設透過手機端 WDA 操作 LINE，也保留 Mac 輔助模式。**無網站登入、無 VIP 驗證。**

自有程式碼採 [PolyForm Noncommercial 1.0.0](LICENSE)：公開原始碼、限非商業使用，商業使用另取得授權。第三方元件保留原授權。這不是 OSI 定義的開源授權。此倉庫公開來源碼；未提供 App Store 版本。

## 開啟、建置

首次從 GitHub 建置請依[建置與安裝指南](../docs/BUILDING.md)，包含 Rust bridge、App／即時動態簽署及獨立 DeviceRunner。

- Xcode 27，iOS 27+；Mac companion 需要 Node.js 24+、npm 10+。
- 打開 `LineDraw.xcodeproj`，scheme 選 `LineDraw`。模擬器不需要簽署。
- 實機：App target 選自己的 Signing Team，使用自己的唯一 Bundle ID。另依 `../ios-wda/README.md` 設定 WDA；兩者是不同的 target / App。
- 先執行 `bash scripts/build-device-bridge.sh` 建置 Rust 靜態 XCFramework（需要 rustup / cargo）。支援 arm64 iPhone、Apple Silicon simulator。
- 第一次 SwiftPM 會取得鎖定的 SwiftSoup 2.8.8。
- 從原始碼建置前，安裝 Ruby `xcodeproj` gem，執行 `ruby scripts/generate-project.rb`。產生器會從本機 Xcode 準備私人建置使用的 DDI；本機沒有 DDI 時不加入該資源，App 會使用固定版本下載。產生器不寫入個人 Team。Apple DDI 不放入來源 ZIP。

```sh
swift test --package-path Core
xcodebuild -project LineDraw.xcodeproj -scheme LineDraw \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .runtime/DerivedData CODE_SIGNING_ALLOWED=NO build
```

## 手機首次配對（build 6）

指定 iOS 27 實機已成功從系統設定輸入 PIN，由手機產生、驗證並保存新配對；使用者也已確認完成。使用者已完成重開機後啟動檢查，尚不外推其他機型。

簽署安裝 App 與 DeviceRunner 後，到「設定 → 手機自主模式」按「開始手機配對」，再到系統開發者模式選擇 **Pair with LineDraw**，輸入即時動態顯示的 PIN。App 經 LocalDevVPN 核對本機身分後，自動保存配對憑證並準備 DDI；不再要求從電腦匯入配對檔。重新配對只有成功後才替換舊憑證。完整操作、變更與實測範圍見 [手機配對說明](docs/PHONE_PAIRING_2026-09-29.md)。

仍需自行完成開發者模式、信任、LocalDevVPN 及本機網路授權。App / Runner 的簽署安裝與續簽是前置條件。新的 PIN 即時動態 extension 也需同一 Team 簽署。本版未內嵌 VPN；「只用手機操作」不代表只安裝一個 App 或所有系統版本皆已驗證。

## 速度驗證逾時修正（build 8／9）

Safari 測試頁第一次畫面結構查詢曾逾時。現在只有唯讀 `GET source` 在逾時後可重新查詢一次，點擊和開網址不重送；正常查詢不增加固定等待。速度驗證直接沿用必要 DDI，不再每次強制下載整套檔案。詳見 [修正與驗證](docs/SNAPSHOT_TIMEOUT_2026-09-29.md)。

build 9 的 Core 49 項與 Debug／Release 建置通過，已安裝至指定手機。build 8 的兩輪五筆實機測試通過，約 39～40 秒；build 9 正常五筆 43.50 秒，受控逾時（注入一次 18 秒等待及 timedOut）測試 5／5 通過、每筆確認一次，查詢途中停止亦未送出點擊。受控注入與真實自然逾時、Safari 測試頁與 LINE 抽選的證據分開記錄。

## 手機自主模式：自動檔案與速度

build 4 啟動時依序驗證快取、載入私人建置隨附的 Xcode DDI，最後才下載固定 revision 的 Cryptex DDI。下載需通過 SHA-256，全部 payload 另依 manifest 驗證 SHA-384，再一次替換；中斷不覆蓋舊檔。設定也可先按「準備必要檔案」。使用 iOS 通用 Cryptex 身分驗證，不能把 legacy `SupportedProductTypes` 清單當成新機型必須出現的條件；真正掛載相容性仍由 Apple 個人化簽署與裝置檢查。

已移除每筆固定 1 秒等待、反覆查尺寸／設定與來源網站 HEAD 請求；由畫面穩定性及即時目標重新核對決定何時點擊。WDA 不等待動畫冷卻，成功回應直接下一筆。慢載入最多兩次 30 秒、回應不明不重送的規則保留。

配對、簽署 DeviceRunner、開啟開發者模式與 LocalDevVPN 仍需首次設定；DDI 自動下載不會代替這些授權。完整數據與限制見 [build 4 驗證報告](docs/AUTO_DDI_AND_SPEED_2026-09-29.md)。

## Mac 輔助模式（保留的既有路徑）

在「設定 → 執行方式」選擇 Mac 輔助模式，再依下列步驟。手機自主模式設定與限制請讀上述實作紀錄。

1. 首次開啟閱讀並同意使用說明；不同意則保持功能鎖定，可自行關閉 App。iOS 不使用強制 `exit()`。
2. 「抽選」下拉同步來源網站。清單依來源順序，地區與狀態可多選，也能搜尋；未知時間及未解析連結不會自動抽選。大量短網址首次解析可能較久，可按取消，保留前次資料。
3. 在 Mac 執行 `ios-wda/啟動控制面板.command`。連接並解鎖 iPhone、完成 LINE 登入及 WDA 連線。
4. Mac 與 iPhone 同一區域網路，Mac 控制台按「配對 iPhone App」。手機「設定 → Mac 輔助程式」掃描 QR 或貼上配對 URI；允許區域網路，掃 QR 時才需相機。
5. 手機選清單、開始本次批次。必要時會加入好友；一筆點擊成功回應後直接進下一筆，不等待中獎結果。LINE 在前景時，可在 Mac 控制台暫停或停止。回到 App 會重新取得進度及紀錄。
6. 手機保持解鎖，Mac 保持運作；USB / WDA 與 Mac 仍然是目前執行必要條件。手機 App 不需自己常駐背景；批次在 Mac 執行。

配對使用本機 HTTPS 4781、QR 中的憑證 SHA-256 指紋與一次性 5 分鐘配對碼。錯誤 5 次使本次邀請失效；配對權杖 30 天有效，放 iOS Keychain；Mac 只保存權杖雜湊。4781 只有按配對後才開啟；Mac「撤銷手機配對」停止該批次、撤銷權杖並關閉端點。Mac 控制台 4780、Appium 4725 保持 localhost。

## Android 功能對照

| 功能 | iPhone 版本 |
|---|---|
| 网站同步、保留來源順序 | SwiftSoup 解析同一來源；失敗保留前次資料 |
| 地區／活動狀態多選、搜尋 | 原生篩選 sheet；同組 OR、不同組 AND |
| 時間判斷 | Asia/Taipei；起始含端點、截止不含端點；優惠券使用期限不當抽選時間 |
| 選取／全選、依序抽選 | 手機凍結本次清單，手機端或 Mac WDA 執行 |
| 自動加好友 | 設定可開關；需要好友且關閉時暫停 |
| 完成後下一筆 | 成功點擊回應記 SUBMITTED，直接接續 |
| 已領取／中獎／未中獎／已結束 | 沿用 WDA 畫面判斷，直接接續，不點兌換 |
| 慢網路 | 30 秒載入重開一次，兩次仍失敗本輪略過；斷網等最多 60 秒後暫停 |
| 來源新增活動 | 本輪後最多 3 輪增量同步，保留原篩選；不重排未選舊項目與本輪失敗項目 |
| 暫停／繼續／停止／略過 | 原生進度；手機模式可用 iOS 工作進度取消或回 App 停止，Mac 模式可用控制台停止。停止同步可取消進行中的來源請求 |
| 手動完成／撤銷 | 詳情及滑動操作；撤銷恢復之前的紀錄，不清掉已送出證據 |
| 紀錄、帳號區隔 | 本機設定檔＋網站／測試／示範分區；不讀取 LINE 身分，更換帳號請換設定檔 |
| 五連結測試區 | 更新為 9/29 提供的新五筆，至 2026/10/31 23:59（台北時間）；更新後自動封存舊內建清單、保留紀錄，使用者自行匯入的清單不覆蓋 |
| 診斷 | 預覽、分享、清除；預設不含聊天、畫面與原始 URL |
| 使用聲明 | 首次及版本變更需同意；已改為公開原始碼版本說明 |
| 登入、VIP | 依需求移除，不移植 |
| Android 無障礙／浮動控制列 | 使用手機端 WDA 或 Mac＋WDA；iOS 不直接移植 Android 跨 App overlay |

同步移除的活動封存，完成紀錄不刪除。若短網址本次暫時解析失敗，保留前次成功的對應與紀錄。首次未解析的連結需先同步成功，才可手動標記，避免身份變更後重抽。未知操作／點擊回應中斷記「待確認」，不自動重送；重新啟動服務也不自動繼續。

## 測試與資料

「設定 → 離線示範」不操作 LINE；可完整體驗選取、批次、紀錄。XCUITest 僅以 `--ui-testing` 啟動 Debug App 並使用獨立 `LineDraw-UITests` 儲存；不影響正常 App 資料、Keychain 或真實手機。

測試 JSON 格式為陣列，每筆含 `title`、完整 LIFF `url`、帶時區的 `startsAt` / `endsAt`；連結須為 `https://liff.line.me/<app>/c/<coupon>`。起訖時間以實際活動為準，不能任填未來時間來繞過截止。

本機資料：iOS Application Support/LineDraw/state.json；Mac ios-wda/.data。資料損毀時保留原檔並鎖住功能，不自行清空。移除 App 會失去本機紀錄；此版未提供跨手機同步或備份還原 UI。歷史原型的 15 筆紀錄保留原 scope，不自動歸入新 App。

[9/28 歷史驗證報告](docs/VALIDATION_2026-09-28.md) 區分單元、TLS fixture、模擬器與實機；當時新 App 的 Mac HTTPS 配對＋LINE 整合仍未完整驗收。後續手機自主模式實測請讀上方 9/29 各版報告，兩種路徑的驗收不互相替代。

## 免電腦研究

[評估文件](docs/COMPUTER_FREE_RESEARCH_2026-09-28.md) 核對 idevice、StikPair、TouchSynthesis、CoreDevice HID 與 Apple continued processing。`idevice` 已整合為 Remote Pairing／RSD 手機端啟動器。已有部分實機證據，完整免電腦驗收狀態見 [9/29 報告](docs/COMPUTER_FREE_VALIDATION_2026-09-29.md)。TouchSynthesis 等替代路線未接入。

## 原始碼

- `DeviceBridge/`：Rust 手機端開發者服務啟動器與固定依賴。
- `App/`：SwiftUI、配對 QR、憑證釘選、Keychain、AppModel。
- `Core/`：清單／時間／篩選／本機儲存／傳輸模型及測試。
- `UITests/`：原生模擬器操作驗證。
- `Resources/`：圖示、色彩、隨 App 提供的完整授權聲明。
- `../ios-wda/src/mobile-*.mjs`：原生 App 的 Mac HTTPS 入口、佇列及來源更新。

發行只包含 ios-app / ios-wda 的來源，Android、網站、憑證、配對檔、UDID、執行紀錄與建置快取不包含在此授權發行範圍。
