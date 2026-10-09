# 個人 fork 與版本發佈

目標帳號：Anxin10；來源：beybladehunter/LineDraw-iOS。先確認自己的 fork 實際存在，登入後才執行發布。

1. 在 GitHub 登入 Anxin10，打開來源倉庫按 Fork，建立自己的 LineDraw-iOS。
2. 在 Mac 終端執行 `gh auth login --hostname github.com --web`，完成瀏覽器登入。用 `gh auth status` 核對登入帳號，勿把 token、密碼貼進文件或聊天室。
3. 將自己的 fork 作為新的 remote，保留 upstream 原倉庫。本機現有修改很多，先檢查內容，勿直接 `git add .` 把安裝產物與診斷一起提交。
4. 發布原始碼前，將生成的 Xcode 個人 Team 清空，移除 .runtime/BundledDDI 的資源引用；使用者依 README 重新產生專案。來源包不含 Apple DDI、憑證、配對檔、個人診斷、裝置識別碼與已簽署 IPA。
5. 提交已檢查的來源、安裝手冊與版本紀錄到自己的 fork。建立 `v1.1.8` GitHub Release，附公開來源 ZIP 與校驗碼，清楚標示最低 iOS 26.0、其他手機需自行簽署，以及尚未完成的實機驗證。
6. 個人簽署的 IPA 包留作私下安裝使用，預設不放公開 Release；描述檔內含註冊裝置資訊，且不是所有手機通用。若要對其他手機提供檔案，先為目標手機準備適用簽署，再檢查分享內容。

來源、授權與第三方聲明必須保留。PolyForm Noncommercial 1.0.0 是授權版本，不隨 App 1.1.8 改號。

GitHub 發佈只負責下載與版本管理，不會替 iPhone 註冊裝置、簽署或完成配對。安装請依 [新手機手冊](INSTALL_NEW_IPHONE.md)。
