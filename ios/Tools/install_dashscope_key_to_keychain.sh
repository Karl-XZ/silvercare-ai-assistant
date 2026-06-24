#!/usr/bin/env bash
set -euo pipefail

service="${SILVERCARE_DASHSCOPE_KEYCHAIN_SERVICE:-com.silvercare.dashscope}"
account="${SILVERCARE_DASHSCOPE_KEYCHAIN_ACCOUNT:-default}"
key="${DASHSCOPE_API_KEY:-}"

if [[ -z "${key//[[:space:]]/}" ]]; then
  printf 'Paste DashScope API Key. Input is hidden: ' >&2
  stty -echo
  IFS= read -r key
  stty echo
  printf '\n' >&2
fi

key="$(printf '%s' "$key" | /usr/bin/python3 -c 'import sys; print(sys.stdin.read().strip())')"
if [[ -z "$key" ]]; then
  printf 'No DashScope API Key provided.\n' >&2
  exit 1
fi

security add-generic-password \
  -a "$account" \
  -s "$service" \
  -w "$key" \
  -U >/dev/null

printf 'Stored DashScope API Key in macOS Keychain service %s account %s.\n' "$service" "$account"
