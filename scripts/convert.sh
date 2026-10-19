#!/usr/bin/env bash
set -euo pipefail

# Convert official Fressh AAB → single arm64-v8a release APK
#
# Steps:
#   1. bundletool --mode=universal → one fat APK
#   2. strip lib/{armeabi-v7a,x86,x86_64,...} keep only arm64-v8a
#   3. zipalign + apksigner with a dedicated release keystore
#
# Usage:
#   ./scripts/convert.sh [path-or-url-to.aab]
#
# Env (optional):
#   KEYSTORE_PATH, KEYSTORE_PASS, KEY_ALIAS, KEY_PASS
#   BUILD_TOOLS_DIR  — path containing zipalign & apksigner

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="${ROOT}/out"
BUNDLETOOL_VERSION="1.17.2"
BUNDLETOOL_JAR="${OUT_DIR}/bundletool-all-${BUNDLETOOL_VERSION}.jar"
DEFAULT_AAB_URL="https://github.com/EthanShoeDev/fressh/releases/download/%40fressh%2Fmobile%400.1.1/fressh-android.aab"

mkdir -p "${OUT_DIR}"

AAB_INPUT="${1:-}"
AAB_FILE="${OUT_DIR}/fressh-android.aab"

if [[ -z "${AAB_INPUT}" ]]; then
  echo "==> Downloading official AAB..."
  curl -L --fail -o "${AAB_FILE}" "${DEFAULT_AAB_URL}"
elif [[ "${AAB_INPUT}" == http://* || "${AAB_INPUT}" == https://* ]]; then
  echo "==> Downloading AAB from ${AAB_INPUT}..."
  curl -L --fail -o "${AAB_FILE}" "${AAB_INPUT}"
elif [[ -f "${AAB_INPUT}" ]]; then
  echo "==> Using local AAB: ${AAB_INPUT}"
  cp "${AAB_INPUT}" "${AAB_FILE}"
else
  echo "Error: not a file or URL: ${AAB_INPUT}" >&2
  exit 1
fi

if [[ ! -f "${BUNDLETOOL_JAR}" ]]; then
  echo "==> Downloading bundletool ${BUNDLETOOL_VERSION}..."
  curl -L --fail -o "${BUNDLETOOL_JAR}" \
    "https://github.com/google/bundletool/releases/download/${BUNDLETOOL_VERSION}/bundletool-all-${BUNDLETOOL_VERSION}.jar"
fi

APKS="${OUT_DIR}/fressh.apks"
FAT_APK="${OUT_DIR}/fressh-universal-unsigned-or-debug.apk"
STRIPPED_DIR="${OUT_DIR}/apk-stripped"
STRIPPED_APK="${OUT_DIR}/fressh-arm64-unsigned.apk"
ALIGNED_APK="${OUT_DIR}/fressh-arm64-aligned.apk"
FINAL_APK="${OUT_DIR}/fressh-arm64-v8a-release.apk"

rm -rf "${APKS}" "${FAT_APK}" "${STRIPPED_DIR}" "${STRIPPED_APK}" "${ALIGNED_APK}" "${FINAL_APK}"

echo "==> Building universal APK (intermediate)..."
java -jar "${BUNDLETOOL_JAR}" build-apks \
  --bundle="${AAB_FILE}" \
  --output="${APKS}" \
  --mode=universal \
  --overwrite

unzip -o -j "${APKS}" "universal.apk" -d "${OUT_DIR}"
mv -f "${OUT_DIR}/universal.apk" "${FAT_APK}"

echo "==> Stripping non-arm64 native libraries..."
rm -rf "${STRIPPED_DIR}"
mkdir -p "${STRIPPED_DIR}"
unzip -q "${FAT_APK}" -d "${STRIPPED_DIR}"

# Keep only arm64-v8a under lib/
if [[ -d "${STRIPPED_DIR}/lib" ]]; then
  find "${STRIPPED_DIR}/lib" -mindepth 1 -maxdepth 1 -type d ! -name 'arm64-v8a' -exec rm -rf {} +
  if [[ ! -d "${STRIPPED_DIR}/lib/arm64-v8a" ]]; then
    echo "Warning: no lib/arm64-v8a found in APK; leaving other ABIs as-is may fail." >&2
  else
    echo "    kept: lib/arm64-v8a"
    ls -la "${STRIPPED_DIR}/lib/" || true
  fi
fi

# Remove existing signature so we can re-sign cleanly
rm -rf "${STRIPPED_DIR}/META-INF"

(
  cd "${STRIPPED_DIR}"
  # Store compression for native libs is typical; use default zip
  zip -qr "${STRIPPED_APK}" .
)

# Locate build-tools (zipalign + apksigner)
ZIPALIGN=""
APKSIGNER=""
if [[ -n "${BUILD_TOOLS_DIR:-}" ]]; then
  ZIPALIGN="${BUILD_TOOLS_DIR}/zipalign"
  APKSIGNER="${BUILD_TOOLS_DIR}/apksigner"
else
  # Common CI / local layouts
  for cand in \
    "${ANDROID_HOME:-}/build-tools"/* \
    "${ANDROID_SDK_ROOT:-}/build-tools"/* \
    /usr/lib/android-sdk/build-tools/* \
    "${HOME}/Android/Sdk/build-tools"/*
  do
    if [[ -x "${cand}/zipalign" && -x "${cand}/apksigner" ]]; then
      ZIPALIGN="${cand}/zipalign"
      APKSIGNER="${cand}/apksigner"
      break
    fi
  done
fi

if [[ -z "${ZIPALIGN}" || -z "${APKSIGNER}" ]]; then
  echo "Error: zipalign/apksigner not found. Install Android build-tools or set BUILD_TOOLS_DIR." >&2
  exit 1
fi

echo "==> zipalign..."
"${ZIPALIGN}" -f 4 "${STRIPPED_APK}" "${ALIGNED_APK}"

# Keystore: use env or generate a local release keystore (sideload only)
KEYSTORE_PATH="${KEYSTORE_PATH:-${OUT_DIR}/fressh-release.keystore}"
KEYSTORE_PASS="${KEYSTORE_PASS:-fressh-sideload}"
KEY_ALIAS="${KEY_ALIAS:-fressh}"
KEY_PASS="${KEY_PASS:-${KEYSTORE_PASS}}"

if [[ ! -f "${KEYSTORE_PATH}" ]]; then
  echo "==> Generating release keystore at ${KEYSTORE_PATH}..."
  keytool -genkeypair \
    -keystore "${KEYSTORE_PATH}" \
    -alias "${KEY_ALIAS}" \
    -keyalg RSA \
    -keysize 2048 \
    -validity 10000 \
    -storepass "${KEYSTORE_PASS}" \
    -keypass "${KEY_PASS}" \
    -dname "CN=Fressh Sideload, OU=Unofficial, O=ssyy6a, L=Unknown, ST=Unknown, C=US"
fi

echo "==> apksigner (v2/v3)..."
"${APKSIGNER}" sign \
  --ks "${KEYSTORE_PATH}" \
  --ks-key-alias "${KEY_ALIAS}" \
  --ks-pass "pass:${KEYSTORE_PASS}" \
  --key-pass "pass:${KEY_PASS}" \
  --out "${FINAL_APK}" \
  "${ALIGNED_APK}"

"${APKSIGNER}" verify --verbose "${FINAL_APK}"

echo
echo "Done (arm64-v8a only, release-signed)."
echo "  AAB : ${AAB_FILE}"
echo "  APK : ${FINAL_APK}"
ls -lh "${FINAL_APK}"
