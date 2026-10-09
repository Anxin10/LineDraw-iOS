# 原生查詢整合 — 1.1.5 (28)

設定 → 漏抽掃描查詢，可選 XML 相容模式、原生 JSON 或精簡查詢。XML 維持預設。三種路徑只用於唯讀「檢查漏抽」，實際抽選批次的點擊流程維持原有驗證。

## 原生 JSON

使用 WDA `GET /session/:id/source?format=json`，排除 focused、重複 frame、nativeFrame、nativeAccessibilityElement、traits、minValue、maxValue、placeholderValue。保留可見性、enabled、accessible 及 rect；舊 LINE WebView 隱藏包裝節點仍需 accessible 資訊判斷。回應識別為 `GET source.json`，不沿用 XML 字串型別檢查。

JSONScreenParser 保留 8 MB、20,000 節點、64 層、每文字 65,536 bytes 上限，檢查座標有限值與非負尺寸。缺少狀態不會讓按鈕變成可點擊；父節點隱藏時不接受其一般子節點。支援既有 WebView 空包裝例外。

## 精簡 Runner

`scripts/patch-runner-observe.py` 修改專案複本的 WDA；prepare/build 腳本均接上 patch。新增唯讀 `GET /session/:id/linedraw/observe?expected_bundle=jp.naver.line`。

- 僅 `LINEDRAW_LOCAL_ONLY` 開啟時可用；目標限 LINE 及 Safari 離線測試。
- 取得前景身分，與請求目標不符時回傳 ready=false；只對已確認目標取得一次標準原生快照。
- 保留有文字、Alert 或 WebView 且有有效矩形的節點，針對保留節點檢查可見性。回傳文字、type、rect、visible、enabled，省去 XML、整棵 JSON 樹的額外屬性與容器。
- 再確認前景身分未變；schema=1，輸出 tree 供相同 JSON 解析器使用。讀取超過 20,000 節點、64 層、4,096 輸出節點或每文字 65,536 bytes 時拒絕。
- 不快取跨頁觀察、不傳截圖、不提供點擊端點。仍需原生 XCTest 快照，不能只憑回傳變小就宣稱速度提升。
- 舊 Runner 404 時本工作階段停用精簡端點並回退 XML；格式異常或可重試讀取失敗回退既有查詢。連線逾時維持停止，不疊加請求。

## 驗證與限制

App、Runner 均編譯通過，核心 JSON 解析、回應型別、舊設定相容性及原有批次測試通過。Runner 已安裝至已連接 iPhone 17 Pro。

實機重試已完成：同一組台中中友店五筆，精簡端點兩輪分別 8.91、9.25 秒，十次觀察均為 COMPLETE、沒有待確認。單筆範圍 1.416–2.301 秒；端點共 12、13 次查詢，合計 7.223、7.237 秒。相較 XML 14.91 秒約縮短 38–40%，但 XML 基線包含一筆待確認，測量亦非同時進行。相較原元素優先 26.23 秒約縮短 65–66%。

這些時間不含 Runner 啟動，僅為唯讀「開頁＋辨識」，不是實際參加抽獎的完整輪次。首筆需 4–5 次觀察，其餘各 2 次，包含頁面切換中的未就緒畫面；尚未驗證可參加／中獎彈窗等其他狀態。前後資料庫參加紀錄相同。報表：`.runtime/compact-native-scan.json`、`.runtime/compact-native-scan-repeat.json`。

原生 JSON 對照首次因 Runner 工作階段啟動失敗而未開始；重試在第一筆取得 14 次 JSON 畫面後，下一次查詢逾時停止，沒有產生完整辨識結果。不能將其當成成功速度或判定 JSON 比較快。報表：`.runtime/native-json-scan.json`。目前建議已安裝新版 Runner 的手機選「精簡查詢」；XML 保留相容預設，JSON 尚待診斷。

使用者在手機回到 LineDraw、保持解鎖及 LocalDevVPN 連線後，可在設定選擇模式，再從「檢查漏抽」啟動。開發測速可用 `--missed-scan --scan-json` 或 `--missed-scan --scan-compact`；均限定前五筆且不送出抽獎。

## 完整批次測試

Debug 明確啟動參數 `--batch-compact` 將正常批次 snapshot 換成精簡觀察，保留正常 DeviceNavigationGuard、穩定觀察、點擊前檢查、操作意圖保存及回應不明防重送；不使用唯讀掃描的 SKU/店家捷徑。正常啟動及 Release 點擊路徑保持既有元素查詢。

手機 Safari 離線五筆完整流程通過：13.45 秒，單筆 2.557、2.059、2.696、3.255、2.874 秒；每筆 HTTP ack 一次，五筆均 SUBMITTED。第四筆超過 3 秒，且此 fixture 使用記憶體紀錄及本機網頁，不能代表 LINE 或本機資料庫保存速度。點擊驗證與送出各筆約 0.825–1.329 秒。報表 `.runtime/full-compact-fixture.json`。

經使用者授權任選未參加活動後，用 `--real-speed-batch --batch-compact` 啟動最多五筆、停用自動接續；依正常 runnable 篩選及參加紀錄防重送。真實測試第一筆（新竹巨城 CX-16）未點擊，30.28 秒後 LOAD_TIMEOUT；進度位置到 1/5，但仍在「需要登入、驗證或其他人工處理」暫停，第二筆尚未開頁。第一筆僅查詢三次、共 1.65 秒，其餘主要在等待人工處理；不是 30 秒連續查詢。已停止測試並保存報表，未取得真實送出耗時。前後資料庫只新增一筆 LOAD_TIMEOUT，沒有 SUBMITTED 或操作意圖紀錄；阻擋原因尚待確認。報表 `.runtime/real-speed-compact.json`。

### 誤判修正後實測

唯讀複查 `.runtime/compact-blocker-review.json` 找到阻擋文字為店家兌換說明「不得以…電腦版登入…進行兌換購買」。分類器原本對全畫面登入字串做子字串匹配，誤判正常抽獎頁。修正只在 StaticText 且同時包含「不得」、「兌換」時移除「電腦版登入」片語後再檢查其他阻擋字；同節點或其他節點真正的登入、驗證碼、付款仍阻擋。回歸及全套核心 137 項測試（3 略過、0 失敗），App 編譯通過，修正版已安裝。

重試同五筆，全部 SUBMITTED：CX-16、UX-13、UX-01、UX-16、CX-17（Fun Box 新竹巨城）。報表 `.runtime/real-speed-compact-fixed.json`；前後資料庫核對五筆完成紀錄，未自動接續更多活動。

| 項目 | 開頁 | 查詢 | 點擊驗證＋送出 | 保存 | 總計 | 查詢次數 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| CX-16 | 0.11 | 2.31 | 0.95 | 0.59 | 4.51 | 5 |
| UX-13 | 0.34 | 1.72 | 0.90 | 0.50 | 3.88 | 3 |
| UX-01 | 0.30 | 1.64 | 0.88 | 0.57 | 3.83 | 3 |
| UX-16 | 0.29 | 7.40 | 0.82 | 0.45 | 11.68 | 22 |
| CX-17 | 0.28 | 1.57 | 0.88 | 0.50 | 3.61 | 3 |

秒數不含 Runner 啟動；單筆其餘時間包含穩定等待、網路檢查及進度回呼，分項不能簡單相加視為總計。單筆總計合計 27.51 秒，報表 elapsed 29.50 秒包含啟動。五筆重用新鮮原生觀察進行點擊，沒有再讀一次元素；指令回應到下一網址四次合計 1.77 秒，其中包含完成紀錄保存與批次回呼。第四筆查詢 22 次，需更多逐次就緒證據才能分清 LINE 載入或畫面穩定性，不能斷言為固定等待。此輪不等待中獎結果；SUBMITTED 表示點擊指令成功回應，不等於已中獎或伺服器結果已驗證。每筆 3 秒目標尚未達成。
