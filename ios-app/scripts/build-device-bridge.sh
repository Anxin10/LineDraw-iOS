#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
export PATH="${CARGO_HOME:-$HOME/.cargo}/bin:$PATH"
export CARGO_TARGET_DIR="$ROOT/.runtime/rust-target"
rustup target add aarch64-apple-ios aarch64-apple-ios-sim
for TARGET in aarch64-apple-ios aarch64-apple-ios-sim; do
  cargo build --manifest-path "$ROOT/DeviceBridge/Cargo.toml" --locked --release --target "$TARGET"
done
OUT="$ROOT/.runtime/LineDrawDeviceBridge.xcframework"
# Only replaces this generated artifact, never the source or device data.
if [[ -d "$OUT" ]]; then mv "$OUT" "$OUT.previous.$(date +%s)"; fi
xcodebuild -create-xcframework \
 -library "$CARGO_TARGET_DIR/aarch64-apple-ios/release/liblinedraw_device_bridge.a" -headers "$ROOT/DeviceBridge/include" \
 -library "$CARGO_TARGET_DIR/aarch64-apple-ios-sim/release/liblinedraw_device_bridge.a" -headers "$ROOT/DeviceBridge/include" \
 -output "$OUT"
