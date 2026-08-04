#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOG_DIR="${ROOT}/build-logs"
SIMULATOR="${IOS_SIMULATOR_DESTINATION:-platform=iOS Simulator,name=iPhone 16 Pro}"
mkdir -p "${LOG_DIR}"
cd "${ROOT}"

if ! command -v xcodegen >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    brew install xcodegen
  else
    echo "xcodegen is missing and Homebrew is unavailable" >&2
    exit 2
  fi
fi

xcodegen generate 2>&1 | tee "${LOG_DIR}/xcodegen.log"
xcodebuild \
  -project XiaomaoApp.xcodeproj \
  -scheme XiaomaoApp \
  -configuration Debug \
  -destination "${SIMULATOR}" \
  CODE_SIGNING_ALLOWED=NO \
  build 2>&1 | tee "${LOG_DIR}/build.log"
xcodebuild \
  -project XiaomaoApp.xcodeproj \
  -scheme XiaomaoApp \
  -configuration Debug \
  -destination "${SIMULATOR}" \
  CODE_SIGNING_ALLOWED=NO \
  test 2>&1 | tee "${LOG_DIR}/test.log"
