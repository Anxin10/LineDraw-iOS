# LineDraw iOS 1.1.0 build 13：五筆測試清單更新

使用者提供新五筆連結，截止時間沿用台北時間 2026/10/31 23:59。依指定順序替換 App 內建測試清單；使用 2026/11/01 00:00（UTC+08:00）排他上限，保留截止日最後一分鐘。開放起日維持 2026/09/29。

| 順序 | 短網址 | LIFF 優惠券 ID |
|---|---|---|
| 1 | https://lin.ee/o2HccT8 | 01M3P1WYDKQCAEXNS2ZH6J1VMN |
| 2 | https://lin.ee/OTyB3Jk | 01M3P1XATPMQ2H6488HC8XVAQ4 |
| 3 | https://lin.ee/97hZCi0 | 01M3P1XMQAXHWFWDZQ8EVFJ6WQ |
| 4 | https://lin.ee/SES3j9s | 01M3P1Y0D3K8KJZWXXZ8NM8A0S |
| 5 | https://lin.ee/S4sB6XO | 01M3P1YEB564HSFGP2FT72RT3N |

五筆均以唯讀 HTTP HEAD 取得 301 Location，導向 `https://liff.line.me/1654883387-DxN9w07M/c/`，ID 互不相同。截止時間依使用者確認設定，未從 LINE 登入頁讀取。

## 變更範圍

- 更新 `TestCatalog.five()`，App build 與即時動態 extension 同步升至 13。
- 把 build 12 的內建五筆 ID 納入舊清單遷移：舊活動封存，所有參加紀錄保留。
- 精確識別前三組內建清單；使用者自行匯入的清單不取代，網站清單不受影響。
- 抽選引擎沿用 build 12；[該版驗證報告](BUTTON_LOOKUP_VALIDATION_2026-09-29.md)中長逾時疊加 OCR 的背景工作限制仍適用。

## 檢查

- Core 77 項測試通過，包含最新網址順序、前三組清單遷移、紀錄保存、自訂清單保護、台北截止時間邊界。
- Debug 簽署建置與 Release 未簽署建置通過。
- build 13 已安裝至指定 iPhone，並以一般模式開啟。讀回 App 資料確認五筆網址順序正確、上一組五筆封存；原有 20 筆紀錄逐筆一致，網站清單與所有其他頂層資料不變。
- 本輪只更新清單；未執行這五筆真實抽選。

私人驗證檔置於 `ios-app/.runtime/`：`build13-new-links.json`、`build13-core.log`、`build13-phone.log`、`build13-release.log`、`build13-install.log`、`build13-state-before.json`、`build13-state-after.json`。不納入原始碼壓縮包。
