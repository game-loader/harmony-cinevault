#!/usr/bin/env bash
# Unit tests for the protocol modules, then an unsigned HAP via hvigor.
#   tools/build.sh [debug|release]
# Needs Java 17 (JAVA_HOME or ~/ohos-build/jdk) and local.properties with sdk.dir (API 26 SDK).
set -uo pipefail
cd "$(dirname "$0")/.."
mode="${1:-debug}"
if [ -z "${JAVA_HOME:-}" ]; then
  JAVA_HOME="$(ls -d "$HOME"/ohos-build/jdk/jdk-17*/ 2>/dev/null | head -1)"
  export JAVA_HOME
fi
export PATH="$JAVA_HOME/bin:$PATH"
if [ -z "${OHOS_BASE_SDK_HOME:-}" ]; then
  OHOS_BASE_SDK_HOME="$(sed -n 's/^sdk\.dir=//p' local.properties)"
  export OHOS_BASE_SDK_HOME
fi
node tools/test.mjs || { echo "unit tests FAILED"; exit 1; }
log=$(pwd)/.build.log
node node_modules/@ohos/hvigor/bin/hvigor.js --mode module -p module=entry@default -p product=default \
  -p buildMode="$mode" assembleHap --no-daemon > "$log" 2>&1
status=$?
sed 's/\x1b\[[0-9;]*m//g' "$log" | grep -E -A4 "ArkTS:ERROR|hvigor ERROR" | head -120
sed 's/\x1b\[[0-9;]*m//g' "$log" | grep -E "COMPILE RESULT|BUILD (SUCCESSFUL|FAILED)" | head -5
find entry/build -name "*.hap" 2>/dev/null
exit $status
