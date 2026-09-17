#!/usr/bin/env bash
# validate_generated.sh
#
# Runs as a null_resource local-exec provisioner after apply to sanity-check
# the artifacts written by the config-file-generator and secrets-placeholder
# modules. Exits non-zero (failing the apply) if anything looks wrong.
#
# Usage: validate_generated.sh <config_file_path> <secrets_file_path>

set -euo pipefail

CONFIG_FILE="$1"
SECRETS_FILE="$2"

echo "[validate] checking config file: ${CONFIG_FILE}"
if [ ! -f "${CONFIG_FILE}" ]; then
  echo "[validate] FAIL: config file does not exist: ${CONFIG_FILE}" >&2
  exit 1
fi

if [ ! -s "${CONFIG_FILE}" ]; then
  echo "[validate] FAIL: config file is empty: ${CONFIG_FILE}" >&2
  exit 1
fi

case "${CONFIG_FILE}" in
  *.json)
    if command -v python3 >/dev/null 2>&1; then
      python3 -c "import json,sys; json.load(open('${CONFIG_FILE}'))" \
        || { echo "[validate] FAIL: config file is not valid JSON" >&2; exit 1; }
    fi
    ;;
esac

echo "[validate] checking secrets file: ${SECRETS_FILE}"
if [ ! -f "${SECRETS_FILE}" ]; then
  echo "[validate] FAIL: secrets file does not exist: ${SECRETS_FILE}" >&2
  exit 1
fi

if [ ! -s "${SECRETS_FILE}" ]; then
  echo "[validate] FAIL: secrets file is empty: ${SECRETS_FILE}" >&2
  exit 1
fi

PERMS=$(stat -f "%Lp" "${SECRETS_FILE}" 2>/dev/null || stat -c "%a" "${SECRETS_FILE}" 2>/dev/null || echo "unknown")
echo "[validate] secrets file permissions: ${PERMS}"
if [ "${PERMS}" != "600" ] && [ "${PERMS}" != "unknown" ]; then
  echo "[validate] WARN: expected secrets file permissions 600, got ${PERMS}" >&2
fi

echo "[validate] OK: all generated artifacts look valid."
