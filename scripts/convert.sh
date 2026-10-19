#!/usr/bin/env bash
set -euo pipefail

# Convert official Fressh AAB → single arm64-v8a release APK
#
# Critical: native .so must be stored UNCOMPRESSED in the APK, otherwise
# install fails with:
#   INSTALL_FAILED_INVALID_APK: Failed to extract native libraries, res=-2
#
# Usage: ./scripts/convert.sh [path-or-url-to.aab]

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
FAT_APK="${OUT_DIR}/fressh-universal-tmp.apk"
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

if [[ -d "${STRIPPED_DIR}/lib" ]]; then
  find "${STRIPPED_DIR}/lib" -mindepth 1 -maxdepth 1 -type d ! -name 'arm64-v8a' -exec rm -rf {} +
  if [[ -d "${STRIPPED_DIR}/lib/arm64-v8a" ]]; then
    echo "    kept: lib/arm64-v8a"
    ls -la "${STRIPPED_DIR}/lib/arm64-v8a/" | head -20 || true
  else
    echo "Warning: no lib/arm64-v8a found" >&2
  fi
fi

# Drop old signature; we re-sign later
rm -rf "${STRIPPED_DIR}/META-INF"

echo "==> Re-packing APK (.so stored UNCOMPRESSED)..."
rm -f "${STRIPPED_APK}"
(
  cd "${STRIPPED_DIR}"
  # 1) Everything except .so — normal compression
  # 2) .so files — store only (-0), required by Android package manager
  mapfile -t NON_SO < <(find . -type f ! -name '*.so' | sort)
  mapfile -t SO_FILES < <(find . -type f -name '*.so' | sort)

  if ((${#NON_SO[@]})); then
    zip -q -X "${STRIPPED_APK}" "${NON_SO[@]}"
  else
    # ensure zip exists
    zip -q -X "${STRIPPED_APK}" -r . -i 'META-INF/*' 2>/dev/null || true
    touch empty_placeholder
    zip -q -X "${STRIPPED_APK}" empty_placeholder
    zip -q -d "${STRIPPED_APK}" empty_placeholder || true
    rm -f empty_placeholder
  fi

  if ((${#SO_FILES[@]})); then
    # -0 = store (no compression), -X = no extra fields
    zip -q -0 -X "${STRIPPED_APK}" "${SO_FILES[@]}"
  fi
)

# Sanity: every .so in the zip must use method 0 (stored)
echo "==> Verifying .so compression method (must be 0/stored)..."
if command -v zipinfo >/dev/null 2>&1; then
  BAD="$(zipinfo -1 "${STRIPPED_APK}" 'lib/*/*.so' 2>/dev/null | while read -r f; do
    method="$(zipinfo -v "${STRIPPED_APK}" "$f" 2>/dev/null | awk '/compression method/{print $3; exit}')"
    # zipinfo may print "stored" or numeric
    if [[ -n "$method" && "$method" != "stored" && "$method" != "0" && "$method" != "none" ]]; then
      echo "$f method=$method"
    fi
  done || true)"
  if [[ -n "${BAD}" ]]; then
    echo "ERROR: compressed .so detected:" >&2
    echo "${BAD}" >&2
    exit 1
  fi
  echo "    all .so entries are stored (uncompressed)"
fi

ZIPALIGN=""
APKSIGNER=""
if [[ -n "${BUILD_TOOLS_DIR:-}" && -x "${BUILD_TOOLS_DIR}/zipalign" ]]; then
  ZIPALIGN="${BUILD_TOOLS_DIR}/zipalign"
  APKSIGNER="${BUILD_TOOLS_DIR}/apksigner"
else
  for cand in \
    "${ANDROID_HOME:-}/build-tools"/* \
    "${ANDROID_SDK_ROOT:-}/build-tools"/* \
    /usr/local/lib/android/sdk/build-tools/* \
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
  echo "Error: zipalign/apksigner not found. Set BUILD_TOOLS_DIR or ANDROID_HOME." >&2
  exit 1
fi

# Page-align shared libraries (4KB; use -P 16 on newer build-tools for 16KB pages)
echo "==> zipalign (page-align native libs)..."
if "${ZIPALIGN}" -h 2>&1 | grep -q -- '-P'; then
  "${ZIPALIGN}" -f -P 16 4 "${STRIPPED_APK}" "${ALIGNED_APK}" 2>/dev/null \
    || "${ZIPALIGN}" -f -p 4 "${STRIPPED_APK}" "${ALIGNED_APK}"
else
  "${ZIPALIGN}" -f -p 4 "${STRIPPED_APK}" "${ALIGNED_APK}"
fi

KEYSTORE_PATH="${KEYSTORE_PATH:-${OUT_DIR}/fressh-release.keystore}"
KEYSTORE_PASS="${KEYSTORE_PASS:-fressh-sideload}"
KEY_ALIAS="${KEY_ALIAS:-fressh}"
KEY_PASS="${KEY_PASS:-${KEYSTORE_PASS}}"

if [[ ! -f "${KEYSTORE_PATH}" ]]; then
  echo "==> Generating release keystore..."
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
  --v1-signing-enabled true \
  --v2-signing-enabled true \
  --v3-signing-enabled true \
  --out "${FINAL_APK}" \
  "${ALIGNED_APK}"

"${APKSIGNER}" verify --verbose "${FINAL_APK}"

echo
echo "Done (arm64-v8a only, .so uncompressed, release-signed)."
echo "  APK : ${FINAL_APK}"
ls -lh "${FINAL_APK}"
