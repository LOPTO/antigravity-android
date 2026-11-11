#!/usr/bin/env bash
# 08_sign.sh - Signs an aligned APK with the configured Fork keystore.
set -euo pipefail

ALIGNED_APK="${1:-$BUILD_DIR/aligned.apk}"
OUT_APK="${2:-$DIST_DIR/antigravity.apk}"
if [ "${DEV_MODE:-0}" = "1" ] && [ -z "${AGY_SIGNING_KEYSTORE:-}" ]; then
    KEYSTORE="$TOOLS_DIR/debug.keystore"
    KEY_ALIAS=androiddebugkey
    export AGY_SIGNING_STORE_PASSWORD=android
    export AGY_SIGNING_KEY_PASSWORD=android
else
    KEYSTORE="${AGY_SIGNING_KEYSTORE:?Set AGY_SIGNING_KEYSTORE}"
    KEY_ALIAS="${AGY_SIGNING_ALIAS:-antigravity-zh}"
    export AGY_SIGNING_STORE_PASSWORD="${AGY_SIGNING_STORE_PASSWORD:?Set AGY_SIGNING_STORE_PASSWORD}"
    export AGY_SIGNING_KEY_PASSWORD="${AGY_SIGNING_KEY_PASSWORD:-$AGY_SIGNING_STORE_PASSWORD}"
fi

echo "[*] [08_sign] Signing APK..."
mkdir -p "$(dirname "$OUT_APK")"

apksigner sign \
    --ks "$KEYSTORE" \
    --ks-key-alias "$KEY_ALIAS" \
    --ks-pass env:AGY_SIGNING_STORE_PASSWORD \
    --key-pass env:AGY_SIGNING_KEY_PASSWORD \
    --out "$OUT_APK" \
    "$ALIGNED_APK"

echo "[OK] [08_sign] Signed APK created: $OUT_APK ($(stat -c%s "$OUT_APK") bytes)"
