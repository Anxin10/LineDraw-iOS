# build 8／9：速度驗證的畫面讀取逾時

日期：2026-09-29，LineDraw 1.1.0 build 8／9。

## 問題與證據

使用者已在手機重新開機後完成「檢查啟動」，確認新手機配對可沿用並啟動 WDA。讀回的最新啟動檢查為台北時間 11:03:03，`passed=true`。

速度驗證失敗紀錄（11:02:29）顯示：DDI 載入、完整下載驗證、Runner 啟動、建立 WDA session、開啟第一個 Safari 測試網址都完成；接著 `GET source` 畫面結構查詢超過原本的請求逾時。尚未點擊任何測試按鈕，`completed=0`、操作確認清單為空。這不是配對失敗或 DDI 下載失敗。

同一 build 6 再跑一次，5／5 通過，每筆確認一次，佇列 21.79 秒。這證明問題具偶發性；不能只因第二次成功就視為已修復。冷啟動／切換畫面時的 AX 查詢延遲是目前工程判斷，不宣稱已取得 Apple 內部停頓原因。

## 最終修改

- 只對 `GET /session/{id}/source` 增加容錯：第一個請求設定 18 秒，僅在 URLSession 回報 timed out 時重查一次，第二次設定 12 秒。取消、連線中斷、其他錯誤不自動重試。
- POST 點擊、開網址、建立 session、更新設定，以及其他查詢不由此機制重送。點擊回應不明仍記錄 REVIEW 並停止。
- 不加入每筆固定等待或 WDA 動畫等待；正常查詢一回應就繼續。請求時間設定是 URLSession 的 timeout，並非保證所有系統排程都精確在同一秒返回。
- 批次在畫面查詢回來後重新檢查該筆 30 秒載入期限；晚到的畫面不會授權點擊，沿用原本重開一次／略過的流程。
- 速度驗證使用正常的 DDI 快取／隨附／必要時下載流程，移除每次測速都強制另下載一套約 17 MB DDI 的行為。DDI 下載能力、固定雜湊與原子安裝保留。
- 報告增加測試階段、每次請求種類、耗時、錯誤碼與嘗試次數。無 session ID、URL、PIN、畫面文字、聊天或配對私鑰。
- Debug 增加 `--cold-fixture`，只能在 Safari + 127.0.0.1 測試情境重新啟動 Safari 程序，不刪除分頁資料、不指定 LINE。這是 App 程序冷啟動，不能當成整支手機重新開機。

曾評估 WDA 的短動畫穩定等待，但測試增加了後續畫面查詢耗時（五筆約 35～36 秒）；最終已移除，保留限定的唯讀查詢容錯。

## 驗證

- 最終 Core 49 項通過：新增畫面逾時後恢復、持續逾時只重試一次、POST（含 session 建立）不重送、其他錯誤不重試、取消阻止重試、取消後丟棄晚到的成功回應，以及超過載入期限的第二次畫面不能觸發點擊。
- 原生 UI 6 項在本輪中間 build 7 通過；build 8 只移除畫面穩定等待，沒有更動 UI。沒有把該結果標成 build 8 重新跑過。
- Debug 實機簽署與 Release 無簽章建置通過；手機配對／Runner 簽章與資料保留。
- 本輪只使用 Safari 本機假優惠券，沒有操作任何真實 LINE 抽選。未抽過的真實活動仍待使用者提供，不能把本機測速當成 LINE 送出速度。

### 實機結果與待驗收項目

| 版本／操作 | 已讀回的結果 | 證據限制 |
|---|---|---|
| build 6 原版重跑 | 五筆 21.79 秒，5／5 通過，每筆確認一次 | 原版曾逾時，重跑成功不能當修復證明 |
| build 7 中間版，重新啟動 Safari 後測試 | 五筆 36.34 秒，5／5 通過，每筆確認一次 | 動畫穩定等待版本，已移除該等待 |
| build 7 中間版，Safari 已啟動 | 五筆 35.09 秒，5／5 通過，每筆確認一次 | 同上，不是最終版效能 |
| build 8 初次啟動 | 在 Runner 啟動階段失敗，沒有進入佇列 | 與原本 GET source 逾時不同；原因未定位，不能因後續恢復就宣稱已修復 |
| build 8 再執行啟動檢查 | 台北時間 11:22:27，`passed=true` | 沒有重新配對或更換 Runner；不等於速度驗證通過 |
| build 8 再次測速 | 啟動 3.08 秒後進入 `runningQueue` | 使用者拔線離開，最後一次已複製紀錄仍為執行中；未讀回最終結果 |

build 8 已在使用者離開前安裝。依使用者指示停止 Mac 與手機通訊，後續僅完成本機程式檢查、測試與來源包；不繼續遠端連線手機。實機尚未觀察到「第一次查詢逾時、第二次成功」的完整復原，本輪容錯證據是單元測試注入逾時。

手機接回後：

1. 先讀回保留的 `device-speed.json`，核對版本、時間與最終狀態，避免先重跑覆蓋證據。
2. 開啟正常 App，執行啟動檢查；若 Runner 啟動錯誤再現，獨立診斷，不自動重新配對或反覆啟動。
3. 分別驗證 Safari 重新啟動及已啟動時的五筆測試；要求 5／5、每筆確認恰好一次，檢查每次請求耗時與重試次數。
4. 驗證停止能中止查詢／重試，結束後 Runner 正常關閉，最後以不含測試參數的方式開啟 App。
5. 拔線後由使用者從手機操作，再確認自主執行。真實 LINE 新抽選仍需尚未抽過的有效連結。

原始證據保留在 `.runtime/`，不進入來源 ZIP：`device-speed-timeout-user.json`、`device-check-after-reboot-user.json`、`device-speed-build6-reproduce.json`、`device-speed-build7-cold.json`、`device-speed-build7-warm.json`、`device-speed-build8-cold.json`、`device-check-build8.json`、`device-speed-build8-cold-retry.json`，及 `speed-timeout-build8-*` 建置／測試紀錄。

主要來源：`Core/Sources/LineDrawCore/WDARequestExecutor.swift`、`DeviceBatch.swift`、`App/LocalWDA.swift`、`App/AppModel.swift`。Android、網站、Rust 配對協定與 DeviceRunner 程式碼未修改。


## 手機接回後的驗證與 build 9

接回時，上次 `device-speed.json` 仍為 11:22 的 `runningQueue`；沒有可補認定的完成結果。重跑時先有兩次在 Runner 啟動期間取消；使用者確認沒有授權提示、手機已解鎖且 VPN 已連線。build 8 當時未保存取消來源，不能斷言是使用者取消、背景工作逾期或某個系統限制。

在僅記錄 LineDraw 相關系統日誌的檢查中，12:44:51 啟動檢查通過，未重新配對。接著 build 8 的 Safari 重新啟動測試為 40.33 秒、已開啟測試為 39.40 秒，兩輪皆 5／5、每筆確認一次。這兩輪沒有畫面查詢逾時；不能把它們當成逾時復原證據，也不能宣稱比先前 21.79 秒快。

build 9 追加：

- 保留 build 8 的唯讀查詢重試規則，不重送操作。
- 區分 App 內停止、iOS 背景工作結束、其他工作取消。背景工作 API 不提供足夠資訊，無法再區分系統自動結束與使用者在系統工作進度按取消；介面如實說明。
- 背景結束回呼只接受目前這個工作，過期工作的回呼不會取消下一個工作。
- Debug 速度報告新增 build、目前請求、Runner 階段碼、取消來源及故障注入標記；在階段及請求變化時保存，避免只有最後一刻才留下診斷。
- 兩種 Debug 故障注入只在明確 CLI 參數、Safari、127.0.0.1 測試頁、第一次導航後的唯讀 source 同時成立時啟用。`--fixture-timeout-once` 在送出查詢前等待 18 秒並注入 timedOut；`--fixture-cancel-read` 呼叫與 App 停止按鈕相同的函式。沒有 CLI 參數時均不啟用，Release 不包含這些測試入口。

最終 Core 49 項、Debug 實機簽署建置及 Release 無簽章建置通過。

| build 9 實機測試 | 結果 |
|---|---|
| 查詢途中停止（`cancelRead`） | 同一 App 停止函式生效；`cancellationSource=appStop`、0 筆完成、0 次 POST tap、無重試 |
| 一次逾時注入（`timeoutOnce`） | 第一次 source 等待 18.10 秒後回報 -1001，第二次 source 0.73 秒成功；5／5 通過、POST tap 五次、每筆確認一次；佇列 54.03 秒含注入等待 |
| 逾時測試結束後清理 | 實機程序清單已無 DeviceRunner |

上述逾時是 App 在指定唯讀操作前注入的錯誤，不是自然重現 WDA 或 URLSession 網路停頓。它驗證真實手機上的佇列、重試、期限、點擊去重與停止整合；原本自然逾時的底層原因仍未完全定位。

最後一輪 build 9 正常測試（`faultMode=none`、Safari 重新啟動）5／5 通過，啟動 3.14 秒、佇列 43.50 秒、POST tap 五次且每筆確認一次，沒有逾時或重試。這次最主要的耗時是 activeAppInfo（22 次／24.99 秒）和 source（17 次／12.39 秒）。尚未證明查詢瓶頸的底層成因，也未宣稱速度提升；不能以少數測試估計所有 LINE 活動耗時。

本輪沒有重新配對、沒有清除 App 或 Safari 資料、沒有操作真實 LINE 活動。build 9 的變更僅為 App／Core 容錯及診斷；Rust 配對、DeviceRunner、Android、網站未改。

本次接回原始證據：`.runtime/device-speed-build8-after-return.json`、`device-check-build8-reconnected.json`、`device-speed-build8-reconnected-cold.json`、`device-check-build8-with-syslog.json`、`device-speed-build8-reconnected-cold-usb.json`、`device-speed-build8-reconnected-warm.json`、`device-speed-build9-cancel.json`、`device-speed-build9-timeout-final.json`、`build9-after-timeout-processes.json`，以及 `build9-core.log`、`build9-phone.log`、`build9-release.log`。系統診斷與裝置識別資料只留在排除於發行範圍的 `.runtime`。

最終正常測試證據：`.runtime/device-speed-build9-normal-cold-final.json`。

最終正常測試結束後，實機程序清單確認 DeviceRunner 已退出（`.runtime/build9-final-processes.json`）；以不含任何測試參數的方式重新開啟 LineDraw。Mac 未保留 Appium、抽選控制台或系統日誌串流。
