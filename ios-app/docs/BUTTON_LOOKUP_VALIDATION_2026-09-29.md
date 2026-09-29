# LineDraw iOS 1.1.0 build 12 驗證報告

日期：2026-09-29。使用者先要求只改程式碼，後續明確允許「開始測試」，並補充本輪新五筆連結與 10/31 23:59 的截止時間。

## 結果摘要

- Core：77 項通過，0 失敗。
- 最新 Debug 簽署建置與 Release 未簽署建置通過；Debug build 12 安裝至指定 iPhone。
- 新五筆真實抽選：5 次開網址、5 次抽選點擊成功回應，5 筆 SUBMITTED，整輪含啟動約 42.10 秒；未等待中獎結果。這組數字是在加入自動成本比較前的 build 12 收集，不能當作最終策略的同條件速度比較。
- 最終成本比較策略：新五筆已抽頁面唯讀回查 5/5，35.58 秒；4 筆 ALREADY、1 筆 COMPLETE。這是內部狀態分類，不能單憑分類推算得獎數。查詢模式回報 `full:measured-faster`，確認可自動轉回較快的完整辨識。
- 舊 15 筆參加紀錄逐筆保持一致；本輪新增 5 筆後共 20 筆。所有後續唯讀／fixture 測試後，資料庫與抽選剛完成時完全一致。內建舊測試活動封存，新五筆保持使用者提供的順序。
- 強制底部 OCR 的本機測試 5/5 通過，每筆只確認一次；佇列 64.03 秒。長逾時與 OCR 合併壓力測試被 iOS 結束背景工作，不能標示為全部通過。

## 測試環境與證據界線

macOS 27、Xcode 27.0；iPhone 18 Pro Max（iPhone19,7），iOS 27.0。手機透過 LocalDevVPN 使用既有配對與手機端 WDA。Mac 以 USB 安裝、啟動測試及讀取報告；抽選流程由手機 App 執行。本輪不是首次配對／重開機後完全拔線驗證，也不外推所有機型。

多尺寸／橫向的幾何、狀態規則已有 Core 案例；其他實機、顯示縮放與大字體的 LINE 相容性仍未驗證。沒有重抽或刪除既有紀錄。

## 性能結論

直接元素查詢在此實機上沒有證明比完整 XML 快。初次本機 Safari 五筆雖成功，但耗時 52.09 秒；較早 build 9 的同類 fixture 是 43.50 秒，條件並非同時控制，不能當成嚴格 A/B。

實機測試發現：

1. 查詢全部按鈕會觸碰優惠券背後聊天室的失效 `voiceButton`；改為已知操作、結果、阻擋文字與 App／Alert 節點。
2. 關閉優惠券時可能短暫出現 SpringBoard；現在持續等候，不能將其當作已關閉或立即判成錯誤。
3. 查詢條件過廣、回傳元素逐筆解析也會增加耗時。採用具體文字條件，並加入每輪成本比較；直接查詢較慢時停用該路徑。

中間版本舊五筆換頁 37.11 秒，較寬的文字預篩選版本新五筆 39.79 秒；最終策略新五筆 35.58 秒。活動與起始頁面不同、網路與系統時序有差異，以上僅作診斷，不宣稱提升百分比。build 11 的 30.64 秒也是唯讀導覽，不能與新五筆真實送出的 42.10 秒直接相比。

## 新五筆活動

| 順序 | 使用者提供的網址 |
|---|---|
| 1 | https://lin.ee/XrzIhlc |
| 2 | https://lin.ee/nM6W6PMb |
| 3 | https://lin.ee/w68FqJz |
| 4 | https://lin.ee/OrL4Wzf |
| 5 | https://lin.ee/vQOsuLS |

全部以 HTTP 301 解析至同一 LIFF app 的不同優惠券 ID。截止時間由使用者確認為台北時間 2026/10/31 23:59；程式使用 2026/11/01 00:00 排他上限。資料遷移涵蓋前兩組內建五筆，不覆蓋使用者自行匯入的清單。

## 私人驗證檔案

保留於 `ios-app/.runtime/`，不放入公開原始碼壓縮包：

- `build12-core-ocr-final.log`、`build12-phone-ocr-final.log`、`build12-release-final-verified.log`
- `build12-speed-normal-final.json`、`build12-wda-error.json`
- `build12-real-final.json`
- `build12-navigation-corrected-final.json`、`build12-navigation-light-query-final.json`、`build12-navigation-adaptive-final.json`
- `build12-state-before.json`、`build12-state-after-real.json`、`build12-state-final.json`
- `build12-ocr-normal-final.json`、`build12-ocr-timeout-final.json`、`build12-ocr-timeout-resumed.json`、`build12-cancel-final.json`
- `build12-final-processes-before.json`

`wdaTimings` 是 HTTP 往返時間；`phaseTimings` 可包含其他階段，不能直接全部相加。真實抽選紀錄的 SUBMITTED 代表點擊已確認回應，不代表中獎或伺服器交易保證。

## OCR 實機發現與修正

強制本機 fixture 只用 OCR 時，Vision 對正確的「抽選」回傳信心分數 0.5，舊 0.9 門檻會排除它。現在只在原生元素已確認優惠券標題、辨識文字完全符合已知操作／結果時接受至少 0.5 的分數；未知文字維持 0.9，低分且無優惠券脈絡不接受。底部範圍、兩次穩定觀察、送出前重新 OCR 與禁止兌換的分類仍保留。此調整依據私人 fixture 的文字／座標記錄，不代表任意 OCR 低分皆可點擊。


## 長逾時與背景工作中斷

最終 OCR 修正後，注入一次約 18 秒的 GET source 逾時：第二次唯讀請求成功，也正確辨識出抽選操作。但在點擊前的新畫面讀取期間，背景工作被 iOS 結束，Runner 退出；報告暫停更新，回到 LineDraw 後回報 `cancelled`／`BACKGROUND_TASK_ENDED`。fixture 沒收到任何點擊，未自動重送，隔離紀錄保留 REVIEW。

此輪 **不通過整批完成驗收**。已證明單次讀取逾時可以重試成功、取消後不重送；未證明長延遲疊加 OCR 時能維持全程背景執行。現有證據無法區分系統資源／進度限制與系統工作面板取消，不能宣稱確定根因。證據為 `build12-ocr-timeout-final.json`（停滯中）及 `build12-ocr-timeout-resumed.json`（回前景後）。這是測試頁壓力情境，沒有觸碰 LINE 或改動真實參加紀錄。


## 強制底部 OCR 驗收

移除測試頁的原生抽選標籤，使五頁都必須使用截圖底部 OCR。最終 build 12 通過 5/5，五個 fixture acknowledgement count 均為 1，15 次底部 OCR（含穩定性觀察及點擊前複查），沒有額外送出。佇列 64.03 秒、含啟動 66.77 秒。證據：`build12-ocr-normal-final.json`。

這證明底部裁切、邏輯座標轉換與低分精確文字的條件式接受可在這支實機完成操作；不是 LINE 原生辨識的速度量測，也不是對所有尺寸的實機保證。OCR 仍是後備路徑。


## 取消與收尾

使用 `--fixture-cancel-read`，在首筆換頁後讀取畫面時呼叫 App 的停止處理。4.80 秒內記錄 `cancelled`／`appStop`，fixture acknowledgement 為空，沒有 POST wda/tap；符合取消預期。證據：`build12-cancel-final.json`。

最後以沒有測試參數的一般方式開啟 LineDraw；程序清單只有 LineDraw 主程式，沒有 DeviceRunner／WebDriverAgent Runner，不需要由 Mac 強制終止 Runner。讀回最終 state，與真實五筆剛抽完時所有頂層欄位完全一致，20 筆紀錄均保存。正常版不會因開啟 App 自動抽選。

## 尚未通過或尚未驗證

- 長逾時疊加 OCR 的整批完成：本輪被背景工作結束，需另行查明並改善；不能宣稱慢網路的所有路徑皆已通過。
- 最終策略相對 build 11 的同條件真實新活動速度比較：沒有可重複的未抽活動基準，不宣稱已加速。
- 其他尺寸實機、顯示縮放、大字體、重新配對與重開機拔線：本輪未重做。
