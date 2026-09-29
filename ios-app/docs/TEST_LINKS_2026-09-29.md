# 五連結測試更新（build 10）

保留外部 LocalDevVPN，不加入 VPN extension。原生 iPhone App 的五連結測試區依使用者提供順序更新如下；Mac 輔助模式由 iPhone 傳入相同清單。獨立的舊版 Mac POC 控制台及 Android 本輪未修改。

| 順序 | 短網址 | 已驗證重新導向的優惠券 ID |
| --- | --- | --- |
| 1 | https://lin.ee/NW1ffdO | 01M3NR6Y99ART5N0WJ1XZVGZDP |
| 2 | https://lin.ee/o3EdJA8F | 01M3NR7CBXE30DDE4GGQB4QCGA |
| 3 | https://lin.ee/6WyOJMT | 01M3NR7QB9JFTEQAMAC38NZCA1 |
| 4 | https://lin.ee/PpGefet | 01M3NR81J75SFMQWHRKGHBJ1H0 |
| 5 | https://lin.ee/ynnssrz | 01M3NR8F5E3B3AR40SS9TM5SED |

2026/09/29 以唯讀 HTTP GET 驗證五個短網址的 301 回應，均指向 `https://liff.line.me/1654883387-DxN9w07M/c/<優惠券 ID>`。公開導流頁不提供抽選期限。使用者確認「到 10/31 日」；本次依目前可用處理，自更新日 2026/09/29 啟用，截止按台北時間 2026/10/31 23:59 設定，程式採 2026/11/01 00:00 排他邊界。啟用日期不宣稱是活動原始開放時間。

## 升級資料處理

- 首次啟動自動載入新五筆。
- 升級前若使用原內建五筆，第一次開啟新版自動替換；舊列封存，抽選紀錄、手動完成／撤銷資訊與待同步紀錄均保留。
- 已匯入自訂測試 JSON 的清單不自動覆寫；可在五連結測試區同步，明確改回新版內建清單。
- 網站清單與紀錄不變。新活動沿用優惠券 ID 作為辨識依據，舊五筆的紀錄不會阻擋新活動。
- 本次只更新清單與安裝 App，不送出抽選。

## 驗證

- Core：52 項測試通過。新增驗證涵蓋截止當天最後一分鐘、舊清單封存與紀錄保留、重新啟動後不重複遷移、自訂 JSON 不被覆蓋。
- Xcode 27 實機 Debug 簽署建置通過，build 10 已安裝並以正常模式開啟。
- 實機更新前後讀回 App 本機資料比對：五筆新網址順序正確、五筆原內建資料封存、五筆既有紀錄及所有手動撤銷／待同步資料不變、網站及示範清單不變。
- 本輪未啟動 WDA 或執行真實 LINE 抽選；以上不代表新五筆抽選已送出或已中獎。

本機驗證摘要：`../.runtime/build10-validation.json`；核心與建置日誌：`../.runtime/build10-core.log`、`../.runtime/build10-phone.log`。個人裝置資料與日誌不包含在來源 ZIP。
