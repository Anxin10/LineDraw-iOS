# LineDraw Mac 輔助程式 1.0.0-alpha

新增原生 iPhone App：網站清單同步、多地區／狀態篩選、手動完成與撤銷、紀錄與測試區都在手機操作。Mac 保留 WDA 執行引擎；啟動控制台並連接 iPhone 後，按「配對 iPhone App」產生限時 QR Code。詳細安裝、配對與功能範圍見 [原生 App README](../ios-app/README.md)。

授權：自有程式碼採 PolyForm Noncommercial 1.0.0，公開原始碼、限非商業使用。第三方保持原授權，見 [第三方聲明](THIRD_PARTY_NOTICES.md)。沒有網站登入或 VIP 驗證。

以下保留原型的 WDA 設定與既有實機證據。新原生介面與 HTTPS 配對尚須在 iPhone 做完整驗收；舊 WDA 抽選通過不等於新整合已通過。

---

# LineDraw iOS WDA 原型 0.1.0

Mac 本機控制面板 → Appium XCUITest Driver → WebDriverAgent → USB iPhone 上的 LINE。

**這是個人實機可行性測試版，不是可獨立安裝操作 LINE 的 iOS App。** 原五筆測試活動已內建；這一段記錄的是 0.1.0 時的原型範圍；1.0.0 的網站同步由原生 App 提供。Android 主版與既有紀錄未修改。2026/09/28 已在 iOS 27 真機完成十筆送出及十筆結果頁重查；首次加入好友及其他機型仍待實機驗證。

## 接手機測試

2026/09/28 實機檢查：升級 macOS 27 與 Xcode 27 後，DDI、WDA 簽署安裝及啟動已通過。原五筆與新增五筆各送出一次；修正後最後四筆首次抽選連續完成，再重新開啟全部十筆，確認 7 筆中獎、3 筆未中獎都能自動接續，沒有重抽或兌換。歷史結果摘要見 [WDA 驗證紀錄](VALIDATION.md)；原始裝置報告與執行資料未納入公開倉庫。

請先在此目錄執行 `npm run setup`，安裝固定依賴並編譯 Vision OCR，再依序操作：

1. iPhone 用 USB 接上這台 Mac，解鎖，選「信任這部電腦」，開啟「設定 → 隱私權與安全性 → 開發者模式」，依系統要求重新啟動。先手動打開 LINE 並完成登入。
2. 雙擊 **`開啟WDA專案.command`**。在 Xcode 選擇 **WebDriverAgentRunner target → Signing & Capabilities**，使用你的 Apple 開發 Team，勾選自動簽署，設定唯一的 Bundle Identifier。個人免費 Team 的 provisioning profile 有七天有效期。
3. 上方 scheme 選 **WebDriverAgentRunner**，執行裝置選你的 iPhone。首次可按 **Product → Test（⌘U）** 確认簽署／安裝正常；若手機要求信任開發者，依提示操作。完成首次檢查後，在 Xcode 停止測試，再讓本工具以預設 Xcode 模式啟動，避免兩個測試 session 互相搶裝置。
4. 雙擊 **`啟動控制面板.command`**，會啟動 Appium 與本機控制面板，開啟 **http://127.0.0.1:4780**。
5. 按「尋找已連接的 iPhone」並選取裝置。Team ID 是 10 碼；若已在上面的 Xcode 專案完成簽署，可留空。控制面板的 WDA Bundle ID 必須與 Xcode 的 **Runner target** 設定一致（不要自行加 `.xctrunner`）。預設值可改成你可簽署的唯一名稱。
6. 啟動方式先選 **Xcode 建置並啟動**，按「連線 iPhone」。首次編譯可能需要數分鐘。維持解鎖；先不要使用鏡像輸出。
7. 手動開一筆測試優惠券，按「檢查目前畫面」確認可辨識。若沒有識別到按鈕，暫停／停止批次並等待目前指令結束後，按「儲存畫面診斷」，便能針對真實 iOS LINE 畫面調整規則。
8. 建議首次只勾第一筆，確認畫面上的 LINE 帳號、勾選操作同意，按「開始依序抽選」。通過後再選剩餘項目。系統不逐筆要求店家／活動核對。

如果本機服務已在執行，重按啟動檔只會開啟既有控制面板。關閉啟動用 Terminal／按 Ctrl+C 會要求停止批次；已送到手機的點擊可能仍會完成。重新啟動不自動繼續抽選。

### 五筆原活動及有效期

以下是 Mac 原型的歷史清單；目前 iPhone App build 15 的五筆測試區另見[清單更新紀錄](../ios-app/docs/TEST_LINKS_BUILD15_2026-09-29.md)。

與 Android `TestCatalog.kt` 保持順序和優惠券 ID 一致，直接派送完整 LIFF 優惠券 URL，避免短網址再次導流：

1. https://lin.ee/WGMIH4U
2. https://lin.ee/niRxKxI
3. https://lin.ee/Q8gr93W
4. https://lin.ee/x2IpNpc
5. https://lin.ee/TCxN08P

使用者於 2026/09/28 確認原連結繼續有效，抽選期間更新為 **2026/09/22 00:00～09/29 23:59（Asia/Taipei）**；截止採 09/30 00:00 的排他邊界。Mac 時區不影響此判定。09/30 之後不能直接用這五筆做新抽選，請提供新的測試優惠券與真實起訖時間。LINE 顯示的「優惠券使用期限」不能替代抽選期間。

若同一個 LINE 帳號已參加過這五筆，本次只能驗證「已抽過／已領取」的跳過流程。要測試首次參加，請建立新的測試優惠券；清除本機紀錄不會重置 LINE 的參加紀錄。

## 已實作的操作

- 清單順序固定、開始後自動開下一個連結，支援獨立「加入好友」以及「加入好友並參加抽獎」。
- 只對已知動作標籤操作；抽選文字優先要求在畫面底部，原生元素無法取得時可在連線前開啟實驗性 Vision OCR。
- 不核對店家、活動名称；但會確認前景 App、底部目標是否唯一、目標是否仍存在，以及是否真的離開舊頁。
- 點擊指令成功回應即記「已送出」並進入下一筆，不等待中獎結果。此狀態不等於已確認參加／中獎。
- 「查看已領取的優惠券」、底部「使用優惠券」、底部停用的「可惜...沒有抽中！」、明確結果或「已結束」接續下一筆；不點擊「查看我的優惠券」、兌換或使用優惠券，也不把其他優惠券推薦上的「已領取」當成本筆結果。
- 每次載入最多 30 秒，未操作抽選時最多重開一次，再記載入逾時並略過。斷線或點擊回應不確定則暫停，不自動重送。
- 有明確的原生頂部「關閉」按鈕時，先關閉前一張優惠券，再開下一張。若兩張優惠券外觀完全相同，又無法關閉或觀察換頁，會等候／略過；這是實機測試要特別確認的項目。
- 暫停／恢復／停止；持久化操作意圖與紀錄；未完成的點擊意圖在重啟後轉「待確認」。
- 按「裝置 UDID＋LINE 設定檔」分隔紀錄。同手機切換 LINE 帳號須自行換設定檔名稱；工具不讀取 LINE 帳號身分。
- 手動標記完成、明確確認後清除單笔紀錄；匯入含時間的 JSON 清單。批次期間不修改清單與紀錄。
- XML 與截圖診斷需要手動按鈕；一般事件紀錄只存階段和已知原因。

目前無排程、自動鎖屏恢復、驗證碼處理、多帳號輪抽或結果兌換。原生 App 批次增加網站同步接續；登入與 VIP 不屬於此版本。

## 環境與啟動模式

- Node.js 24+、npm 10+、macOS、完整 Xcode。
- 已鎖定 Appium **3.8.0**、XCUITest Driver **12.13.2**；此次安裝 WDA **16.12.10**。
- 本次實機環境：macOS **27.0 (26A428)**、Xcode **27.0 (27A266a)**、iPhone 18 Pro Max／iOS **27.0 (24A437)**、LINE **26.15.0**。先前離線模擬器驗證使用 iOS **26.2**，兩者證據分開記錄。
- `mobile: deepLink` 的底層需要 iOS 16.4+；本原型目前以 iOS 18+ 的環境為目標，不承諾所有舊系統。

一般先用 **Xcode 模式**。**預裝 WDA** 是進階模式：新系統可能需要 RemoteXPC tunnel；iOS 27 的 `devicectl` 備援限制與此啟動途徑相關。工具不會自動執行 sudo 或調整全機 Xcode 選擇。需要 tunnel 時請依 Appium 文件處理，勿將此選項當成首次設定捷徑。

**連接已啟動 WDA** 模式要求 WDA 正在跑 XCTest session，且本機 URL 可到達。實機需要正確 USB port forwarding；預設 `8105` 是本工具的一般本機埠，不代表 Xcode 手動啟動的 WDA 自動轉發到此埠。可自行轉發後填入正確 URL。

## 開發與驗證

```bash
cd <專案目錄>/ios-wda
npm run setup
npm run doctor
npm test
npm exec playwright test
```

手動分開啟動服務：

```bash
npm run appium  # Terminal 1，127.0.0.1:4725
npm start       # Terminal 2，127.0.0.1:4780
```

測試架構：`fixture/Fixture.swift` 是完全離線的獨立 iOS App，模擬底部抽選按鈕、加好友、已領取、已結束、驗證碼與慢速頁面；不安裝或登入 LINE。`scripts/test-simulator.mjs` 只接受名為 `LineDraw_WDA_Lab` 的模擬器，其 UDID 放在 `.runtime/simulator-udid`。**禁止將這套腳本改指向個人手機來代替實機驗收。**

```bash
bash scripts/build-fixture.sh
node scripts/prepare-simulator.mjs  # 需先安裝 iOS 26.2 runtime；只建立／使用專用模擬器
# 另個 Terminal 先執行 npm run appium，再執行：
node scripts/test-simulator.mjs
```

控制面板瀏覽器測試用獨立的 headless Chrome，不讀取你的既有瀏覽器設定檔。WDA 模擬器通過不代表 LINE 實機通過，詳見 `VALIDATION.md`。

## 資料位置

- `src/`：Appium client、畫面規則、執行佇列、記錄、本機 HTTP 服務。
- `public/`：液態玻璃風格 Mac 控制面板。
- `native/Recognize.swift`：Apple Vision 中文／英文 OCR。
- `.data/state.json`：裝置設定檔範圍的抽選紀錄與清單。
- `.data/diagnostics/`：使用者明確擷取的原始截圖與 XML；可能含個資，分享前先檢查。
- `.runtime/appium.log`：Appium 的本機診斷日誌；底層錯誤可能包含装置資訊，分享前檢查。
- `.runtime/appium/node_modules/appium-xcuitest-driver/node_modules/appium-webdriveragent/WebDriverAgent.xcodeproj`：此次上游 WDA Xcode 專案；`npm run open:wda` 會自動找到。

本機控制服務只監聽 `127.0.0.1`；拒絕外部 Origin／Host，寫入 API 需要本次啟動的 token。不要把 Appium/WDA port 開到外網。

## 技術依據

- [Appium 維護的 WebDriverAgent](https://github.com/appium/WebDriverAgent)
- [XCUITest execute methods：deepLink、activeAppInfo 等](https://appium.github.io/appium-xcuitest-driver/latest/reference/execute-methods/)
- [WDA 簽署與啟動](https://appium.github.io/appium-xcuitest-driver/latest/guides/run-preinstalled-wda/)
- [RemoteXPC tunnels](https://appium.github.io/appium-xcuitest-driver/latest/guides/remotexpc-tunnels-real-devices/)
