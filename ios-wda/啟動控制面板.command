#!/bin/bash
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
cd "$(dirname "$0")"
if [ ! -x node_modules/.bin/appium ]; then echo '請先執行「準備環境.command」。'; read -r -p '按 Enter 結束'; exit 1; fi
node scripts/launch.mjs
