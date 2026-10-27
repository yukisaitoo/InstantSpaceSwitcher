#!/bin/bash
set -e

# Every path below is relative to the repo root, wherever this script is run from
cd "$(dirname "$0")/.."

CLEAN=false
INSTALL=true
BUILD_CONFIG="release"

for arg in "$@"; do
  case "$arg" in
    --clean) CLEAN=true ;;
    --debug) BUILD_CONFIG="debug" ;;
    --no-install) INSTALL=false ;;
    --help)
      echo "Usage: $0 [--clean] [--debug] [--no-install] [--help]"
      echo ""
      echo "Builds the app, then quits the running copy, replaces /Applications/InstantSpaceSwitcher.app"
      echo "and relaunches it."
      echo ""
      echo "Options:"
      echo "  --clean       Delete build directory before building"
      echo "  --debug       Build in debug mode (default: release)"
      echo "  --no-install  Only build the app bundle in build/"
      echo "  --help        Show this help message"
      echo ""
      echo "Environment:"
      echo "  CODESIGN_IDENTITY  Code-signing identity. Default: \"InstantSpaceSwitcher Dev\" if that"
      echo "                     certificate exists in your keychain (run dist/make-dev-cert.sh once),"
      echo "                     otherwise '-' (ad-hoc). Set CODESIGN_IDENTITY=- to force ad-hoc."
      echo "                     Ad-hoc signatures change every build, so macOS forgets the"
      echo "                     Accessibility grant after each rebuild."
      exit 0
      ;;
  esac
done

PRODUCT_NAME="InstantSpaceSwitcher"
BUILD_DIR="build"
DEV_CERT_NAME="InstantSpaceSwitcher Dev"

# Pick the signing identity: explicit env var wins; otherwise use the local dev
# certificate if dist/make-dev-cert.sh has created it; otherwise ad-hoc.
if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  IDENTITY_SOURCE="from environment"
elif security find-identity -v -p codesigning 2>/dev/null | grep -Fq "\"${DEV_CERT_NAME}\""; then
  CODESIGN_IDENTITY="${DEV_CERT_NAME}"
  IDENTITY_SOURCE="auto-detected in keychain"
else
  CODESIGN_IDENTITY="-"
  IDENTITY_SOURCE="no dev certificate found"
fi

if [[ "$CLEAN" == true ]]; then
  echo "Cleaning build directory..."
  rm -rf "${BUILD_DIR:?}"
fi

APP_BUNDLE="${BUILD_DIR}/${PRODUCT_NAME}.app"

echo "Building (${BUILD_CONFIG})..."
swift build -c "${BUILD_CONFIG}" --arch arm64 --build-path "${BUILD_DIR}" --disable-sandbox
BIN_PATH=$(swift build -c "${BUILD_CONFIG}" --arch arm64 --build-path "${BUILD_DIR}" --show-bin-path)

echo ""
echo "Bundling..."
# Start from an empty bundle so files from older builds don't end up in this one.
rm -rf "${APP_BUNDLE:?}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
cp "${BIN_PATH}/${PRODUCT_NAME}" "${APP_BUNDLE}/Contents/MacOS/"
cp Info.plist "${APP_BUNDLE}/Contents/"

GIT_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
echo "Injecting git SHA: ${GIT_SHA}"
/usr/libexec/PlistBuddy -c "Add :GitCommitHash string ${GIT_SHA}" "${APP_BUNDLE}/Contents/Info.plist"

echo ""
if [[ "${CODESIGN_IDENTITY}" == "-" ]]; then
  echo "Signing (ad-hoc, ${IDENTITY_SOURCE})..."
else
  echo "Signing with identity \"${CODESIGN_IDENTITY}\" (${IDENTITY_SOURCE})..."
fi
# --timestamp=none: ad-hoc and self-signed identities cannot obtain an Apple
# timestamp, and asking for one would fail the build.
codesign --force --sign "${CODESIGN_IDENTITY}" --timestamp=none "${APP_BUNDLE}"

# macOS (TCC) remembers the Accessibility grant by this "designated requirement".
# If it is a cdhash, it changes with every build and the grant will not carry over.
echo "Designated requirement:"
codesign -d -r- "${APP_BUNDLE}" 2>&1 | grep 'designated' | sed 's/^/  /'
if [[ "${CODESIGN_IDENTITY}" == "-" ]]; then
  echo "  Note: ad-hoc signatures change every build, so macOS will ask for Accessibility"
  echo "  again after each rebuild. Run ./dist/make-dev-cert.sh once; after that this"
  echo "  script picks the certificate up automatically."
fi

echo ""
echo "App bundled at $(pwd)/${APP_BUNDLE} (${BUILD_CONFIG})"

if [[ "$INSTALL" == true ]]; then
  INSTALL_PATH="/Applications/${PRODUCT_NAME}.app"
  BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" Info.plist)

  echo ""
  echo "Installing to ${INSTALL_PATH}..."
  if pgrep -xq "${PRODUCT_NAME}"; then
    echo "  Quitting running ${PRODUCT_NAME}..."
    osascript -e "quit app id \"${BUNDLE_ID}\"" >/dev/null 2>&1 || true
    for _ in $(seq 1 25); do
      pgrep -xq "${PRODUCT_NAME}" || break
      sleep 0.2
    done
    if pgrep -xq "${PRODUCT_NAME}"; then
      echo "  Still running; sending SIGTERM..."
      pkill -x "${PRODUCT_NAME}" || true
      sleep 0.5
    fi
  fi

  # Delete first: ditto merges into an existing folder, which would leave
  # files from older builds inside the installed app.
  rm -rf "${INSTALL_PATH:?}"
  ditto "${APP_BUNDLE}" "${INSTALL_PATH}"
  echo "  Installed. Launching..."
  # LaunchServices can briefly still list the copy that just quit, and open then fails with -600
  open "${INSTALL_PATH}" || { sleep 1; open "${INSTALL_PATH}"; }
fi
