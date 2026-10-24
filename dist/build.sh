#!/bin/bash
set -e

CLEAN=false
INSTALL=false
BUILD_CONFIG="release"

for arg in "$@"; do
  case "$arg" in
    --clean) CLEAN=true ;;
    --debug) BUILD_CONFIG="debug" ;;
    --install) INSTALL=true ;;
    --help)
      echo "Usage: $0 [--clean] [--debug] [--install] [--help]"
      echo ""
      echo "Options:"
      echo "  --clean    Delete build directory before building"
      echo "  --debug    Build in debug mode (default: release)"
      echo "  --install  Quit the running app, replace /Applications/InstantSpaceSwitcher.app, relaunch"
      echo "  --help     Show this help message"
      echo ""
      echo "Environment:"
      echo "  CODESIGN_IDENTITY  Code-signing identity. Default: \"InstantSpaceSwitcher Dev\" if that"
      echo "                     certificate exists in your keychain (run dist/make-dev-cert.sh once),"
      echo "                     otherwise '-' (ad-hoc). Set CODESIGN_IDENTITY=- to force ad-hoc."
      echo "                     Ad-hoc signatures change every build, so macOS forgets the"
      echo "                     Accessibility grant after each rebuild."
      echo "  A .env file in the repo root is sourced if present (gitignored)."
      exit 0
      ;;
  esac
done

PRODUCT_NAME="InstantSpaceSwitcher"
BUILD_DIR="build"
DEV_CERT_NAME="InstantSpaceSwitcher Dev"

# Optional local defaults (gitignored), e.g. export CODESIGN_IDENTITY="...".
# A value given on the command line (CODESIGN_IDENTITY=- ./dist/build.sh) wins over .env.
PRESET_CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-}"
if [[ -f .env ]]; then
  # shellcheck disable=SC1091
  source .env
fi
if [[ -n "${PRESET_CODESIGN_IDENTITY}" ]]; then
  CODESIGN_IDENTITY="${PRESET_CODESIGN_IDENTITY}"
fi

# Pick the signing identity: explicit env var wins; otherwise use the local dev
# certificate if dist/make-dev-cert.sh has created it; otherwise ad-hoc (CI).
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
  rm -rf "${BUILD_DIR}"
fi

BUILD_PATH="${BUILD_DIR}/${BUILD_CONFIG}"
APP_BUNDLE="${BUILD_DIR}/${PRODUCT_NAME}.app"

# Build arm64 and x86_64 in parallel
echo "Building arm64 and x86_64 in parallel..."
ARM64_LOG=$(mktemp)
X86_LOG=$(mktemp)

swift build -c "${BUILD_CONFIG}" --arch arm64  --build-path "${BUILD_DIR}/arm64"  --disable-sandbox > "${ARM64_LOG}" 2>&1 &
PID_ARM64=$!
swift build -c "${BUILD_CONFIG}" --arch x86_64 --build-path "${BUILD_DIR}/x86_64" --disable-sandbox > "${X86_LOG}"  2>&1 &
PID_X86=$!

printf "  arm64: starting...\n x86_64: starting...\n"
while kill -0 "${PID_ARM64}" 2>/dev/null || kill -0 "${PID_X86}" 2>/dev/null; do
    ARM_LINE=$(tail -1 "${ARM64_LOG}" 2>/dev/null)
    X86_LINE=$(tail -1 "${X86_LOG}"  2>/dev/null)
    printf "\033[2A\033[2K  arm64: %.110s\n\033[2K x86_64: %.110s\n" \
        "${ARM_LINE:-starting...}" "${X86_LINE:-starting...}"
    sleep 0.2
done

wait "${PID_ARM64}" && ARM64_STATUS=0 || ARM64_STATUS=$?
wait "${PID_X86}"   && X86_STATUS=0  || X86_STATUS=$?

[[ ${ARM64_STATUS} -eq 0 ]] && ARM_FINAL="done" || ARM_FINAL="FAILED"
[[ ${X86_STATUS}   -eq 0 ]] && X86_FINAL="done" || X86_FINAL="FAILED"
printf "\033[2A\033[2K  arm64: %s\n\033[2K x86_64: %s\n" "${ARM_FINAL}" "${X86_FINAL}"

if [[ ${ARM64_STATUS} -ne 0 ]]; then
    echo ""; echo "=== arm64 build output ==="; cat "${ARM64_LOG}"
fi
if [[ ${X86_STATUS} -ne 0 ]]; then
    echo ""; echo "=== x86_64 build output ==="; cat "${X86_LOG}"
fi
rm -f "${ARM64_LOG}" "${X86_LOG}"

[[ ${ARM64_STATUS} -eq 0 ]] || exit 1
[[ ${X86_STATUS}   -eq 0 ]] || exit 1

echo ""
echo "Creating universal binaries..."
mkdir -p "${BUILD_PATH}"
lipo -create \
  "${BUILD_DIR}/arm64/${BUILD_CONFIG}/${PRODUCT_NAME}" \
  "${BUILD_DIR}/x86_64/${BUILD_CONFIG}/${PRODUCT_NAME}" \
  -output "${BUILD_PATH}/${PRODUCT_NAME}"

echo ""
echo "Bundling..."
# Start from an empty bundle so files from older builds don't end up in this one.
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"
cp "${BUILD_PATH}/${PRODUCT_NAME}" "${APP_BUNDLE}/Contents/MacOS/"
cp Info.plist "${APP_BUNDLE}/Contents/"

GIT_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
echo "Injecting git SHA: ${GIT_SHA}"
/usr/libexec/PlistBuddy -c "Add :GitCommitHash string ${GIT_SHA}" "${APP_BUNDLE}/Contents/Info.plist" 2>/dev/null || \
/usr/libexec/PlistBuddy -c "Set :GitCommitHash ${GIT_SHA}" "${APP_BUNDLE}/Contents/Info.plist"

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
  rm -rf "${INSTALL_PATH}"
  ditto "${APP_BUNDLE}" "${INSTALL_PATH}"
  echo "  Installed. Launching..."
  open "${INSTALL_PATH}"
fi
