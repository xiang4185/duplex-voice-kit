#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="${ROOT}/XiaomaoApp.xcodeproj"
SCHEME="XiaomaoApp"
CONFIGURATION="Release"
BUILD_ROOT="${XIAOMAO_BUILD_ROOT:-${ROOT}/.trusted-alpha-build}"
ARCHIVE_PATH="${BUILD_ROOT}/XiaomaoApp.xcarchive"
EXPORT_PATH="${BUILD_ROOT}/export"
EXPORT_OPTIONS_PLIST="${XIAOMAO_EXPORT_OPTIONS_PLIST:-}"
DEVICE_UDID="${XIAOMAO_DEVICE_UDID:-}"
SECRETS_FILE="${ROOT}/Config/Secrets.xcconfig"

fail() {
  printf 'error: %s\n' "$1" >&2
  exit "${2:-1}"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "required command is unavailable: $1" 2
}

require_nonempty_setting() {
  local key="$1"
  grep -Eq "^[[:space:]]*${key}[[:space:]]*=[[:space:]]*[^[:space:]].*$" "${SECRETS_FILE}" \
    || fail "${key} is missing from trusted Config/Secrets.xcconfig" 3
}

[[ "$(uname -s)" == "Darwin" ]] || fail "trusted Alpha verification requires macOS with Xcode" 2
require_command xcodebuild
require_command xcrun
require_command python3
require_command xcodegen

[[ -f "${SECRETS_FILE}" ]] || fail "copy Config/Secrets.example.xcconfig to ignored Config/Secrets.xcconfig and inject trusted values" 3

# Validate presence only. Never print secret values or copy the file into logs/artifacts.
require_nonempty_setting API_BASE_URL
require_nonempty_setting VOICE_WS_URL
require_nonempty_setting DEVICE_ID
require_nonempty_setting DEVELOPMENT_TEAM
require_nonempty_setting BUNDLE_ID

grep -Eq '^[[:space:]]*API_BASE_URL[[:space:]]*=[[:space:]]*https://' "${SECRETS_FILE}" \
  || fail "API_BASE_URL must use HTTPS" 3
grep -Eq '^[[:space:]]*VOICE_WS_URL[[:space:]]*=[[:space:]]*wss://' "${SECRETS_FILE}" \
  || fail "VOICE_WS_URL must use WSS" 3

mkdir -p "${BUILD_ROOT}"
cd "${ROOT}"

python3 Scripts/static_check.py
xcodegen generate

xcodebuild \
  -project "${PROJECT}" \
  -scheme "${SCHEME}" \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  CODE_SIGNING_ALLOWED=NO \
  test

rm -rf "${ARCHIVE_PATH}" "${EXPORT_PATH}"
xcodebuild \
  -project "${PROJECT}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -destination 'generic/platform=iOS' \
  -archivePath "${ARCHIVE_PATH}" \
  archive

[[ -n "${EXPORT_OPTIONS_PLIST}" ]] || fail "set XIAOMAO_EXPORT_OPTIONS_PLIST to a trusted, untracked export options plist" 3
[[ -f "${EXPORT_OPTIONS_PLIST}" ]] || fail "XIAOMAO_EXPORT_OPTIONS_PLIST does not exist" 3

xcodebuild \
  -exportArchive \
  -archivePath "${ARCHIVE_PATH}" \
  -exportPath "${EXPORT_PATH}" \
  -exportOptionsPlist "${EXPORT_OPTIONS_PLIST}"

IPA_PATH="$(find "${EXPORT_PATH}" -maxdepth 1 -type f -name '*.ipa' -print -quit)"
[[ -n "${IPA_PATH}" ]] || fail "signed IPA was not produced" 4

if [[ -n "${DEVICE_UDID}" ]]; then
  xcrun devicectl device install app --device "${DEVICE_UDID}" "${IPA_PATH}"
fi

printf 'Alpha artifact ready: %s\n' "${IPA_PATH}"
if [[ -z "${DEVICE_UDID}" ]]; then
  printf 'Device install skipped. Set XIAOMAO_DEVICE_UDID to install with devicectl.\n'
fi
