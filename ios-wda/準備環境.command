#!/bin/bash
set -euo pipefail
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
cd "$(dirname "$0")"
bash scripts/setup.sh
read -r -p '完成。按 Enter 結束'
