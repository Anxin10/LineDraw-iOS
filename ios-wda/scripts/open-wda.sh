#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
project="$(node scripts/wda-path.mjs)"
open -a Xcode "$project"
echo '請在 Xcode 選 WebDriverAgentRunner → Signing & Capabilities 設定 Team 與唯一 Bundle ID。'
echo '接上 iPhone 後選擇該裝置，再 Product → Test。也可完成簽署設定後由控制面板啟動。'
