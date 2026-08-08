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
APP_ICON_SOURCE="${XIAOMAO_APP_ICON_SOURCE:-}"
SECRETS_FILE="${ROOT}/Config/Secrets.xcconfig"
APP_ICON_DIR="${ROOT}/XiaomaoApp/Resources/Assets.xcassets/AppIcon.appiconset"
APP_ICON_BACKUP="${BUILD_ROOT}/.public-appicon-backup"

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
require_command sips

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

restore_public_app_icon() {
  if [[ -d "${APP_ICON_BACKUP}" ]]; then
    rm -rf "${APP_ICON_DIR}"
    mv "${APP_ICON_BACKUP}" "${APP_ICON_DIR}"
  fi
}
trap restore_public_app_icon EXIT INT TERM

if [[ -n "${APP_ICON_SOURCE}" ]]; then
  [[ -f "${APP_ICON_SOURCE}" ]] || fail "XIAOMAO_APP_ICON_SOURCE does not exist" 3
  width="$(sips -g pixelWidth "${APP_ICON_SOURCE}" 2>/dev/null | awk '/pixelWidth:/ {print $2}')"
  height="$(sips -g pixelHeight "${APP_ICON_SOURCE}" 2>/dev/null | awk '/pixelHeight:/ {print $2}')"
  [[ "${width}" =~ ^[0-9]+$ && "${height}" =~ ^[0-9]+$ ]] \
    || fail "private AppIcon source is not a readable image" 3
  [[ "${width}" -eq "${height}" ]] || fail "private AppIcon source must be square" 3

  rm -rf "${APP_ICON_BACKUP}"
  cp -R "${APP_ICON_DIR}" "${APP_ICON_BACKUP}"

  while read -r filename pixels; do
    sips -s format png -z "${pixels}" "${pixels}" "${APP_ICON_SOURCE}" \
      --out "${APP_ICON_DIR}/${filename}" >/dev/null
  done <<'ICONS'
AppIcon20@2x.png 40
AppIcon20@3x.png 60
AppIcon29@2x.png 58
AppIcon29@3x.png 87
AppIcon40@2x.png 80
AppIcon40@3x.png 120
AppIcon60@2x.png 120
AppIcon60@3x.png 180
AppIcon1024.png 1024
ICONS
  printf 'Private AppIcon override staged for trusted build.\n'
fi

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
