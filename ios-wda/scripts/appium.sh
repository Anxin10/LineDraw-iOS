#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export APPIUM_HOME="$PWD/.runtime/appium"
mkdir -p .runtime
exec ./node_modules/.bin/appium --address 127.0.0.1 --port 4725 --log-level warn --log-no-colors --log .runtime/appium.log
