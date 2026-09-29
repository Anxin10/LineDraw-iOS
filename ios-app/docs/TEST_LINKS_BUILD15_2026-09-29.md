# LineDraw iOS 1.1.0 build 15：五筆測試清單更新

依使用者指定順序更新，截止時間經確認維持台北時間 2026/10/31 23:59。程式使用 2026/11/01 00:00（UTC+08:00）排他上限，保留最後一分鐘。起始日沿用測試區的 2026/09/29。

| 順序 | 短網址 | LIFF 優惠券 ID |
|---|---|---|
| 1 | https://lin.ee/Qd5hJVq | 01M3PFR9C1EN49S8949WFHDPGA |
| 2 | https://lin.ee/QGhOsnX | 01M3PFRTX70E47T6BY81FAZZSR |
| 3 | https://lin.ee/XnMZVTX | 01M3PFSB92G86W4Y7KWR01DNQZ |
| 4 | https://lin.ee/W0zn6z4 | 01M3PFSRSA9210CX5B1VA6PH1T |
| 5 | https://lin.ee/yz7xFEWc | 01M3PFT6EBNAC6XZ8J4BCBHKNX |

五筆均以唯讀 HTTP HEAD 收到 301 Location，導向 `https://liff.line.me/1654883387-DxN9w07M/c/`，活動 ID 互不相同。僅驗證公開導向，沒有登入 LINE 或送出抽選；期限依使用者確認設定。

## 變更

- 更新 `TestCatalog.five()`；App 與即時動態 extension 的 build 同步為 15。
- 上一組 build 13／14 的五個 ID 加入既有清單遷移。舊活動封存、所有參加紀錄保留；自訂匯入清單與網站資料不取代。
- 抽選引擎、手機配對、DDI 與 VPN 沿用 build 14；本次僅更新清單。
- 使用者要自行手動測試。本輪不使用自動化啟動參數、不啟動 Runner、不執行新五筆抽選。

## 驗證

- Core 93 項測試通過，包含精確網址順序、四組舊內建清單遷移、紀錄保留、自訂清單保護與台北截止時間邊界。
- Debug 簽署建置與 Release 未簽署建置通過。
- build 15 已安裝到指定 iPhone，僅以一般模式開啟。讀回 App 資料確認新五筆順序、LIFF 對應與截止時間正確，上一組五筆已封存。
- 原有 25 筆參加紀錄逐筆一致；舊活動除本次封存旗標外不變，網站清單內容與設定完整保留；總活動數 919 → 924。新五筆均尚無參加紀錄。建置期間 App 另於台北 19:49:58 完成一次一般同步（893 筆、新增 0、封存 0），因此 lastSync、syncSummary 與新增一筆 SYNC 診斷有正常變動；這些變動保留，未覆蓋。
- 確認 DeviceRunner 程序為 0；沒有執行這五筆抽選，保留給使用者手動測試。

私人證據存於 `ios-app/.runtime/`：`build15-new-links.json`、`build15-core.log`、`build15-phone.log`、`build15-release.log`、`build15-install.log`、`build15-state-before.json`、`build15-state-after.json`。不放入來源 ZIP。
