# 同步閃退修復

2026-10-07 手機系統報告 `LineDraw-2026-10-07-230946.ips`：EXC_BREAKPOINT / SIGTRAP。使用對應 Release dSYM 還原，堆疊為 `_NativeDictionary.merge(trappingOnDuplicates:)` → `AppModel.sync()`。

手機快照中已解析網址有兩組重複，每組兩筆。同步前使用 Dictionary(uniqueKeysWithValues:) 建立快取，遇到相同 URL 直接 trap，無法進入 catch 或產生 SYNC_FAILED 診斷。

修正：新增 CatalogResolutionCache，同 URL 同 canonical 合併；不同有效 canonical 視為衝突，整組不沿用快取，交給同步重新解析。無效或缺失 mapping 不覆蓋有效 mapping。手動同步及批次增量同步共用此規則，不刪除既有活動、封存資料或參加紀錄。

驗證：Core 106 tests，1 skipped、0 failures。新增重複歷史資料、衝突順序、無效／缺失 mapping 測試。Release archive 成功。真實網站同步完成仍須於手機按同步確認；單元測試不代替網路與整體流程驗證。
