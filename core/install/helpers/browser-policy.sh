#!/usr/bin/env bash

# Enterprise policy trust roots for Chromium browsers
BROWSER_POLICY_MANAGED_DIRS=(
  /etc/chromium/policies/managed
  /etc/opt/chrome/policies/managed
  /etc/opt/edge/policies/managed
  /etc/brave/policies/managed
)

BROWSER_POLICY_DEFAULT_COLOR="#1a1b26"

browser_policy_theme_hex() {
  local input="${1:-}"
  input="${input#"#"}"
  input="$(echo "$input" | tr -d '[:space:]')"
  if [[ $input =~ ^([0-9]{1,3}),([0-9]{1,3}),([0-9]{1,3})$ ]]; then
    printf '#%02x%02x%02x\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}"
  elif [[ $input =~ ^[0-9a-fA-F]{6}$ ]]; then
    printf '#%s\n' "${input,,}"
  else
    printf '%s\n' "$BROWSER_POLICY_DEFAULT_COLOR"
  fi
}
