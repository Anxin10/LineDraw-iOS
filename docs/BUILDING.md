# 從原始碼建置與安裝

以下命令從倉庫根目錄開始。工具鏈為 Xcode 27、Rust／rustup／cargo、Python 3、Ruby 與 `xcodeproj` gem；Mac 依賴準備另需 Node.js 24+、npm 10+。本指南不會提供個人的 Team、簽章或配對憑證。

## 1. 取得來源

```sh
git clone https://github.com/beybladehunter/LineDraw-iOS.git
cd LineDraw-iOS
```

如果 Ruby 尚未安裝 `xcodeproj`，在你使用的 Ruby 環境執行 `gem install xcodeproj`。

## 2. 建置 Rust bridge 與 iPhone App

```sh
cd ios-app
bash scripts/build-device-bridge.sh
ruby scripts/generate-project.rb
swift test --package-path Core
open LineDraw.xcodeproj
```

bridge 腳本會準備 arm64 iPhone／Apple Silicon 模擬器所需的 Rust target，產生 `.runtime/LineDrawDeviceBridge.xcframework`。專案產生器會依本機 Xcode 的可用 DDI 準備私人建置資源；若無本機 DDI，App 仍有固定版本、雜湊驗證的下載路徑。DDI 與 XCFramework 不存入 Git。

在 Xcode 選擇 `LineDraw` scheme。實機建置時，為 `LineDraw` 與 `PairingActivity` 選擇自己的 Signing Team。Bundle ID 必須可由自己的 Team 簽署，extension 的 ID 必須以 App ID 加點號為前綴。

若需更換 Bundle ID，請先修改 `scripts/generate-project.rb` 中 App、extension 與 UI test 的值，再重新產生專案；重新執行產生器會覆蓋直接在 Xcode 專案內做的設定。完成後再於 Xcode 指定 Team。模擬器建置不需簽署：

```sh
xcodebuild -project LineDraw.xcodeproj -scheme LineDraw \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .runtime/DerivedData CODE_SIGNING_ALLOWED=NO build
```

模擬器可操作離線示範，不能代替真實 LINE 自動化驗收。

## 3. 準備獨立 DeviceRunner

手機自主模式仍需另外安裝 WDA DeviceRunner。先取得固定版本的上游來源；這一步只準備 Mac 端依賴，不開始抽選：

```sh
cd ../ios-wda
npm run setup
cd ../ios-app
python3 scripts/prepare-device-runner.py
```

`setup` 固定 XCUITest Driver 12.13.2；Runner 準備工具要求 WDA 16.12.10。工具會複製到 `.runtime/DeviceRunnerSource`，保留上游授權，與 Mac 模式使用的 WDA 分開。

預設 Runner target ID 是 `com.beybladehunter.linedraw.DeviceRunner`。若你的 Team 不能簽署此 ID，須同步調整：

- `scripts/prepare-device-runner.py` 的 `PRODUCT_BUNDLE_IDENTIFIER`。
- `App/DeviceRuntime.swift` 的 `runner`，設為上述 ID 加上 `.xctrunner`。

這兩處須一致，否則 App 找不到已安裝的 Runner。若已執行過準備工具，先將舊的 `.runtime/DeviceRunnerSource` 移到備份位置，再重新產生；App 也需重新建置。

連接並解鎖自己的 iPhone，在 Xcode 完成帳號登入及信任後，使用自己的 Team ID／裝置識別碼：

```sh
LINEDRAW_TEAM_ID='<自己的 Apple Team ID>' \
LINEDRAW_DEVICE_ID='<自己的 iPhone UDID>' \
  bash scripts/build-device-runner.sh
```

腳本產生 `.runtime/DeviceRunner-Preinstalled.app`，使用裝置上的 XCTest framework 並重新簽署。它不會自動安裝或啟動 Runner。將產物安裝到同一支手機：

```sh
xcrun devicectl device install app \
  --device '<自己的 iPhone UDID>' .runtime/DeviceRunner-Preinstalled.app
```

若需要重新建置，先保留並移開舊的 `DeviceRunner-Preinstalled.app`；腳本刻意不覆蓋既有產物。配對 PIN extension 與 Runner 都需要有效的簽署。免費 Personal Team 的描述檔需定期續簽，不能把日常免電腦執行視為永久免續簽。

## 4. 手機配對與日常使用

依 [手機配對說明](../ios-app/docs/PHONE_PAIRING_2026-09-29.md) 完成：開發者模式與信任 → Wi-Fi／LocalDevVPN → App 開始配對 → 系統 Pair with LineDraw → PIN → 檢查啟動。

正常路徑不需要從電腦匯入配對檔。DDI 依序使用已驗證快取、建置時隨附資源或固定版本下載；系統版本不相容時仍可能失敗，請保留錯誤訊息以供檢查。

歷史報告包含 USB 匯入與手動 DDI 操作，這些是早期版本／進階修復流程；日常使用以現行手機配對步驟為準。

## 本機驗證

以下為本機邏輯測試，不會連接個人手機或執行 LINE 抽選：

```sh
# 在倉庫根目錄
swift test --package-path ios-app/Core
cd ios-wda
npm ci --ignore-scripts --no-fund --no-audit
npm test
```

Rust、UI、WDA fixture 與實機驗收範圍分別記錄於 `ios-app/docs/` 及 [Mac 驗證紀錄](../ios-wda/VALIDATION.md)。不要將 fixture 測試腳本指向個人實機。
