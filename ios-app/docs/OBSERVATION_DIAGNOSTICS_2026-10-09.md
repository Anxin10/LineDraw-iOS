# 完整抽選逐次查詢診斷

## 紀錄內容與判讀

DeviceBatch 每次成功或失敗查詢都留下有上限的結構化資料，最多保留最近 2,000 筆；不保存全頁文字、截圖或優惠券網址。每筆包含活動佇列位置、查詢序號、活動開始後秒數、本次查詢耗時、前景 bundle、查詢模式、決策、換頁驗證原因、是否仍待確認、是否與舊頁相同、決策穩定次數、節點與可用按鈕數、候選按鈕矩形。buttonCount 是所有 enabled Button，不代表全部為抽選按鈕；只有 click:SUBMIT 等決策與 targetRect 表示已辨識候選目標。

| reason / navigationReason | 可證明的狀態 |
| --- | --- |
| foreignForeground / foreignForeground | 前景尚未到 LINE，不算人工暫停 |
| navigationPending / noActionOrResult | 本次畫面未辨識出可操作目標或終止結果；不能單憑此證明網路載入慢 |
| navigationPending / firstCandidate | 已辨識按鈕或結果，但尚待第二次穩定觀察 |
| navigationPending / candidateChanged | 候選文字、類型、矩形或狀態改變，換頁穩定確認重新開始 |
| navigationPending / settleWindow | 候選吻合，但尚未滿足最小確認時間 |
| navigationPending / differentDocument | WebView 明確提供不同活動網址，拒絕操作 |
| decisionStability | 換頁條件通過後，決策自身仍待穩定確認 |
| manualPause | LINE 中的登入、驗證、對話框等觸發人工處理 |
| tapCandidateAccepted / stableCandidate 或 matchingDocument | 正常換頁檢查通過，準備保存意圖並驗證點擊；尚不等於送出成功 |
| tapNotDispatched | 點擊前重新檢查失敗；已回復原紀錄，沒有授權重送不明操作 |
| queryFailed、deadlineAfterQuery、cancelledAfterQuery | 查詢失敗、查詢完成後已超時或取消 |

DeviceItemTiming 新增 manualWait：單獨計算 gate 中的人工暫停時間。每次查詢不写資料庫，批次结束時一次寫 Documents/device-observations.json，診斷畫面保存最近 20 項 DEVICE_OBSERVATION_SUMMARY。Debug 授權測速報表 real-speed-batch.json 也包含 observations，在既有進度回呼時更新；不額外逐次 publish。一般暫停期間記憶體仍持有資料，普通流程檔案需批次返回後更新；非正常閃退可能無法匯出最後資料。

## 真實驗證

139 項核心測試，3 項略過、0 失敗；App 編譯成功。使用者授權剩餘活動作實驗，本轮仅選五筆未被完成紀錄阻擋的活動、關閉自動接續。

新竹巨城 CX-00、CX-01、CX-02、UX-17、UX-19 均保存 SUBMITTED；單筆時間依序 4.146、3.538、3.540、3.621、3.529 秒，合計 18.375 秒，不含 Runner 啟動。SUBMITTED 只代表指令成功回應，不代表中獎或已驗證伺服器結果。

第一筆 6 次查詢：1 次外部前景、3 次尚無可辨識操作／結果、1 次首次候選、1 次穩定候選。此次實測版本將外部前景的 pause 決策標為 manualPause，但沒有進入人工暫停（manualWait=0）；隨後修正診斷標籤為 foreignForeground，不修改控制流程，原始報表保留以供核對。

其餘四筆每筆 3 次：noActionOrResult → firstCandidate → stableCandidate，沒有 candidateChanged、differentDocument、queryFailed 或 tapNotDispatched。每筆人工等待均 0，點擊驗證重用最近原生觀察，沒有額外查畫面。

第二筆示例：第 1 次 1.128 秒、3 節點，尚無可識別操作；第 2 次 0.183 秒、33 節點，找到 SUBMIT，矩形 (0,784,402,91)，但等待換頁確認；第 3 次 0.270 秒、相同矩形，換頁確認通過並接受候選。實測資料現在足以分開「尚無可辨識內容」與「按鈕已有但等待穩定」，仍無法僅憑節點證明 LINE 內部網路、渲染或動畫的耗時。

報表 `.runtime/real-observation-trace.json`，前後資料庫核對新增五筆 SUBMITTED，未接續更多活動。先前 UX-16 的 22 次查詢發生於逐次診斷加入前，不能事後補造原因；之後若再次出現長尾，將依當次 trace 判讀，不再僅以總次數猜測。
