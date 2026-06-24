#!/usr/bin/env bash
set -euo pipefail

key="${DASHSCOPE_API_KEY:-}"
keychain_service="${SILVERCARE_DASHSCOPE_KEYCHAIN_SERVICE:-com.silvercare.dashscope}"
keychain_account="${SILVERCARE_DASHSCOPE_KEYCHAIN_ACCOUNT:-default}"
home_key_file="${SILVERCARE_DASHSCOPE_KEY_FILE:-$HOME/.silvercare/dashscope_api_key}"

trim_key() {
  /usr/bin/python3 -c 'import sys; print(sys.stdin.read().strip())'
}

if [[ -z "${key//[[:space:]]/}" ]] && command -v security >/dev/null 2>&1; then
  key="$(security find-generic-password -s "$keychain_service" -a "$keychain_account" -w 2>/dev/null || true)"
fi

if [[ -z "${key//[[:space:]]/}" && -f "$home_key_file" ]]; then
  key="$(cat "$home_key_file")"
fi

key="$(printf '%s' "$key" | trim_key)"
if [[ -z "$key" ]]; then
  printf 'SilverCare private config: no DashScope key found; skipping app-bundled private config.\n'
  exit 0
fi

if [[ -z "${TARGET_BUILD_DIR:-}" || -z "${UNLOCALIZED_RESOURCES_FOLDER_PATH:-}" ]]; then
  printf 'SilverCare private config: TARGET_BUILD_DIR or UNLOCALIZED_RESOURCES_FOLDER_PATH is missing; skipping.\n' >&2
  exit 0
fi

resource_dir="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH"
output_path="$resource_dir/SilverCarePrivateConfig.plist"
mkdir -p "$resource_dir"

SILVERCARE_PRIVATE_DASHSCOPE_API_KEY="$key" /usr/bin/python3 - "$output_path" <<'PY'
import os
import plistlib
import sys

output_path = sys.argv[1]
api_key = os.environ.get("SILVERCARE_PRIVATE_DASHSCOPE_API_KEY", "").strip()
with open(output_path, "wb") as handle:
    plistlib.dump({"DASHSCOPE_API_KEY": api_key}, handle, sort_keys=True)
PY

chmod 600 "$output_path"
printf 'SilverCare private config: embedded DashScope key into app bundle resource.\n'
