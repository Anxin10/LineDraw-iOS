# 精簡決策查詢 — 1.1.6（29）

## 正式入口

設定 → 抽選畫面查詢 → 精簡決策查詢。已連接 iPhone 的本機設定已切換 compact，正常啟動可使用；沒有自動開始抽選。其他手機舊設定預設相容查詢。App 的 Debug 與 Release 都編譯通過，實機安裝為 Debug 1.1.6（29）；不是已簽署匯出的 Release IPA。

正式 DeviceBatch snapshot 使用此設定，透過新版 Runner 的 /linedraw/observe 取得精簡節點；保留 DeviceNavigationGuard、穩定觀察、點擊前檢查、原子意圖保存、成功回應紀錄與不明操作防重送。舊 Runner 缺少端點時回退既有查詢。唯讀漏抽掃描沒有 decision_filter，仍保留商品／店家文字，不沿用唯讀 SKU 捷徑授權點擊。

## Runner v3

1. 一次標準原生快照；只對与 Application 矩形相交的非結構文字檢查可見性。Alert、WebView 不做這個幾何略過，仍检查原生可見性；所有子節點仍遍歷，不因容器矩形而整支剪掉。
2. App 傳入與分類器相同的 observationLabels、blockers，標準化規則相同（相容字元正規化、移除空白、修剪指定末尾標點）。只對決策需要的 label/value 檢查可見性；Alert、WebView 永遠列為結構候選。登入等阻擋字採子字串匹配，未將一般未知頁面變為可點擊。
3. 篩選資料大小上限 8 KB、labels 最多 128、blockers 最多 32，每字串最多 1 KB，格式錯誤拒絕；原有 20,000 節點、64 層、4,096 輸出與文字上限保留。沒有跨頁快取或盲點擊。
4. 加入 snapshotSeconds、collectSeconds、visibilityChecks、geometrySkipped；App 逐次診斷保存於 nativeMetrics，nativeQuerySeconds 保留 Runner 整體時間。這些計時不含回應序列化與傳输；客戶端 querySeconds 包含請求與解析，差額不能全部當成網路時間。

`scripts/patch-runner-observe.py` 支援新樹、v1／v2 升級及重複執行不變；Runner build-for-testing 與簽章驗證通過。141 項核心測試、3 項略過、0 失敗，包含舊設定相容及 compact 設定持久保存。

## 實驗結果

本次四輪各五筆真實活動均 SUBMITTED，共 20 筆；另有五筆 Safari 離線流程，ack 各一次。沒有自動接續到其他活動；SUBMITTED 表示點擊指令成功回應，不代表中獎或伺服器結果已驗證。各輪為不同活動／時間，不能當成嚴格相同頁面的 A/B。

| 輪次 | 單筆完整秒數 | 合計 | 說明 |
| --- | --- | ---: | --- |
| v1 基線 | 2.866、2.822、3.334、3.245、3.023 | 15.29 | `.runtime/real-native-baseline.json` |
| v2 幾何略過＋原生分段計時 | 3.287、3.036、2.907、2.956、3.068 | 15.25 | `.runtime/real-compact-v2.json`；候選頁常需 35 或 115 次可見性檢查，collect 0.03–0.48 秒 |
| v3 決策篩選 | 3.024、2.701、2.800、2.723、2.706 | 13.95 | `.runtime/real-compact-v3.json`；候選觀察約 8 次檢查，collect 0.01–0.02 秒 |
| v3 正式設定（沒有 --batch-compact） | 3.188、2.971、3.206、2.784、5.976 | 18.13 | `.runtime/real-compact-setting.json`，build 29、lookupMode=batch:compact |

離線完整流程 8.57 秒／五筆，但使用本機頁面與記憶體紀錄，不能當作 LINE 速度。

正式設定最後一筆出現 20 次查詢，已能判讀原因：前 18 次 navigationPending/noActionOrResult（1–5 個輸出節點），第 19 次約活動開始後 4.53 秒出現 click:SUBMIT／firstCandidate，第 20 次 4.79 秒通過 stableCandidate，總計 5.98 秒。中間多數單次端到端查詢約 0.09–0.11 秒，快照約 0.05 秒、節點處理約 0.015 秒。此輪沒有人工暫停、不同文件或候選變化。

因此這筆剩餘長尾不是「20 次都各花很久」，而是原生觀察一直未辨識到操作／結果。尚未有同步截圖／LINE 內部資料，不能直接認定網路慢、畫面尚未載入或原生樹暴露延遲。兩輪 v3 共十筆有六筆低於 3 秒，每筆 3 秒仍未穩定達成。
