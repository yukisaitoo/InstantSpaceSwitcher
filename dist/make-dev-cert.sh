#!/bin/bash
#
# One-time setup: create a self-signed code-signing certificate in your login
# keychain so local builds keep their Accessibility permission across rebuilds.
#
# Why: build.sh signs ad-hoc by default. An ad-hoc signature's identity is the
# hash of the binary, which changes on every build, so macOS "forgets" the
# Accessibility grant each time you rebuild (System Settings still shows the old
# entry as enabled, and toggling it does not help). Signing with a certificate
# gives every build the same identity ("identifier X and certificate leaf = H..."),
# which macOS matches across rebuilds.
#
# Usage:
#   ./dist/make-dev-cert.sh
#   ./dist/build.sh --install   # picks up the certificate automatically
#
# After the FIRST certificate-signed build, remove the app from
# System Settings > Privacy & Security > Accessibility with the "-" button
# (or: tccutil reset Accessibility com.interversehq.InstantSpaceSwitcher),
# launch it, and grant once. From then on rebuilds are recognised.
#
# Manual alternative: Keychain Access > Certificate Assistant > Create a
# Certificate..., Name "InstantSpaceSwitcher Dev", Certificate Type "Code Signing".
#
# Notes:
# - Uses /usr/bin/openssl (LibreSSL) on purpose. Homebrew's OpenSSL 3.x writes
#   PKCS#12 files that `security import` rejects ("MAC verification failed").
# - The trust step is required: codesign refuses a certificate macOS does not
#   trust for code signing ("no identity found").
# - On the first builds macOS asks "codesign wants to use the key". Click
#   "Always Allow" for silent builds, or "Allow" to be asked (twice) per build.
#   Always Allow lets any program running as you sign with this certificate; the
#   only thing it unlocks is this app's Accessibility grant.

set -eo pipefail

CERT_NAME="${CERT_NAME:-InstantSpaceSwitcher Dev}"
KEYCHAIN="${KEYCHAIN:-${HOME}/Library/Keychains/login.keychain-db}"   # override only for testing
SKIP_TRUST="${SKIP_TRUST:-0}"                                        # 1 = skip trust step (testing)
OPENSSL=/usr/bin/openssl

if security find-certificate -c "${CERT_NAME}" "${KEYCHAIN}" >/dev/null 2>&1; then
  echo "Certificate \"${CERT_NAME}\" already exists in the keychain; nothing to do."
  echo ""
  if security find-identity -v -p codesigning 2>/dev/null | grep -Fq "\"${CERT_NAME}\""; then
    security find-identity -v -p codesigning | grep -F "\"${CERT_NAME}\""
  else
    echo "But it is not listed as a valid code-signing identity, so codesign will refuse"
    echo "it (\"no identity found\"). The trust step was probably cancelled. Retry it with:"
    echo "  security find-certificate -c \"${CERT_NAME}\" -p \"${KEYCHAIN}\" > /tmp/iss-dev.pem"
    echo "  security add-trusted-cert -r trustRoot -p codeSign -k \"${KEYCHAIN}\" /tmp/iss-dev.pem"
    echo "  rm /tmp/iss-dev.pem"
  fi
  echo ""
  echo "Build with: ./dist/build.sh --install (the certificate is detected automatically)"
  exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "${TMP}"' EXIT

echo "Generating self-signed code-signing certificate \"${CERT_NAME}\" (valid 10 years)..."
"${OPENSSL}" req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -subj "/CN=${CERT_NAME}" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" \
  -addext "basicConstraints=critical,CA:false" \
  -keyout "${TMP}/key.pem" -out "${TMP}/cert.pem" 2>/dev/null

# Throwaway password for the intermediate .p12 (deleted on exit).
P12_PW=$("${OPENSSL}" rand -hex 16)
export P12_PW

# OpenSSL 3.x needs -legacy for a .p12 that `security import` can read.
# /usr/bin/openssl is LibreSSL today; this guards against that changing.
P12_EXTRA=()
if "${OPENSSL}" version | grep -q '^OpenSSL 3'; then
  P12_EXTRA=(-legacy)
fi

"${OPENSSL}" pkcs12 -export "${P12_EXTRA[@]}" \
  -inkey "${TMP}/key.pem" -in "${TMP}/cert.pem" \
  -name "${CERT_NAME}" -out "${TMP}/dev.p12" -passout env:P12_PW

echo "Importing into keychain $(basename "${KEYCHAIN}")..."
security import "${TMP}/dev.p12" -k "${KEYCHAIN}" -P "${P12_PW}" -T /usr/bin/codesign >/dev/null

if [[ "${SKIP_TRUST}" == "1" ]]; then
  echo "Skipping trust step (SKIP_TRUST=1)."
else
  echo "Marking it trusted for code signing (macOS will ask for your password)..."
  if ! security add-trusted-cert -r trustRoot -p codeSign -k "${KEYCHAIN}" "${TMP}/cert.pem"; then
    echo ""
    echo "ERROR: trust step failed or was cancelled. codesign refuses untrusted certificates"
    echo "(\"no identity found\"), so builds will fail until this is done. The certificate is"
    echo "already in your keychain; re-run this script and it will print the retry command."
    exit 1
  fi
fi

echo ""
echo "Code-signing identities now available:"
security find-identity -v -p codesigning
echo ""
echo "Next: ./dist/build.sh --install (the certificate is detected automatically)"
echo "If an older build already had Accessibility permission, remove it there once (\"-\" button) and grant again."
echo "The first build will ask whether codesign may use the key; choose \"Always Allow\" for silent builds."
