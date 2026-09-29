#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="LaunchNG.xcodeproj"
SCHEME="LaunchNG"
CONFIGURATION="Release"

cd "${ROOT_DIR}"

# This fork ships unsigned/ad-hoc builds (see README's Code Signing Status) --
# no Developer ID certificate is configured, so override the project's
# inherited team-signing settings the same way every local dev build in this
# repo does.
CODE_SIGN_ARGS=(
  CODE_SIGN_IDENTITY="-"
  CODE_SIGNING_REQUIRED=NO
  CODE_SIGNING_ALLOWED=NO
)

xcodebuild \
  -project "${PROJECT}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  "${CODE_SIGN_ARGS[@]}" \
  clean build

BUILT_PRODUCTS_DIR="$(xcodebuild \
  -project "${PROJECT}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  "${CODE_SIGN_ARGS[@]}" \
  -showBuildSettings \
  | awk -F ' = ' '/^[[:space:]]*BUILT_PRODUCTS_DIR = / { print $2 }' \
  | tail -n 1)"

APP_PATH="${BUILT_PRODUCTS_DIR}/LaunchNG.app"
BUILD_DIR="$(cd "${BUILT_PRODUCTS_DIR}/../.." && pwd)"
RELEASE_DIR="${BUILD_DIR}/dist"

rm -rf "${RELEASE_DIR}"
mkdir -p "${RELEASE_DIR}"

if [[ ! -d "${APP_PATH}" ]]; then
  echo "error: Release app not found at ${APP_PATH}" >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${APP_PATH}/Contents/Info.plist")"
if [[ -z "${VERSION}" ]]; then
  echo "error: Could not read CFBundleShortVersionString from ${APP_PATH}" >&2
  exit 1
fi

ZIP_NAME="LaunchNG${VERSION}.zip"
ZIP_PATH="${RELEASE_DIR}/${ZIP_NAME}"
DMG_NAME="LaunchNG${VERSION}.dmg"
DMG_PATH="${RELEASE_DIR}/${DMG_NAME}"
DMG_STAGING="${RELEASE_DIR}/dmg-staging"
CHECKSUMS_PATH="${RELEASE_DIR}/checksums.txt"

ditto -c -k --sequesterRsrc --keepParent "${APP_PATH}" "${ZIP_PATH}"

rm -rf "${DMG_STAGING}"
mkdir -p "${DMG_STAGING}"
ditto "${APP_PATH}" "${DMG_STAGING}/LaunchNG.app"
ln -s /Applications "${DMG_STAGING}/Applications"

rm -f "${DMG_PATH}"
hdiutil create \
  -volname "LaunchNG" \
  -srcfolder "${DMG_STAGING}" \
  -fs HFS+ \
  -format UDZO \
  -ov \
  "${DMG_PATH}"

rm -rf "${DMG_STAGING}"

(
  cd "${RELEASE_DIR}"
  shasum -a 256 "${ZIP_NAME}" "${DMG_NAME}" > "${CHECKSUMS_PATH}"
)

ZIP_SHA256="$(awk -v f="${ZIP_NAME}" '$2 == f { print $1 }' "${CHECKSUMS_PATH}")"
DMG_SHA256="$(awk -v f="${DMG_NAME}" '$2 == f { print $1 }' "${CHECKSUMS_PATH}")"

echo "Release artifacts:"
echo "  App: ${APP_PATH}"
echo "  ${ZIP_PATH}"
echo "  ${DMG_PATH}"
echo "  ${CHECKSUMS_PATH}"
echo ""
echo "Version: ${VERSION}"
echo "ZIP SHA256: ${ZIP_SHA256}"
echo "DMG SHA256: ${DMG_SHA256}"
echo ""
echo "Upload these assets to the GitHub release tagged ${VERSION}:"
echo "  ${ZIP_NAME}"
echo "  ${DMG_NAME}"
echo "  checksums.txt"
