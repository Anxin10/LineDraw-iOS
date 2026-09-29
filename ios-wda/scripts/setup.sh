#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export APPIUM_HOME="$PWD/.runtime/appium"
command -v node >/dev/null || { echo '請先安裝 Node.js 24。'; exit 1; }
node -e 'if (Number(process.versions.node.split(".")[0]) < 24) { console.error("需要 Node.js 24 或以上。"); process.exit(1); }'
xcodebuild -version
npm ci --no-fund --no-audit
if [ ! -f "$APPIUM_HOME/node_modules/appium-xcuitest-driver/package.json" ]; then
  ./node_modules/.bin/appium driver install xcuitest@12.13.2
fi
node -e 'const p=require(process.env.APPIUM_HOME+"/node_modules/appium-xcuitest-driver/package.json"); if(p.version!=="12.13.2")throw Error("XCUITest 版本不符，請檢查 .runtime/appium");'
mkdir -p .runtime
xcrun swiftc -O native/Recognize.swift -o .runtime/recognize
echo '依賴與 OCR 已準備完成。執行 npm run doctor 可檢查環境。'
