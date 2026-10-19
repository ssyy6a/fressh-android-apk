#!/usr/bin/env bash
set -euo pipefail

# Convert Fressh (or any) AAB to a universal APK using Google bundletool.
# Usage:
#   ./scripts/convert.sh [path-or-url-to.aab]
#
# Default URL points to the official @fressh/mobile@0.1.1 AAB.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="${ROOT}/out"
BUNDLETOOL_VERSION="1.17.2"
BUNDLETOOL_JAR="${OUT_DIR}/bundletool-all-${BUNDLETOOL_VERSION}.jar"
DEFAULT_AAB_URL="https://github.com/EthanShoeDev/fressh/releases/download/%40fressh%2Fmobile%400.1.1/fressh-android.aab"

mkdir -p "${OUT_DIR}"

AAB_INPUT="${1:-}"
AAB_FILE="${OUT_DIR}/fressh-android.aab"

if [[ -z "${AAB_INPUT}" ]]; then
  echo "==> Downloading official AAB from default URL..."
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
APK="${OUT_DIR}/fressh-universal.apk"

rm -f "${APKS}" "${APK}"

echo "==> Building universal APK set (debug-signed)..."
java -jar "${BUNDLETOOL_JAR}" build-apks \
  --bundle="${AAB_FILE}" \
  --output="${APKS}" \
  --mode=universal \
  --overwrite

echo "==> Extracting universal.apk..."
# .apks is a zip
unzip -o -j "${APKS}" "universal.apk" -d "${OUT_DIR}"
mv -f "${OUT_DIR}/universal.apk" "${APK}"

echo
echo "Done."
echo "  AAB : ${AAB_FILE}"
echo "  APK : ${APK}"
ls -lh "${APK}"
