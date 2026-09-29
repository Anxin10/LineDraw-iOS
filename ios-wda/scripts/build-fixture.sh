#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
output="$PWD/.runtime/LineDrawFixture.app"
mkdir -p "$output"
sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
architecture="$(uname -m)"
xcrun --sdk iphonesimulator swiftc -parse-as-library -O -sdk "$sdk" -target "$architecture-apple-ios18.0-simulator" fixture/Fixture.swift -o "$output/LineDrawFixture"
cp fixture/Info.plist "$output/Info.plist"
codesign --force --sign - "$output"
echo "$output"
