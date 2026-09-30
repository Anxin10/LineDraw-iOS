# 建置索引與開發者驗證

**從零開始請依 [README 完整教學](../README.md#requirements)。** Xcode 下載、工具安裝、自己的 Bundle ID、簽署、App／Runner 安裝、LocalDevVPN 與手機配對都集中在 README，避免兩份步驟不同步。

| 工作 | 說明 |
|---|---|
| 安裝 Xcode 與依賴 | [Xcode](../README.md#xcode)、[建置工具](../README.md#tools) |
| 免費 Apple Account、手機信任與開發者模式 | [準備 iPhone](../README.md#apple-account) |
| 個人簽署識別碼 | [App／Runner／背景工作一起設定](../README.md#identifiers) |
| Rust bridge、Xcode 專案與 App | [編譯並安裝 LineDraw](../README.md#build-app) |
| WDA DeviceRunner | [獨立建置、簽署與安裝](../README.md#build-runner) |
| 手機自行配對 | [LocalDevVPN](../README.md#localdevvpn)、[PIN 配對](../README.md#phone-pairing) |
| 更新與續簽 | [保留識別碼、備份產物及覆蓋安裝](../README.md#maintenance) |

## 本機邏輯測試

在倉庫根目錄執行；這些測試不連接個人手機，也不執行 LINE 抽選：

```sh
swift test --package-path ios-app/Core
cd ios-wda
npm ci --ignore-scripts --no-fund --no-audit
npm test
```

2026/09/29 公開來源整理時，Swift Core 93 項、Node 63 項通過。這是該版的歷史結果，不代表本文件每次更新都重新跑過程式測試。

## 模擬器建置

先依 README 建置 bridge 並產生專案，再於 `ios-app` 執行：

```sh
xcodebuild -project LineDraw.xcodeproj -scheme LineDraw \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .runtime/DerivedData CODE_SIGNING_ALLOWED=NO build
```

此 bridge 只包含 arm64 iPhone 與 Apple Silicon 模擬器。模擬器可驗證離線示範與 UI，不能證明真實 LINE 相容性。

Rust、UI、WDA fixture 與實機驗收分別記錄於 [App README](../ios-app/README.md) 與 [Mac 驗證紀錄](../ios-wda/VALIDATION.md)。不要將 fixture 腳本改指向個人實機。

## 本機檔案

- `.runtime/LineDrawDeviceBridge.xcframework`、RunnerSource、Runner 建置與簽署產物、DDI 均為本機生成內容，不納入 Git。
- `generate-project.rb` 重新產生專案後，要重新檢查 Signing Team；個人 Bundle ID 應先設定在來源與產生器，不能只改生成的 Xcode 專案。
- 已生成的 DeviceRunnerSource／Preinstalled.app 需要重做時，先依 README 移到備份名稱，保留既有可用版本。
- 不提交個人 Team 設定、描述檔、私鑰、配對資料、UDID、原始診斷或實機截圖。
