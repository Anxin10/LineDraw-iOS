# XML 與雙來源整合

## 已實作
- Funbox／陀螺獵人來源切換，預設 Funbox，舊 snapshot 可直接載入。
- 各來源分開封存、同步時間與摘要；以 canonical activityKey 共用紀錄。
- 陀螺獵人只接受 draws envelope；合法空清單僅封存該來源。錯誤／重複 ID／不合法網址拒絕合併。
- 手機同步、自動續抓固定來源；共用既有 URL 解析快取。
- Mac 舊橋接的陀螺獵人批次可執行選取清單，但不啟用只支援 Funbox 的自動續抓。
- 每筆共用 30 秒 deadline；targeted／XML／OCR 次數上限 6／2／2。
- 跨導航觀測失效、單一在途請求、XML 資源限制、解析取消與過期結果拒絕。
- OCR 截圖錯誤向上傳遞，不吞掉取消／逾時。

## 驗證與限制
- Core 117 項測試，1 項略過，0 失敗。
- 公開 API 格式核對：stores／draws，586 筆（2026-10-08）。
- 保留底部 40% OCR；25% 裁切尚待實機驗證。
- 每輪 3 秒目標尚未實機驗證；30 秒是失敗上限，不是速度承諾。
- 本次未操作真實抽選；未完成單一 IPA 內整合 DeviceRunner。

## 啟動閃退修正
舊資料缺少 catalogSync 時，AppModel.catalogSummary 的 fallback 誤讀自身，導致堆疊溢位。已改為 Core 的 syncStatus(for:)，驗證初次啟動、舊資料及來源專屬摘要；118 項測試中 117 通過、1 略過。修正版 IPA 位於 exports/2026-10-08-summary-fix；原 exports/2026-10-08 版本不可再使用。
